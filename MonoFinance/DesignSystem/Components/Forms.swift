import SwiftUI
import MonoCore

/// Каркас модального редактора: заголовок, прокручиваемая форма, крупная кнопка сохранения внизу.
struct EditorScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var saveTitle: LocalizedStringKey = "Сохранить"
    var saveColors: [Color] = [Color.mono.electric, Color.mono.violet]
    var canSave = true
    var error: String?
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        content()
                        if let error {
                            Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.coral)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                Button(saveTitle, action: onSave)
                    .buttonStyle(PrimaryButtonStyle(colors: saveColors))
                    .disabled(!canSave)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.mono.backgroundRaised)
            }
            .background(Color.mono.backgroundRaised.ignoresSafeArea())
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Раздел формы: кикер, содержимое, необязательная подсказка.
struct FormSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(title)
            content()
            if let footer {
                Text(footer)
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Поле суммы: крупные цифры серифом и символ валюты. Разбор — `MoneyFormatter.parseUserInput`.
struct AmountField: View {
    let placeholder: String
    @Binding var text: String
    let currency: Currency
    var tint: Color = Color.mono.textPrimary

    @Environment(\.moneyFormatter) private var formatter
    @FocusState private var focused: Bool

    init(_ placeholder: String = "0", text: Binding<String>, currency: Currency, tint: Color = Color.mono.textPrimary) {
        self.placeholder = placeholder
        self._text = text
        self.currency = currency
        self.tint = tint
    }

    var isValid: Bool { AmountField.parse(text, currency: currency) != nil }

    static func parse(_ text: String, currency: Currency) -> Money? {
        guard let money = MoneyFormatter.parseUserInput(text, currency: currency), money.isPositive, money.isWithinLimits else { return nil }
        return money
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TextField(placeholder, text: $text)
                .keyboardType(currency.minorUnitDigits > 0 ? .decimalPad : .numberPad)
                .focused($focused)
                .font(.system(size: 40, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.5)
            Text(verbatim: formatter.symbol(for: currency).text)
                .monoFont(.title2)
                .foregroundStyle(Color.mono.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous).fill(Color.mono.surface2))
        .overlay(
            RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous)
                .strokeBorder(focused ? Color.mono.electric.opacity(0.6) : Color.mono.strokeSubtle, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Строка-переключатель.
struct ToggleRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool
    var tint: Color = Color.mono.electric

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
    }
}

/// Выбор цвета из палитры категорий.
struct ColorSwatchPicker: View {
    @Binding var selection: CategoryColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(CategoryColor.allCases, id: \.self) { option in
                Button {
                    Haptics.selection()
                    withMonoAnimation(.quick) { selection = option }
                } label: {
                    Circle()
                        .fill(option.color.gradient)
                        .frame(height: 36)
                        .overlay {
                            if selection == option {
                                Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(3)
                            }
                        }
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(Text(verbatim: option.rawValue))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}

/// Выбор SF Symbol из подборки.
struct SymbolPicker: View {
    @Binding var selection: String
    let symbols: [String]
    var tint: Color = Color.mono.electric

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 8)], spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                let selected = symbol == selection
                Button {
                    Haptics.selection()
                    withMonoAnimation(.quick) { selection = symbol }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : tint)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? tint : tint.opacity(0.12)))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Меню выбора валюты.
struct CurrencyMenu: View {
    @Binding var selection: Currency
    var options: [Currency] = Currency.common

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { currency in
                Button(currency.code) { selection = currency }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: selection.code)
                    .monoFont(.headline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.mono.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule(style: .continuous).fill(Color.mono.surface3))
        }
    }
}

/// Выбор категории сеткой значков.
struct CategoryGridPicker: View {
    let categories: [FinanceCategory]
    @Binding var selection: UUID?
    var allowsNone = true

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
            if allowsNone {
                cell(id: nil, icon: "circle.dashed", color: Color.mono.steel, name: String(localized: "Без категории"))
            }
            ForEach(categories) { category in
                cell(id: category.id, icon: category.icon, color: category.color.color, name: category.name)
            }
        }
    }

    private func cell(id: UUID?, icon: String, color: Color, name: String) -> some View {
        let selected = selection == id
        return Button {
            Haptics.selection()
            withMonoAnimation(.quick) { selection = id }
        } label: {
            VStack(spacing: 6) {
                CategoryGlyph(icon: icon, color: selected ? .white : color, size: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? color : Color.clear))
                Text(verbatim: name)
                    .monoFont(.caption)
                    .foregroundStyle(selected ? Color.mono.textPrimary : Color.mono.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.sm, style: .continuous).fill(selected ? color.opacity(0.14) : Color.clear))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Выбор счёта меню с мини-картой.
struct AccountPickerMenu: View {
    let accounts: [Account]
    @Binding var selection: UUID?
    var placeholder: LocalizedStringKey = "Выберите счёт"

    @Environment(FinanceStore.self) private var store

    var body: some View {
        Menu {
            ForEach(accounts) { option in
                Button {
                    Haptics.selection()
                    selection = option.id
                } label: {
                    Text(verbatim: "\(option.displayName) · \(option.currency.code)")
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let selected = selection.flatMap({ store.accountMap[$0] }) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected.skin.linearGradient)
                        .frame(width: 36, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: selected.displayName).monoFont(.body).foregroundStyle(Color.mono.textPrimary)
                        MoneyText(money: store.balance(of: selected), token: .caption, color: Color.mono.textSecondary)
                    }
                } else {
                    Image(systemName: "creditcard")
                        .foregroundStyle(Color.mono.textTertiary)
                    Text(placeholder).monoFont(.body).foregroundStyle(Color.mono.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
            .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
        }
    }
}
