import XCTest
import MonoCore
@testable import MonoIntelligence

final class PrivacySanitizerTests: XCTestCase {
    private func clean(_ text: String) -> String { PrivacySanitizer.clean(text) }

    private func assertHidden(_ text: String, _ secrets: [String], file: StaticString = #filePath, line: UInt = #line) {
        let result = clean(text)
        for secret in secrets {
            XCTAssertFalse(result.contains(secret), "«\(secret)» осталось в «\(result)»", file: file, line: line)
        }
    }

    // MARK: - Карты и счета

    func testMaskedCardNumbers() {
        XCTAssertEqual(clean("Оплата картой 414084******7058 в Korzinka"), "Оплата картой [карта] в Korzinka")
        assertHidden("Карта 4140 84** **** 7058", ["4140", "7058"])
        assertHidden("8600-12XX-XXXX-3456", ["8600", "3456"])
    }

    func testCardTailAfterMask() {
        XCTAssertEqual(clean("Uzcard •• 1234"), "Uzcard [карта]")
        XCTAssertEqual(clean("VISA *7058"), "VISA [карта]")
        assertHidden("Humo **** 4321", ["4321"])
    }

    func testLastFourDigitsByContext() {
        assertHidden("карта 1234", ["1234"])
        assertHidden("Visa 7058", ["7058"])
        assertHidden("карта оканчивается на 1234", ["1234"])
        assertHidden("последние 4 цифры 7058", ["7058"])
    }

    func testFullCardAndAccountNumbers() {
        assertHidden("карта 8600 1234 5678 9012", ["8600", "9012"])
        assertHidden("Перевод на карту 8600123456789012", ["8600123456789012"])
        XCTAssertEqual(clean("счёт 20208000900123456789"), "счёт [номер]")
        assertHidden("ПИНФЛ 31234567890123", ["31234567890123"])
    }

    func testDocumentAndTerminalNumbers() {
        assertHidden("RRN: 123456789012 TID 12345678 MID: 90010023", ["123456789012", "12345678", "90010023"])
        assertHidden("Номер документа 4512/77", ["4512"])
        assertHidden("чек № 0012345", ["0012345"])
        assertHidden("док. 77812", ["77812"])
    }

    // MARK: - Контакты и документы

    func testPhonesAndEmail() {
        XCTAssertEqual(clean("Позвоните +998 90 123-45-67 или 90 123 45 67"), "Позвоните [телефон] или [телефон]")
        assertHidden("+998901234567", ["901234567"])
        assertHidden("+7 (912) 345-67-89", ["912", "345"])
        XCTAssertEqual(clean("mail: ivan.petrov@mail.ru"), "mail: [e-mail]")
    }

    func testPassport() {
        assertHidden("паспорт AA 1234567", ["1234567"])
        assertHidden("Паспорт 4510 123456", ["4510", "123456"])
        assertHidden("AB1234567", ["1234567"])
    }

    // MARK: - Имена

    func testPersonNames() {
        XCTAssertEqual(clean("Перевод Алишеру Каримову"), "Перевод [имя]")
        assertHidden("Получатель: ALIYEV ALISHER ANVAROVICH", ["ALIYEV", "ALISHER", "ANVAROVICH"])
        assertHidden("Иванов Иван Иванович", ["Иванов", "Иван"])
        assertHidden("Иванов И.И.", ["Иванов"])
        assertHidden("И. И. Иванов", ["Иванов"])
        assertHidden("Karimov Alisher o‘g‘li", ["Karimov", "Alisher"])
        assertHidden("KARIMOV ALISHER", ["KARIMOV", "ALISHER"])
    }

    func testMerchantTransfersBecomePersonTransfer() {
        XCTAssertEqual(PrivacySanitizer.merchant("P2P ALIYEV A."), PrivacySanitizer.personTransfer)
        XCTAssertEqual(PrivacySanitizer.merchant("Перевод на карту 8600 12** **** 3456"), PrivacySanitizer.personTransfer)
        XCTAssertEqual(PrivacySanitizer.merchant("O‘tkazma Karimov A."), PrivacySanitizer.personTransfer)
        XCTAssertEqual(PrivacySanitizer.merchant("Иванов Иван Иванович"), PrivacySanitizer.personTransfer)
    }

    // MARK: - Обычный текст не портится

    func testOrdinaryMerchantsStay() {
        for name in ["Korzinka", "EVOS", "OOO TEST MARKET", "Yandex Go", "Mediapark", "Uztelecom", "Coffee Bean",
                     "Makro Express", "Netflix.com", "UZUM MARKET", "Кафе Пушкин"] {
            XCTAssertEqual(PrivacySanitizer.merchant(name), name)
        }
    }

    func testQuestionsStay() {
        for question in ["На что я трачу больше всего?", "Где можно сэкономить?", "Сравни этот месяц с прошлым",
                         "Какие подписки и регулярные траты?", "Сколько я перевёл маме?",
                         "Сколько я потратил на еду в октябре 2026?", "Хочу накопить 12 500 000 сум за 3 месяца"] {
            XCTAssertEqual(clean(question), question)
        }
    }

    func testStrippedTransactionLosesNotesAndTags() {
        let transaction = FinanceTransaction(
            kind: .expense, amount: Money(major: 50_000, currency: .uzs)!, accountID: UUID(),
            merchant: "Перевод Алишеру Каримову", note: "долг за обед, тел. +998 90 123 45 67", tags: ["личное"],
            date: Date(), importFingerprint: "abc", receiptFileName: "receipt.jpg"
        )
        let stripped = PrivacySanitizer.stripped(transaction)
        XCTAssertNil(stripped.note)
        XCTAssertTrue(stripped.tags.isEmpty)
        XCTAssertNil(stripped.receiptFileName)
        XCTAssertNil(stripped.importFingerprint)
        XCTAssertEqual(stripped.merchant, PrivacySanitizer.personTransfer)
        XCTAssertEqual(stripped.amount, transaction.amount)
    }
}
