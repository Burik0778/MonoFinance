import SwiftUI
import MonoCore
import MonoAnalytics

/// Главный экран — и единственный «корневой». Отвечает на два вопроса: сколько у меня денег и что я потратил.
/// Сверху выбор счёта, крупный баланс и одна строка месяца; дальше — лента операций по дням.
/// Статистика, планы, поиск и настройки открываются отсюда, но не занимают место на экране.
struct OverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("home.accountScope") private var scopeID = ""
    @State private var showsScope = DebugFlags.showsScopeSheet

    /// Выбранный счёт или `nil` — все счета.
    private var scopeAccount: Account? {
        guard let id = UUID(uuidString: scopeID), let account = store.accountMap[id], !account.isArchived else { return nil }
        return account
    }

    var body: some View {
        let now = Date()
        let account = scopeAccount
        let scoped = account.map { store.transactions(for: $0) } ?? store.transactions
        let analytics = account == nil
            ? store.analytics()
            : AnalyticsEngine(transactions: scoped, accounts: store.accounts, categories: store.categories, converter: store.converter, periods: store.periods)
        let month = analytics.summary(store.periods.range(for: .thisMonth, now: now))
        let total = analytics.totalBalance()

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeTopBar(account: account, onScope: { showsScope = true })
                if store.isDemo {
                    DemoBanner { environment.setDemoMode(false) }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                if store.activeAccounts.isEmpty {
                    EmptyStateView(symbol: "creditcard", title: "Добавьте первый счёт",
                                   message: "Карта, вклад или наличные. Укажите реальный остаток — дальше MONO посчитает всё сам.") {
                        Button("Добавить счёт") { router.present(.account(nil)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: 260)
                    }
                    .padding(.top, 60)
                } else {
                    HomeHero(account: account,
                             balance: account.map { store.balance(of: $0) } ?? total.total,
                             excluded: account == nil ? total.excluded : [],
                             month: month, now: now)
                        .padding(.top, 36)
                        .riseIn()
                    if account == nil {
                        MonthLimitLine(now: now)
                            .padding(.top, 24)
                    }
                    DueRecurringSection(now: now)
                        .padding(.top, 20)
                    HomeFeed(transactions: scoped.filter { !$0.isOpeningBalance }, account: account, now: now)
                        .padding(.top, 20)
                        .riseIn(delay: 0.06)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.35), value: scopeID)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(DebugFlags.scrollAnchor)
        .background(MonoBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { store.reload() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.activeAccounts.isEmpty {
                CommandBar(
                    onVoice: { router.present(.voice(prefill: nil)) },
                    onManual: { router.newTransaction(.expense, accountID: account?.id) },
                    onIncome: { router.newTransaction(.income, accountID: account?.id) },
                    onTransfer: { router.newTransaction(.transfer, accountID: account?.id) },
                    onImport: { router.present(.importStatement(account)) }
                )
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showsScope) {
            AccountScopeSheet(selection: $scopeID)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.mono.backgroundRaised)
                .presentationCornerRadius(MonoTokens.Radius.xxl)
        }
    }
}

// MARK: - Шапка

/// Слева — выбор счёта, справа — поиск, статистика и настройки в одной капсуле.
private struct HomeTopBar: View {
    let account: Account?
    let onScope: () -> Void

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.selection()
                onScope()
            } label: {
                HStack(spacing: 10) {
                    if let account {
                        CardThumbnail(skin: account.skin, width: 30)
                    } else {
                        StackedThumbnails(skins: store.activeAccounts.prefix(3).map(\.skin))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: account?.displayName ?? Phrase(ru: "Все счета", uz: "Barcha hisoblar", en: "All accounts")(language))
                            .monoFont(.subhead)
                            .foregroundStyle(Color.mono.textPrimary)
                            .lineLimit(1)
                        Text(verbatim: subtitle)
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.mono.textTertiary)
                }
                .padding(.leading, 8)
                .padding(.trailing, 14)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(Color.mono.surface1))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .accessibilityLabel(Text("Выбрать счёт"))

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                toolbarIcon("magnifyingglass", label: "Поиск") { router.open(.history) }
                toolbarIcon("chart.bar", label: "Статистика") { router.open(.analytics) }
                toolbarIcon("gearshape", label: "Настройки") { router.open(.settings) }
            }
            .padding(.horizontal, 4)
            .background(Capsule(style: .continuous).fill(Color.mono.surface1))
        }
    }

    private var subtitle: String {
        if let account {
            var parts = [account.bank.isBank ? account.bank.shortName : account.kind.title(language)]
            if let masked = account.maskedNumber { parts.append(masked) }
            return parts.joined(separator: " · ")
        }
        let count = store.activeAccounts.count
        return Phrase(ru: "\(count) \(Self.accountsWord(count))", uz: "\(count) ta hisob", en: "\(count) accounts")(language)
    }

    private static func accountsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "счёт" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "счёта" }
        return "счетов"
    }

    private func toolbarIcon(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.mono.textPrimary)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(Text(label))
    }
}

