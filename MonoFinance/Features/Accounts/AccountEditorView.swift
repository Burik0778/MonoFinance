import SwiftUI
import MonoCore

/// Создание и редактирование счёта. Начальный остаток вводится один раз при создании (как корректировка в истории).
struct AccountEditorView: View {
    let account: Account?

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter

    @State private var bank: Bank = .kapitalbank
    @State private var name = ""
    @State private var kind: AccountKind = .card
    @State private var paymentSystem: PaymentSystem? = .humo
    @State private var currency: Currency = .uzs
    @State private var lastFour = ""
    @State private var skin: CardSkin = .aurora
    @State private var includeInTotal = true
    @State private var openingText = ""
    @State private var openingNegative = false
    @State private var makeDefault = false
    @State private var error: String?
    @State private var loaded = false

    private var isNew: Bool { account == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VirtualCardView(account: preview, balance: previewBalance)
                        .aspectRatio(1.586, contentMode: .fit)
                        .monoAnimation(.standard, value: skin)
                        .padding(.top, 4)

                    section("Банк") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                            ForEach(Bank.allCases) { option in
                                Button {
                                    Haptics.selection()
                                    withMonoAnimation(.quick) {
                                        bank = option
                                        skin = CardSkin.default(for: option)
                                        if option == .cash {
                                            kind = .cash
                                            paymentSystem = nil
                                        } else if kind == .cash {
                                            kind = .card
                                        }
                                    }
                                } label: {
                                    Text(verbatim: option.displayName)
                                        .monoFont(.subhead)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .padding(.horizontal, 6)
                                        .foregroundStyle(bank == option ? Color.white : Color.mono.textPrimary)
                                        .background(
                                            RoundedRectangle(cornerRadius: MonoTokens.Radius.sm, style: .continuous)
                                                .fill(bank == option ? AnyShapeStyle(CardSkin.default(for: option).linearGradient) : AnyShapeStyle(Color.mono.surface2))
                                        )
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityAddTraits(bank == option ? .isSelected : [])
                            }
                        }
                    }

                    section("Название") {
                        MonoTextField(title: "Например, «Зарплатная Humo»", text: $name, systemImage: "character.cursor.ibeam")
                    }

