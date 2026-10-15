import SwiftUI
import UniformTypeIdentifiers
import MonoCore
import MonoImport

/// Импорт выписки CSV/XLSX/PDF. Проверенные форматы (Payme, PDF Kapitalbank и Uzum Bank) распознаются сами,
/// для остальных колонки определяются автоматически; пользователь видит и подтверждает сопоставление и каждую строку.
struct ImportFlowView: View {
    let preselectedAccount: Account?

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var model = ImportFlowModel()
    @State private var showsImporter = false

    private static var contentTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        types.append(.pdf)
        return types
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepIndicator(step: model.step)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                Group {
                    switch model.step {
                    case .source: sourceStep
                    case .mapping: mappingStep
                    case .preview: previewStep
                    case .done: doneStep
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .monoAnimation(.standard, value: model.step)
            .background(Color.mono.backgroundRaised.ignoresSafeArea())
            .navigationTitle(Text("Импорт выписки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.step == .done ? "Готово" : "Отмена") { dismiss() }
                }
                if model.step == .mapping || model.step == .preview {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Назад") {
                            model.error = nil
                            model.step = model.step == .preview ? .mapping : .source
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: Self.contentTypes, allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await model.load(url: url, store: store) }
                case .failure(let failure):
                    model.error = failure.localizedDescription
                }
            }
            .onAppear {
                if model.accountID == nil { model.accountID = preselectedAccount?.id ?? store.defaultAccount?.id }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.step == .preview)
    }

    // MARK: - Шаг 1. Файл

