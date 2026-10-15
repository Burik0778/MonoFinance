import SwiftUI
import MonoCore
import MonoAnalytics

/// Все регулярные правила: ближайшие, приостановленные, найденные автоматически.
struct RecurringListView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let now = Date()
        let active = store.recurring.filter(\.isActive).sorted { $0.nextDueDate < $1.nextDueDate }
        let paused = store.recurring.filter { !$0.isActive }
        let candidates = store.analytics().recurringCandidates(now: now)

        List {
            if store.recurring.isEmpty {
                EmptyStateView(symbol: "repeat", title: "Регулярных платежей нет",
                               message: "Аренда, связь, подписки, зарплата. MONO напомнит о дате и предложит записать операцию — без автоматического списания.") {
                    Button("Добавить") { router.present(.recurring(nil)) }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 220)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { rule in
                        row(rule, now: now)
                    }
                } header: {
                    Kicker("Активные")
                }
            }
            if !paused.isEmpty {
                Section {
                    ForEach(paused) { rule in
                        row(rule, now: now)
                    }
                } header: {
                    Kicker("Приостановлены")
                }
            }
            if !candidates.isEmpty {
                Section {
                    RecurringCandidatesCard(candidates: candidates)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Регулярные платежи"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.present(.recurring(nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Новый регулярный платёж"))
            }
        }
    }

    private func row(_ rule: RecurringRule, now: Date) -> some View {
        Button {
            router.present(.recurring(rule))
        } label: {
            RecurringRuleRow(rule: rule, now: now)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.mono.surface1)
        .swipeActions(edge: .trailing) {
            Button(rule.isActive ? "Пауза" : "Включить", systemImage: rule.isActive ? "pause.fill" : "play.fill") {
                var updated = rule
                updated.isActive.toggle()
                if updated.isActive, updated.nextDueDate < store.periods.startOfDay(now) {
                    updated.nextDueDate = RecurrenceMath.nextOccurrence(after: store.periods.startOfDay(now).addingTimeInterval(-1),
                                                                       anchor: rule.anchorDate, frequency: rule.frequency,
                                                                       interval: rule.interval, calendar: store.periods.calendar)
                }
                try? store.saveRecurring(updated)
            }
            .tint(Color.mono.warning)
        }
        .swipeActions(edge: .leading) {
            if rule.isActive {
                Button("Пропустить", systemImage: "forward.end.fill") {
                    try? store.skipRecurring(rule)
                    toasts.show(ToastMessage(text: String(localized: "Ближайший платёж пропущен"), symbol: "forward.end.fill", tint: Color.mono.accent))
                }
                .tint(Color.mono.accent)
            }
        }
    }
}

/// Редактор регулярного правила. Операции по нему создаются только после подтверждения.
struct RecurringEditorView: View {
    let rule: RecurringRule?

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter
    @Environment(\.appLanguage) private var language

    @State private var title = ""
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var merchant = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var anchorDate = Date()
    @State private var reminder = true
    @State private var active = true
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var loaded = false

    /// Правило уже сохранено (а не предложено из найденных повторов).
    private var existing: RecurringRule? { rule.flatMap { candidate in store.recurring.first { $0.id == candidate.id } } }
    private var account: Account? { accountID.flatMap { store.accountMap[$0] } }
    private var currency: Currency { account?.currency ?? store.baseCurrency }

