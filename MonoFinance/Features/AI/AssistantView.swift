import SwiftUI
import MonoCore
import MonoIntelligence

/// Финансовый ассистент — чат.
///
/// Если включена нейросеть, есть согласие и ключ, вопрос уходит выбранному сервису вместе со сводкой, посчитанной
/// на телефоне (`FinancialSummaryBuilder` + `PrivacySanitizer`). Без сети, без согласия или при ошибке — прежние
/// локальные ответы `AssistantEngine` по реальным операциям.
struct AssistantView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    @State private var exchanges: [Exchange] = []
    @State private var question = ""
    @FocusState private var inputFocused: Bool

    @State private var showPayload = false
    @State private var pendingTask: Task<Void, Never>?

    /// Реплика чата: вопрос и ответ нейросети или локальный ответ.
    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        let question: String
        /// Локальный ответ: без нейросети или если она не ответила.
        var answer: AssistantAnswer?
        /// Ответ нейросети.
        var reply: String?
        /// Кто ответил.
        var providerName: String?
        /// «Groq не ответил — ответил Gemini».
        var notice: String?
        /// Почему нейросеть не ответила.
        var error: String?
        var pending = false
    }

    private var remoteAvailable: Bool { settings.llmReady }

    private var suggestionPhrases: [String] {
        remoteAvailable ? LLMPrompt.suggestions : AssistantEngine.suggestions.map { $0(language) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            intro
                            ForEach(exchanges) { exchange in
                                ExchangeView(exchange: exchange, onOpen: open)
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
                    .onChange(of: exchanges) { _, _ in
                        guard let last = exchanges.last else { return }
                        withMonoAnimation(.standard) { proxy.scrollTo(last.id, anchor: .top) }
                    }
                }
                inputBar
            }
            .background(MonoBackdrop().ignoresSafeArea())
            .navigationTitle(Text("Спросить MONO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                if !exchanges.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            pendingTask?.cancel()
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
        .sheet(isPresented: $showPayload) {
            NavigationStack {
                LLMPayloadPreviewView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { DismissButton() }
                    }
            }
        }
        .onDisappear { pendingTask?.cancel() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Ассистент", color: Color.mono.accentText)
            Text("Спросите о своих деньгах")
                .monoFont(.display)
                .foregroundStyle(Color.mono.textPrimary)
            if remoteAvailable, let provider = settings.llmCandidates.first {
                Text("Отвечает нейросеть \(provider.name) по сводке, посчитанной на телефоне. Операции, карты и имена не отправляются.")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textSecondary)
                Button {
                    showPayload = true
                } label: {
                    Label("Что будет отправлено", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(ChipStyle())
            } else {
                Text("Ответы считаются на устройстве по вашим операциям. Если данных нет — я так и скажу.")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textSecondary)
                if settings.llmEnabled && !settings.llmConsent {
                    Button {
                        showPayload = true
                    } label: {
                        Label("Нейросеть ждёт вашего согласия", systemImage: "sparkles")
                    }
                    .buttonStyle(ChipStyle())
                }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker("Например")
                .padding(.bottom, 6)
            ForEach(Array(suggestionPhrases.enumerated()), id: \.offset) { index, phrase in
                Button {
                    ask(phrase)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: String(format: "%02d", index + 1))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.mono.accentText)
                        Text(verbatim: phrase)
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
        guard !trimmed.isEmpty, !(exchanges.last?.pending ?? false) else { return }
        Haptics.soft()
        question = ""
        guard remoteAvailable else {
            withMonoAnimation(.standard) {
                exchanges.append(Exchange(question: trimmed, answer: localAnswer(trimmed)))
            }
            return
        }
        let exchange = Exchange(question: trimmed, pending: true)
        let history = exchanges.flatMap { item -> [LLMMessage] in
            guard let reply = item.reply else { return [] }
            return [LLMMessage(role: .user, content: item.question), LLMMessage(role: .assistant, content: reply)]
        }
        withMonoAnimation(.standard) { exchanges.append(exchange) }
        let summary = FinancialSummaryBuilder(analytics: store.analytics(), budgets: store.budgets, now: Date()).text()
        let messages = LLMPrompt.messages(summary: summary, history: history, question: trimmed)
        let candidates = settings.llmCandidates
        pendingTask = Task { @MainActor in
            let result = await LLMClient().ask(messages: messages, candidates: candidates)
            guard !Task.isCancelled, let index = exchanges.firstIndex(where: { $0.id == exchange.id }) else { return }
            var updated = exchanges[index]
            updated.pending = false
            switch result {
            case .success(let outcome):
                updated.reply = outcome.value
                updated.providerName = outcome.provider.name
                if !outcome.skipped.isEmpty {
                    let names = outcome.skipped.map(\.name).joined(separator: ", ")
                    updated.notice = String(localized: "\(names) не ответил — ответил \(outcome.provider.name)")
                }
                Haptics.success()
            case .failure(let error):
                updated.error = error.message
                updated.answer = localAnswer(trimmed)
            }
            withMonoAnimation(.standard) { exchanges[index] = updated }
        }
    }

    private func localAnswer(_ question: String) -> AssistantAnswer {
        AssistantEngine(analytics: store.analytics(), budgets: store.budgets, planned: store.planned, language: language, now: Date())
            .ask(question)
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

/// Вопрос и ответ: ответ нейросети или локальный ответ (заголовок-цифра, пояснение, строки с долями, оговорки).
private struct ExchangeView: View {
    let exchange: AssistantView.Exchange
    let onOpen: (AssistantAnswer.Row) -> Void

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

            if exchange.pending {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Нейросеть думает…")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                .padding(.leading, 4)
            }

            if let reply = exchange.reply {
                replyView(reply)
            }

            if let error = exchange.error {
                Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.warning)
            }

            if let answer = exchange.answer {
                localAnswerView(answer)
            }
        }
    }

    private func replyView(_ reply: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule(style: .continuous)
                .fill(Color.mono.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.formatted(reply))
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .blur(radius: hideAmounts ? 6 : 0)
                if let name = exchange.providerName {
                    Text("Ответила нейросеть · \(name)")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                }
                if let notice = exchange.notice {
                    Text(verbatim: notice)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.warning)
                }
            }
        }
    }

    /// Ответ нейросети: жирный и курсив из Markdown, переносы строк сохраняются.
    static func formatted(_ reply: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: reply, options: options)) ?? AttributedString(reply)
    }

    private func localAnswerView(_ answer: AssistantAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Capsule(style: .continuous)
                    .fill(Color.mono.accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: hideAmounts && answer.hasData ? "•••" : answer.headline)
                        .monoFont(.title)
                        .foregroundStyle(answer.hasData ? Color.mono.textPrimary : Color.mono.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !answer.text.isEmpty && !hideAmounts {
                        Text(verbatim: answer.text)
                            .monoFont(.quote)
                            .foregroundStyle(Color.mono.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !answer.rows.isEmpty && !hideAmounts {
                VStack(spacing: 0) {
                    ForEach(answer.rows) { row in
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

            if let note = answer.note {
                Label { Text(verbatim: note) } icon: { Image(systemName: "info.circle") }
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.warning)
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
}