                    section("Тип") {
                        Picker("Тип счёта", selection: $kind) {
                            ForEach(AccountKind.allCases) { option in
                                Text(verbatim: option.title(.current)).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.mono.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .monoSurface(level: 1, radius: MonoTokens.Radius.md, padding: 8)

                        if kind == .card || kind == .credit {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(PaymentSystem.allCases) { system in
                                        Button(system.label) {
                                            Haptics.selection()
                                            paymentSystem = paymentSystem == system ? nil : system
                                        }
                                        .buttonStyle(ChipStyle(isSelected: paymentSystem == system))
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            MonoTextField(title: "Последние 4 цифры (необязательно)", text: $lastFour, systemImage: "number", keyboard: .numberPad)
                                .onChange(of: lastFour) { _, value in
                                    let digits = String(value.filter(\.isNumber).prefix(4))
                                    if digits != value { lastFour = digits }
                                }
                        }
                    }

                    section("Валюта") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Currency.common, id: \.self) { option in
                                    Button(option.code) {
                                        Haptics.selection()
                                        currency = option
                                    }
                                    .buttonStyle(ChipStyle(isSelected: currency == option))
                                    .disabled(!isNew && hasTransactions && option != currency)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        if !isNew && hasTransactions {
                            Text("Валюту нельзя изменить, пока на счёте есть операции.")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                        }
                    }

                    if isNew {
                        section("Текущий остаток") {
                            HStack(spacing: 10) {
                                MonoTextField(title: "0", text: $openingText, systemImage: "banknote", keyboard: .decimalPad)
                                Text(verbatim: formatter.symbol(for: currency).text)
                                    .monoFont(.headline)
                                    .foregroundStyle(Color.mono.textSecondary)
                            }
                            if kind == .credit {
                                Toggle("Это задолженность (минус)", isOn: $openingNegative)
                                    .monoFont(.callout)
                                    .tint(Color.mono.coral)
                            }
                            Text("Введите реальный остаток из банковского приложения. Он станет отправной точкой — дальше баланс считается из операций.")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    section("Оформление") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(CardSkin.allCases) { option in
                                    Button {
                                        Haptics.selection()
                                        skin = option
                                    } label: {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(option.linearGradient)
                                            .frame(width: 64, height: 42)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(skin == option ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                    }
                                    .buttonStyle(PressableStyle())
                                    .accessibilityLabel(Text(option.title))
                                    .accessibilityAddTraits(skin == option ? .isSelected : [])
                                }
                            }
                            .padding(2)
                        }
                        .scrollIndicators(.hidden)
                    }

                    VStack(spacing: 4) {
                        Toggle("Учитывать в общем балансе", isOn: $includeInTotal)
                        Toggle("Основной счёт для голосового ввода", isOn: $makeDefault)
                    }
                    .monoFont(.callout)
                    .tint(Color.mono.electric)
                    .monoSurface(padding: 16)

                    if let error {
                        Text(verbatim: error)
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.coral)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.mono.backgroundRaised.ignoresSafeArea())
            .navigationTitle(isNew ? Text("Новый счёт") : Text("Счёт"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var hasTransactions: Bool {
        guard let account else { return false }
        return store.transactions.contains { $0.involves(account: account.id) }
    }

    private var preview: Account {
        Account(id: account?.id ?? UUID(), bank: bank, name: name, kind: kind, paymentSystem: paymentSystem, currency: currency,
                lastFour: lastFour, skin: skin, includeInTotal: includeInTotal)
    }

    private var previewBalance: Money {
        if let account { return store.balance(of: account).currency == currency ? store.balance(of: account) : .zero(currency) }
        return MoneyFormatter.parseUserInput(openingText, currency: currency) ?? .zero(currency)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(title)
            content()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let account {
            bank = account.bank
            name = account.name
            kind = account.kind
            paymentSystem = account.paymentSystem
            currency = account.currency
            lastFour = account.lastFour ?? ""
            skin = account.skin
            includeInTotal = account.includeInTotal
            makeDefault = store.defaultAccountID == account.id
        } else {
            makeDefault = store.activeAccounts.isEmpty
        }
    }

    private func save() {
        error = nil
        var opening: Money?
        if isNew, !openingText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let value = MoneyFormatter.parseUserInput(openingText, currency: currency) else {
                error = String(localized: "Не удалось прочитать сумму остатка.")
                Haptics.error()
                return
            }
            opening = openingNegative ? value.magnitude.negated : value
        }
        do {
            if var existing = account {
                existing.bank = bank
                existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.kind = kind
                existing.paymentSystem = (kind == .card || kind == .credit) ? paymentSystem : nil
                existing.currency = currency
                existing.lastFour = Account.sanitizeLastFour(lastFour)
                existing.skin = skin
                existing.includeInTotal = includeInTotal
                try store.updateAccount(existing)
                if makeDefault { try store.setDefaultAccount(existing) }
            } else {
                let created = Account(bank: bank, name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                                      paymentSystem: (kind == .card || kind == .credit) ? paymentSystem : nil,
                                      currency: currency, lastFour: lastFour, skin: skin, includeInTotal: includeInTotal)
                try store.createAccount(created, openingBalance: opening)
                if makeDefault { try store.setDefaultAccount(created) }
            }
            Haptics.success()
            toasts.show(ToastMessage(text: isNew ? String(localized: "Счёт добавлен") : String(localized: "Счёт сохранён")))
            dismiss()
        } catch {
            self.error = AppError(error).message
            Haptics.error()
        }
    }
}
