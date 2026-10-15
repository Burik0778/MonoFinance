import Foundation

/// Блок ответа нейросети для красивого показа в чате: заголовки, абзацы, списки и таблицы вместо сырой разметки.
public enum ChatBlock: Equatable, Sendable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    /// Таблица: заголовки столбцов и строки (в каждой строке столько же ячеек, сколько заголовков).
    case table(headers: [String], rows: [[String]])
}

/// Разбор Markdown-ответа на блоки. Внутри блоков остаётся строчная разметка (`**жирный**`, `*курсив*`),
/// её показывает `AttributedString(markdown:)`.
public enum ChatMarkdown {
    public static func blocks(from text: String) -> [ChatBlock] {
        var blocks: [ChatBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var tableLines: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
        }
        func flushTable() {
            guard !tableLines.isEmpty else { return }
            if let table = parseTable(tableLines) {
                blocks.append(table)
            } else {
                blocks.append(.paragraph(tableLines.joined(separator: " ")))
            }
            tableLines = []
        }
        func flushAll() {
            flushParagraph()
            flushLists()
            flushTable()
        }

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushAll()
                continue
            }
            // Продолжение перенесённой строки таблицы.
            if let last = tableLines.last, !last.hasSuffix("|") {
                tableLines[tableLines.count - 1] = last + " " + line
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph()
                flushLists()
                tableLines.append(line)
                continue
            }
            flushTable()
            if isRule(line) {
                flushAll()
                continue
            }
            if let heading = heading(line) {
                flushAll()
                blocks.append(.heading(heading))
                continue
            }
            if let item = bulletItem(line) {
                flushParagraph()
                if !numbered.isEmpty { flushLists() }
                bullets.append(item)
                continue
            }
            if let item = numberedItem(line) {
                flushParagraph()
                if !bullets.isEmpty { flushLists() }
                numbered.append(item)
                continue
            }
            // Продолжение пункта списка (перенос строки внутри пункта).
            if !bullets.isEmpty, rawLine.hasPrefix("  ") {
                bullets[bullets.count - 1] += " " + line
                continue
            }
            if !numbered.isEmpty, rawLine.hasPrefix("  ") {
                numbered[numbered.count - 1] += " " + line
                continue
            }
            flushLists()
            paragraph.append(line)
        }
        flushAll()
        return blocks
    }

    // MARK: - Строки

    /// «# Заголовок», «### Заголовок» или строка целиком жирным: «**Где можно сэкономить:**».
    static func heading(_ line: String) -> String? {
        if line.hasPrefix("#") {
            let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : stripBold(text)
        }
        if line.hasPrefix("**"), line.hasSuffix("**") || line.hasSuffix("**:"), line.count > 4 {
            var inner = line
            if inner.hasSuffix(":") { inner.removeLast() }
            inner = String(inner.dropFirst(2).dropLast(2))
            guard !inner.contains("**") else { return nil }
            inner = inner.trimmingCharacters(in: .whitespaces)
            if inner.hasSuffix(":") { inner.removeLast() }
            return inner.isEmpty ? nil : inner
        }
        return nil
    }

    static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "• ", "* ", "– ", "— "] where line.hasPrefix(marker) {
            let text = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// «1. Текст», «2) Текст».
    static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 2 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && Set(compact).isSubset(of: ["-", "*", "_", "="])
    }

    static func stripBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }

    // MARK: - Таблицы

    static func cells(_ line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Строка-разделитель «|---|:---:|».
    static func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    static func parseTable(_ lines: [String]) -> ChatBlock? {
        // Модель иногда переносит строку таблицы: склеиваем, пока строка не закрыта «|».
        var joined: [String] = []
        for line in lines {
            if let last = joined.last, !last.hasSuffix("|") {
                joined[joined.count - 1] = last + " " + line
            } else {
                joined.append(line)
            }
        }
        let rows = joined.map(cells).filter { !isSeparatorRow($0) && !$0.allSatisfy(\.isEmpty) }
        guard let headers = rows.first, headers.count >= 2, rows.count >= 2 else { return nil }
        let body = rows.dropFirst().map { row -> [String] in
            if row.count == headers.count { return row }
            if row.count > headers.count { return Array(row.prefix(headers.count)) }
            return row + Array(repeating: "", count: headers.count - row.count)
        }
        return .table(headers: headers.map(stripBold), rows: body)
    }
}
