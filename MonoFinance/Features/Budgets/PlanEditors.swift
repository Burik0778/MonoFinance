import SwiftUI
import MonoCore

// MARK: - Бюджет

/// Бюджет: общий лимит месяца или лимит категории, с необязательным переносом остатка.
struct BudgetEditorView: View {
    let budget: Budget?

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter

    @State private var categoryID: UUID?
    @State private var amountText = ""
    @State private var rollover = false
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var loaded = false

    private var isNew: Bool { budget == nil }
    private var currency: Currency { budget?.limit.currency ?? store.baseCurrency }

    /// Категории без активного бюджета (у каждой категории — не больше одного).
    private var availableCategories: [FinanceCategory] {
        let taken = Set(store.budgets.filter { !$0.isArchived && $0.id != budget?.id }.compactMap(\.categoryID))
        return store.categories(for: .expense).filter { !taken.contains($0.id) }
    }

    private var overallTaken: Bool {
        store.budgets.contains { !$0.isArchived && $0.isOverall && $0.id != budget?.id }
    }

    var body: some View {
        EditorScaffold(title: isNew ? "Новый бюджет" : "Бюджет", canSave: AmountField.parse(amountText, currency: currency) != nil && (categoryID != nil || !overallTaken),
                       error: error, onSave: save) {
            FormSection(title: "Лимит в месяц", footer: "Считается в основной валюте; операции в других валютах пересчитываются по курсу.") {
                AmountField(text: $amountText, currency: currency)
            }

            FormSection(title: "Что ограничиваем") {
                VStack(spacing: 10) {
                    if !overallTaken {
                        Button {
                            Haptics.selection()
                            withMonoAnimation(.quick) { categoryID = nil }
                        } label: {
                            FormRow(icon: "circle.hexagongrid.fill", tint: Color.mono.electric, title: "Все расходы месяца",
                                    subtitle: Text("Общий лимит, включая комиссии")) {
                                if categoryID == nil {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mono.electric)
                                }
                            }
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                        }
                        .buttonStyle(.plain)
                    }
                    CategoryGridPicker(categories: availableCategories, selection: $categoryID, allowsNone: false)
                }
            }

            ToggleRow(title: "Переносить остаток", subtitle: "Неистраченное в этом месяце добавится к лимиту следующего.", isOn: $rollover, tint: Color.mono.violet)

            if !isNew {
                Button("Удалить бюджет", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(SecondaryButtonStyle(tint: Color.mono.coral))
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Удалить бюджет?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let budget else { return }
                do {
                    try store.deleteBudget(budget)
                    Haptics.warning()
                    dismiss()
                } catch {
                    self.error = AppError(error).message
                }
            }
        } message: {
            Text("Операции не изменятся — удалится только лимит.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let budget {
            categoryID = budget.categoryID
            amountText = formatter.editableString(budget.limit)
            rollover = budget.rolloverEnabled
        } else if overallTaken {
            categoryID = availableCategories.first?.id
        }
    }

    private func save() {
        guard let limit = AmountField.parse(amountText, currency: currency) else {
            error = String(localized: "Введите сумму лимита.")
            return
        }
        var item = budget ?? Budget(categoryID: categoryID, limit: limit, startMonth: store.periods.monthKey(Date()))
        item.categoryID = categoryID
        item.limit = limit
        item.rolloverEnabled = rollover
        do {
            try store.saveBudget(item)
            Haptics.success()
            toasts.show(ToastMessage(text: isNew ? String(localized: "Бюджет создан") : String(localized: "Бюджет сохранён"), symbol: "chart.bar.fill"))
            dismiss()
        } catch {
            self.error = AppError(error).message
            Haptics.error()
        }
    }
}

// MARK: - Цель

struct GoalEditorView: View {
    let goal: Goal?

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter

    @State private var name = ""
    @State private var amountText = ""
    @State private var currency: Currency = .uzs
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var icon = "star.fill"
    @State private var color: CategoryColor = .violet
    @State private var trackAccount = false
    @State private var linkedAccountID: UUID?
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var loaded = false

