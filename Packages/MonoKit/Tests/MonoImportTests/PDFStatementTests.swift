import XCTest
import MonoCore
import MonoIntelligence
import MonoStorage
@testable import MonoImport

/// PDF-выписки Kapitalbank и Uzum Bank: восстановление таблицы по координатам слов, разбор строк,
/// сверка с операциями из других выписок (Payme по той же карте) и переводы со вкладом.
final class PDFStatementTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }
    let categories = DefaultCategories.make(language: .ru)
    let visa = Account(bank: .kapitalbank, name: "Kapital Visa", currency: .uzs, lastFour: "7058")
    let humo = Account(bank: .kapitalbank, name: "Kapital Humo", currency: .uzs)
    let deposit = Account(bank: .kapitalbank, name: "Вклад", kind: .deposit, currency: .uzs)

    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"), name)
        return try Data(contentsOf: url)
    }

    func uzs(_ value: Decimal) -> Money { Money(major: value, currency: .uzs)! }

    func date(_ text: String, _ time: String = "12:00") -> Date {
        ValueParsers.date(.text(text), time: .text(time), calendar: calendar)!
    }

    /// Слова строки: (x, текст) на высоте y.
    func line(_ y: Double, _ items: [(Double, String)], height: Double = 9) -> [PDFWord] {
        items.flatMap { item -> [PDFWord] in
            let (x, text) = item
            var words: [PDFWord] = []
            var cursor = x
            for part in text.split(separator: " ") {
                let width = Double(part.count) * 4.5
                words.append(PDFWord(text: String(part), minX: cursor, maxX: cursor + width, minY: y - height / 2, maxY: y + height / 2))
                cursor += width + 2.5
            }
            return words
        }
    }

    // MARK: - Kapitalbank

    /// Две страницы в духе выписки Капиталбанка: дата и сумма — по центру многострочных деталей,
    /// заголовок повторяется, в подвале подписи, одна запись продолжается на следующей странице.
    func kapitalPages() -> [PDFPageText] {
        var first: [PDFWord] = []
        first += line(87, [(40, "Акционерный коммерческий банк «Капиталбанк»")])
        first += line(302, [(40, "Выписка за период: с 01.01.2026 год по 15.10.2026 год.")])
        first += line(431, [(46, "Дата проведения")])
        first += line(436.8, [(125, "Сумма"), (205, "Детали операции")])
        first += line(442, [(46, "операции")])
        first += line(460.8, [(46, "29.01.2026"), (125, "196 431,51"),
                              (205, "Выплата начисленных процентов по сделке № 312999 за период с 27.01.2026 по 28.01.2026")])
        first += line(479.5, [(205, "Списание по операциям покупке OOO TEST MARKET SLIP No 52352")])
        first += line(484.8, [(46, "17.08.2026"), (125, "-103 550,00")])
        first += line(489.3, [(205, "за 15.08.2026 Номер карты: 414084******7058; TID: 121127QI RRN:_30_7605")])
        first += line(508.3, [(46, "18.08.2026"), (125, "-1 010 000,00"),
                              (205, "Перевод с VISA UZS KB на HUMO KB через МП ТЕR.ID: VNDK0002; за 18.08.2026;")])
        first += line(527.8, [(205, "Перевод с DEPOSIT UZS на VISA UZS KB через МП ТЕR.ID: КОД_ТЕРМИНАЛА]; за 19.08.2026")])
        first += line(532.6, [(46, "19.08.2026"), (125, "600 000,00")])
        first += line(537.3, [(205, "Номер карты: 414084******7058;")])
        first += line(758.6, [(40, "Управляющий директор")])
        first += line(764.6, [(449, "Онлайн проверка")])
        first += line(772.8, [(40, "АКБ «Капиталбанк»")])
        first += line(776.6, [(449, "подлинности выписки")])

        var second: [PDFWord] = []
        second += line(123.3, [(46, "Дата проведения")])
        second += line(128.6, [(125, "Сумма"), (205, "Детали операции")])
        second += line(133.8, [(46, "операции")])
        second += line(152.6, [(205, "RRN:611106842825 15007_1")])
        second += line(171.3, [(46, "21.08.2026"), (125, "-8 000,00"),
                               (205, "Списание по переводу UzumBank H2H VisaKB Debit SLIP No 0000923 через МП ТЕR.ID: TM0041; за 20.08.2026;")])
        return [PDFPageText(words: first), PDFPageText(words: second)]
    }

    func testLayoutRestoresKapitalRows() {
        let rows = PDFTableLayout.rows(pages: kapitalPages(), titles: ["Дата", "Сумма", "Детали"], spine: 2, anchor: 0,
                                       isAnchor: PDFStatementText.startsWithDate)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map { $0[0] }, ["29.01.2026", "17.08.2026", "18.08.2026", "19.08.2026", "21.08.2026"])
        XCTAssertEqual(rows[1][1], "-103 550,00")
        XCTAssertTrue(rows[1][2].hasPrefix("Списание по операциям покупке OOO TEST MARKET"), "Строка над датой — начало деталей этой же записи")
        XCTAssertTrue(rows[1][2].hasSuffix("RRN:_30_7605"))
        XCTAssertTrue(rows[3][2].hasSuffix("RRN:611106842825 15007_1"), "Продолжение со следующей страницы")
        XCTAssertFalse(rows.joined().joined().contains("Онлайн"), "Подвал страницы не попадает в операции")
    }

    func testKapitalbankRows() throws {
        let table = try XCTUnwrap(PDFStatementReader.table(from: kapitalPages()))
        let adapter = StatementAdapterRegistry.adapter(for: table)
        XCTAssertEqual(adapter.displayName, "Kapitalbank")
        XCTAssertEqual(adapter.bank, .kapitalbank)
        XCTAssertEqual(table.rows.count, 6)
        let rows = KapitalbankPDFParser().rows(from: kapitalPages())

        XCTAssertEqual(rows[0].amount, Decimal(string: "196431.51"))
        XCTAssertEqual(rows[0].date, "29.01.2026", "«за период» — не дата операции")
        XCTAssertEqual(rows[0].description, "Выплата начисленных процентов")
        XCTAssertEqual(rows[0].card, "414084******7058", "Карта счёта — для строк без номера")

        XCTAssertEqual(rows[1].date, "15.08.2026", "Дата совершения из «за ДД.ММ.ГГГГ», а не дата проведения")
        XCTAssertEqual(rows[1].amount, -103_550)
        XCTAssertEqual(rows[1].merchant, "OOO TEST MARKET")
        XCTAssertEqual(rows[1].description, "Списание по операциям покупке OOO TEST MARKET")
        XCTAssertEqual(rows[2].description, "Перевод с VISA UZS KB на HUMO KB")
        XCTAssertEqual(rows[3].description, "Перевод с DEPOSIT UZS на VISA UZS KB")
        XCTAssertEqual(rows[4].date, "20.08.2026")
        for row in rows {
            XCTAssertFalse(row.description.contains("RRN") || row.description.contains("414084") || row.description.contains("ID:"), row.description)
        }
        XCTAssertTrue(ImportPipeline.isDepositTransfer(rows[3].description))
        XCTAssertTrue(ImportPipeline.isDepositTransfer("DEP UZS 2 VISA"))
        XCTAssertFalse(ImportPipeline.isDepositTransfer(rows[2].description))
        XCTAssertFalse(ImportPipeline.isDepositTransfer(rows[0].description))
    }

    // MARK: - Uzum Bank

    /// Справка Uzum: дата/время и сумма переносятся по строкам, записи разделены чуть большим интервалом,
    /// время совершения операции — в конце деталей, запись продолжается на следующей странице.
    func uzumPages() -> [PDFPageText] {
        var first: [PDFWord] = []
        let h = 10.0
        first += line(73.5, [(92, "АО «UZUM BANK»")], height: h)
        first += line(298.2, [(268, "СПРАВКА")], height: h)
        first += line(467.7, [(96, "Дата и")], height: h)
        first += line(474.0, [(152, "Дата"), (209, "Номер"), (265, "Сумма")], height: h)
        first += line(480.3, [(96, "время"), (316, "Детали операции")], height: h)
        first += line(486.6, [(152, "документа"), (209, "документа"), (265, "операции")], height: h)
        first += line(493.0, [(96, "операции")], height: h)
        // 1: поступление 805 000 (сумма на двух строках)
        first += line(509.4, [(316, "Поступление по P2P МПС UZS")], height: h)
        first += line(522.0, [(316, "491699******5275 по MID 000000010000020 в")], height: h)
        first += line(534.7, [(96, "20.01.2026"), (265, "805"), (316, "TID 10000020 сог-но RRN 2601190401109565 в")], height: h)
        first += line(541.0, [(152, "20.01.2026"), (209, "75158046")], height: h)
        first += line(547.3, [(96, "17:23:01"), (265, "000,00"), (316, "UBCL_us-on-")], height: h)
        first += line(560.0, [(316, "us_visa_20260120_1001_14_1_001.xml, 2026-01-")], height: h)
        first += line(572.6, [(316, "19 10.38.55")], height: h)
        // 2: оплата 68 759
        first += line(589.0, [(316, "Оплата по карте МПС UZS 491699******5275")], height: h)
        first += line(601.7, [(316, "по MID 000000010001882 в TID 10005551 сог-")], height: h)
        first += line(608.0, [(96, "20.01.2026")], height: h)
        first += line(614.3, [(152, "20.01.2026"), (209, "75158821"), (265, "68 759,00"), (316, "но RRN 2601190401265730 в UBCL_us-on-")], height: h)
        first += line(620.6, [(96, "17:23:01")], height: h)
        first += line(627.0, [(316, "us_visa_20260120_1001_14_1_001.xml, 2026-01-")], height: h)
        first += line(639.6, [(316, "19 12.13.42")], height: h)
        // 3: перевод 10 000 — окончание на следующей странице
        first += line(656.0, [(316, "P2P перевод по VISA UZS 491699******5275")], height: h)
        first += line(668.7, [(316, "по MID 000000010000020 в")], height: h)
        first += line(681.3, [(96, "21.01.2026"), (265, "10 000,00"), (316, "TID 10000020 сог-но RRN 2601190401414195 в")], height: h)
        first += line(687.6, [(152, "21.01.2026"), (209, "75163135")], height: h)

        var second: [PDFWord] = []
        second += line(90.7, [(316, "UBCL_us-on- us_visa_20260121_1001_14_2_001.xml, 2026-01-")], height: h)
        second += line(103.3, [(316, "21 09.15.00")], height: h)
        // 4: возврат 5 000 без времени совершения
        second += line(119.7, [(316, "Возврат оплаты по карте 491699******5275")], height: h)
        second += line(126.0, [(96, "22.01.2026"), (152, "22.01.2026"), (209, "75170001"), (265, "5 000,00")], height: h)
        second += line(132.3, [(316, "по MID 000000010000020 в TID 10000020")], height: h)
        second += line(138.6, [(96, "10:00:00")], height: h)
        second += line(145.0, [(316, "UBCL_visa.xml, 2026-01-22 00.00.00")], height: h)
        return [PDFPageText(words: first), PDFPageText(words: second)]
    }

    func testUzumRows() throws {
        let table = try XCTUnwrap(PDFStatementReader.table(from: uzumPages()))
        XCTAssertEqual(StatementAdapterRegistry.adapter(for: table).displayName, "Uzum Bank")
        let rows = UzumPDFParser().rows(from: uzumPages())
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.amount), [805_000, -68_759, -10_000, 5_000], "Направление — по началу деталей")
        XCTAssertEqual(rows.map(\.date), ["19.01.2026", "19.01.2026", "21.01.2026", "22.01.2026"], "Дата совершения из деталей")
        XCTAssertEqual(rows.map(\.time), ["10:38:55", "12:13:42", "09:15:00", "10:00:00"])
        XCTAssertEqual(rows.map(\.description), ["Поступление по P2P МПС UZS", "Оплата по карте МПС UZS", "P2P перевод по VISA UZS", "Возврат оплаты по карте"])
        XCTAssertEqual(Set(rows.map(\.card)), ["491699******5275"])
    }

    func testUnknownPDFIsNotRecognized() {
        let page = PDFPageText(words: line(100, [(40, "Счёт на оплату № 15 от 01.02.2026")]))
        XCTAssertNil(PDFStatementReader.table(from: [page]))
    }

    // MARK: - Настоящие PDF (PDFKit)

    #if canImport(PDFKit)
    /// Синтетические выписки, свёрстанные как у банков и напечатанные Chromium в PDF: проверяется извлечение слов PDFKit.
    func testReadsKapitalbankPDF() throws {
        let pages = try PDFTextExtractor.pages(from: try fixture("kapitalbank_statement.pdf"))
        XCTAssertNotNil(PDFStatementReader.table(from: pages), debugWords(pages))
        let document = try ImportReader.read(data: try fixture("kapitalbank_statement.pdf"), fileName: "statement.pdf")
        XCTAssertEqual(document.format, .pdf)
        let table = try XCTUnwrap(document.tables.first)
        XCTAssertEqual(table.rows.count, 61, debugWords("kapitalbank_statement.pdf"))
        let amounts = table.rows.dropFirst().compactMap { ValueParsers.amount($0[2]) }
        XCTAssertEqual(amounts.filter { $0 > 0 }.reduce(0, +), Decimal(string: "7565406.12"))
        XCTAssertEqual(amounts.filter { $0 < 0 }.reduce(0, +), -13_342_440)
        XCTAssertEqual(table.rows[2][3].text, "IP OOO DEMO FOOD")
        XCTAssertEqual(table.rows[2][0].text, "02.03.2026")
        XCTAssertEqual(table.rows[1][5].text, "414000******1234")
    }

    func testReadsUzumPDF() throws {
        let pages = try PDFTextExtractor.pages(from: try fixture("uzum_statement.pdf"))
        XCTAssertNotNil(PDFStatementReader.table(from: pages), debugWords(pages))
        let document = try ImportReader.read(data: try fixture("uzum_statement.pdf"), fileName: "statement.pdf")
        let table = try XCTUnwrap(document.tables.first)
        XCTAssertEqual(table.rows.count, 41, debugWords("uzum_statement.pdf"))
        let amounts = table.rows.dropFirst().compactMap { ValueParsers.amount($0[2]) }
        XCTAssertEqual(amounts.filter { $0 > 0 }.reduce(0, +), 10_880_410)
        XCTAssertEqual(amounts.filter { $0 < 0 }.reduce(0, +), -689_490)
        XCTAssertEqual(table.rows[1][0].text, "01.03.2026")
        XCTAssertEqual(table.rows[1][1].text, "10:00:00")
    }

    /// Строки первой страницы — для разбора падения в CI.
    func debugWords(_ name: String) -> String {
        guard let data = try? fixture(name), let pages = try? PDFTextExtractor.pages(from: data) else { return "no pages" }
        return debugWords(pages)
    }

    func debugWords(_ pages: [PDFPageText]) -> String {
        guard let page = pages.first else { return "no pages" }
        return "pages \(pages.count), words \(page.words.count)\n" + PDFTableLayout.lines(page.words).prefix(40).map { line in
            String(format: "%.1f ", line.y) + line.words.map { String(format: "[%.0f-%.0f h%.1f]", $0.minX, $0.maxX, $0.height) + $0.text }.joined(separator: " ")
        }.joined(separator: "\n")
    }
    #endif

    // MARK: - Та же карта в Payme и в выписке банка

    func kapitalPipeline(existing: [FinanceTransaction], fingerprints: Set<String> = [], deposit: Account? = nil) -> ImportPipeline {
        ImportPipeline(account: visa, cardAccounts: ["414084*7058": visa], existing: existing, existingFingerprints: fingerprints,
                       depositAccount: deposit, categorizer: CategorizationEngine(categories: categories, rules: []), calendar: calendar)
    }

    func kapitalPreview(existing: [FinanceTransaction], deposit: Account? = nil) throws -> ImportPreview {
        let table = try XCTUnwrap(PDFStatementReader.table(from: kapitalPages()))
        let mapping = StatementAdapterRegistry.adapter(for: table).mapping(for: table, calendar: calendar)
        XCTAssertEqual(StatementCard.cards(in: table, mapping: mapping).map(\.id), ["414084*7058"])
        return try kapitalPipeline(existing: existing, deposit: deposit).preview(table: table, mapping: mapping)
    }

    /// Уже загружено из Payme: покупка, перевод Visa → Humo с комиссией, пополнение с вклада.
    func paymeHistory() -> [FinanceTransaction] {
        let transfer = FinanceTransaction(kind: .transfer, amount: uzs(1_000_000), accountID: visa.id, counterAccountID: humo.id,
                                          counterAmount: uzs(1_000_000), date: date("18.08.2026", "10:05"), source: .importFile,
                                          importFingerprint: "payme-out ⇄ payme-in")
        return [
            FinanceTransaction(kind: .expense, amount: uzs(103_550), accountID: visa.id, merchant: "Test Market",
                               date: date("15.08.2026", "19:40"), source: .importFile, importFingerprint: "payme-shop"),
            transfer,
            FinanceTransaction(kind: .fee, amount: uzs(10_000), accountID: visa.id, date: date("18.08.2026", "10:05"),
                               source: .importFile, importFingerprint: "fee:payme-out", linkedTransactionID: transfer.id),
            FinanceTransaction(kind: .income, amount: uzs(600_000), accountID: visa.id, merchant: "DEP UZS 2 VISA",
                               date: date("19.08.2026", "09:00"), source: .importFile, importFingerprint: "payme-dep"),
            // Та же сумма, но через пять дней — другая операция.
            FinanceTransaction(kind: .expense, amount: uzs(8_000), accountID: visa.id, date: date("26.08.2026", "11:00"),
                               source: .importFile, importFingerprint: "payme-other")
        ]
    }

    func testBankStatementDoesNotDoublePayme() throws {
        let preview = try kapitalPreview(existing: paymeHistory())
        func row(_ amount: Decimal) throws -> ImportCandidate { try XCTUnwrap(preview.candidates.first { $0.amount == uzs(amount) }) }

        let shop = try row(103_550)
        guard case .importedElsewhere(_, let replaceable) = shop.duplicate else { return XCTFail("Покупка уже есть из Payme") }
        XCTAssertTrue(replaceable)
        XCTAssertFalse(shop.include)
        let transfer = try row(1_010_000)
        guard case .importedElsewhere(_, false) = transfer.duplicate else { return XCTFail("Перевод из Payme вместе с комиссией — та же операция") }
        guard case .importedElsewhere = try row(600_000).duplicate else { return XCTFail("Пополнение с вклада уже есть") }

        XCTAssertEqual(try row(Decimal(string: "196431.51")!).duplicate, .none, "Процентов в Payme не было")
        XCTAssertEqual(try row(8_000).duplicate, .none, "Через пять дней — другая операция")
        XCTAssertEqual(preview.elsewhereCount, 3)
        XCTAssertEqual(kapitalPipeline(existing: paymeHistory()).transactions(from: preview.candidates).count, 2)
    }

    func testDepositRowsBecomeTransfers() throws {
        let alone = try kapitalPreview(existing: [], deposit: deposit)
        let row = try XCTUnwrap(alone.candidates.first { $0.amount == uzs(600_000) })
        XCTAssertEqual(row.depositAccountID, deposit.id)
        XCTAssertEqual(row.transferRoute?.from, deposit.id)
        XCTAssertEqual(row.transferRoute?.to, visa.id)
        XCTAssertEqual(alone.total(.inflow), uzs(Decimal(string: "196431.51")!), "Деньги со своего вклада — не доход")

        let written = kapitalPipeline(existing: [], deposit: deposit).transactions(from: alone.candidates)
        let transfer = try XCTUnwrap(written.first { $0.kind == .transfer })
        XCTAssertEqual(transfer.accountID, deposit.id)
        XCTAssertEqual(transfer.counterAccountID, visa.id)

        // Пополнение уже записано из Payme доходом: перевод со вкладом заменяет его.
        let history = paymeHistory()
        let afterPayme = try kapitalPreview(existing: history, deposit: deposit)
        let replacing = try XCTUnwrap(afterPayme.candidates.first { $0.amount == uzs(600_000) })
        XCTAssertTrue(replacing.include)
        XCTAssertEqual(replacing.depositAccountID, deposit.id)
        XCTAssertEqual(afterPayme.replacedTransactionIDs, [history[3].id])
        XCTAssertEqual(afterPayme.replacedCount, 1)

        // Без счёта вклада — обычный доход.
        let plain = try kapitalPreview(existing: [])
        XCTAssertNil(plain.candidates.first { $0.amount == uzs(600_000) }?.depositAccountID)
    }

    /// Сначала выписка банка (перевод выглядит расходом), потом Payme: пара «списание + зачисление» становится
    /// переводом и заменяет расход, балансы и расходы — как при импорте одного Payme.
    func testPaymeTransferReplacesBankExpense() throws {
        let k = Account(bank: .kapitalbank, name: "Kapital", currency: .uzs)
        let orient = Account(bank: .orientFinans, name: "OFB", currency: .uzs)
        let work = Account(bank: .trastbank, name: "Work", currency: .uzs, lastFour: "9012")
        let table = try ImportReader.read(data: try fixture("payme_statement.xlsx"), fileName: "payme.xlsx").tables[0]
        let mapping = PaymeStatementAdapter().mapping(for: table, calendar: calendar)
        func payme(_ existing: [FinanceTransaction], _ fingerprints: Set<String> = []) -> ImportPipeline {
            ImportPipeline(account: k, cardAccounts: ["414000*1234": k, "860000*5678": orient, "561400*9012": work],
                           existing: existing, existingFingerprints: fingerprints,
                           categorizer: CategorizationEngine(categories: categories, rules: []), calendar: calendar)
        }
        let plain = try payme([]).preview(table: table, mapping: mapping)
        let pair = try XCTUnwrap(plain.candidates.first { $0.ownTransfer?.confirmedByDetails == true })

        let db = try LedgerDatabase.inMemory()
        try db.seedDefaultCategories(language: .ru)
        for item in [k, orient, work] { try db.createAccount(item) }
        // Строка из выписки Капиталбанка: дата — без времени.
        let day = calendar.startOfDay(for: pair.date).addingTimeInterval(12 * 3600)
        let bankExpense = FinanceTransaction(kind: .expense, amount: pair.amount, accountID: k.id, note: "Перевод с VISA UZS KB на VISA",
                                             date: day, source: .importFile, importFingerprint: "kapital-row")
        XCTAssertEqual(try db.importTransactions([bankExpense]).inserted, 1)

        let stored = try db.transactions()
        let preview = try payme(stored, try db.existingFingerprints()).preview(table: table, mapping: mapping)
        let replaced = try XCTUnwrap(preview.candidates.first { $0.fingerprint == pair.fingerprint })
        XCTAssertNotNil(replaced.ownTransfer, "Строка из другой выписки всё равно собирается в перевод")
        XCTAssertTrue(replaced.include)
        XCTAssertEqual(preview.replacedTransactionIDs, [bankExpense.id])

        let rows = payme(stored).transactions(from: preview.candidates)
        XCTAssertEqual(try db.importTransactions(rows, replacing: preview.replacedTransactionIDs).inserted, 11)
        let after = try db.transactions()
        XCTAssertNil(after.first { $0.id == bankExpense.id }, "Расход из выписки банка заменён переводом")
        let balances = Ledger.balances(accounts: [k, orient, work], transactions: after)
        XCTAssertEqual(balances[k.id]?.minorUnits, -10_386_725)
        XCTAssertEqual(balances[work.id]?.minorUnits, -30_040_300)
        XCTAssertEqual(balances[orient.id]?.minorUnits, 9_300_800)
        XCTAssertTrue(try db.integrityIssues().isEmpty)
    }
}
