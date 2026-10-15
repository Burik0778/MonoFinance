import SwiftUI
import UIKit
import MonoCore
import MonoStorage

/// Карточка операции: крупная сумма, все поля, чек, история изменений, действия.
struct TransactionDetailView: View {
    let transaction: FinanceTransaction

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter
    @State private var confirmsDelete = false
    @State private var showsReceipt = false

    private var current: FinanceTransaction { store.transaction(id: transaction.id) ?? transaction }

    var body: some View {
        let item = current
        let category = item.categoryID.flatMap { store.categoryMap[$0] }
        let account = store.accountMap[item.accountID]
        let counter = item.counterAccountID.flatMap { store.accountMap[$0] }
        let audit = store.auditTrail(for: item)
        let fees = store.linkedFees(of: item)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        CategoryGlyph(category: category, kind: item.kind, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker(LocalizedStringKey(item.kind.title(language)), color: item.kind.tint)
                            Text(verbatim: item.merchant ?? category?.name ?? item.kind.title(language))
                                .monoFont(.title)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(2)
                        }
                    }
                    HeroAmount(money: signedAmount(item), token: .display, secondaryToken: .title2,
                               color: item.kind == .income || item.kind == .refund ? Color.mono.positive : Color.mono.textPrimary)
                    if let counterAmount = item.counterAmount, counterAmount.currency != item.amount.currency {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                            Text("Зачислено")
                            MoneyText(money: counterAmount, token: .callout, color: Color.mono.textSecondary)
                        }
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                    }
                }

                VStack(spacing: 0) {
                    detailRow("Дата", value: DateFormatting.full(item.date, calendar: store.periods.calendar, language: language))
                    if item.kind == .transfer {
                        detailRow("Откуда", value: account?.displayName ?? "—")
                        detailRow("Куда", value: counter?.displayName ?? "—")
                    } else {
                        detailRow("Счёт", value: account.map { "\($0.displayName) · \($0.bank.displayName)" } ?? "—")
                    }
                    if item.kind.usesCategory {
                        detailRow("Категория", value: category?.name ?? String(localized: "Без категории"))
                    }
                    if let merchant = item.merchant { detailRow("Получатель / магазин", value: merchant) }
                    if let note = item.note { detailRow("Описание", value: note) }
                    if !item.tags.isEmpty { detailRow("Теги", value: item.tags.map { "#" + $0 }.joined(separator: " ")) }
                    detailRow("Источник", value: sourceTitle(item.source))
                    ForEach(fees) { fee in
                        detailRow("Комиссия", value: formatter.string(fee.amount))
                    }
                }
                .monoSurface(radius: MonoTokens.Radius.xl, padding: 6)

                if let receipt = item.receiptFileName, let data = ReceiptStore.load(receipt), let image = UIImage(data: data) {
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker("Чек")
                        Button { showsReceipt = true } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .accessibilityLabel(Text("Открыть чек"))
                    }
                    .sheet(isPresented: $showsReceipt) {
                        ZoomableImage(image: image)
                            .presentationBackground(.black)
                    }
                }

                if audit.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Kicker("История изменений")
                        ForEach(audit) { entry in
                            AuditRow(entry: entry)
                        }
                    }
                    .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
                }

                VStack(spacing: 10) {
                    if !item.isOpeningBalance {
                        Button("Изменить") {
                            router.present(.transaction(TransactionEditorContext(existingID: item.id, kind: item.kind)))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Удалить", role: .destructive) { confirmsDelete = true }
                        .buttonStyle(SecondaryButtonStyle(tint: Color.mono.negative))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Операция"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Удалить операцию?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                do {
                    try store.delete(item)
                    Haptics.warning()
                    toasts.show(ToastMessage(text: String(localized: "Операция удалена"), symbol: "trash.fill", tint: Color.mono.negative,
                                             actionTitle: String(localized: "Вернуть")) {
                        try? store.restore([item] + fees)
                    })
                    dismiss()
                } catch {
                    toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                }
            }
        } message: {
            Text(fees.isEmpty ? "Балансы будут пересчитаны." : "Связанная комиссия тоже будет удалена.")
        }
    }

    private func signedAmount(_ item: FinanceTransaction) -> Money {
        switch item.kind {
        case .expense, .fee: return item.amount.magnitude.negated
        case .income, .refund, .transfer: return item.amount.magnitude
        case .adjustment: return item.amount
        }
    }

    private func detailRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .monoFont(.subhead)
                .foregroundStyle(Color.mono.textSecondary)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .monoFont(.body)
                .foregroundStyle(Color.mono.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .hairlineDivider()
    }

    private func sourceTitle(_ source: TransactionSource) -> String {
        switch source {
        case .manual: return Phrase(ru: "Вручную", uz: "Qo‘lda", en: "Manual")(language)
        case .voice: return Phrase(ru: "Голосовой ввод", uz: "Ovozli kiritish", en: "Voice")(language)
        case .importFile: return Phrase(ru: "Импорт выписки", uz: "Ko‘chirma importi", en: "Statement import")(language)
        case .recurring: return Phrase(ru: "Регулярный платёж", uz: "Doimiy to‘lov", en: "Recurring")(language)
        case .shortcut: return Phrase(ru: "Быстрая команда", uz: "Tezkor buyruq", en: "Shortcut")(language)
        case .demo: return Phrase(ru: "Демо-данные", uz: "Demo", en: "Demo")(language)
        }
    }
}

