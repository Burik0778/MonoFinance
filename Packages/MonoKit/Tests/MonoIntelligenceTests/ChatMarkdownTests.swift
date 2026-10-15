import XCTest
@testable import MonoIntelligence

final class ChatMarkdownTests: XCTestCase {
    func testHeadingsParagraphsAndLists() {
        let text = """
        **Где можно сэкономить:**

        - «Без категории» — самая крупная статья.
        - **Подписки**:
          • перевод человеку
        1. Первое
        2) Второе

        Итог: около **1,4 млн сум**.
        """
        let blocks = ChatMarkdown.blocks(from: text)
        XCTAssertEqual(blocks.first, .heading("Где можно сэкономить"))
        XCTAssertEqual(blocks[1], .bullets(["«Без категории» — самая крупная статья.", "**Подписки**:", "перевод человеку"]))
        XCTAssertEqual(blocks[2], .numbered(["Первое", "Второе"]))
        XCTAssertEqual(blocks.last, .paragraph("Итог: около **1,4 млн сум**."))
    }

    func testTableWithWrappedSeparator() {
        let text = """
        ### Частые траты
        | Продавец | Сумма за 90 дней | Кол-во покупок |
        |-----------|-----------
        ------|-----|
        | **Перевод человеку** | 25 741 760 сум | 157 |
        | Korzinka | 4 744 267 сум | 20 |
        """
        let blocks = ChatMarkdown.blocks(from: text)
        XCTAssertEqual(blocks.first, .heading("Частые траты"))
        XCTAssertEqual(blocks.count, 2)
        guard case .table(let headers, let rows) = blocks[1] else { return XCTFail("ожидалась таблица: \(blocks)") }
        XCTAssertEqual(headers, ["Продавец", "Сумма за 90 дней", "Кол-во покупок"])
        XCTAssertEqual(rows, [["**Перевод человеку**", "25 741 760 сум", "157"], ["Korzinka", "4 744 267 сум", "20"]])
    }

    func testRuleAndPlainText() {
        XCTAssertEqual(ChatMarkdown.blocks(from: "Привет\n---\nПока"), [.paragraph("Привет"), .paragraph("Пока")])
        XCTAssertEqual(ChatMarkdown.blocks(from: ""), [])
    }
}
