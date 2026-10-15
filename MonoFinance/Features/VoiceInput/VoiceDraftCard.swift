import SwiftUI
import MonoCore
import MonoIntelligence

/// Карточка голосового черновика: что распознано, что нужно уточнить, быстрые исправления.
/// Ничего не сохраняется, пока пользователь не нажмёт «Сохранить».
struct VoiceDraftCard: View {
    let draft: VoiceDraft
    let onChange: (VoiceDraft) -> Void
    let onRemove: () -> Void

    @Environment(FinanceStore.self) private var store
    @Environment(\.moneyFormatter) private var formatter
    @Environment(\.appLanguage) private var language

    @State private var editingAmount = false
    @State private var amountText = ""
    @State private var counterText = ""
    @State private var merchantText = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case amount
        case counter
        case merchant
    }

    private var account: Account? { draft.accountID.flatMap { store.accountMap[$0] } }
    private var destination: Account? { draft.counterAccountID.flatMap { store.accountMap[$0] } }
    private var category: FinanceCategory? { draft.categoryID.flatMap { store.categoryMap[$0] } }
    private var statusTint: Color { draft.isReady ? Color.mono.positive : Color.mono.warning }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Кромка-статус: зелёная — готово, янтарная — нужно уточнить.
            Capsule(style: .continuous)
                .fill(statusTint)
                .frame(width: 2)
                .padding(.vertical, 18)
                .padding(.trailing, 14)
            VStack(alignment: .leading, spacing: 14) {
                header
                amountBlock
                if !draft.sourceText.isEmpty {
                    Text(verbatim: "«\(draft.sourceText)»")
                        .monoFont(.footnote)
                        .italic()
                        .foregroundStyle(Color.mono.textTertiary)
                        .lineLimit(2)
                }
                issuesBlock
                fieldsBlock
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
        }
        .padding(.leading, 12)
        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous).fill(Color.mono.surface1))
        .overlay(
            RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous)
                .strokeBorder(draft.isReady ? Color.mono.strokeSubtle : Color.mono.warning.opacity(0.35), lineWidth: 1)
        )
        .monoAnimation(.standard, value: draft)
        .onAppear(perform: syncTexts)
        .onChange(of: draft) { _, _ in syncTexts() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach([TransactionKind.expense, .income, .transfer, .refund], id: \.self) { option in
                    Button {
                        changeKind(to: option)
                    } label: {
                        Label(option.title(language), systemImage: option.symbol)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: draft.kind.symbol)
                        .font(.system(size: 12, weight: .bold))
                    Text(verbatim: draft.kind.title(language))
                        .monoFont(.kicker)
                        .textCase(.uppercase)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(kindTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(kindTint.opacity(0.14)))
            }
            .accessibilityLabel(Text("Тип операции: \(draft.kind.title(language))"))

            Spacer()

            Label(draft.isReady ? "Готово" : "Уточните", systemImage: draft.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .monoFont(.caption)
                .foregroundStyle(statusTint)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mono.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.mono.surface3))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(Text("Убрать черновик"))
        }
    }

    private var kindTint: Color {
        switch draft.kind {
        case .income, .refund: return Color.mono.positive
        default: return Color.mono.accentText
        }
    }

    // MARK: - Сумма

    private var amountBlock: some View {
        Group {
            if editingAmount || draft.amount == nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .amount)
                        .font(.system(size: 38, weight: .semibold, design: .default).monospacedDigit())
                        .foregroundStyle(Color.mono.textPrimary)
                        .onSubmit(commitAmount)
                    Text(verbatim: formatter.symbol(for: draft.currency).text)
                        .monoFont(.title2)
                        .foregroundStyle(Color.mono.textSecondary)
                    Button("Готово", action: commitAmount)
                        .buttonStyle(ChipStyle(isSelected: true))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface3))
            } else if let amount = draft.amount, let money = Money(major: amount, currency: draft.currency) {
                Button {
                    editingAmount = true
                    focus = .amount
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HeroAmount(money: money, token: .display, secondaryToken: .title2,
                                   color: draft.kind == .income || draft.kind == .refund ? Color.mono.positive : Color.mono.textPrimary)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.mono.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Изменить сумму"))
            }
        }
    }

    private func commitAmount() {
        guard let money = MoneyFormatter.parseUserInput(amountText, currency: draft.currency), money.isPositive else {
            focus = .amount
            return
        }
        mutate { $0.setAmount(money.majorValue, accounts: store.accountMap, converter: store.converter) }
        editingAmount = false
        focus = nil
        Haptics.selection()
    }

    // MARK: - Вопросы и быстрые исправления

    @ViewBuilder
    private var issuesBlock: some View {
        let blocking = draft.blockingIssues
        if !blocking.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocking, id: \.self) { issue in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Color.mono.warning).frame(width: 6, height: 6)
                            Text(verbatim: issue.message(language, formatter: formatter, currency: draft.currency))
                                .monoFont(.callout)
                                .foregroundStyle(Color.mono.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        quickFixes(for: issue)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.warning.opacity(0.08)))
        }
    }

    @ViewBuilder
    private func quickFixes(for issue: VoiceIssue) -> some View {
        switch issue {
        case .amountMayNeedThousands(let suggested):
            FlowLayout(spacing: 8) {
                if let money = Money(major: suggested, currency: draft.currency) {
                    Button(formatter.string(money)) {
                        mutate { $0.setAmount(suggested, accounts: store.accountMap, converter: store.converter) }
                        Haptics.selection()
                    }
                    .buttonStyle(ChipStyle(isSelected: true, tint: Color.mono.accent))
                }
                if let amount = draft.amount, let money = Money(major: amount, currency: draft.currency) {
                    Button(String(localized: "Нет, \(formatter.string(money))")) {
                        mutate { $0.setAmount(amount, accounts: store.accountMap, converter: store.converter) }
                        Haptics.selection()
                    }
                    .buttonStyle(ChipStyle())
                }
            }
        case .missingAmount:
            Button("Ввести сумму") {
                editingAmount = true
                focus = .amount
            }
            .buttonStyle(ChipStyle(isSelected: true))
        case .ambiguousAccount(let candidates):
            FlowLayout(spacing: 8) {
                ForEach(candidates.compactMap { store.accountMap[$0] }) { option in
                    Button(option.displayName) { selectAccount(option) }
                        .buttonStyle(ChipStyle())
                }
            }
        case .currencyMismatch(let spoken, let accountCurrency):
            FlowLayout(spacing: 8) {
                ForEach(store.activeAccounts.filter { $0.currency == spoken }) { option in
                    Button(option.displayName) { selectAccount(option) }
                        .buttonStyle(ChipStyle())
                }
                if let amount = draft.amount, let money = Money(major: amount, currency: spoken),
                   let converted = store.converter.convert(money, to: accountCurrency) {
                    Button(String(localized: "Списано в \(accountCurrency.code) ≈ \(formatter.string(converted))")) {
                        // Сумма в валюте счёта по курсу ЦБ — дальше её можно поправить на фактическую.
                        mutate { draft in
                            draft.currency = accountCurrency
                            draft.setAmount(converted.majorValue, accounts: store.accountMap, converter: store.converter)
                        }
                        editingAmount = true
                        focus = .amount
                    }
                    .buttonStyle(ChipStyle(tint: Color.mono.accent))
                }
            }
        case .accountNotFound, .missingAccount:
            accountChips(selected: draft.accountID, excluding: nil) { selectAccount($0) }
        case .missingDestination, .sameAccount:
            accountChips(selected: draft.counterAccountID, excluding: draft.accountID) { option in
                mutate { $0.selectDestination(option.id, accounts: store.accountMap, converter: store.converter) }
                Haptics.selection()
            }
        case .needsCounterAmount(let suggested):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Зачислено", text: $counterText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .counter)
                        .monoFont(.headline, digits: true)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.sm, style: .continuous).fill(Color.mono.surface3))
                        .onSubmit(commitCounter)
                    Text(verbatim: destination.map { formatter.symbol(for: $0.currency).text } ?? "")
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textSecondary)
                    Button("OK", action: commitCounter)
                        .buttonStyle(ChipStyle(isSelected: true))
                }
                if let suggested, let destination, let money = Money(major: suggested, currency: destination.currency) {
                    Button(String(localized: "По курсу ЦБ: \(formatter.string(money))")) {
                        counterText = formatter.editableString(money)
                        commitCounter()
                    }
                    .buttonStyle(ChipStyle(tint: Color.mono.accent))
                }
            }
        default:
            EmptyView()
        }
    }

    private func accountChips(selected: UUID?, excluding: UUID?, action: @escaping (Account) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(store.activeAccounts.filter { $0.id != excluding }) { option in
                Button {
                    action(option)
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(option.skin.linearGradient)
                            .frame(width: 16, height: 11)
                        Text(verbatim: option.displayName)
                    }
                }
                .buttonStyle(ChipStyle(isSelected: option.id == selected))
            }
        }
    }

    private func commitCounter() {
        guard let destination,
              let money = MoneyFormatter.parseUserInput(counterText, currency: destination.currency), money.isPositive else {
            focus = .counter
            return
        }
        mutate { draft in
            draft.counterAmount = money.majorValue
            draft.revalidate(accounts: store.accountMap, converter: store.converter)
        }
        focus = nil
        Haptics.selection()
    }

    // MARK: - Поля

    private var fieldsBlock: some View {
        VStack(spacing: 0) {
            fieldRow(title: draft.kind == .transfer ? "Откуда" : (draft.kind == .income || draft.kind == .refund ? "На счёт" : "Со счёта")) {
                accountMenu(selected: account, excluding: draft.kind == .transfer ? draft.counterAccountID : nil) { selectAccount($0) }
            } note: {
                if draft.issues.contains(.usedDefaultAccount) {
                    noteBadge("по умолчанию")
                } else if draft.issues.contains(.accountInferredFromCurrency) {
                    noteBadge("по валюте")
                }
            }
            if draft.kind == .transfer {
                fieldRow(title: "Куда") {
                    accountMenu(selected: destination, excluding: draft.accountID) { option in
                        mutate { $0.selectDestination(option.id, accounts: store.accountMap, converter: store.converter) }
                    }
                } note: { EmptyView() }
                if let counter = draft.counterAmount, let destination, destination.currency != account?.currency,
                   let money = Money(major: counter, currency: destination.currency) {
                    fieldRow(title: "Зачислено") {
                        MoneyText(money: money, token: .callout, color: Color.mono.textPrimary)
                    } note: { EmptyView() }
                }
            }
            if draft.kind.usesCategory {
                fieldRow(title: "Категория") {
                    categoryMenu
                } note: {
                    if draft.issues.contains(.categoryUncertain) { noteBadge("не определена") }
                }
                if draft.categoryID == nil {
                    categorySuggestions
                        .padding(.vertical, 8)
                }
                fieldRow(title: draft.kind == .income ? "От кого" : "Где") {
                    TextField("Не указано", text: $merchantText)
                        .focused($focus, equals: .merchant)
                        .multilineTextAlignment(.trailing)
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(commitMerchant)
                        .onChange(of: focus) { old, new in
                            if old == .merchant && new != .merchant { commitMerchant() }
                        }
                } note: { EmptyView() }
            }
            fieldRow(title: "Дата") {
                DatePicker("", selection: Binding(get: { draft.date }, set: { value in mutate { $0.date = value } }),
                           in: ...Date().addingTimeInterval(86_400), displayedComponents: [.date])
                    .labelsHidden()
                    .tint(Color.mono.positive)
            } note: { EmptyView() }
        }
    }

    private func fieldRow<Content: View, Badge: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content, @ViewBuilder note: () -> Badge) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .monoFont(.subhead)
                    .foregroundStyle(Color.mono.textSecondary)
                note()
            }
            Spacer(minLength: 8)
            content()
        }
        .padding(.vertical, 9)
        .hairlineDivider()
    }

    private func noteBadge(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .monoFont(.caption)
            .foregroundStyle(Color.mono.accentText)
    }

    private func accountMenu(selected: Account?, excluding: UUID?, action: @escaping (Account) -> Void) -> some View {
        Menu {
            ForEach(store.activeAccounts.filter { $0.id != excluding }) { option in
                Button {
                    action(option)
                } label: {
                    Text(verbatim: "\(option.displayName) · \(option.currency.code)")
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let selected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected.skin.linearGradient)
                        .frame(width: 22, height: 15)
                    Text(verbatim: selected.displayName)
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("Выбрать")
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.accentText)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.mono.textTertiary)
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                mutate { $0.setCategory(nil) }
            } label: {
                Label("Без категории", systemImage: "circle.dashed")
            }
            ForEach(store.categories(for: draft.kind)) { option in
                Button {
                    mutate { $0.setCategory(option.id) }
                    Haptics.selection()
                } label: {
                    Label(option.name, systemImage: option.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let category {
                    CategoryGlyph(category: category, kind: draft.kind, size: 24)
                    Text(verbatim: category.name)
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("Выбрать")
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.accentText)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.mono.textTertiary)
            }
        }
    }

    /// Самые частые категории этого типа — выбор в одно касание.
    private var categorySuggestions: some View {
        let options = store.categories(for: draft.kind)
        var usage: [UUID: Int] = [:]
        for transaction in store.transactions.prefix(300) {
            if let id = transaction.categoryID { usage[id, default: 0] += 1 }
        }
        let top = options.sorted { (usage[$0.id] ?? 0, -$0.sortOrder) > (usage[$1.id] ?? 0, -$1.sortOrder) }.prefix(6)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(top)) { option in
                    Button {
                        mutate { $0.setCategory(option.id) }
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .foregroundStyle(option.color.color)
                            Text(verbatim: option.name)
                        }
                    }
                    .buttonStyle(ChipStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Изменения

    private func mutate(_ body: (inout VoiceDraft) -> Void) {
        var copy = draft
        body(&copy)
        onChange(copy)
    }

    private func selectAccount(_ option: Account) {
        mutate { $0.selectAccount(option.id, accounts: store.accountMap, converter: store.converter) }
        Haptics.selection()
    }

    private func changeKind(to kind: TransactionKind) {
        guard kind != draft.kind else { return }
        mutate { draft in
            draft.kind = kind
            if kind != .transfer {
                draft.counterAccountID = nil
                draft.counterAmount = nil
            }
            if let categoryID = draft.categoryID, store.categoryMap[categoryID]?.kind != kind.categoryKind {
                draft.categoryID = nil
            }
            if kind.usesCategory && draft.categoryID == nil {
                // Повторная подсказка категории по продавцу/фразе для нового типа.
                draft.categoryID = store.categorizer().suggest(merchant: draft.merchant, text: draft.sourceText, kind: kind)?.categoryID
            }
            draft.issues.removeAll { $0 == .categoryUncertain }
            if kind.usesCategory && draft.categoryID == nil { draft.issues.append(.categoryUncertain) }
            draft.revalidate(accounts: store.accountMap, converter: store.converter)
        }
        Haptics.selection()
    }

    private func commitMerchant() {
        let value = merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue: String? = value.isEmpty ? nil : value
        guard newValue != draft.merchant else { return }
        mutate { $0.merchant = newValue }
    }

    private func syncTexts() {
        if focus != .amount, let amount = draft.amount, let money = Money(major: amount, currency: draft.currency) {
            amountText = formatter.editableString(money)
        }
        if focus != .merchant { merchantText = draft.merchant ?? "" }
    }
}