/// Строка истории изменений: что поменялось.
private struct AuditRow: View {
    let entry: AuditEntry
    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .monoFont(.subhead)
                    .foregroundStyle(Color.mono.textPrimary)
                ForEach(changes, id: \.self) { change in
                    Text(verbatim: change)
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                Text(verbatim: DateFormatting.full(entry.date, calendar: store.periods.calendar, language: language))
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
        }
    }

    private var tint: Color {
        switch entry.change {
        case .created: return Color.mono.positive
        case .updated: return Color.mono.accent
        case .deleted: return Color.mono.negative
        }
    }

    private var title: String {
        switch entry.change {
        case .created: return Phrase(ru: "Создана", uz: "Yaratildi", en: "Created")(language)
        case .updated: return Phrase(ru: "Изменена", uz: "O‘zgartirildi", en: "Edited")(language)
        case .deleted: return Phrase(ru: "Удалена", uz: "O‘chirildi", en: "Deleted")(language)
        }
    }

    private var changes: [String] {
        guard entry.change == .updated, let before = entry.before, let after = entry.after else { return [] }
        var result: [String] = []
        if before.amount != after.amount {
            result.append("\(Phrase(ru: "Сумма", uz: "Summa", en: "Amount")(language)): \(formatter.string(before.amount)) → \(formatter.string(after.amount))")
        }
        if before.categoryID != after.categoryID {
            let old = before.categoryID.flatMap { store.categoryMap[$0]?.name } ?? "—"
            let new = after.categoryID.flatMap { store.categoryMap[$0]?.name } ?? "—"
            result.append("\(Phrase(ru: "Категория", uz: "Kategoriya", en: "Category")(language)): \(old) → \(new)")
        }
        if before.accountID != after.accountID {
            let old = store.accountMap[before.accountID]?.displayName ?? "—"
            let new = store.accountMap[after.accountID]?.displayName ?? "—"
            result.append("\(Phrase(ru: "Счёт", uz: "Hisob", en: "Account")(language)): \(old) → \(new)")
        }
        if before.date != after.date {
            result.append("\(Phrase(ru: "Дата", uz: "Sana", en: "Date")(language)): \(DateFormatting.short(before.date, calendar: store.periods.calendar, language: language)) → \(DateFormatting.short(after.date, calendar: store.periods.calendar, language: language))")
        }
        if before.merchant != after.merchant {
            result.append("\(Phrase(ru: "Магазин", uz: "Do‘kon", en: "Merchant")(language)): \(before.merchant ?? "—") → \(after.merchant ?? "—")")
        }
        if before.kind != after.kind {
            result.append("\(Phrase(ru: "Тип", uz: "Tur", en: "Type")(language)): \(before.kind.title(language)) → \(after.kind.title(language))")
        }
        return result
    }
}

/// Просмотр фото чека с масштабированием.
struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { value in scale = max(1, min(value.magnification, 5)) }.onEnded { _ in
                    withMonoAnimation(.quick) { scale = max(1, min(scale, 5)) }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IconButton(systemName: "xmark", label: "Закрыть") { dismiss() }
                .padding()
        }
    }
}
