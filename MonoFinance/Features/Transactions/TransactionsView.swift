import SwiftUI
import MonoCore

/// История операций: поиск, фильтры, группировка по дням с итогом дня, удаление с возможностью вернуть.
struct TransactionsView: View {
    var initialFilter = TransactionFilter()
    var isRoot = true

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language
    @State private var filter = TransactionFilter()
    @State private var showsFilters = false
    @State private var pendingDelete: FinanceTransaction?
    @State private var applied = false

    var body: some View {
        let categories = store.categoryMap
        let accounts = store.accountMap
        let filtered = store.transactions.filter { filter.matches($0, categories: categories, accounts: accounts) }
        let groups = group(filtered)

        List {
            if isRoot {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
            }
            filterChips
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))

            if filtered.isEmpty {
                EmptyStateView(symbol: filter.isActive || !filter.query.isEmpty ? "magnifyingglass" : "list.bullet.rectangle",
                               title: filter.isActive || !filter.query.isEmpty ? "Ничего не найдено" : "Операций пока нет",
                               message: filter.isActive || !filter.query.isEmpty ? "Измените запрос или сбросьте фильтры." : "Скажите в микрофон, например: «Заправился на 300 тысяч» — или добавьте операцию вручную.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.items) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(transaction: transaction,
                                           category: transaction.categoryID.flatMap { categories[$0] },
                                           account: accounts[transaction.accountID],
                                           counterAccount: transaction.counterAccountID.flatMap { accounts[$0] },
                                           calendar: store.periods.calendar)
                        }
                        .listRowBackground(Color.mono.surface1)
                        .listRowSeparatorTint(Color.mono.strokeSubtle)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDelete = transaction } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            Button { router.present(.transaction(TransactionEditorContext(existingID: transaction.id, kind: transaction.kind))) } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                            .tint(Color.mono.accent)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                var copy = transaction
                                copy.id = UUID()
                                copy.date = Date()
                                copy.importFingerprint = nil
                                copy.isOpeningBalance = false
                                copy.source = .manual
                                router.present(.transaction(TransactionEditorContext(kind: transaction.kind, prefill: copy)))
                            } label: {
                                Label("Повторить", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(Color.mono.accent)
                        }
                    }
                } header: {
                    HStack {
                        Text(verbatim: DateFormatting.dayTitle(group.day, calendar: store.periods.calendar, language: language))
                            .monoFont(.subhead)
                            .foregroundStyle(Color.mono.textSecondary)
                        Spacer()
                        if group.spending.minorUnits > 0 {
                            MoneyText(money: group.spending.negated, token: .caption, color: Color.mono.textTertiary)
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.mono.background.ignoresSafeArea())
        .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Магазин, заметка, сумма"))
        .navigationTitle(isRoot ? Text("Операции") : Text("Отобранные операции"))
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showsFilters = true } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(Text("Фильтры"))
                if isRoot {
                    Button { router.newTransaction(.expense) } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Новая операция"))
                }
            }
        }
        .sheet(isPresented: $showsFilters) {
            TransactionFilterSheet(filter: $filter)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.mono.backgroundRaised)
        }
        .confirmationDialog("Удалить операцию?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let transaction = pendingDelete { delete(transaction) }
            }
        } message: {
            if let transaction = pendingDelete, transaction.kind == .transfer, !store.linkedFees(of: transaction).isEmpty {
                Text("Комиссия за этот перевод тоже будет удалена.")
            } else {
                Text("Балансы будут пересчитаны. Удаление сохранится в истории изменений.")
            }
        }
        .onAppear {
            if !applied {
                filter = initialFilter
                applied = true
            }
        }
    }

    private var header: some View {
        let analytics = store.analytics()
        let month = analytics.summary(store.periods.range(for: .thisMonth, now: Date()))
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: DateFormatting.monthTitle(store.periods.monthKey(Date()), calendar: store.periods.calendar, language: language, includeYear: false))
                .monoFont(.subhead)
                .foregroundStyle(Color.mono.textSecondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Расходы")
                    MoneyText(money: month.outflow, token: .title2, color: Color.mono.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Kicker("Доходы")
                    MoneyText(money: month.income, token: .title2, sign: .always, color: Color.mono.positive)
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Все", selected: filter.kinds.isEmpty) { filter.kinds = [] }
                ForEach([TransactionKind.expense, .income, .transfer, .fee, .refund], id: \.self) { kind in
                    chip(LocalizedStringKey(kind.title(language)), selected: filter.kinds.contains(kind)) {
                        if filter.kinds.contains(kind) { filter.kinds.remove(kind) } else { filter.kinds.insert(kind) }
                    }
                }
                chip("Голосом", selected: filter.source == .voice) {
                    filter.source = filter.source == .voice ? nil : .voice
                }
                if filter.isActive {
                    Button {
                        Haptics.tap()
                        filter = TransactionFilter(query: filter.query)
                    } label: {
                        Label("Сбросить", systemImage: "xmark")
                    }
                    .buttonStyle(ChipStyle(tint: Color.mono.negative))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withMonoAnimation(.quick) { action() }
        } label: {
            Text(title)
        }
        .buttonStyle(ChipStyle(isSelected: selected))
    }

    private struct DayGroup {
        let day: Date
        let items: [FinanceTransaction]
        let spending: Money
    }

    private func group(_ transactions: [FinanceTransaction]) -> [DayGroup] {
        let calendar = store.periods.calendar
        let converter = store.converter
        var order: [Date] = []
        var buckets: [Date: [FinanceTransaction]] = [:]
        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(transaction)
        }
        return order.map { day in
            let items = buckets[day] ?? []
            var spending = Money.zero(store.baseCurrency)
            for item in items where item.kind == .expense || item.kind == .fee {
                if let base = converter.toBase(item.amount) { spending += base }
            }
            return DayGroup(day: day, items: items, spending: spending)
        }
    }

    private func delete(_ transaction: FinanceTransaction) {
        let fees = store.linkedFees(of: transaction)
        do {
            try store.delete(transaction)
            Haptics.warning()
            toasts.show(ToastMessage(text: String(localized: "Операция удалена"), symbol: "trash.fill", tint: Color.mono.negative,
                                     actionTitle: String(localized: "Вернуть")) {
                try? store.restore([transaction] + fees)
            })
        } catch {
            toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
        }
        pendingDelete = nil
    }
}