    static let symbols = ["star.fill", "airplane", "car.fill", "house.fill", "graduationcap.fill", "gift.fill", "heart.fill",
                          "laptopcomputer", "iphone", "camera.fill", "bicycle", "beach.umbrella.fill", "shield.lefthalf.filled",
                          "figure.2.and.child.holdinghands", "pawprint.fill", "sparkles"]

    private var isNew: Bool { goal == nil }

    private var currencies: [Currency] {
        var list = [store.baseCurrency]
        for account in store.activeAccounts where !list.contains(account.currency) { list.append(account.currency) }
        for code in [Currency.usd, .eur] where !list.contains(code) { list.append(code) }
        return list
    }

    var body: some View {
        EditorScaffold(title: isNew ? "Новая цель" : "Цель", saveColors: [color.color, Color.mono.electric],
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && AmountField.parse(amountText, currency: currency) != nil,
                       error: error, onSave: save) {
            HStack(spacing: 14) {
                CategoryGlyph(icon: icon, color: color.color, size: 56)
                MonoTextField(title: "Название цели", text: $name, systemImage: nil)
            }

            FormSection(title: "Сколько нужно") {
                HStack(spacing: 10) {
                    AmountField(text: $amountText, currency: currency)
                    CurrencyMenu(selection: $currency, options: currencies)
                        .disabled(!isNew && !(store.contributions.filter { $0.goalID == goal?.id }.isEmpty))
                }
            }

            VStack(spacing: 10) {
                ToggleRow(title: "Срок", subtitle: "MONO посчитает, сколько откладывать в месяц.", isOn: $hasDeadline, tint: color.color)
                if hasDeadline {
                    DatePicker("Дата", selection: $deadline, in: Date()..., displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .tint(color.color)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .monoAnimation(.standard, value: hasDeadline)

            FormSection(title: "Как считать накопленное",
                        footer: trackAccount ? "Прогресс — это текущий баланс выбранного счёта (например, вклада)." : "Отмечайте взносы вручную. Деньги при этом остаются на ваших счетах — это пометка, а не перевод.") {
                VStack(spacing: 10) {
                    ToggleRow(title: "По балансу счёта", isOn: $trackAccount, tint: color.color)
                    if trackAccount {
                        AccountPickerMenu(accounts: store.activeAccounts, selection: $linkedAccountID)
                    }
                }
            }

            FormSection(title: "Значок") {
                SymbolPicker(selection: $icon, symbols: Self.symbols, tint: color.color)
            }

            FormSection(title: "Цвет") {
                ColorSwatchPicker(selection: $color)
            }

            if !isNew {
                Button("Удалить цель", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(SecondaryButtonStyle(tint: Color.mono.coral))
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Удалить цель?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let goal else { return }
                do {
                    try store.deleteGoal(goal)
                    Haptics.warning()
                    dismiss()
                } catch {
                    self.error = AppError(error).message
                }
            }
        } message: {
            Text("Взносы цели тоже удалятся. Счета и операции не изменятся.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        currency = store.baseCurrency
        guard let goal else { return }
        name = goal.name
        currency = goal.target.currency
        amountText = formatter.editableString(goal.target)
        if let date = goal.deadline {
            hasDeadline = true
            deadline = date
        }
        icon = goal.icon
        color = goal.color
        trackAccount = goal.linkedAccountID != nil
        linkedAccountID = goal.linkedAccountID
    }

    private func save() {
        guard let target = AmountField.parse(amountText, currency: currency) else {
            error = String(localized: "Введите сумму цели.")
            return
        }
        if trackAccount && linkedAccountID == nil {
            error = String(localized: "Выберите счёт или отключите «По балансу счёта».")
            return
        }
        var item = goal ?? Goal(name: name, target: target)
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.target = target
        item.deadline = hasDeadline ? deadline : nil
        item.icon = icon
        item.color = color
        item.linkedAccountID = trackAccount ? linkedAccountID : nil
        do {
            try store.saveGoal(item)
            Haptics.success()
            toasts.show(ToastMessage(text: isNew ? String(localized: "Цель создана") : String(localized: "Цель сохранена"), symbol: icon, tint: color.color))
            dismiss()
        } catch {
            self.error = AppError(error).message
            Haptics.error()
        }
    }
}

// MARK: - Взнос в цель

struct ContributionEditorView: View {
    let goal: Goal

    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var withdraw = false
    @State private var date = Date()
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        EditorScaffold(title: "Взнос", saveColors: [goal.color.color, Color.mono.electric],
                       canSave: AmountField.parse(amountText, currency: goal.target.currency) != nil, error: error, onSave: save) {
            HStack(spacing: 12) {
                CategoryGlyph(icon: goal.icon, color: goal.color.color, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Kicker("Цель")
                    Text(verbatim: goal.name)
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textPrimary)
                }
            }
            SegmentedPills(options: [false, true], selection: $withdraw,
                           title: { $0 ? String(localized: "Забрать") : String(localized: "Отложить") }, stretch: true)
            AmountField(text: $amountText, currency: goal.target.currency, tint: withdraw ? Color.mono.coral : Color.mono.textPrimary)
            DatePicker(selection: $date, in: ...Date()) {
                Label("Дата", systemImage: "calendar")
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            .tint(goal.color.color)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
            MonoTextField(title: "Комментарий", text: $note, systemImage: "text.alignleft")
            Text("Взнос — пометка о накоплении. Деньги остаются на ваших счетах; балансы не меняются.")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
        }
    }

    private func save() {
        guard let amount = AmountField.parse(amountText, currency: goal.target.currency) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let contribution = GoalContribution(goalID: goal.id, amount: withdraw ? amount.negated : amount, date: date,
                                            note: trimmed.isEmpty ? nil : trimmed)
        do {
            try store.addContribution(contribution)
            Haptics.success()
            dismiss()
        } catch {
            self.error = AppError(error).message
        }
    }
}

// MARK: - Запланированная трата

struct PlannedEditorView: View {
    let item: PlannedExpense?

    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter

    @State private var title = ""
    @State private var amountText = ""
    @State private var currency: Currency = .uzs
    @State private var date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var categoryID: UUID?
    @State private var note = ""
    @State private var completed = false
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var loaded = false

    private var isNew: Bool { item == nil }

    var body: some View {
        EditorScaffold(title: isNew ? "Запланировать трату" : "Запланированная трата", saveColors: [Color.mono.tangerine, Color.mono.coral],
                       canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty && AmountField.parse(amountText, currency: currency) != nil,
                       error: error, onSave: save) {
            MonoTextField(title: "Что планируете", text: $title, systemImage: "calendar.badge.plus")
            HStack(spacing: 10) {
                AmountField(text: $amountText, currency: currency)
                CurrencyMenu(selection: $currency, options: Array(Set([store.baseCurrency] + store.activeAccounts.map(\.currency))).sorted())
            }
            DatePicker(selection: $date, displayedComponents: [.date]) {
                Label("Когда", systemImage: "calendar")
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            .tint(Color.mono.tangerine)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
            FormSection(title: "Категория") {
                CategoryGridPicker(categories: store.categories(for: .expense), selection: $categoryID)
            }
            MonoTextField(title: "Заметка", text: $note, systemImage: "text.alignleft")
            if !isNew {
                ToggleRow(title: "Выполнено", isOn: $completed, tint: Color.mono.emerald)
                Button("Удалить", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(SecondaryButtonStyle(tint: Color.mono.coral))
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Удалить запланированную трату?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let item else { return }
                try? store.deletePlanned(item)
                dismiss()
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        currency = store.baseCurrency
        guard let item else { return }
        title = item.title
        currency = item.amount.currency
        amountText = formatter.editableString(item.amount)
        date = item.date
        categoryID = item.categoryID
        note = item.note ?? ""
        completed = item.isCompleted
    }

    private func save() {
        guard let amount = AmountField.parse(amountText, currency: currency) else { return }
        var value = item ?? PlannedExpense(title: title, amount: amount, date: date)
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.amount = amount
        value.date = date
        value.categoryID = categoryID
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = trimmed.isEmpty ? nil : trimmed
        value.isCompleted = completed
        do {
            try store.savePlanned(value)
            Haptics.success()
            dismiss()
        } catch {
            self.error = AppError(error).message
        }
    }
}
