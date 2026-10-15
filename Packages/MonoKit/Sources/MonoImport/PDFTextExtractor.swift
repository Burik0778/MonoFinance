import Foundation

#if canImport(PDFKit)
import PDFKit

/// Слова страниц PDF с положением (PDFKit).
///
/// Буква и её прямоугольник берутся из одного выделения `selection(for: NSRange)`: индексы `PDFPage.string`
/// и `characterBounds(at:)` в PDF из Chromium расходятся (буквы оказываются в чужих строках).
enum PDFTextExtractor {
    static func pages(from data: Data) throws -> [PDFPageText] {
        guard let document = PDFDocument(data: data) else { throw ImportError.corruptPDF }
        guard !document.isLocked else { throw ImportError.lockedPDF }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index).map { PDFPageText(words: words(on: $0)) }
        }
    }

    static func words(on page: PDFPage) -> [PDFWord] {
        let box = page.bounds(for: .mediaBox)
        var words: [PDFWord] = []
        var text = ""
        var rect = CGRect.null

        func flush() {
            defer { text = ""; rect = .null }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !rect.isNull else { return }
            // В PDF ось y направлена вверх — переворачиваем, чтобы строки шли сверху вниз.
            words.append(PDFWord(text: value, minX: rect.minX - box.minX, maxX: rect.maxX - box.minX,
                                 minY: box.maxY - rect.maxY, maxY: box.maxY - rect.minY))
        }

        for index in 0..<page.numberOfCharacters {
            guard let selection = page.selection(for: NSRange(location: index, length: 1)),
                  let character = selection.string, !character.isEmpty else { continue }
            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                flush()
                continue
            }
            let bounds = selection.bounds(for: page)
            guard bounds.height > 0, bounds.width >= 0, bounds.minX.isFinite, bounds.minY.isFinite else { continue }
            if !rect.isNull {
                let height = max(rect.height, bounds.height)
                let sameLine = abs(rect.midY - bounds.midY) < 0.5 * height
                let gap = bounds.minX - rect.maxX
                if !(sameLine && gap < 0.15 * height && gap > -0.5 * height) { flush() }
            }
            text += character
            rect = rect.isNull ? bounds : rect.union(bounds)
        }
        flush()
        return words
    }
}
#endif
