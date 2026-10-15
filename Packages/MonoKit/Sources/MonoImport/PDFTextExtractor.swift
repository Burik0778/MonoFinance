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
        let count = document.pageCount
        guard count > 1 else { return document.page(at: 0).map { [PDFPageText(words: words(on: $0))] } ?? [] }
        // Буквы по одной — небыстро (~0,5 с на страницу), поэтому страницы читаются параллельно.
        // У каждого потока свой экземпляр документа: PDFKit не обещает потокобезопасность одного PDFDocument.
        let workers = max(1, min(count, ProcessInfo.processInfo.activeProcessorCount))
        let results = PageResults(count: count)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            guard let copy = PDFDocument(data: data) else { return }
            for index in stride(from: worker, to: count, by: workers) {
                if let page = copy.page(at: index) { results.set(index, PDFPageText(words: words(on: page))) }
            }
        }
        // Если копия документа не открылась, недостающие страницы читаем по порядку.
        return (0..<count).map { index in
            results.page(index) ?? document.page(at: index).map { PDFPageText(words: words(on: $0)) } ?? PDFPageText(words: [])
        }
    }

    /// Результаты по страницам из нескольких потоков.
    private final class PageResults: @unchecked Sendable {
        private let lock = NSLock()
        private var pages: [PDFPageText?]

        init(count: Int) { pages = Array(repeating: nil, count: count) }

        func set(_ index: Int, _ page: PDFPageText) {
            lock.lock()
            pages[index] = page
            lock.unlock()
        }

        func page(_ index: Int) -> PDFPageText? {
            lock.lock()
            defer { lock.unlock() }
            return pages[index]
        }
    }

    static func words(on page: PDFPage) -> [PDFWord] {
        let box = page.bounds(for: .mediaBox)
        var words: [PDFWord] = []
        var text = ""
        var rect = CGRect.null
        // PDFKit повторяет последнюю букву каждого текстового фрагмента на том же месте («BANK»» , «000,000»).
        var previous: (character: String, bounds: CGRect)?

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
            if let previous, previous.character == character, Self.overlap(previous.bounds, bounds) > 0.5 { continue }
            previous = (character, bounds)
            if !rect.isNull {
                let height = min(rect.height, bounds.height)
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

    /// Доля меньшего прямоугольника, закрытая пересечением.
    static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let common = a.intersection(b)
        guard !common.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? Double(common.width * common.height / smaller) : (abs(a.minX - b.minX) < 0.5 ? 1 : 0)
    }
}
#endif
