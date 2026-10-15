import SwiftUI
import MonoCore

/// Сумма с учётом режима конфиденциальности и плавной сменой цифр.
struct MoneyText: View {
    let money: Money
    var token: FontToken = .amountRow
    var sign: MoneyFormatter.SignDisplay = .automatic
    var color: Color?
    var compact = false

    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.moneyFormatter) private var formatter

    var body: some View {
        Text(verbatim: displayText)
            .monoFont(token, digits: true)
            .foregroundStyle(color ?? Color.mono.textPrimary)
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(hideAmounts ? Text("Сумма скрыта") : Text(verbatim: formatter.string(money, sign: sign)))
    }

    private var displayText: String {
        if hideAmounts { return "••• •••" }
        return compact ? formatter.compact(money, sign: sign) : formatter.string(money, sign: sign)
    }
}

/// Крупная сумма для героя экрана: целая часть серифом, дробная часть и валюта — мельче и спокойнее.
struct HeroAmount: View {
    let money: Money
    var token: FontToken = .hero
    var secondaryToken: FontToken = .title
    var color: Color = Color.mono.textPrimary

    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.moneyFormatter) private var formatter

    var body: some View {
        let parts = formatter.parts(money)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if hideAmounts {
                Text(verbatim: "••••••")
                    .monoFont(token)
                    .foregroundStyle(color)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text(verbatim: parts.sign + (parts.symbolLeading ? parts.symbol : "") + parts.integerPart)
                    .monoFont(token, digits: true)
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(money.minorUnits)))
                if let fraction = parts.fractionPart {
                    Text(verbatim: parts.decimalSeparator + fraction)
                        .monoFont(secondaryToken, digits: true)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                if !parts.symbolLeading {
                    Text(verbatim: parts.symbol)
                        .monoFont(secondaryToken)
                        .foregroundStyle(Color.mono.textSecondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hideAmounts ? Text("Сумма скрыта") : Text(verbatim: formatter.string(money)))
    }
}

/// Подпись изменения: «+1,2 млн сум за 30 дней» с цветом и стрелкой.
struct DeltaBadge: View {
    let delta: Money
    var caption: Text?

    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.moneyFormatter) private var formatter

    private var tint: Color {
        if delta.isZero { return Color.mono.textSecondary }
        return delta.isPositive ? Color.mono.emerald : Color.mono.coral
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: delta.isZero ? "equal" : (delta.isPositive ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: 11, weight: .bold))
            Text(verbatim: hideAmounts ? "•••" : formatter.compact(delta, sign: .always))
                .monoFont(.subhead, digits: true)
            if let caption {
                caption
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textSecondary)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}
