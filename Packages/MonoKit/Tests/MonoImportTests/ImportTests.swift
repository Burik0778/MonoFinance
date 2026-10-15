import XCTest
import MonoCore
import MonoIntelligence
import MonoStorage
@testable import MonoImport

final class ImportTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }
    let categories = DefaultCategories.make(language: .ru)
    let account = Account(bank: .kapitalbank, name: "Kapital", currency: .uzs)

    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"), name)
        return try Data(contentsOf: url)
    }

    func cat(_ key: String) -> UUID { DefaultCategories.id(for: key) }

    func pipeline(existing: [FinanceTransaction] = [], fingerprints: Set<String> = []) -> ImportPipeline {
        ImportPipeline(account: account, existing: existing, existingFingerprints: fingerprints,
                       categorizer: CategorizationEngine(categories: categories, rules: []), calendar: calendar)
    }

    func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - Распаковка

    func testInflateMatchesZlib() throws {
        for name in ["text", "random", "mixed"] {
            let original = try fixture("deflate_\(name).orig")
            for level in [0, 1, 9] {
                let compressed = try fixture("deflate_\(name)_\(level).bin")
                XCTAssertEqual(try Inflate.decompress(compressed), original, "\(name) level \(level)")
            }
        }
        XCTAssertThrowsError(try Inflate.decompress(Data([0xFF, 0xFF, 0xFF])))
        XCTAssertThrowsError(try Inflate.decompress(Data()))
    }

    func testZipArchive() throws {
        let archive = try ZipArchive(data: try fixture("archive.zip"))
        XCTAssertEqual(String(decoding: try archive.data(for: "stored.txt"), as: UTF8.self), "hello stored")
        XCTAssertEqual(String(decoding: try archive.data(for: "deflated.txt"), as: UTF8.self), String(repeating: "hello deflated ", count: 100))
        XCTAssertThrowsError(try archive.data(for: "missing.txt"))
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip at all, definitely".utf8)))
    }

    // MARK: - XLSX

    func testXLSXReading() throws {
        let document = try ImportReader.read(data: try fixture("statement.xlsx"), fileName: "statement.xlsx")
        XCTAssertEqual(document.format, .xlsx)
        XCTAssertEqual(document.tables.count, 1, "Пустой лист пропускается")
        let table = document.tables[0]
        XCTAssertEqual(table.name, "Выписка")
        XCTAssertEqual(table.rows[2].map(\.text), ["Дата операции", "Описание", "Сумма", "Валюта"], "Пустые строки отбрасываются")
        guard case .date(let first) = table.rows[3][0] else { return XCTFail("Ожидалась дата Excel") }
        XCTAssertEqual(ValueParsers.date(.date(first), calendar: calendar).map(components),
                       DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 15), "Время из Excel сохраняется в часовом поясе пользователя")
        XCTAssertEqual(table.rows[4][2], .number(Decimal(string: "-32000.5")!))
        XCTAssertEqual(table.rows[3][1], .text("KORZINKA CHILANZAR 12 TASHKENT UZ"))
    }

    func testXLSXPipeline() throws {
        let table = try ImportReader.read(data: try fixture("statement.xlsx"), fileName: "statement.xlsx").tables[0]
        let mapping = ColumnDetector.suggestMapping(for: table, calendar: calendar)
        XCTAssertEqual(mapping.headerRow, 2, "Преамбула выписки пропускается")
        XCTAssertEqual(mapping.column(.date), 0)
        XCTAssertEqual(mapping.column(.description), 1)
        XCTAssertEqual(mapping.column(.amount), 2)
        XCTAssertEqual(mapping.column(.currency), 3)

        let preview = try pipeline().preview(table: table, mapping: mapping)
        XCTAssertEqual(preview.candidates.count, 7)
        XCTAssertEqual(preview.skipped.map(\.reason), [.otherCurrency, .noDate], "USD-строка и строка «Итого»")

        let korzinka = preview.candidates[0]
        XCTAssertEqual(korzinka.amount, Money(major: 245_000, currency: .uzs))
        XCTAssertEqual(korzinka.direction, .outflow)
        XCTAssertEqual(korzinka.kind, .expense)
        XCTAssertEqual(korzinka.merchant, "Korzinka")
        XCTAssertEqual(korzinka.categoryID, cat(SystemCategoryKey.groceries))

        XCTAssertEqual(preview.candidates[1].amount.minorUnits, 3_200_050, "Дробная сумма 32 000,50")
        XCTAssertNotEqual(preview.candidates[1].fingerprint, preview.candidates[2].fingerprint, "Две одинаковые поездки — две операции")
        XCTAssertEqual(preview.candidates[3].kind, .income)
        XCTAssertEqual(preview.candidates[3].categoryID, cat(SystemCategoryKey.salary))
        XCTAssertEqual(preview.candidates[4].kind, .fee)
        XCTAssertNil(preview.candidates[4].categoryID)
        XCTAssertEqual(preview.candidates[6].kind, .refund)
        XCTAssertEqual(preview.total(.outflow), Money(major: Decimal(string: "399001")!, currency: .uzs))
    }

    func testReimportIsDeduplicatedThroughDatabase() throws {
        let db = try LedgerDatabase.inMemory()
        try db.seedDefaultCategories(language: .ru)
        try db.createAccount(account)
        let table = try ImportReader.read(data: try fixture("statement.xlsx"), fileName: "statement.xlsx").tables[0]
        let mapping = ColumnDetector.suggestMapping(for: table, calendar: calendar)

        let first = try pipeline().preview(table: table, mapping: mapping)
        let firstResult = try db.importTransactions(pipeline().transactions(from: first.candidates))
        XCTAssertEqual(firstResult.inserted, 7)

        let second = try pipeline(existing: try db.transactions(), fingerprints: try db.existingFingerprints()).preview(table: table, mapping: mapping)
        XCTAssertTrue(second.candidates.allSatisfy { $0.duplicate == .alreadyImported })
        XCTAssertEqual(second.includedCount, 0)
        let secondResult = try db.importTransactions(pipeline().transactions(from: second.candidates))
        XCTAssertEqual(secondResult.inserted, 0)
        XCTAssertEqual(try db.transactionCount(), 7)
        XCTAssertTrue(try db.integrityIssues().isEmpty)
    }

    func testManualEntryIsFlaggedAsPossibleDuplicate() throws {
        let table = try ImportReader.read(data: try fixture("statement.xlsx"), fileName: "statement.xlsx").tables[0]
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 7; c.hour = 21
        let manual = FinanceTransaction(kind: .expense, amount: Money(major: 85_000, currency: .uzs)!, accountID: account.id,
                                        categoryID: cat(SystemCategoryKey.cafe), date: calendar.date(from: c)!, source: .voice)
        let preview = try pipeline(existing: [manual]).preview(table: table, mapping: ColumnDetector.suggestMapping(for: table, calendar: calendar))
        let evos = preview.candidates.first { $0.merchant == "EVOS" }!
        XCTAssertEqual(evos.duplicate, ImportCandidate.DuplicateStatus.possible(existingID: manual.id))
        XCTAssertFalse(evos.include, "Возможный дубль по умолчанию не импортируется — решает пользователь")
    }

    func testOwnTransferHint() throws {
        let uzum = Account(bank: .uzum, name: "Uzum", currency: .uzs)
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 5; c.hour = 11
        let other = FinanceTransaction(kind: .expense, amount: Money(major: 12_000_000, currency: .uzs)!, accountID: uzum.id, date: calendar.date(from: c)!)
        let table = try ImportReader.read(data: try fixture("statement.xlsx"), fileName: "statement.xlsx").tables[0]
        let preview = try pipeline(existing: [other]).preview(table: table, mapping: ColumnDetector.suggestMapping(for: table, calendar: calendar))
        XCTAssertEqual(preview.candidates[3].possibleOwnTransferID, other.id, "Поступление совпало со списанием на другом своём счёте")
    }

    // MARK: - CSV

    func testCP1251DebitCreditCSV() throws {
        let document = try ImportReader.read(data: try fixture("statement_cp1251.csv"), fileName: "statement.csv")
        XCTAssertEqual(document.format, .csv)
        let table = document.tables[0]
        XCTAssertEqual(table.rows[0].map(\.text), ["Дата", "Время", "Назначение платежа", "Дебет", "Кредит"])
        XCTAssertEqual(table.rows[3][2].text, "Кафе \"Сафия\"; торт", "Кавычки и разделитель внутри поля")

        let mapping = ColumnDetector.suggestMapping(for: table, calendar: calendar)
        XCTAssertEqual(mapping.column(.date), 0)
        XCTAssertEqual(mapping.column(.time), 1)
        XCTAssertEqual(mapping.column(.description), 2)
        XCTAssertEqual(mapping.column(.debit), 3)
        XCTAssertEqual(mapping.column(.credit), 4)

        let preview = try pipeline().preview(table: table, mapping: mapping)
        XCTAssertEqual(preview.candidates.count, 3)
        XCTAssertEqual(preview.candidates[0].amount, Money(major: 1_250_000, currency: .uzs))
        XCTAssertEqual(preview.candidates[0].direction, .outflow)
        XCTAssertEqual(preview.candidates[0].merchant, "Makro")
        XCTAssertEqual(components(preview.candidates[0].date), DateComponents(year: 2026, month: 10, day: 14, hour: 8, minute: 30))
        XCTAssertEqual(preview.candidates[1].direction, .inflow)
        XCTAssertEqual(preview.candidates[2].categoryID, cat(SystemCategoryKey.cafe))
    }

    func testUTF8BOMCSVWithUSAmounts() throws {
        let table = try ImportReader.read(data: try fixture("statement_utf8_bom.csv"), fileName: "s.csv").tables[0]
        XCTAssertEqual(table.rows[0][0].text, "Date", "BOM удалён")
        let dollarAccount = Account(bank: .orientFinans, name: "OFB", currency: .usd)
        let pipeline = ImportPipeline(account: dollarAccount, existing: [], existingFingerprints: [],
                                      categorizer: CategorizationEngine(categories: categories, rules: []), calendar: calendar)
        let mapping = ColumnDetector.suggestMapping(for: table, calendar: calendar)
        XCTAssertEqual(mapping.column(.merchant), 1)
        let preview = try pipeline.preview(table: table, mapping: mapping)
        XCTAssertEqual(preview.candidates.map(\.amount.minorUnits), [125_000, 240_000])
        XCTAssertEqual(preview.candidates[0].categoryID, cat(SystemCategoryKey.subscriptions))
        XCTAssertEqual(preview.candidates[1].categoryID, cat(SystemCategoryKey.freelance))
    }

    func testDelimiterDetectionAndQuotes() {
        XCTAssertEqual(CSVReader.detectDelimiter("a;b;c\n1;2;3\n4;5;6"), ";")
        XCTAssertEqual(CSVReader.detectDelimiter("a,b\n1,\"2,5\"\n3,4"), ",")
        XCTAssertEqual(CSVReader.detectDelimiter("a\tb\tc\n1\t2\t3"), "\t")
        XCTAssertEqual(CSVReader.parse("a,\"b\nc\",d\r\ne,f,g", delimiter: ","), [["a", "b\nc", "d"], ["e", "f", "g"]])
    }

    // MARK: - Значения

    func testAmountParsing() {
        let cases: [(String, String)] = [
            ("1 234 567,89", "1234567.89"), ("1,234,567.89", "1234567.89"), ("1.234.567,89", "1234567.89"),
            ("-85 000.00", "-85000"), ("(1 000)", "-1000"), ("−5 000 UZS", "-5000"), ("+12.5", "12.5"),
            ("245,000", "245000"), ("85000,50", "85000.5"), ("1 250 000,00 сум", "1250000"), ("5000-", "-5000"),
            ("$1,250.00", "1250")
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ValueParsers.amount(raw), Decimal(string: expected), raw)
        }
        XCTAssertNil(ValueParsers.amount("abc"))
        XCTAssertNil(ValueParsers.amount(""))
        XCTAssertNil(ValueParsers.amount("12-34"))
    }

    func testDateParsing() {
        func parse(_ text: String) -> DateComponents? {
            ValueParsers.date(.text(text), calendar: calendar).map(components)
        }
        XCTAssertEqual(parse("14.10.2026"), DateComponents(year: 2026, month: 10, day: 14, hour: 12, minute: 0))
        XCTAssertEqual(parse("14.10.2026 18:45"), DateComponents(year: 2026, month: 10, day: 14, hour: 18, minute: 45))
        XCTAssertEqual(parse("2026-10-14T18:45:10"), DateComponents(year: 2026, month: 10, day: 14, hour: 18, minute: 45))
        XCTAssertEqual(parse("14/10/26"), DateComponents(year: 2026, month: 10, day: 14, hour: 12, minute: 0))
        XCTAssertEqual(parse("10/14/2026"), DateComponents(year: 2026, month: 10, day: 14, hour: 12, minute: 0), "Американский порядок, если иначе дата невозможна")
        XCTAssertNil(parse("31.02.2026"))
        XCTAssertNil(parse("Итого"))
        XCTAssertNil(parse("12345"))
        XCTAssertEqual(ValueParsers.date(.number(46_309), calendar: calendar).map(components)?.day, 14, "Серийная дата Excel в CSV")
    }

    func testCurrencyAndDirectionParsing() {
        XCTAssertEqual(ValueParsers.currency(.text("860")), .uzs)
        XCTAssertEqual(ValueParsers.currency(.text("сум")), .uzs)
        XCTAssertEqual(ValueParsers.currency(.text("usd")), .usd)
        XCTAssertNil(ValueParsers.currency(.empty))
        XCTAssertEqual(ValueParsers.direction(.text("Списание")), .outflow)
        XCTAssertEqual(ValueParsers.direction(.text("Зачисление")), .inflow)
        XCTAssertEqual(ValueParsers.direction(.text("CREDIT")), .inflow)
    }

    func testHeaderRoles() {
        XCTAssertEqual(ColumnDetector.role(forHeader: "Сумма списания"), .debit)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Сумма зачисления"), .credit)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Сумма операции"), .amount)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Дата транзакции"), .date)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Остаток"), .balance)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Tavsif"), .description)
        XCTAssertNil(ColumnDetector.role(forHeader: "Что-то"))
    }

    func testProfilesRoundTripAndSignature() throws {
        let table = try ImportReader.read(data: try fixture("statement_cp1251.csv"), fileName: "s.csv").tables[0]
        let mapping = ColumnDetector.suggestMapping(for: table, calendar: calendar)
        let signature = ColumnDetector.signature(for: table, mapping: mapping)
        XCTAssertEqual(signature, "data|vremya|naznachenieplatezha|debet|kredit")
        let profile = ImportProfile(signature: signature, name: "Kapitalbank CSV", mapping: mapping, accountID: account.id)
        XCTAssertEqual(ImportProfile.decode(payload: profile.encodedPayload()), profile)
    }

    func testUnsupportedAndEmptyFiles() {
        XCTAssertThrowsError(try ImportReader.read(data: Data(), fileName: "a.csv")) { XCTAssertEqual($0 as? ImportError, .emptyFile) }
        XCTAssertThrowsError(try ImportReader.read(data: Data([0xD0, 0xCF, 0x11, 0xE0]), fileName: "old.xls")) {
            XCTAssertEqual($0 as? ImportError, .unsupportedFormat)
        }
        XCTAssertThrowsError(try ImportReader.read(data: Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]), fileName: "broken.xlsx")) {
            XCTAssertEqual($0 as? ImportError, .corruptArchive)
        }
        XCTAssertEqual(StatementAdapterRegistry.verifiedBanks, [.kapitalbank, .uzum], "Проверенными считаются только форматы, разобранные на реальных выписках (PDF Kapitalbank и Uzum Bank)")
    }

    // MARK: - Payme: все карты в одном файле

    let orient = Account(bank: .orientFinans, name: "OFB", currency: .uzs)
    let work = Account(bank: .trastbank, name: "Work", currency: .uzs, lastFour: "9012")

    func paymeTable() throws -> ImportTable {
        try ImportReader.read(data: try fixture("payme_statement.xlsx"), fileName: "payme.xlsx").tables[0]
    }

    func paymePipeline(existing: [FinanceTransaction] = [], fingerprints: Set<String> = []) -> ImportPipeline {
        ImportPipeline(account: account,
                       cardAccounts: ["414000*1234": account, "860000*5678": orient, "561400*9012": work],
                       existing: existing, existingFingerprints: fingerprints,
                       categorizer: CategorizationEngine(categories: categories, rules: []), calendar: calendar)
    }

    func testCardKeys() throws {
        let card = try XCTUnwrap(CardKey("414084******7058"))
        XCTAssertEqual(card.bin, "414084")
        XCTAssertEqual(card.tail, "7058")
        XCTAssertEqual(card.lastFour, "7058")
        let sender = try XCTUnwrap(CardKey("Карта отправителя:\n 414084*******058\t"))
        XCTAssertEqual(sender.tail, "058")
        XCTAssertTrue(card.matches(sender), "Payme маскирует номер отправителя иначе — та же карта")
        XCTAssertFalse(card.matches(try XCTUnwrap(CardKey("414084******7158"))))
        XCTAssertFalse(card.matches(try XCTUnwrap(CardKey("561468******7058"))))
        XCTAssertEqual(CardKey("8600123456789012")?.id, "860012*9012")
        XCTAssertNil(CardKey("ID маркета:\n K224\t"))
        XCTAssertNil(CardKey("Пользователь:\n 61b6db656280d501c6f4597b\t"))
        XCTAssertNil(CardKey("15-10-2026"))
    }

    func testPaymeStatusAndHeaders() {
        XCTAssertTrue(ValueParsers.isCompleted(.text("Оплачен")))
        XCTAssertTrue(ValueParsers.isCompleted(.empty))
        XCTAssertFalse(ValueParsers.isCompleted(.text("Отменен")))
        XCTAssertFalse(ValueParsers.isCompleted(.text("В очереди")))
        XCTAssertEqual(ColumnDetector.role(forHeader: "Номер карты"), .card)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Название карты"), .cardName)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Состояние чека"), .status)
        XCTAssertEqual(ColumnDetector.role(forHeader: "Реквизиты платежа"), .details)
    }

    func testPaymeFormatIsRecognized() throws {
        let table = try paymeTable()
        let adapter = StatementAdapterRegistry.adapter(for: table)
        XCTAssertEqual(adapter.id, "payme")
        XCTAssertEqual(adapter.displayName, "Payme")
        XCTAssertFalse(PaymeStatementAdapter().matches(try ImportReader.read(data: try fixture("statement.xlsx"), fileName: "s.xlsx").tables[0]))

        let mapping = adapter.mapping(for: table, calendar: calendar)
        XCTAssertEqual(mapping.headerRow, 0)
        XCTAssertEqual(mapping.column(.date), 0)
        XCTAssertEqual(mapping.column(.time), 1)
        XCTAssertEqual(mapping.column(.direction), 2)
        XCTAssertEqual(mapping.column(.merchant), 3)
        XCTAssertEqual(mapping.column(.amount), 5)
        XCTAssertEqual(mapping.column(.category), 6)
        XCTAssertEqual(mapping.column(.details), 8)
        XCTAssertEqual(mapping.column(.card), 9)
        XCTAssertEqual(mapping.column(.cardName), 10)
        XCTAssertEqual(mapping.column(.status), 13)

        let cards = StatementCard.cards(in: table, mapping: mapping)
        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(cards.first?.name, "KapitalVisa", "Карты по числу строк")
        let accounts = [account, orient, work]
        func suggestion(_ name: String) -> UUID? { cards.first { $0.name == name }?.suggestedAccount(in: accounts)?.id }
        XCTAssertEqual(suggestion("KapitalVisa"), account.id, "По названию банка в имени карты")
        XCTAssertEqual(suggestion("Orient Finans Bank"), orient.id)
        XCTAssertEqual(suggestion("Work"), work.id, "По последним 4 цифрам")
        XCTAssertNil(suggestion("Humo"))
    }

    func testPaymeOwnTransfersBecomeTransfersWithFees() throws {
        let table = try paymeTable()
        let preview = try paymePipeline().preview(table: table, mapping: PaymeStatementAdapter().mapping(for: table, calendar: calendar))
        func uzs(_ value: Decimal) -> Money { Money(major: value, currency: .uzs)! }

        XCTAssertEqual(preview.skipped.filter { $0.reason == .notCompleted }.count, 2, "Отменённый и «В очереди»")
        XCTAssertEqual(preview.skipped.filter { $0.reason == .unassignedCard }.count, 1, "Карта без счёта не импортируется")
        XCTAssertEqual(preview.candidates.count, 11)
        XCTAssertEqual(preview.visibleCandidates.count, 9, "Зачисления внутри переводов скрыты")
        XCTAssertEqual(preview.transferCount, 2)
        XCTAssertEqual(preview.feeTotal, uzs(1500))

        let payme = try XCTUnwrap(preview.candidates.first { $0.ownTransfer?.confirmedByDetails == true })
        XCTAssertEqual(payme.accountID, account.id)
        XCTAssertEqual(payme.ownTransfer?.destinationAccountID, work.id)
        XCTAssertEqual(payme.ownTransfer?.received, uzs(50_000))
        XCTAssertEqual(payme.ownTransfer?.fee, uzs(500))

        let bankApp = try XCTUnwrap(preview.candidates.first { $0.ownTransfer?.confirmedByDetails == false })
        XCTAssertEqual(bankApp.accountID, account.id)
        XCTAssertEqual(bankApp.ownTransfer?.destinationAccountID, orient.id)
        XCTAssertEqual(bankApp.ownTransfer?.received, uzs(100_000))
        XCTAssertEqual(bankApp.ownTransfer?.fee, uzs(1000))

        // Покупка в магазине через минуту после чужого зачисления — не перевод.
        let shop = try XCTUnwrap(preview.candidates.first { $0.amount == uzs(336_446) })
        XCTAssertNil(shop.ownTransfer)
        XCTAssertEqual(shop.kind, .expense)
        XCTAssertEqual(shop.accountID, work.id)
        XCTAssertTrue(preview.candidates.contains { $0.amount == uzs(336_000) && $0.kind == .income && $0.isVisible })
        // Перевод на чужую карту — расход.
        let person = try XCTUnwrap(preview.candidates.first { $0.amount == uzs(10_100) })
        XCTAssertNil(person.ownTransfer)
        XCTAssertEqual(person.kind, .expense)
        XCTAssertTrue(preview.candidates.contains { $0.amount.minorUnits == 11_566_975 }, "Тийины сохраняются")

        XCTAssertEqual(preview.total(.outflow), uzs(393_937 + 13_957 + 336_446 + 10_100 + 6_992), "Переводы не попадают в списания")
        XCTAssertEqual(preview.total(.inflow), uzs(Decimal(string: "451669.75")!))

        // «Это не перевод» — пара снова две строки.
        var split = preview
        split.splitTransfer(bankApp.id)
        XCTAssertEqual(split.transferCount, 1)
        XCTAssertEqual(split.visibleCandidates.count, 10)
        XCTAssertTrue(split.candidates.contains { $0.amount == uzs(100_000) && $0.isVisible && $0.include })
    }

    func testPaymeImportKeepsBalancesAndIsIdempotent() throws {
        let db = try LedgerDatabase.inMemory()
        try db.seedDefaultCategories(language: .ru)
        for item in [account, orient, work] { try db.createAccount(item) }
        let table = try paymeTable()
        let mapping = PaymeStatementAdapter().mapping(for: table, calendar: calendar)

        let preview = try paymePipeline().preview(table: table, mapping: mapping)
        let rows = paymePipeline().transactions(from: preview.candidates)
        let transfers = rows.filter { $0.kind == .transfer }
        let fees = rows.filter { $0.kind == .fee }
        XCTAssertEqual(transfers.count, 2)
        XCTAssertEqual(fees.count, 2)
        XCTAssertEqual(Set(fees.compactMap(\.linkedTransactionID)), Set(transfers.map(\.id)), "Комиссия связана со своим переводом")
        XCTAssertEqual(try db.importTransactions(rows).inserted, 11)

        let stored = try db.transactions()
        let balances = Ledger.balances(accounts: [account, orient, work], transactions: stored)
        XCTAssertEqual(balances[account.id]?.minorUnits, -10_386_725)
        XCTAssertEqual(balances[work.id]?.minorUnits, -30_040_300)
        XCTAssertEqual(balances[orient.id]?.minorUnits, 9_300_800)
        let expenses = stored.filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        XCTAssertEqual(expenses, (393_937 + 13_957 + 336_446 + 10_100 + 6_992) * 100, "Переводы между своими картами — не расходы")

        let again = try paymePipeline(existing: stored, fingerprints: try db.existingFingerprints()).preview(table: table, mapping: mapping)
        XCTAssertTrue(again.candidates.allSatisfy { $0.duplicate == .alreadyImported }, "Обе строки перевода узнаются при повторном импорте")
        XCTAssertEqual(again.transferCount, 0)
        XCTAssertEqual(try db.importTransactions(paymePipeline().transactions(from: again.candidates)).inserted, 0)
        XCTAssertTrue(try db.integrityIssues().isEmpty)
    }

    func testProfileKeepsCardAccounts() {
        let profile = ImportProfile(signature: "s", name: "Payme", mapping: ColumnMapping(headerRow: 0, roles: [9: .card]),
                                    accountID: nil, cardAccounts: ["414000*1234": account.id])
        XCTAssertEqual(ImportProfile.decode(payload: profile.encodedPayload())?.cardAccounts, ["414000*1234": account.id])
        let single = ImportProfile(signature: "s", name: "Kapital", mapping: ColumnMapping(headerRow: 0, roles: [0: .date]), accountID: account.id)
        XCTAssertFalse(single.encodedPayload().contains("cardAccounts"), "Формат старых профилей не меняется")
        XCTAssertEqual(ImportProfile.decode(payload: single.encodedPayload()), single)
    }
}