    private var sourceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Загрузите выписку из банка")
                        .monoFont(.display)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("Экспортируйте историю операций в CSV, Excel (XLSX) или PDF из приложения или интернет-банка и выберите файл. Файл обрабатывается только на этом iPhone.")
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                }

                FormSection(title: "Счёт выписки", footer: "Все операции из файла будут привязаны к этому счёту в его валюте. Если в выписке несколько карт (Payme), счёт для каждой карты выберете на следующем шаге.") {
                    AccountPickerMenu(accounts: store.activeAccounts, selection: $model.accountID)
                }

                Button {
                    showsImporter = true
                } label: {
                    VStack(spacing: 12) {
                        if model.isWorking {
                            ProgressView().controlSize(.large).tint(Color.mono.positive)
                            Text("Читаю файл…")
                                .monoFont(.callout)
                                .foregroundStyle(Color.mono.textSecondary)
                        } else {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.mono.accentText)
                            Text("Выбрать файл")
                                .monoFont(.headline)
                                .foregroundStyle(Color.mono.textPrimary)
                            Text(verbatim: "CSV · XLSX · PDF")
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .background(
                        RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                            .foregroundStyle(Color.mono.strokeStrong)
                    )
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous).fill(Color.mono.surface1))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .disabled(model.isWorking || store.activeAccounts.isEmpty)

                errorLabel

                VStack(alignment: .leading, spacing: 10) {
                    Kicker("Важно знать")
                    note("checkmark.shield", "Повторный импорт того же файла не создаст дублей: уже загруженные строки распознаются и пропускаются.")
                    note("hand.raised", "Операции, похожие на внесённые вручную или голосом, по умолчанию не отмечены — решаете вы.")
                    note("arrow.left.arrow.right", "Выписка Payme со всеми картами распознаётся сама. Переводы между своими картами становятся переводами, а не расходами; комиссия записывается отдельно.")
                    note("doc.richtext", "PDF-выписки Kapitalbank и Uzum Bank распознаются сами. Если та же карта уже загружена из Payme, совпадающие операции не задвоятся: они отмечаются как «уже есть из другой выписки».")
                    note("questionmark.diamond", "Для Orient Finans и Trastbank шаблонов пока нет: их форматы не проверены на реальных файлах. Колонки определяются автоматически, проверьте их на следующем шаге.")
                    note("xmark.bin", "Старый формат Excel 97–2003 (.xls) не поддерживается — сохраните файл как XLSX или CSV.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func note(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mono.accentText)
                .frame(width: 20)
            Text(text)
                .monoFont(.footnote)
                .foregroundStyle(Color.mono.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let error = model.error {
            Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                .monoFont(.footnote)
                .foregroundStyle(Color.mono.negative)
        }
    }

    // MARK: - Шаг 2. Колонки

    private var mappingStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let fileName = model.fileName {
                        HStack(spacing: 10) {
                            Image(systemName: model.document?.format == .pdf ? "doc.richtext" : (model.document?.format == .xlsx ? "tablecells" : "doc.plaintext"))
                                .foregroundStyle(Color.mono.accentText)
                            Text(verbatim: fileName)
                                .monoFont(.subhead)
                                .foregroundStyle(Color.mono.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    if let format = model.formatName {
                        Label { Text("Распознан формат выписки \(format)") } icon: { Image(systemName: "checkmark.seal.fill") }
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.positive)
                    }
                    if let profile = model.appliedProfileName {
                        Label { Text("Применено сохранённое сопоставление «\(profile)»") } icon: { Image(systemName: "wand.and.stars") }
                            .monoFont(.footnote)
                            .foregroundStyle(Color.mono.accentText)
                    }
                    if let document = model.document, document.tables.count > 1 {
                        FormSection(title: "Лист") {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(document.tables.enumerated()), id: \.offset) { index, table in
                                        Button(table.name.isEmpty ? String(localized: "Лист \(index + 1)") : table.name) {
                                            model.selectTable(index, store: store)
                                        }
                                        .buttonStyle(ChipStyle(isSelected: index == model.tableIndex))
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }

                    if model.document?.format != .pdf {
                        FormSection(title: "Строка заголовков") {
                            Stepper(value: Binding(get: { (model.mapping.headerRow ?? -1) + 1 }, set: { model.setHeaderRow($0 == 0 ? nil : $0 - 1, store: store) }),
                                    in: 0...max(0, min(30, (model.table?.rows.count ?? 1) - 1))) {
                                Text(verbatim: model.mapping.headerRow.map { Phrase(ru: "Строка \($0 + 1)", uz: "\($0 + 1)-qator", en: "Row \($0 + 1)")(language) }
                                     ?? Phrase(ru: "Без заголовка", uz: "Sarlavhasiz", en: "No header")(language))
                                    .monoFont(.body)
                                    .foregroundStyle(Color.mono.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                        }
                    }

                    FormSection(title: "Что в колонках", footer: "Нажмите на заголовок колонки, чтобы изменить её роль. Нужны как минимум дата и сумма (или списание / зачисление).") {
                        if let table = model.table {
                            MappingGrid(table: table, mapping: model.mapping) { column, role in
                                model.setRole(role, for: column, store: store)
                            }
                        }
                    }

                    if model.document?.format != .pdf && model.mapping.column(.amount) != nil && model.mapping.column(.debit) == nil && model.mapping.column(.credit) == nil {
                        FormSection(title: "Знак суммы") {
                            SegmentedPills(options: [AmountSignConvention.negativeIsOutflow, .positiveIsOutflow],
                                           selection: $model.mapping.signConvention,
                                           title: { $0 == .negativeIsOutflow ? String(localized: "Минус — списание") : String(localized: "Плюс — списание") },
                                           stretch: true)
                        }
                    }

                    if model.isMultiCard {
                        FormSection(title: "Карты в выписке", footer: "Выберите счёт для каждой карты. Карты без счёта не импортируются.") {
                            VStack(spacing: 8) {
                                ForEach(model.cards) { card in
                                    StatementCardRow(card: card, accountID: model.cardAccounts[card.id], accounts: store.activeAccounts) {
                                        model.assign($0, to: card)
                                    }
                                }
                            }
                        }
                    } else {
                        FormSection(title: "Счёт") {
                            AccountPickerMenu(accounts: store.activeAccounts, selection: $model.accountID)
                        }
                    }

                    if model.hasDepositRows {
                        FormSection(title: "Вклад", footer: "Строки вроде «Перевод с DEPOSIT на VISA» — это ваши деньги со своего вклада, а не доход. Выберите счёт вклада, и они станут переводами. Без счёта они останутся доходами и расходами.") {
                            DepositAccountMenu(accounts: store.activeAccounts, selection: model.depositAccountID,
                                               onSelect: { model.depositAccountID = $0; model.preview = nil },
                                               onCreate: { model.createDepositAccount(store: store) })
                        }
                    }

                    ToggleRow(title: "Запомнить сопоставление", subtitle: "В следующий раз файл с такими же колонками разберётся сам.", isOn: $model.rememberMapping)
                    errorLabel
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            Button("Показать операции") { model.buildPreview(store: store) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canBuildPreview)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Шаг 3. Предпросмотр

    private var previewStep: some View {
        VStack(spacing: 0) {
            if let preview = model.preview {
                List {
                    Section {
                        PreviewSummary(preview: preview)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    }
                    Section {
                        ForEach(preview.visibleCandidates) { candidate in
                            CandidateRow(candidate: candidate, showsAccount: model.isMultiCard, onToggle: { model.toggle(candidate) },
                                         onCategory: { model.setCategory($0, for: candidate) },
                                         onSplit: { model.splitTransfer(candidate) })
                                .listRowBackground(Color.mono.surface1)
                        }
                    } header: {
                        HStack {
                            Kicker("Строки выписки")
                            Spacer()
                            Button("Все") { model.setAll(included: true) }
                                .monoFont(.caption)
                            Button("Ни одной") { model.setAll(included: false) }
                                .monoFont(.caption)
                        }
                    }
                    if !preview.skipped.isEmpty {
                        Section {
                            SkippedSummary(skipped: preview.skipped)
                                .listRowBackground(Color.mono.surface1)
                        } header: {
                            Kicker("Пропущено")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)

                VStack(spacing: 8) {
                    errorLabel
                    Button {
                        model.commit(store: store)
                        if model.step == .done { Haptics.success() }
                    } label: {
                        Text("Импортировать: \(preview.visibleCandidates.filter { $0.include && $0.duplicate != .alreadyImported }.count)")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(preview.includedCount == 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Шаг 4. Готово

    private var doneStep: some View {
        VStack(spacing: 18) {
            Spacer()
            OrbitIllustration(symbol: "checkmark")
                .frame(width: 150, height: 150)
            if let result = model.result {
                Text("Добавлено операций: \(result.inserted)")
                    .monoFont(.title)
                    .foregroundStyle(Color.mono.textPrimary)
                if result.skippedDuplicates > 0 {
                    Text("Пропущено как уже импортированные: \(result.skippedDuplicates)")
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                }
            }
            Text("Балансы и аналитика уже пересчитаны. Каждую операцию можно открыть и исправить.")
                .monoFont(.callout)
                .foregroundStyle(Color.mono.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Готово") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Индикатор шагов

private struct StepIndicator: View {
    let step: ImportFlowModel.Step
    private let titles: [LocalizedStringKey] = ["Файл", "Колонки", "Проверка", "Готово"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(index <= step.rawValue ? AnyShapeStyle(Color.mono.accent) : AnyShapeStyle(Color.mono.surface3))
                        .frame(height: 4)
                    Text(titles[index])
                        .monoFont(.caption)
                        .foregroundStyle(index == step.rawValue ? Color.mono.textPrimary : Color.mono.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Шаг \(step.rawValue + 1) из 4"))
    }
}

// MARK: - Сетка сопоставления

/// Таблица-предпросмотр: над каждой колонкой — её роль (меню), ниже — первые строки данных.
private struct MappingGrid: View {
    let table: ImportTable
    let mapping: ColumnMapping
    let onChange: (Int, ColumnRole?) -> Void

    @Environment(\.appLanguage) private var language

    private var columns: Range<Int> { 0..<min(table.columnCount, 24) }
    private var sampleRows: [Int] {
        let start = mapping.firstDataRow
        return Array(start..<min(table.rows.count, start + 6))
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(columns, id: \.self) { column in
                    let role = mapping.roles[column]
                    VStack(alignment: .leading, spacing: 0) {
                        Menu {
                            ForEach(ColumnRole.allCases) { option in
                                Button {
                                    Haptics.selection()
                                    onChange(column, option == .ignore ? nil : option)
                                } label: {
                                    if option == role {
                                        Label(option.title(language), systemImage: "checkmark")
                                    } else {
                                        Text(verbatim: option.title(language))
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: role?.title(language) ?? Phrase(ru: "Не использовать", uz: "Ishlatilmasin", en: "Ignore")(language))
                                    .monoFont(.caption)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(role == nil ? Color.mono.textTertiary : Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Capsule().fill(role.map { tint(for: $0) } ?? Color.mono.surface3))
                        }
                        if let header = mapping.headerRow {
                            Text(verbatim: table.cell(header, column).text)
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textSecondary)
                                .lineLimit(1)
                                .padding(.top, 8)
                                .padding(.horizontal, 4)
                        }
                        ForEach(sampleRows, id: \.self) { row in
                            Text(verbatim: display(table.cell(row, column)))
                                .monoFont(.footnote, digits: true)
                                .foregroundStyle(role == nil ? Color.mono.textTertiary : Color.mono.textPrimary)
                                .lineLimit(1)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .hairlineDivider()
                        }
                    }
                    .frame(width: 150)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(role == nil ? Color.mono.surface1 : tint(for: role!).opacity(0.08)))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func display(_ cell: CellValue) -> String {
        switch cell {
        case .date(let date):
            return date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: language.locale, timeZone: TimeZone(identifier: "UTC") ?? .current))
        default:
            return cell.text
        }
    }

    private func tint(for role: ColumnRole) -> Color {
        switch role {
        case .date, .time: return Color.mono.accent
        case .amount: return Color.mono.accent
        case .debit: return Color.mono.negative
        case .credit: return Color.mono.positive
        case .direction, .currency: return Color.mono.textSecondary
        case .description, .merchant: return Color.mono.accent
        case .category: return Color.mono.accent
        case .card, .cardName, .details: return Color.mono.accent
        case .status: return Color.mono.textSecondary
        case .balance, .ignore: return Color.mono.neutral
        }
    }
}

// MARK: - Сводка и строки предпросмотра

private struct PreviewSummary: View {
    let preview: ImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(preview.includedCount)")
                    .font(.system(size: 44, weight: .semibold, design: .default).monospacedDigit())
                    .foregroundStyle(Color.mono.textPrimary)
                Text("операций к импорту")
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            HStack(spacing: 16) {
                if let outflow = preview.total(.outflow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Списания")
                        MoneyText(money: outflow.negated, token: .callout, compact: true)
                    }
                }
                if let inflow = preview.total(.inflow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Поступления")
                        MoneyText(money: inflow, token: .callout, sign: .always, color: Color.mono.positive, compact: true)
                    }
                }
            }
            if preview.transferCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Label { Text("Переводов между своими счетами: \(preview.transferCount). Это не расходы и не доходы.") } icon: { Image(systemName: "arrow.left.arrow.right") }
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textPrimary)
                    if let fees = preview.feeTotal {
                        HStack(spacing: 4) {
                            Text("Комиссии за переводы:")
                            MoneyText(money: fees, token: .footnote, color: Color.mono.textSecondary)
                        }
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                    }
                }
            }
            if preview.replacedCount > 0 {
                Label { Text("Станут переводами вместо расходов и доходов из другой выписки: \(preview.replacedCount).") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textPrimary)
            }
            if preview.elsewhereCount > 0 {
                Label { Text("Уже есть из другой выписки (например, Payme): \(preview.elsewhereCount). Они не задвоятся и не отмечены.") } icon: { Image(systemName: "checkmark.shield") }
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.textSecondary)
            }
            if preview.duplicateCount - preview.elsewhereCount > 0 {
                Label { Text("Похожих или уже загруженных строк: \(preview.duplicateCount - preview.elsewhereCount). Они не отмечены.") } icon: { Image(systemName: "square.on.square") }
                    .monoFont(.footnote)
                    .foregroundStyle(Color.mono.warning)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.xl, style: .continuous).fill(Color.mono.surface1))
    }
}

private struct CandidateRow: View {
    let candidate: ImportCandidate
    var showsAccount = false
    let onToggle: () -> Void
    let onCategory: (UUID?) -> Void
    var onSplit: () -> Void = {}

    @Environment(FinanceStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        let category = candidate.categoryID.flatMap { store.categoryMap[$0] }
        let locked = candidate.duplicate == .alreadyImported
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: candidate.include ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(candidate.include ? Color.mono.positive : Color.mono.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityLabel(candidate.include ? Text("Отмечено") : Text("Не отмечено"))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: title)
                        .monoFont(.body)
                        .foregroundStyle(locked ? Color.mono.textTertiary : Color.mono.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if candidate.isTransfer {
                        MoneyText(money: candidate.ownTransfer?.received ?? candidate.amount, token: .amountRow, color: Color.mono.textSecondary)
                    } else {
                        MoneyText(money: candidate.direction == .outflow ? candidate.amount.negated : candidate.amount, token: .amountRow,
                                  color: candidate.direction == .inflow ? Color.mono.positive : Color.mono.textPrimary)
                    }
                }
                HStack(spacing: 6) {
                    Text(verbatim: DateFormatting.short(candidate.date, calendar: store.periods.calendar, language: language))
                    if showsAccount, !candidate.isTransfer, let account = store.accountMap[candidate.accountID] {
                        Text(verbatim: "· \(account.displayName)")
                    }
                    if candidate.kind == .fee || candidate.kind == .refund {
                        Text(verbatim: "· \(candidate.kind.title(language))")
                    }
                }
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)

                if candidate.isTransfer {
                    HStack(spacing: 8) {
                        if let fee = candidate.ownTransfer?.fee {
                            HStack(spacing: 3) {
                                Text("Комиссия")
                                MoneyText(money: fee, token: .caption, color: Color.mono.textTertiary)
                            }
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Button("Это не перевод", action: onSplit)
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textSecondary)
                            .buttonStyle(.plain)
                            .disabled(locked)
                    }
                } else if candidate.kind.usesCategory {
                    Menu {
                        Button("Без категории") { onCategory(nil) }
                        ForEach(store.categories(for: candidate.kind)) { option in
                            Button {
                                onCategory(option.id)
                            } label: {
                                Label(option.name, systemImage: option.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category?.icon ?? "tag")
                                .foregroundStyle(category?.color.color ?? Color.mono.textTertiary)
                            Text(verbatim: category?.name ?? Phrase(ru: "Категория?", uz: "Kategoriya?", en: "Category?")(language))
                                .foregroundStyle(category == nil ? Color.mono.warning : Color.mono.textSecondary)
                        }
                        .monoFont(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.mono.surface3))
                    }
                    .disabled(locked)
                }

                switch candidate.duplicate {
                case .alreadyImported:
                    tag("Уже импортирована — будет пропущена", color: Color.mono.neutral)
                case .possible(let existingID):
                    tag(possibleText(existingID), color: Color.mono.warning)
                case .importedElsewhere(let existingID, let replaceable):
                    if replaceable && candidate.isTransfer {
                        tag("Заменит такую же операцию из другой выписки: станет переводом", color: Color.mono.textSecondary)
                    } else {
                        tag(elsewhereText(existingID), color: Color.mono.textSecondary)
                    }
                case .none:
                    EmptyView()
                }
                if candidate.possibleOwnTransferID != nil && candidate.ownTransfer == nil {
                    tag("Похоже на перевод между своими счетами — проверьте, чтобы не учесть дважды", color: Color.mono.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(locked ? 0.6 : 1)
    }

    /// «Перевод · Kapital → Orient» для пары, иначе продавец или описание.
    private var title: String {
        if let route = candidate.transferRoute {
            let from = store.accountMap[route.from]?.displayName ?? ""
            let to = store.accountMap[route.to]?.displayName ?? ""
            return "\(TransactionKind.transfer.title(language)) · \(from) → \(to)"
        }
        return candidate.merchant ?? (candidate.description.isEmpty ? candidate.kind.title(language) : candidate.description)
    }

    private func tag(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .monoFont(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func possibleText(_ id: UUID) -> LocalizedStringKey {
        if let existing = store.transaction(id: id) {
            let date = DateFormatting.short(existing.date, calendar: store.periods.calendar, language: language)
            return "Похожа на операцию от \(date) (\(existing.merchant ?? existing.kind.title(language)))"
        }
        return "Похожа на уже внесённую операцию"
    }

    private func elsewhereText(_ id: UUID) -> LocalizedStringKey {
        if let existing = store.transaction(id: id) {
            let date = DateFormatting.short(existing.date, calendar: store.periods.calendar, language: language)
            return "Уже есть из другой выписки: \(date), \(existing.merchant ?? existing.note ?? existing.kind.title(language)). Не задвоится"
        }
        return "Уже есть из другой выписки. Не задвоится"
    }
}

/// Счёт вклада для строк «Перевод с DEPOSIT на карту».
private struct DepositAccountMenu: View {
    let accounts: [Account]
    let selection: UUID?
    let onSelect: (UUID?) -> Void
    let onCreate: () -> Void

    var body: some View {
        let selected = selection.flatMap { id in accounts.first { $0.id == id } }
        Menu {
            Button("Не связывать") { onSelect(nil) }
            ForEach(accounts) { account in
                Button {
                    onSelect(account.id)
                } label: {
                    if account.id == selection {
                        Label(account.displayName, systemImage: "checkmark")
                    } else {
                        Text(verbatim: account.displayName)
                    }
                }
            }
            Divider()
            Button(action: onCreate) {
                Label("Создать счёт «Вклад»", systemImage: "plus")
            }
        } label: {
            HStack {
                Image(systemName: "building.columns")
                    .foregroundStyle(Color.mono.accentText)
                Text(verbatim: selected?.displayName ?? String(localized: "Не связывать"))
                    .monoFont(.body)
                    .foregroundStyle(selected == nil ? Color.mono.textSecondary : Color.mono.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mono.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
        }
    }
}

private struct SkippedSummary: View {
    let skipped: [SkippedRow]
    @Environment(\.appLanguage) private var language

    var body: some View {
        let groups = Dictionary(grouping: skipped, by: \.reason)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(groups.keys).sorted { $0.rawValue < $1.rawValue }, id: \.self) { reason in
                HStack {
                    Text(verbatim: title(reason))
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                    Spacer()
                    Text(verbatim: "\(groups[reason]?.count ?? 0)")
                        .monoFont(.footnote, digits: true)
                        .foregroundStyle(Color.mono.textTertiary)
                }
            }
            Text("Обычно это заголовки, итоговые строки или подписи внутри таблицы.")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
        }
    }

    private func title(_ reason: SkippedRow.Reason) -> String {
        switch reason {
        case .noDate: return Phrase(ru: "Нет даты", uz: "Sana yo‘q", en: "No date")(language)
        case .noAmount: return Phrase(ru: "Нет суммы", uz: "Summa yo‘q", en: "No amount")(language)
        case .zeroAmount: return Phrase(ru: "Нулевая сумма", uz: "Nol summa", en: "Zero amount")(language)
        case .otherCurrency: return Phrase(ru: "Другая валюта", uz: "Boshqa valyuta", en: "Other currency")(language)
        case .notCompleted: return Phrase(ru: "Отменённые или не проведённые", uz: "Bekor qilingan yoki o‘tkazilmagan", en: "Cancelled or pending")(language)
        case .unassignedCard: return Phrase(ru: "Карта без выбранного счёта", uz: "Hisob tanlanmagan karta", en: "Card without an account")(language)
        }
    }
}

// MARK: - Карты выписки

/// Карта из выписки и счёт, к которому относятся её операции.
private struct StatementCardRow: View {
    let card: StatementCard
    let accountID: UUID?
    let accounts: [Account]
    let onSelect: (UUID?) -> Void

    @Environment(FinanceStore.self) private var store

    var body: some View {
        let account = accountID.flatMap { store.accountMap[$0] }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: card.name ?? card.number)
                    .monoFont(.headline)
                    .foregroundStyle(Color.mono.textPrimary)
                    .lineLimit(1)
                Text(verbatim: "\(card.lastFour.map { "•• \($0)" } ?? card.number) · \(card.rowCount)")
                    .monoFont(.caption, digits: true)
                    .foregroundStyle(Color.mono.textTertiary)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(accounts) { option in
                    Button {
                        Haptics.selection()
                        onSelect(option.id)
                    } label: {
                        if option.id == accountID {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(verbatim: "\(option.displayName) · \(option.currency.code)")
                        }
                    }
                }
                Divider()
                Button(role: .destructive) { onSelect(nil) } label: { Label("Не импортировать", systemImage: "xmark") }
            } label: {
                HStack(spacing: 8) {
                    if let account {
                        CardThumbnail(skin: account.skin, width: 30)
                        Text(verbatim: account.displayName)
                            .foregroundStyle(Color.mono.textPrimary)
                    } else {
                        Text("Выбрать счёт")
                            .foregroundStyle(Color.mono.warning)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mono.textTertiary)
                }
                .monoFont(.subhead)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
    }
}
