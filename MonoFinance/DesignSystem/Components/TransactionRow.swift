import SwiftUI
import MonoCore

/// Строка операции: значок категории, продавец/категория, счёт, сумма со знаком.
struct TransactionRow: View {
    let transaction: FinanceTransaction
    let category: FinanceCategory?
    let account: Account?
    let counterAccount: Account?
    var showsTime = true
    var calendar: Calendar = Calendar.current

    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(category: category, kind: transaction.kind, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if transaction.source == .voice {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.mono.violet)
                            .accessibilityLabel(Text("Голосовой ввод"))
                    } else if transaction.source == .importFile {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.mono.cyan)
                            .accessibilityLabel(Text("Импорт"))
                    }
                    Text(verbatim: subtitle)
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                MoneyText(money: displayAmount, token: .amountRow, sign: sign, color: amountColor)
                if showsTime {
                    Text(verbatim: DateFormatting.time(transaction.date, calendar: calendar, language: language))
                        .monoFont(.caption, digits: true)
                        .foregroundStyle(Color.mono.textTertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if transaction.kind == .transfer {
            return Phrase(ru: "Перевод", uz: "O‘tkazma", en: "Transfer")(language)
        }
        if transaction.isOpeningBalance {
            return Phrase(ru: "Начальный остаток", uz: "Boshlang‘ich qoldiq", en: "Opening balance")(language)
        }
        if let merchant = transaction.merchant, !merchant.isEmpty { return merchant }
        if let category { return category.name }
        if let note = transaction.note, !note.isEmpty { return note }
        return transaction.kind.title(language)
    }

    private var subtitle: String {
        if transaction.kind == .transfer {
            return "\(account?.displayName ?? "—") → \(counterAccount?.displayName ?? "—")"
        }
        var parts: [String] = []
        if transaction.merchant != nil, let category { parts.append(category.name) }
        if transaction.kind == .refund || transaction.kind == .fee || transaction.kind == .adjustment {
            if !transaction.isOpeningBalance { parts.insert(transaction.kind.title(language), at: 0) }
        }
        if let account { parts.append(account.displayName) }
        return parts.joined(separator: " · ")
    }

    private var displayAmount: Money {
        switch transaction.kind {
        case .expense, .fee: return transaction.amount.magnitude.negated
        case .income, .refund: return transaction.amount.magnitude
        case .transfer: return transaction.amount.magnitude
        case .adjustment: return transaction.amount
        }
    }

    private var sign: MoneyFormatter.SignDisplay {
        switch transaction.kind {
        case .income, .refund, .adjustment: return .always
        case .transfer: return .never
        default: return .automatic
        }
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income, .refund: return Color.mono.emerald
        case .expense: return Color.mono.textPrimary
        case .fee: return Color.mono.tangerine
        case .transfer: return Color.mono.sky
        case .adjustment: return Color.mono.steel
        }
    }
}
