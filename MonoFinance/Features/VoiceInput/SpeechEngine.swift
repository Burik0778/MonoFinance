import Foundation
import Speech
import AVFoundation
import MonoCore

/// Событие распознавания речи.
enum SpeechEvent: Sendable {
    /// Громкость 0…1.
    case level(Float)
    case partial(String)
    case final(String)
    case failed(SpeechFailure)
}

enum SpeechFailure: Error, Equatable, Sendable {
    case recognizerUnavailable
    case audioSessionFailed
    case engineFailed
    case noSpeech
    case recognitionFailed(String)
}

/// Движок распознавания. Модульный: Apple Speech сейчас; позже можно добавить другой (например, SpeechAnalyzer или собственный сервер).
protocol SpeechRecognitionEngine: AnyObject {
    func start(localeIdentifier: String, onDeviceOnly: Bool, contextualStrings: [String]) throws -> AsyncStream<SpeechEvent>
    /// Завершить запись и дождаться финального результата.
    func stop()
    /// Прервать без результата.
    func cancel()
}

/// Распознавание через Speech framework + AVAudioEngine.
final class AppleSpeechEngine: NSObject, SpeechRecognitionEngine, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var continuation: AsyncStream<SpeechEvent>.Continuation?
    private var tapInstalled = false
    /// Токен сессии: отложенная очистка старой сессии не должна остановить новую.
    private var sessionID = UUID()

    func start(localeIdentifier: String, onDeviceOnly: Bool, contextualStrings: [String]) throws -> AsyncStream<SpeechEvent> {
        cancel()
        let session = UUID()
        sessionID = session
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw SpeechFailure.recognizerUnavailable
        }
        self.recognizer = recognizer

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechFailure.audioSessionFailed
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings
        // Если доступно распознавание на устройстве и пользователь не разрешил серверы Apple — аудио не покидает iPhone.
        request.requiresOnDeviceRecognition = onDeviceOnly
        self.request = request

        let (stream, continuation) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        self.continuation = continuation

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechFailure.engineFailed
        }
        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            continuation.yield(.level(AppleSpeechEngine.level(of: buffer)))
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw SpeechFailure.engineFailed
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    continuation.yield(.final(text))
                    continuation.finish()
                    DispatchQueue.main.async { self?.teardown(session: session) }
                } else {
                    continuation.yield(.partial(text))
                }
            } else if let error {
                let nsError = error as NSError
                // 1110 / 203 — речь не обнаружена; 216 / 301 — запрос отменён.
                let failure: SpeechFailure = [1110, 203].contains(nsError.code) ? .noSpeech : .recognitionFailed(nsError.localizedDescription)
                if ![216, 301].contains(nsError.code) {
                    continuation.yield(.failed(failure))
                }
                continuation.finish()
                DispatchQueue.main.async { self?.teardown(session: session) }
            }
        }
        continuation.onTermination = { [weak self] _ in
            DispatchQueue.main.async { self?.teardown(session: session) }
        }
        return stream
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
    }

    func cancel() {
        task?.cancel()
        continuation?.onTermination = nil
        continuation?.finish()
        teardown()
    }

    private func teardown(session: UUID) {
        guard session == sessionID else { return }
        teardown()
    }

    private func teardown() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request = nil
        task = nil
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Громкость буфера: RMS → дБ → 0…1 (−50 дБ … 0 дБ).
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, (decibels + 50) / 50))
    }
}

/// Разрешения на микрофон и распознавание речи.
enum SpeechPermissions {
    static var speechStatus: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

    static func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static var microphoneStatus: AVAudioApplication.recordPermission { AVAudioApplication.shared.recordPermission }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// Фактическая поддержка языка на этом устройстве — проверяется в рантайме, ничего не обещаем заранее.
struct SpeechSupportInfo: Equatable {
    let language: AppLanguage
    /// Язык есть в списке `SFSpeechRecognizer.supportedLocales()`.
    let isSupported: Bool
    /// Распознавание возможно без отправки аудио на серверы Apple.
    let supportsOnDevice: Bool
    /// Распознаватель готов прямо сейчас (на сервере — нужна сеть).
    let isAvailable: Bool
}

enum SpeechSupport {
    static func info(for language: AppLanguage) -> SpeechSupportInfo {
        let identifier = language.speechLocaleIdentifier
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let supported = SFSpeechRecognizer.supportedLocales().contains { locale in
            locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased() == normalized
        }
        let recognizer = supported ? SFSpeechRecognizer(locale: Locale(identifier: identifier)) : nil
        return SpeechSupportInfo(
            language: language,
            isSupported: supported && recognizer != nil,
            supportsOnDevice: recognizer?.supportsOnDeviceRecognition ?? false,
            isAvailable: recognizer?.isAvailable ?? false
        )
    }

    /// Подсказки распознавателю: банки, счета, частые продавцы — повышают точность имён собственных.
    static func contextualStrings(accounts: [Account]) -> [String] {
        var strings = ["Капиталбанк", "Узум", "Узум Банк", "Ориент Финанс", "Трастбанк", "Корзинка", "Макро", "Хавас",
                       "Яндекс Го", "Эвос", "Макс Вей", "Хумо", "Узкарт", "сум", "тысяч", "миллион"]
        strings += accounts.map(\.displayName)
        return Array(Set(strings)).sorted()
    }
}
