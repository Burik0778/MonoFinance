import Foundation

/// Минимальное чтение ZIP (для XLSX): центральный каталог, методы «stored» и «deflate». ZIP64 и шифрование не поддерживаются.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum Error: Swift.Error, Equatable {
        case notZip
        case truncated
        case unsupportedMethod(UInt16)
        case encrypted
        case missingEntry(String)
    }

    private let bytes: [UInt8]
    let entries: [String: Entry]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 22, bytes[0] == 0x50, bytes[1] == 0x4B else { throw Error.notZip }

        // Конец центрального каталога ищем с конца файла (после него может быть комментарий до 64 КБ).
        var eocd = -1
        let lowest = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= lowest {
            if bytes[index] == 0x50 && bytes[index + 1] == 0x4B && bytes[index + 2] == 0x05 && bytes[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { throw Error.notZip }

        let count = Int(Self.u16(bytes, eocd + 10))
        let directoryOffset = Int(Self.u32(bytes, eocd + 16))
        var entries: [String: Entry] = [:]
        var cursor = directoryOffset
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, Self.u32(bytes, cursor) == 0x02014B50 else { throw Error.truncated }
            let flags = Self.u16(bytes, cursor + 8)
            let method = Self.u16(bytes, cursor + 10)
            let compressed = Int(Self.u32(bytes, cursor + 20))
            let uncompressed = Int(Self.u32(bytes, cursor + 24))
            let nameLength = Int(Self.u16(bytes, cursor + 28))
            let extraLength = Int(Self.u16(bytes, cursor + 30))
            let commentLength = Int(Self.u16(bytes, cursor + 32))
            let localOffset = Int(Self.u32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw Error.truncated }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            if flags & 0x1 != 0 { throw Error.encrypted }
            entries[name] = Entry(name: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset)
            cursor += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else { throw Error.missingEntry(name) }
        let offset = entry.localHeaderOffset
        guard offset + 30 <= bytes.count, Self.u32(bytes, offset) == 0x04034B50 else { throw Error.truncated }
        let nameLength = Int(Self.u16(bytes, offset + 26))
        let extraLength = Int(Self.u16(bytes, offset + 28))
        let start = offset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw Error.truncated }
        let payload = Data(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0: return payload
        case 8: return try Inflate.decompress(payload, expectedSize: entry.uncompressedSize)
        default: throw Error.unsupportedMethod(entry.method)
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