/// Миниатюры нескольких карт веером — знак «все счета».
private struct StackedThumbnails: View {
    let skins: [CardSkin]

    var body: some View {
        ZStack {
            ForEach(Array(skins.enumerated().reversed()), id: \.offset) { index, skin in
                CardThumbnail(skin: skin, width: 26)
                    .offset(x: CGFloat(index) * 3, y: CGFloat(index) * -3)
            }
        }
        .frame(width: 32, height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - Баланс и месяц

private struct HomeHero: View {
    let account: Account?
    let balance: Money
    let excluded: Set<Currency>
    let month: PeriodSummary
    let now: Date

    @Environment(SettingsStore.self) private var settings
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Показанная сумма: при открытии «накручивается» от нуля, при смене счёта — перекатывается цифрами.
    @State private var shown: Money?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(account == nil ? "Всего на счетах" : "Баланс счёта")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textTertiary)
                    Button {
                        Haptics.soft()
                        withMonoAnimation(.quick) { settings.hideAmounts.toggle() }
                    } label: {
                        Image(systemName: settings.hideAmounts ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.mono.textTertiary)
                            .frame(width: 28, height: 22)
                            .contentShape(Rectangle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.hideAmounts ? Text("Показать суммы") : Text("Скрыть суммы"))
                }
                HeroAmount(money: shown ?? balance)
                    .onAppear {
                        guard shown == nil, !reduceMotion else { return }
                        shown = Money.zero(balance.currency)
                        withAnimation(.smooth(duration: 1.1).delay(0.1)) { shown = balance }
                    }
                    .onChange(of: balance) { _, value in
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { shown = value }
                    }
                    .onTapGesture(count: 2) {
                        Haptics.soft()
                        withMonoAnimation(.quick) { settings.hideAmounts.toggle() }
                    }
                if !excluded.isEmpty {
                    Button { router.open(.exchangeRates) } label: {
                        Label {
                            Text("Без курса: \(excluded.map(\.code).sorted().joined(separator: ", ")) — не в итоге")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.warning)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 22) {
                figure(symbol: "arrow.down.left", money: month.income, sign: .always,
                       tint: month.income.isZero ? Color.mono.textSecondary : Color.mono.positive)
                figure(symbol: "arrow.up.right", money: month.outflow, sign: .never, tint: Color.mono.textPrimary)
                Spacer(minLength: 0)
                Text(verbatim: DateFormatting.monthTitle(store.periods.monthKey(now), calendar: store.periods.calendar, language: language, includeYear: false))
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func figure(symbol: String, money: Money, sign: MoneyFormatter.SignDisplay, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.opacity(0.14)))
            MoneyText(money: money, token: .subhead, sign: sign, color: tint, compact: true)
        }
    }
}

/// Лимит месяца одной строкой — только если он задан. Нажатие открывает планы.
private struct MonthLimitLine: View {
    let now: Date
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let statuses = store.analytics().budgetStatuses(store.budgets, month: store.periods.monthKey(now), now: now)
        if let status = statuses.first(where: { $0.budget.isOverall }) {
            Button {
                Haptics.selection()
                router.open(.plans)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(status.remaining.isNegative ? "Лимит превышен на" : "Осталось")
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.textSecondary)
                        MoneyText(money: status.remaining.magnitude, token: .subhead,
                                  color: status.remaining.isNegative ? Color.mono.negative : Color.mono.textPrimary, compact: true)
                        Spacer(minLength: 8)
                        if let daily = status.dailyAllowance, !status.remaining.isNegative {
                            MoneyText(money: daily, token: .caption, color: Color.mono.textTertiary, compact: true)
                            Text("в день")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                                .fixedSize()
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                    ProgressTrack(progress: status.progress, tint: status.state.tint, height: 4)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.mono.surface1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
    }
}

// MARK: - Лента

/// Последние операции по дням: название дня и итог трат дня, строки без карточек — на фоне, через волосяные линии.
private struct HomeFeed: View {
    let transactions: [FinanceTransaction]
    let account: Account?
    let now: Date

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language

