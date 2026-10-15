import SwiftUI
import MonoCore

/// Клавиша цифровой клавиатуры.
enum NumberPadKey: Hashable {
    case digit(Int)
    case tripleZero
    case separator
    case delete
    case clear
}

/// Набор суммы с клавиатуры: только цифры и один десятичный разделитель, ограничение по знакам валюты.
struct AmountEntry: Equatable {
    private(set) var text = ""

    init(text: String = "") {
        self.text = text
    }

    init(money: Money?, formatter: MoneyFormatter) {
        if let money, !money.isZero {
            self.text = formatter.editableString(money.magnitude).replacingOccurrences(of: ",", with: ".")
        }
    }

    var isEmpty: Bool { text.isEmpty }

    mutating func apply(_ key: NumberPadKey, fractionDigits: Int) {
        switch key {
        case .digit(let digit):
            if let dot = text.firstIndex(of: ".") {
                guard text[text.index(after: dot)...].count < fractionDigits else { return }
            } else if text == "0" {
                text = ""
            }
            guard integerDigits < 13 else { return }
            text.append(String(digit))
        case .tripleZero:
            guard !text.isEmpty, !text.contains("."), integerDigits <= 10 else { return }
            text += "000"
        case .separator:
            guard fractionDigits > 0, !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
        case .delete:
            if !text.isEmpty { text.removeLast() }
        case .clear:
            text = ""
        }
    }

    private var integerDigits: Int {
        (text.split(separator: ".").first ?? "").count
    }

    func money(currency: Currency) -> Money? {
        guard let value = DecimalMath.parse(text.hasSuffix(".") ? String(text.dropLast()) : text) else { return nil }
        return Money(major: value, currency: currency)
    }
}

/// Цифровая клавиатура MONO с тактильным откликом.
struct NumberPad: View {
    var allowsSeparator: Bool
    var decimalSeparator: String = ","
    let onKey: (NumberPadKey) -> Void

    private let rows: [[NumberPadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(rows[row], id: \.self) { key in keyButton(key) }
                }
            }
            HStack(spacing: 8) {
                keyButton(allowsSeparator ? .separator : .tripleZero)
                keyButton(.digit(0))
                keyButton(.delete)
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: NumberPadKey) -> some View {
        Button {
            Haptics.tap()
            onKey(key)
        } label: {
            label(for: key)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                if key == .delete {
                    Haptics.rigid()
                    onKey(.clear)
                }
            }
        )
        .accessibilityLabel(accessibilityLabel(for: key))
    }

    @ViewBuilder
    private func label(for key: NumberPadKey) -> some View {
        switch key {
        case .digit(let digit):
            Text(verbatim: "\(digit)")
                .font(.system(size: 26, weight: .medium, design: .default))
                .foregroundStyle(Color.mono.textPrimary)
        case .tripleZero:
            Text(verbatim: "000")
                .font(.system(size: 20, weight: .medium, design: .default))
                .foregroundStyle(Color.mono.textPrimary)
        case .separator:
            Text(verbatim: decimalSeparator)
                .font(.system(size: 26, weight: .medium, design: .default))
                .foregroundStyle(Color.mono.textPrimary)
        case .delete, .clear:
            Image(systemName: "delete.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.mono.textSecondary)
        }
    }

    private func accessibilityLabel(for key: NumberPadKey) -> Text {
        switch key {
        case .digit(let digit): return Text(verbatim: "\(digit)")
        case .tripleZero: return Text("Три нуля")
        case .separator: return Text("Десятичный разделитель")
        case .delete: return Text("Удалить цифру")
        case .clear: return Text("Очистить")
        }
    }
}