    var body: some View {
        EditorScaffold(title: existing == nil ? "Регулярный платёж" : "Изменение платежа",
                       canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty && AmountField.parse(amountText, currency: currency) != nil && accountID != nil,
                       error: error, onSave: save) {
            SegmentedPills(options: [TransactionKind.expense, .income], selection: $kind, title: { $0.title(language) }, stretch: true)
            MonoTextField(title: "Название (например, «Аренда»)", text: $title, systemImage: "repeat")
            AmountField(text: $amountText, currency: currency, tint: kind == .income ? Color.mono.positive : Color.mono.textPrimary)

            FormSection(title: kind == .income ? "На счёт" : "Со счёта") {
                AccountPickerMenu(accounts: store.activeAccounts, selection: $accountID)
            }

            FormSection(title: "Как часто") {
                VStack(spacing: 10) {
                    SegmentedPills(options: RecurrenceFrequency.allCases, selection: $frequency, title: { $0.title(language) }, stretch: true)
                    Stepper(value: $interval, in: 1...12) {
                        Text(verbatim: intervalText)
                            .monoFont(.body)
                            .foregroundStyle(Color.mono.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                    DatePicker(selection: $anchorDate, displayedComponents: [.date]) {
                        Label("Дата платежа", systemImage: "calendar")
                            .monoFont(.body)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                    .tint(Color.mono.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                    Text(verbatim: nextText)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            FormSection(title: "Категория") {
                CategoryGridPicker(categories: store.categories(for: kind), selection: $categoryID)
            }

            MonoTextField(title: kind == .income ? "От кого" : "Получатель", text: $merchant, systemImage: "storefront")

            ToggleRow(title: "Напоминание", subtitle: "Уведомление в день платежа. Операция создаётся только после вашего подтверждения.", isOn: $reminder)
            if existing != nil {
                ToggleRow(title: "Активно", isOn: $active, tint: Color.mono.positive)
                Button("Удалить", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(SecondaryButtonStyle(tint: Color.mono.negative))
            }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, newKind in
            if let id = categoryID, store.categoryMap[id]?.kind != newKind.categoryKind { categoryID = nil }
        }
        .confirmationDialog("Удалить регулярный платёж?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let existing else { return }
                do {
                    try store.deleteRecurring(existing)
                    dismiss()
                } catch {
                    self.error = AppError(error).message
                }
            }
        } message: {
            Text("Уже записанные операции останутся в истории.")
        }
    }

    private var intervalText: String {
        let unit: String
        switch frequency {
        case .weekly: unit = Phrase(ru: "нед.", uz: "hafta", en: "wk")(language)
        case .monthly: unit = Phrase(ru: "мес.", uz: "oy", en: "mo")(language)
        case .yearly: unit = Phrase(ru: "г.", uz: "yil", en: "yr")(language)
        }
        return interval == 1
            ? frequency.title(language)
            : Phrase(ru: "Каждые \(interval) \(unit)", uz: "Har \(interval) \(unit)", en: "Every \(interval) \(unit)")(language)
    }

    /// Ближайшая дата считается от выбранной даты платежа: 31-е число не «съезжает» после февраля.
    private var nextDue: Date {
        let today = store.periods.startOfDay(Date())
        return RecurrenceMath.nextOccurrence(after: today.addingTimeInterval(-1), anchor: anchorDate, frequency: frequency,
                                             interval: interval, calendar: store.periods.calendar)
    }

    private var nextText: String {
        Phrase(ru: "Ближайший платёж: ", uz: "Keyingi to‘lov: ", en: "Next payment: ")(language)
            + DateFormatting.dayTitle(nextDue, calendar: store.periods.calendar, language: language)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        accountID = store.defaultAccount?.id
        guard let rule else { return }
        title = rule.title
        kind = rule.kind
        amountText = formatter.editableString(rule.amount)
        accountID = store.accountMap[rule.accountID] != nil ? rule.accountID : store.defaultAccount?.id
        categoryID = rule.categoryID
        merchant = rule.merchant ?? ""
        frequency = rule.frequency
        interval = rule.interval
        anchorDate = rule.anchorDate
        reminder = rule.reminderEnabled
        active = rule.isActive
    }

    private func save() {
        guard let accountID, let amount = AmountField.parse(amountText, currency: currency) else {
            error = String(localized: "Укажите сумму и счёт.")
            return
        }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduleChanged = existing.map { $0.anchorDate != anchorDate || $0.frequency != frequency || $0.interval != interval } ?? true
        var value = existing ?? RecurringRule(id: rule?.id ?? UUID(), title: title, amount: amount, accountID: accountID, anchorDate: anchorDate)
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.kind = kind
        value.amount = amount
        value.accountID = accountID
        value.categoryID = categoryID
        value.merchant = trimmedMerchant.isEmpty ? nil : trimmedMerchant
        value.frequency = frequency
        value.interval = interval
        value.anchorDate = anchorDate
        if scheduleChanged { value.nextDueDate = nextDue }
        value.reminderEnabled = reminder
        value.isActive = active
        do {
            try store.saveRecurring(value)
            Haptics.success()
            toasts.show(ToastMessage(text: existing == nil ? String(localized: "Регулярный платёж добавлен") : String(localized: "Сохранено"), symbol: "repeat"))
            dismiss()
        } catch {
            self.error = AppError(error).message
            Haptics.error()
        }
    }
}
