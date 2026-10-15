import SwiftUI
import UIKit
import MonoCore
import MonoIntelligence

/// Голосовой ввод: сфера, живая расшифровка, черновики с исправлениями, сохранение по подтверждению.
struct VoiceCaptureView: View {
    let prefill: String?

    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = VoiceInputModel()
    @State private var typing = false
    @State private var saveError: String?
    @FocusState private var typedFocused: Bool

    var body: some View {
        ZStack {
            MonoBackdrop()
            VStack(spacing: 0) {
                topBar
                switch model.phase {
                case .review:
                    reviewContent
                default:
                    captureContent
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.phase == .listening || model.phase == .review)
        .task {
            if let prefill, !prefill.isEmpty {
                model.parse(prefill, store: store)
            } else if model.phase == .idle && !DebugFlags.voiceIdle {
                await model.start(store: store, settings: settings)
            }
        }
        .onDisappear { model.cancel() }
    }

    // MARK: - Шапка

    private var topBar: some View {
        HStack {
            IconButton(systemName: "xmark", label: "Закрыть") {
                model.cancel()
                dismiss()
            }
            Spacer()
            VStack(spacing: 2) {
                Kicker("Голосовой ввод")
                HStack(spacing: 6) {
                    Text(verbatim: settings.speechLanguage.nativeName)
                    Text(verbatim: "·")
                    Image(systemName: model.usesOnDevice ? "lock.iphone" : "icloud")
                    Text(model.usesOnDevice ? "на устройстве" : "серверы Apple")
                }
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
            }
            Spacer()
            IconButton(systemName: typing ? "mic.fill" : "keyboard", label: typing ? "Голосом" : "Ввести текстом") {
                withMonoAnimation(.quick) { typing.toggle() }
                if typing {
                    model.cancel()
                    typedFocused = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Запись

    private var captureContent: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            if typing {
                typedInput
            } else {
                Button {
                    switch model.phase {
                    case .listening: model.stop()
                    case .processing: break
                    default: Task { await model.start(store: store, settings: settings) }
                    }
                } label: {
                    VoiceOrb(level: model.level, isActive: model.phase == .listening, levels: model.levels)
                        .frame(width: 270, height: 270)
                        .overlay {
                            Image(systemName: model.phase == .listening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Color.mono.onAccent)
                                .contentTransition(.symbolEffect(.replace))
                        }
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityLabel(model.phase == .listening ? Text("Остановить запись") : Text("Начать запись"))

                statusLine
                transcriptView
            }
            if case .failed(let failure) = model.phase {
                failureView(failure)
            }
            Spacer(minLength: 8)
            bottomButtons
        }
        .padding(.bottom, 20)
    }

    /// Состояние записи одной строкой: «Слушаю», «Разбираю», «Нажмите, чтобы говорить».
    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.phase == .listening ? Color.mono.negative : Color.mono.textTertiary)
                .frame(width: 7, height: 7)
                .opacity(model.phase == .listening ? 1 : 0.6)
            Group {
                switch model.phase {
                case .listening: Text("Слушаю")
                case .processing, .preparing: Text("Разбираю фразу")
                default: Text("Нажмите и говорите")
                }
            }
            .textCase(.uppercase)
            .monoFont(.kicker)
            .foregroundStyle(model.phase == .listening ? Color.mono.textPrimary : Color.mono.textTertiary)
        }
        .monoAnimation(.quick, value: model.phase)
        .accessibilityElement(children: .combine)
    }

    private var transcriptView: some View {
        Group {
            if model.transcript.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Self.examples, id: \.self) { example in
                        Text(verbatim: "«\(example)»")
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Text(verbatim: model.transcript)
                    .monoFont(.title)
                    .foregroundStyle(Color.mono.textPrimary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .monoAnimation(.quick, value: model.transcript)
            }
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 96)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private static let examples = [
        "Потратил 85 тысяч на обед",
        "Вчера купил продукты на 230 тысяч с Капиталбанка",
        "Перевёл миллион сум с Капиталбанка на Узум"
    ]

    private var typedInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Фраза текстом")
            TextField("Например: потратил 120 тысяч на такси и 75 тысяч на кофе", text: $model.typedText, axis: .vertical)
                .monoFont(.quote)
                .foregroundStyle(Color.mono.textPrimary)
                .lineLimit(3...6)
                .focused($typedFocused)
                .submitLabel(.done)
                .onSubmit { model.submitTyped(store: store) }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous).fill(Color.mono.surface1))
                .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous).strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
            Text("Тот же разбор, что и для голоса. Подходит для узбекского и тех случаев, когда говорить неудобно.")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
        }
        .padding(.horizontal, 20)
    }

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            if typing {
                Button("Разобрать фразу") { model.submitTyped(store: store) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.typedText.trimmingCharacters(in: .whitespaces).isEmpty)
            } else if model.phase == .listening {
                Button("Готово") { model.stop() }
                    .buttonStyle(PrimaryButtonStyle())
            } else if model.phase == .processing {
                ProgressView().tint(Color.mono.textPrimary)
            } else if model.phase == .idle {
                Button {
                    model.cancel()
                    withMonoAnimation(.quick) { typing = true }
                    typedFocused = true
                } label: {
                    Label("Ввести фразу текстом", systemImage: "keyboard")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func failureView(_ failure: VoiceInputModel.Failure) -> some View {
        VStack(spacing: 12) {
            Text(verbatim: message(for: failure))
                .monoFont(.callout)
                .foregroundStyle(Color.mono.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                switch failure {
                case .microphoneDenied, .speechDenied:
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(ChipStyle(isSelected: true))
                case .needsServerConsent:
                    Button("Разрешить серверы Apple") {
                        settings.speechServerConsent = true
                        Task { await model.start(store: store, settings: settings) }
                    }
                    .buttonStyle(ChipStyle(isSelected: true))
                default:
                    Button("Повторить") { Task { await model.start(store: store, settings: settings) } }
                        .buttonStyle(ChipStyle(isSelected: true))
                }
                Button("Ввести текстом") {
                    withMonoAnimation(.quick) { typing = true }
                    typedFocused = true
                }
                .buttonStyle(ChipStyle())
            }
        }
        .padding(.horizontal, 24)
    }

    private func message(for failure: VoiceInputModel.Failure) -> String {
        switch failure {
        case .microphoneDenied:
            return String(localized: "Нет доступа к микрофону. Разрешите его в Настройках, чтобы добавлять операции голосом.")
        case .speechDenied:
            return String(localized: "Распознавание речи запрещено. Разрешите его в Настройках или введите фразу текстом.")
        case .restricted:
            return String(localized: "Распознавание речи ограничено на этом устройстве.")
        case .unsupportedLanguage(let language):
            return String(localized: "Системное распознавание речи не поддерживает язык «\(language.nativeName)» на этом устройстве. Введите фразу текстом — разбор работает так же.")
        case .needsServerConsent:
            return String(localized: "На этом устройстве распознавание выбранного языка возможно только через серверы Apple: аудио будет отправлено Apple для расшифровки. Финансовые данные приложения не передаются.")
        case .recognizerUnavailable:
            return String(localized: "Распознаватель сейчас недоступен. Проверьте подключение к интернету или попробуйте позже.")
        case .noSpeech:
            return String(localized: "Не услышал речь. Говорите ближе к микрофону.")
        case .nothingRecognized:
            return String(localized: "Не нашёл в фразе операцию. Назовите сумму и на что потратили, например: «такси 40 тысяч».")
        case .generic(let text):
            return text
        }
    }

    // MARK: - Проверка черновиков

    private var reviewContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Распознано")
                        Text(verbatim: "«\(model.transcript)»")
                            .monoFont(.quote)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                    ForEach(model.drafts) { draft in
                        VoiceDraftCard(draft: draft, onChange: { model.update($0) }, onRemove: {
                            withMonoAnimation(.standard) { model.remove(draft) }
                        })
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
                    }
                    if let saveError {
                        Text(verbatim: saveError)
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.negative)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                Button {
                    save()
                } label: {
                    Text(model.drafts.count == 1 ? "Сохранить операцию" : "Сохранить \(model.drafts.count) операции")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.allReady)
                Button("Записать заново") {
                    model.reset()
                    typing = false
                    Task { await model.start(store: store, settings: settings) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func save() {
        do {
            let count = try model.saveAll(store: store)
            toasts.show(ToastMessage(text: count == 1 ? String(localized: "Операция добавлена") : String(localized: "Добавлено операций: \(count)"),
                                     symbol: "waveform.badge.checkmark", tint: Color.mono.positive))
            Haptics.success()
            dismiss()
        } catch {
            saveError = AppError(error).message
            Haptics.error()
        }
    }
}