/// Шторка фильтров.
struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var periodChoice: PeriodPreset?
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Период") {
                    Picker("Период", selection: $periodChoice) {
                        Text("Всё время").tag(PeriodPreset?.none)
                        ForEach([PeriodPreset.thisWeek, .thisMonth, .lastMonth, .last90Days, .thisYear], id: \.self) { preset in
                            Text(verbatim: preset.shortTitle(.current)).tag(PeriodPreset?.some(preset))
                        }
                    }
                    .onChange(of: periodChoice) { _, value in
                        filter.range = value.map { store.periods.range(for: $0, now: Date()) }
                    }
                }
                Section("Счёт") {
                    Picker("Счёт", selection: $filter.accountID) {
                        Text("Все счета").tag(UUID?.none)
                        ForEach(store.accounts) { account in
                            Text(verbatim: account.displayName).tag(UUID?.some(account.id))
                        }
                    }
                }
                Section("Категория") {
                    Picker("Категория", selection: $filter.categoryID) {
                        Text("Все категории").tag(UUID?.none)
                        ForEach(store.activeCategories) { category in
                            Label(category.name, systemImage: category.icon).tag(UUID?.some(category.id))
                        }
                    }
                }
                Section("Сумма") {
                    TextField("От", text: $minText).keyboardType(.decimalPad)
                    TextField("До", text: $maxText).keyboardType(.decimalPad)
                }
                Section {
                    Button("Сбросить фильтры", role: .destructive) {
                        filter = TransactionFilter(query: filter.query)
                        periodChoice = nil
                        minText = ""
                        maxText = ""
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        filter.minAmount = MoneyFormatter.parseUserInput(minText, currency: store.baseCurrency)?.majorValue
                        filter.maxAmount = MoneyFormatter.parseUserInput(maxText, currency: store.baseCurrency)?.majorValue
                        dismiss()
                    }
                }
            }
            .onAppear {
                minText = filter.minAmount.map { "\($0)" } ?? ""
                maxText = filter.maxAmount.map { "\($0)" } ?? ""
            }
        }
    }
}
