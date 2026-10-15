import SwiftUI
import PhotosUI
import UIKit
import MonoCore
import MonoIntelligence

/// Редактор операции: тип, сумма на собственной клавиатуре, счёт, категория (с подсказкой), детали, чек.
struct TransactionEditorView: View {
    let context: TransactionEditorContext

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var formatter
    @Environment(\.appLanguage) private var language

    @State private var kind: TransactionKind = .expense
    @State private var entry = AmountEntry()
    @State private var adjustmentNegative = false
    @State private var accountID: UUID?
    @State private var destinationID: UUID?
    @State private var counterText = ""
    @State private var feeText = ""
    @State private var categoryID: UUID?
    @State private var suggestedCategoryID: UUID?
    @State private var categoryTouched = false
    @State private var merchant = ""
    @State private var note = ""
    @State private var tagsText = ""
    @State private var date = Date()
    @State private var receiptName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPad = true
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case merchant
        case note
        case tags
        case counter
        case fee
    }

    private var existing: FinanceTransaction? { context.existingID.flatMap { store.transaction(id: $0) } }
    private var isNew: Bool { existing == nil }
    private var account: Account? { accountID.flatMap { store.accountMap[$0] } }
    private var destination: Account? { destinationID.flatMap { store.accountMap[$0] } }
    private var currency: Currency { account?.currency ?? store.baseCurrency }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        kindPicker
                        amountDisplay
                        accountSection
                        if kind == .transfer { transferSection }
                        if kind.usesCategory { categorySection }
                        detailsSection
                        if let error {
                            Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.negative)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                VStack(spacing: 10) {
                    if showsPad && focusedField == nil {
                        NumberPad(allowsSeparator: currency.minorUnitDigits > 0, decimalSeparator: formatter.decimalSeparator) { key in
                            entry.apply(key, fractionDigits: currency.minorUnitDigits)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Button(isNew ? "Сохранить" : "Сохранить изменения") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(entry.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.mono.backgroundRaised)
                .monoAnimation(.standard, value: showsPad && focusedField == nil)
            }
            .background(Color.mono.backgroundRaised.ignoresSafeArea())
            .navigationTitle(isNew ? Text("Новая операция") : Text("Изменение операции"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: merchant) { _, _ in updateSuggestion() }
            .onChange(of: kind) { old, new in kindChanged(from: old, to: new) }
            .onChange(of: photoItem) { _, item in loadReceipt(item) }
        }
        .presentationDetents([.large])
    }

    // MARK: - Тип

    private var isSecondaryKind: Bool {
        kind == .refund || kind == .fee || kind == .adjustment
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            SegmentedPills(options: [TransactionKind.expense, .income, .transfer], selection: $kind,
                           title: { $0.title(language) }, stretch: true)
            Menu {
                ForEach([TransactionKind.refund, .fee, .adjustment], id: \.self) { option in
                    Button {
                        kind = option
                    } label: {
                        Label(option.title(language), systemImage: option.symbol)
                    }
                }
            } label: {
                Image(systemName: isSecondaryKind ? kind.symbol : "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSecondaryKind ? Color.white : Color.mono.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(isSecondaryKind ? kind.tint : Color.mono.surface1))
                    .overlay(Circle().strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
            }
            .disabled(!isNew && existing?.kind == .transfer)
            .accessibilityLabel(Text("Другие типы операций"))
        }
        .disabled(!isNew && (existing?.kind == .transfer || existing?.isOpeningBalance == true))
    }

    // MARK: - Сумма

    private var amountDisplay: some View {
        Button {
            focusedField = nil
            withMonoAnimation(.quick) { showsPad = true }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(kind == .adjustment ? "Изменение баланса" : "Сумма")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if kind == .adjustment {
                        Text(verbatim: adjustmentNegative ? MoneyFormatter.minus : "+")
                            .font(.system(size: 48, weight: .semibold, design: .default))
                            .foregroundStyle(adjustmentNegative ? Color.mono.negative : Color.mono.positive)
                    }
                    Text(verbatim: amountText)
                        .font(.system(size: 52, weight: .semibold, design: .default).monospacedDigit())
                        .foregroundStyle(entry.isEmpty ? Color.mono.textTertiary : Color.mono.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(verbatim: formatter.symbol(for: currency).text)
                        .monoFont(.title)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                .monoAnimation(.quick, value: entry)
                if kind == .adjustment {
                    Toggle("Уменьшить баланс", isOn: $adjustmentNegative)
                        .monoFont(.callout)
                        .tint(Color.mono.negative)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Сумма \(amountText)"))
    }

    private var amountText: String {
        guard let money = entry.money(currency: currency), !entry.isEmpty else { return "0" }
        var text = formatter.number(money, fraction: entry.text.contains(".") ? .always : .never)
        if entry.text.hasSuffix(".") { text += formatter.decimalSeparator }
        if let dot = entry.text.firstIndex(of: "."), entry.text[entry.text.index(after: dot)...].count == 1 {
            text.removeLast()
        }
        return text
    }

    // MARK: - Счета

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(kind == .transfer ? "Откуда" : (kind == .income || kind == .refund ? "На счёт" : "Со счёта"))
            accountMenu(selection: $accountID, excluding: kind == .transfer ? destinationID : nil)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Куда")
            accountMenu(selection: $destinationID, excluding: accountID)
            if let account, let destination, account.currency != destination.currency {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        MonoTextField(title: "Зачислено", text: $counterText, systemImage: "arrow.down.to.line", keyboard: .decimalPad)
                            .focused($focusedField, equals: .counter)
                        Text(verbatim: formatter.symbol(for: destination.currency).text)
                            .monoFont(.headline)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                    if let money = entry.money(currency: account.currency), let suggested = store.converter.convert(money, to: destination.currency) {
                        Button {
                            counterText = formatter.editableString(suggested)
                        } label: {
                            Text("По курсу ЦБ: \(formatter.string(suggested)) — подставить")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.accentText)
                        }
                    }
                    Text("Укажите сумму, которая фактически пришла: курс банка может отличаться от курса ЦБ.")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                }
            }
            if isNew {
                HStack {
                    MonoTextField(title: "Комиссия (необязательно)", text: $feeText, systemImage: "percent", keyboard: .decimalPad)
                        .focused($focusedField, equals: .fee)
                    Text(verbatim: formatter.symbol(for: currency).text)
                        .monoFont(.headline)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                Text("Комиссия запишется отдельной операцией и не попадёт в расходы по категориям.")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
        }
    }

    private func accountMenu(selection: Binding<UUID?>, excluding: UUID?) -> some View {
        Menu {
            ForEach(store.activeAccounts.filter { $0.id != excluding }) { option in
                Button {
                    Haptics.selection()
                    selection.wrappedValue = option.id
                } label: {
                    Text(verbatim: "\(option.displayName) · \(formatter.string(store.balance(of: option)))")
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let selected = selection.wrappedValue.flatMap({ store.accountMap[$0] }) {
                    CardThumbnail(skin: selected.skin, width: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: selected.displayName).monoFont(.body).foregroundStyle(Color.mono.textPrimary)
                        MoneyText(money: store.balance(of: selected), token: .caption, color: Color.mono.textSecondary)
                    }
                } else {
                    Image(systemName: "creditcard")
                        .foregroundStyle(Color.mono.textTertiary)
                    Text("Выберите счёт").monoFont(.body).foregroundStyle(Color.mono.textTertiary)
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

    // MARK: - Категории

    private var categorySection: some View {
        let options = orderedCategories
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Kicker("Категория")
                Spacer()
                if let suggested = suggestedCategoryID, suggested == categoryID, !categoryTouched {
                    Label("Предложено", systemImage: "sparkles")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.accentText)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(options) { category in
                    let selected = categoryID == category.id
                    Button {
                        Haptics.selection()
                        categoryTouched = true
                        withMonoAnimation(.quick) { categoryID = selected ? nil : category.id }
                    } label: {
                        VStack(spacing: 6) {
                            CategoryGlyph(icon: category.icon, color: category.color.color, size: 40, isSelected: selected)
                            Text(verbatim: category.name)
                                .monoFont(.caption)
                                .foregroundStyle(selected ? Color.mono.textPrimary : Color.mono.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: MonoTokens.Radius.sm, style: .continuous)
                                .fill(selected ? Color.mono.accentWash : Color.clear)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text(verbatim: category.name))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    /// Предложенная категория первой, затем по частоте использования.
    private var orderedCategories: [FinanceCategory] {
        let list = store.categories(for: kind)
        var usage: [UUID: Int] = [:]
        for transaction in store.transactions.prefix(400) {
            if let id = transaction.categoryID { usage[id, default: 0] += 1 }
        }
        return list.sorted { lhs, rhs in
            if lhs.id == suggestedCategoryID { return true }
            if rhs.id == suggestedCategoryID { return false }
            let l = usage[lhs.id] ?? 0
            let r = usage[rhs.id] ?? 0
            return l != r ? l > r : lhs.sortOrder < rhs.sortOrder
        }
    }

    // MARK: - Детали

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Детали")
            if kind != .transfer && kind != .adjustment {
                MonoTextField(title: kind == .income ? "От кого" : "Магазин или получатель", text: $merchant, systemImage: "storefront")
                    .focused($focusedField, equals: .merchant)
            }
            DatePicker(selection: $date, in: ...Date().addingTimeInterval(86_400 * 365)) {
                Label("Дата", systemImage: "calendar")
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            .tint(Color.mono.positive)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface3))
            MonoTextField(title: "Описание", text: $note, systemImage: "text.alignleft")
                .focused($focusedField, equals: .note)
            MonoTextField(title: "Теги через запятую", text: $tagsText, systemImage: "number")
                .focused($focusedField, equals: .tags)
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(receiptName == nil ? "Прикрепить чек" : "Заменить чек", systemImage: "doc.viewfinder")
                        .monoFont(.subhead)
                }
                .buttonStyle(ChipStyle())
                if receiptName != nil {
                    Button(role: .destructive) {
                        receiptName = nil
                    } label: {
                        Label("Убрать", systemImage: "xmark")
                    }
                    .buttonStyle(ChipStyle(tint: Color.mono.negative))
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.mono.positive)
                        .accessibilityLabel(Text("Чек прикреплён"))
                }
            }
        }
    }

    // MARK: - Логика

    private func load() {
        guard !loaded else { return }
        loaded = true
        let source = existing ?? context.prefill
        kind = existing?.kind ?? context.prefill?.kind ?? context.kind
        accountID = source?.accountID ?? context.accountID ?? store.defaultAccount?.id
        if let source {
            if kind == .adjustment {
                adjustmentNegative = source.amount.isNegative
                entry = AmountEntry(money: source.amount.magnitude, formatter: formatter)
            } else {
                entry = AmountEntry(money: source.amount, formatter: formatter)
            }
            destinationID = source.counterAccountID
            if let counter = source.counterAmount, counter.currency != source.amount.currency {
                counterText = formatter.editableString(counter)
            }
            categoryID = source.categoryID
            categoryTouched = source.categoryID != nil
            merchant = source.merchant ?? ""
            note = source.note ?? ""
            tagsText = source.tags.joined(separator: ", ")
            receiptName = existing?.receiptFileName
            if existing != nil { date = source.date }
            showsPad = existing == nil
        } else {
            categoryID = context.categoryID
            categoryTouched = context.categoryID != nil
            if kind == .transfer {
                destinationID = store.activeAccounts.first { $0.id != accountID }?.id
            }
        }
    }

    private func kindChanged(from old: TransactionKind, to new: TransactionKind) {
        Haptics.selection()
        if old.categoryKind != new.categoryKind {
            categoryID = nil
            categoryTouched = false
        }
        if new == .transfer && destinationID == nil {
            destinationID = store.activeAccounts.first { $0.id != accountID }?.id
        }
        updateSuggestion()
    }

    private func updateSuggestion() {
        guard kind.usesCategory else { return }
        let suggestion = store.categorizer().suggest(merchant: merchant.isEmpty ? nil : merchant, text: note, kind: kind)
        suggestedCategoryID = suggestion?.categoryID
        if !categoryTouched, let suggestion {
            withMonoAnimation(.quick) { categoryID = suggestion.categoryID }
        }
    }

    private func loadReceipt(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.72) else {
                error = String(localized: "Не удалось загрузить изображение.")
                return
            }
            do {
                receiptName = try ReceiptStore.save(jpeg)
            } catch {
                self.error = String(localized: "Не удалось сохранить чек.")
            }
        }
    }

    private func save() {
        error = nil
        guard let account else {
            error = String(localized: "Выберите счёт.")
            Haptics.error()
            return
        }
        guard var amount = entry.money(currency: account.currency), amount.isPositive else {
            error = String(localized: "Введите сумму больше нуля.")
            Haptics.error()
            return
        }
        if kind == .adjustment && adjustmentNegative { amount = amount.negated }

        var counterAmount: Money?
        if kind == .transfer {
            guard let destination else {
                error = String(localized: "Выберите счёт получателя.")
                Haptics.error()
                return
            }
            if destination.currency == account.currency {
                counterAmount = amount
            } else {
                guard let parsed = MoneyFormatter.parseUserInput(counterText, currency: destination.currency), parsed.isPositive else {
                    error = String(localized: "Укажите сумму, зачисленную на счёт получателя.")
                    Haptics.error()
                    focusedField = .counter
                    return
                }
                counterAmount = parsed
            }
        }

        var fee: Money?
        if kind == .transfer, isNew, !feeText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = MoneyFormatter.parseUserInput(feeText, currency: account.currency), parsed.isPositive else {
                error = String(localized: "Не удалось прочитать комиссию.")
                Haptics.error()
                return
            }
            fee = parsed
        }

        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var transaction = existing ?? FinanceTransaction(kind: kind, amount: amount, accountID: account.id, date: date, source: .manual)
        transaction.kind = kind
        transaction.amount = amount
        transaction.accountID = account.id
        transaction.counterAccountID = kind == .transfer ? destinationID : nil
        transaction.counterAmount = counterAmount
        transaction.categoryID = kind.usesCategory ? categoryID : nil
        transaction.merchant = (kind == .transfer || kind == .adjustment || trimmedMerchant.isEmpty) ? nil : trimmedMerchant
        transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        transaction.tags = tags
        transaction.date = date
        transaction.receiptFileName = receiptName

        do {
            if kind == .transfer && isNew {
                try store.saveTransfer(transaction, fee: fee)
            } else {
                try store.save(transaction, isNew: isNew)
            }
            if categoryTouched, let categoryID, transaction.merchant != nil {
                store.learnCategory(merchant: transaction.merchant, categoryID: categoryID)
            }
            if let old = existing?.receiptFileName, old != receiptName { ReceiptStore.delete(old) }
            Haptics.success()
            toasts.show(ToastMessage(text: isNew ? String(localized: "Операция добавлена") : String(localized: "Изменения сохранены")))
            dismiss()
        } catch {
            self.error = AppError(error).message
            Haptics.error()
        }
    }
}
