import SwiftUI
import MonoCore
import MonoIntelligence

/// Финансовый ассистент. Все числа считает локальный `AssistantEngine` по реальным операциям.
/// Внешняя модель (если пользователь сам подключил свой сервер и дал согласие) только поясняет уже посчитанный ответ.
struct AssistantView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    @State private var exchanges: [Exchange] = []
    @State private var question = ""
    @FocusState private var inputFocused: Bool

    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let answer: AssistantAnswer
        var explanation: String?
        var explaining = false
        var explanationError: String?
    }

    private var remoteAvailable: Bool {
        settings.llmEnabled && settings.llmConsent && URL(string: settings.llmEndpoint)?.scheme == "https"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            intro
                            ForEach($exchanges) { $exchange in
                                ExchangeView(exchange: $exchange, remoteAvailable: remoteAvailable, onOpen: open)
                                    .id(exchange.id)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            if exchanges.isEmpty { suggestions }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: exchanges.count) { _, _ in
                        guard let last = exchanges.last else { return }
                        withMonoAnimation(.standard) { proxy.scrollTo(last.id, anchor: .top) }
                    }
                }
                inputBar
            }
            .background(MonoBackdrop(haze: true).ignoresSafeArea())
            .navigationTitle(Text("Спросить MONO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                if !exchanges.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withMonoAnimation(.standard) { exchanges.removeAll() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel(Text("Начать заново"))
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Ассистент", color: Color.mono.accentText)
            Text("Спросите о своих деньгах")
                .monoFont(.display)
                .foregroundStyle(Color.mono.textPrimary)
            Text("Ответы считаются на устройстве по вашим операциям. Если данных нет — я так и скажу.")
                .monoFont(.callout)
                .foregroundStyle(Color.mono.textSecondary)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker("Например")
                .padding(.bottom, 6)
            ForEach(Array(AssistantEngine.suggestions.enumerated()), id: \.offset) { index, phrase in
                Button {
                    ask(phrase(language))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: String(format: "%02d", index + 1))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.mono.accentText)
                        Text(verbatim: phrase(language))
                            .monoFont(.quote)
                            .foregroundStyle(Color.mono.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .hairlineDivider()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ваш вопрос…", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .monoFont(.body)
                .foregroundStyle(Color.mono.textPrimary)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { ask(question) }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule(style: .continuous).fill(Color.mono.surface2))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
            Button {
                ask(question)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.mono.accent))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel(Text("Спросить"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mono.backgroundRaised.opacity(0.92))
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let engine = AssistantEngine(analytics: store.analytics(), budgets: store.budgets, planned: store.planned, language: language, now: Date())
        let answer = engine.ask(trimmed)
        Haptics.soft()
        withMonoAnimation(.standard) {
            exchanges.append(Exchange(question: trimmed, answer: answer))
        }
        question = ""
    }

    private func open(_ row: AssistantAnswer.Row) {
        let route: Route
        if let transactionID = row.transactionID {
            route = .transaction(transactionID)
        } else if let categoryID = row.categoryID {
            route = .filteredTransactions(TransactionFilter(categoryID: categoryID))
        } else {
            return
        }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.open(route)
        }
    }
}

/// Вопрос и ответ: заголовок-цифра, пояснение, строки с долями, оговорки.
private struct ExchangeView: View {
    @Binding var exchange: AssistantView.Exchange
    let remoteAvailable: Bool
    let onOpen: (AssistantAnswer.Row) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.appLanguage) private var language
    @Environment(\.hideAmounts) private var hideAmounts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 40)
                Text(verbatim: exchange.question)
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous).fill(Color.mono.surface3))
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Capsule(style: .continuous)
                        .fill(Color.mono.accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: hideAmounts && exchange.answer.hasData ? "•••" : exchange.answer.headline)
                            .monoFont(.title)
                            .foregroundStyle(exchange.answer.hasData ? Color.mono.textPrimary : Color.mono.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !exchange.answer.text.isEmpty && !hideAmounts {
                            Text(verbatim: exchange.answer.text)
                                .monoFont(.quote)
                                .foregroundStyle(Color.mono.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !exchange.answer.rows.isEmpty && !hideAmounts {
                    VStack(spacing: 0) {
                        ForEach(exchange.answer.rows) { row in
                            Button {
                                onOpen(row)
                            } label: {
                                rowView(row)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            .disabled(row.categoryID == nil && row.transactionID == nil)
                        }
                    }
                    .monoSurface(radius: MonoTokens.Radius.lg, padding: 12)
                }

                if let note = exchange.answer.note {
                    Label { Text(verbatim: note) } icon: { Image(systemName: "info.circle") }
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.warning)
                }

                if let explanation = exchange.explanation {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Пояснение модели", color: Color.mono.accentText)
                        Text(verbatim: explanation)
                            .monoFont(.callout)
                            .foregroundStyle(Color.mono.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Цифры выше посчитаны приложением; модель их только поясняет.")
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.accent.opacity(0.08)))
                } else if remoteAvailable && exchange.answer.hasData && !hideAmounts {
                    Button {
                        Task { await explain() }
                    } label: {
                        HStack(spacing: 6) {
                            if exchange.explaining {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "text.bubble")
                            }
                            Text("Пояснить подробнее")
                        }
                    }
                    .buttonStyle(ChipStyle())
                    .disabled(exchange.explaining)
                    if let error = exchange.explanationError {
                        Text(verbatim: error)
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.negative)
                    }
                }
            }
        }
    }

    private func rowView(_ row: AssistantAnswer.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.title)
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(verbatim: row.value)
                    .monoFont(.amountRow, digits: true)
                    .foregroundStyle(tint(row.tone))
            }
            if let detail = row.detail {
                Text(verbatim: detail)
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
            if let share = row.share {
                ProgressTrack(progress: share, tint: row.tone == .neutral ? Color.mono.accent : tint(row.tone), height: 4)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func tint(_ tone: AssistantAnswer.Row.Tone) -> Color {
        switch tone {
        case .neutral: return Color.mono.textPrimary
        case .positive: return Color.mono.positive
        case .negative: return Color.mono.negative
        }
    }

    /// Отправляет на сервер пользователя только вопрос и уже посчитанные цифры ответа — не операции и не выписки.
    private func explain() async {
        guard let url = URL(string: settings.llmEndpoint), url.scheme == "https" else { return }
        exchange.explaining = true
        exchange.explanationError = nil
        let client = AssistantRemoteClient(endpoint: url, token: KeychainStore.get(KeychainStore.Keys.llmToken))
        do {
            let text = try await client.explain(
                question: exchange.question,
                headline: exchange.answer.headline,
                text: exchange.answer.text,
                facts: exchange.answer.rows.map { "\($0.title): \($0.value)" + ($0.detail.map { " (\($0))" } ?? "") },
                language: language
            )
            withMonoAnimation(.standard) { exchange.explanation = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        } catch {
            exchange.explanationError = String(localized: "Не удалось получить пояснение. Проверьте адрес сервера в настройках ИИ.")
        }
        exchange.explaining = false
    }
}
