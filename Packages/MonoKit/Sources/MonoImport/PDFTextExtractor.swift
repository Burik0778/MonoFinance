import Foundation

#if canImport(PDFKit)
import PDFKit

/// Слова страниц PDF с положением (PDFKit). Текст собирается по символам: `PDFPage.string` + `characterBounds(at:)`.
enum PDFTextExtractor {
    static func pages(from data: Data) throws -> [PDFPageText] {
        guard let document = PDFDocument(data: data) else { throw ImportError.corruptPDF }
        guard !document.isLocked else { throw ImportError.lockedPDF }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index).map { PDFPageText(words: words(on: $0)) }
        }
    }

    static func words(on page: PDFPage) -> [PDFWord] {
        guard let string = page.string, !string.isEmpty else { return [] }
        let box = page.bounds(for: .mediaBox)
        var words: [PDFWord] = []
        var units: [UInt16] = []
        var rect = CGRect.null

        func flush() {
            defer { units = []; rect = .null }
            let text = String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !rect.isNull else { return }
            // В PDF ось y направлена вверх — переворачиваем, чтобы строки шли сверху вниз.
            words.append(PDFWord(text: text, minX: rect.minX - box.minX, maxX: rect.maxX - box.minX,
                                 minY: box.maxY - rect.maxY, maxY: box.maxY - rect.minY))
        }

        for (index, unit) in string.utf16.enumerated() {
            if let scalar = Unicode.Scalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flush()
                continue
            }
            // Вторая половина суррогатной пары — та же буква.
            if UTF16.isTrailSurrogate(unit) {
                units.append(unit)
                continue
            }
            let bounds = page.characterBounds(at: index)
            guard bounds.height > 0, bounds.width >= 0, bounds.minX.isFinite, bounds.minY.isFinite else { continue }
            if !rect.isNull {
                let height = max(rect.height, bounds.height)
                let sameLine = abs(rect.midY - bounds.midY) < 0.5 * height
                let gap = bounds.minX - rect.maxX
                if !(sameLine && gap < 0.15 * height && gap > -0.5 * height) { flush() }
            }
            units.append(unit)
            rect = rect.isNull ? bounds : rect.union(bounds)
        }
        flush()
        return words
    }
}
#endif