    private static let limit = 60

    var body: some View {
        let shown = Array(transactions.prefix(Self.limit))
        let groups = group(shown)
        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.mono.accentText)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.mono.surface1))
                    Text("Операций пока нет")
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("Нажмите на микрофон и скажите, например: «Потратил 85 тысяч на обед».")
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            }
            ForEach(groups, id: \.day) { group in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: DateFormatting.dayTitle(group.day, now: now, calendar: store.periods.calendar, language: language))
                        .monoFont(.subhead)
                        .foregroundStyle(Color.mono.textSecondary)
                    Spacer()
                    if group.spending.minorUnits > 0 {
                        MoneyText(money: group.spending.negated, token: .caption, color: Color.mono.textTertiary)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 10)
                VStack(spacing: 6) {
                    ForEach(group.items) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(
                                transaction: transaction,
                                category: transaction.categoryID.flatMap { store.categoryMap[$0] },
                                account: store.accountMap[transaction.accountID],
                                counterAccount: transaction.counterAccountID.flatMap { store.accountMap[$0] },
                                calendar: store.periods.calendar
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.mono.surface1))
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.975))
                        .contextMenu { menu(for: transaction) }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        ))
                    }
                }
            }
            if transactions.count > Self.limit || !shown.isEmpty {
                Button {
                    Haptics.selection()
                    router.open(account.map { Route.filteredTransactions(TransactionFilter(accountID: $0.id)) } ?? Route.history)
                } label: {
                    HStack(spacing: 6) {
                        Text("Вся история")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .monoFont(.subhead)
                    .foregroundStyle(Color.mono.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: shown.map(\.id))
    }

    @ViewBuilder
    private func menu(for transaction: FinanceTransaction) -> some View {
        if !transaction.isOpeningBalance {
            Button { router.present(.transaction(TransactionEditorContext(existingID: transaction.id, kind: transaction.kind))) } label: {
                Label("Изменить", systemImage: "pencil")
            }
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
        }
        Button(role: .destructive) { delete(transaction) } label: {
            Label("Удалить", systemImage: "trash")
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
    }

    private struct DayGroup {
        let day: Date
        let items: [FinanceTransaction]
        let spending: Money
    }

    /// Итог дня — как в аналитике: расходы и комиссии минус возвраты; переводы не учитываются.
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
            for item in items {
                guard let base = converter.toBase(item.amount.magnitude) else { continue }
                switch item.kind {
                case .expense, .fee: spending += base
                case .refund: spending -= base
                default: break
                }
            }
            return DayGroup(day: day, items: items, spending: spending)
        }
    }
}
