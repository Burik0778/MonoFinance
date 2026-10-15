import Foundation
import Observation
import Speech
import MonoCore
import MonoIntelligence

/// Состояние голосового ввода: разрешения → запись → разбор → проверка черновиков → сохранение.
@MainActor
@Observable
final class VoiceInputModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case processing
        case review
        case failed(Failure)
    }

    enum Failure: Equatable {
        case microphoneDenied
        case speechDenied
        case restricted
        case unsupportedLanguage(AppLanguage)
        /// Локальное распознавание недоступно — нужно согласие на серверы Apple.
        case needsServerConsent
        case recognizerUnavailable
        case noSpeech
        case nothingRecognized
        case generic(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var level: Double = 0
    private(set) var levels: [Double] = []
    private(set) var usesOnDevice = true
    var drafts: [VoiceDraft] = []
    var typedText = ""
    /// Категории, предложенные парсером: если пользователь их поменял — запоминаем выбор для продавца.
    private var suggestedCategories: [UUID: UUID?] = [:]

    private let engine: SpeechRecognitionEngine
    private var listenTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var lastChange = Date()
    private var startedAt = Date()

    init(engine: SpeechRecognitionEngine = AppleSpeechEngine()) {
        self.engine = engine
    }

    var isListening: Bool { phase == .listening }
    var allReady: Bool { !drafts.isEmpty && drafts.allSatisfy(\.isReady) }

    // MARK: - Запись

    func start(store: FinanceStore, settings: SettingsStore) async {
        guard phase != .listening else { return }
        phase = .preparing
        transcript = ""
        levels = []

        // 1. Микрофон
        switch SpeechPermissions.microphoneStatus {
        case .denied:
            phase = .failed(.microphoneDenied)
            return
        case .undetermined:
            guard await SpeechPermissions.requestMicrophone() else {
                phase = .failed(.microphoneDenied)
                return
            }
        default:
            break
        }

        // 2. Распознавание речи
        var status = SpeechPermissions.speechStatus
        if status == .notDetermined { status = await SpeechPermissions.requestSpeech() }
        switch status {
        case .denied:
            phase = .failed(.speechDenied)
            return
        case .restricted:
            phase = .failed(.restricted)
            return
        default:
            break
        }

        // 3. Язык и приватность
        let language = settings.speechLanguage
        let support = SpeechSupport.info(for: language)
        guard support.isSupported else {
            phase = .failed(.unsupportedLanguage(language))
            return
        }
        if !support.supportsOnDevice && !settings.speechServerConsent {
            phase = .failed(.needsServerConsent)
            return
        }
        usesOnDevice = support.supportsOnDevice

        // 4. Запуск
        let stream: AsyncStream<SpeechEvent>
        do {
            stream = try engine.start(
                localeIdentifier: language.speechLocaleIdentifier,
                onDeviceOnly: support.supportsOnDevice,
                contextualStrings: SpeechSupport.contextualStrings(accounts: store.activeAccounts)
            )
        } catch {
            phase = .failed(.recognizerUnavailable)
            return
        }
        phase = .listening
        Haptics.rigid()
        startedAt = Date()
        lastChange = Date()

        listenTask?.cancel()
        listenTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event, store: store)
            }
            guard let self else { return }
            if self.phase == .listening || self.phase == .processing {
                self.finishRecognition(store: store)
            }
        }
        startWatchdog(autoStop: settings.autoStopOnSilence)
    }

    private func handle(_ event: SpeechEvent, store: FinanceStore) {
        switch event {
        case .level(let value):
            let smoothed = level * 0.6 + Double(value) * 0.4
            level = smoothed
            levels.append(smoothed)
            if levels.count > 160 { levels.removeFirst(levels.count - 160) }
        case .partial(let text):
            if text != transcript {
                transcript = text
                lastChange = Date()
            }
        case .final(let text):
            transcript = text
            finishRecognition(store: store)
        case .failed(let failure):
            watchdog?.cancel()
            if failure == .noSpeech || transcript.isEmpty {
                phase = .failed(failure == .noSpeech ? .noSpeech : .generic(String(localized: "Не удалось распознать речь. Попробуйте ещё раз или введите текстом.")))
            } else {
                finishRecognition(store: store)
            }
        }
    }

    /// Автоостановка: тишина 1,8 с после начала речи или 30 секунд записи.
    private func startWatchdog(autoStop: Bool) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.phase == .listening else { return }
                let silence = Date().timeIntervalSince(self.lastChange)
                let total = Date().timeIntervalSince(self.startedAt)
                if (autoStop && !self.transcript.isEmpty && silence > 1.8) || total > 30 {
                    self.stop()
                    return
                }
            }
        }
    }

    func stop() {
        guard phase == .listening else { return }
        watchdog?.cancel()
        phase = .processing
        level = 0
        Haptics.soft()
        engine.stop()
    }

    func cancel() {
        watchdog?.cancel()
        listenTask?.cancel()
        engine.cancel()
        if phase == .listening || phase == .preparing || phase == .processing { phase = .idle }
        level = 0
    }

    private func finishRecognition(store: FinanceStore) {
        guard phase == .listening || phase == .processing else { return }
        watchdog?.cancel()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed(.noSpeech)
            return
        }
        parse(text, store: store)
    }

    // MARK: - Разбор и проверка

    func parse(_ text: String, store: FinanceStore) {
        transcript = text
        let result = store.voiceParser().parse(text)
        guard !result.drafts.isEmpty else {
            drafts = []
            phase = .failed(.nothingRecognized)
            Haptics.warning()
            return
        }
        drafts = result.drafts
        suggestedCategories = Dictionary(uniqueKeysWithValues: result.drafts.map { ($0.id, $0.categoryID) })
        phase = .review
        if result.drafts.allSatisfy(\.isReady) { Haptics.success() } else { Haptics.warning() }
    }

    func submitTyped(store: FinanceStore) {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        parse(text, store: store)
    }

    func update(_ draft: VoiceDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft
    }

    func remove(_ draft: VoiceDraft) {
        drafts.removeAll { $0.id == draft.id }
        if drafts.isEmpty { phase = .idle }
    }

    /// Сохраняет все черновики одной транзакцией. Только после явного подтверждения пользователем.
    func saveAll(store: FinanceStore) throws -> Int {
        let accounts = store.accountMap
        let transactions = drafts.compactMap { $0.makeTransaction(accounts: accounts) }
        guard transactions.count == drafts.count else {
            throw AppError(String(localized: "Не все операции заполнены."))
        }
        try store.insert(batch: transactions)
        for draft in drafts {
            if let original = suggestedCategories[draft.id], original != draft.categoryID {
                store.learnCategory(merchant: draft.merchant, categoryID: draft.categoryID)
            }
        }
        let count = transactions.count
        reset()
        return count
    }

    func reset() {
        cancel()
        drafts = []
        transcript = ""
        typedText = ""
        levels = []
        phase = .idle
    }
}
