import Foundation

/// Распаковка DEFLATE (RFC 1951) на чистом Swift — одинаково работает на iOS и в тестах на Linux.
/// Реализация следует эталонному puff.c (Mark Adler): простая, проверяемая, без внешних зависимостей.
enum Inflate {
    enum Error: Swift.Error, Equatable {
        case unexpectedEnd
        case invalidBlockType
        case invalidStoredLength
        case invalidCode
        case invalidDistance
        case outputTooLarge
    }

    /// Ограничение на размер распакованных данных — защита от «zip-бомб».
    static let maxOutput = 200 * 1024 * 1024

    private struct BitReader {
        let bytes: [UInt8]
        var position = 0
        var bitBuffer: UInt32 = 0
        var bitCount = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func bits(_ need: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard position < bytes.count else { throw Error.unexpectedEnd }
                value |= UInt32(bytes[position]) << UInt32(bitCount)
                position += 1
                bitCount += 8
            }
            bitBuffer = value >> UInt32(need)
            bitCount -= need
            return Int(value & ((1 << UInt32(need)) - 1))
        }

        mutating func alignToByte() {
            bitBuffer = 0
            bitCount = 0
        }
    }

    private struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        init(lengths: [Int]) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for length in lengths { count[length] += 1 }
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 { offsets[length + 1] = offsets[length] + count[length] }
            count[0] = 0
            for (index, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[length]] = index
                offsets[length] += 1
            }
        }

        func decode(_ reader: inout BitReader) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1...15 {
                code |= try reader.bits(1)
                let count = self.count[length]
                if code - count < first { return symbol[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Error.invalidCode
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                                       4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let fixedTables: (Huffman, Huffman) = {
        var lengths = [Int](repeating: 0, count: 288)
        for i in 0..<144 { lengths[i] = 8 }
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        for i in 280..<288 { lengths[i] = 8 }
        return (Huffman(lengths: lengths), Huffman(lengths: [Int](repeating: 5, count: 30)))
    }()

    static func decompress(_ data: Data, expectedSize: Int? = nil) throws -> Data {
        var reader = BitReader([UInt8](data))
        var output: [UInt8] = []
        if let expectedSize, expectedSize > 0, expectedSize <= maxOutput { output.reserveCapacity(expectedSize) }
        var isLast = false
        repeat {
            isLast = try reader.bits(1) == 1
            let type = try reader.bits(2)
            switch type {
            case 0: try stored(&reader, &output)
            case 1: try codes(&reader, &output, fixedTables.0, fixedTables.1)
            case 2:
                let tables = try dynamicTables(&reader)
                try codes(&reader, &output, tables.0, tables.1)
            default: throw Error.invalidBlockType
            }
        } while !isLast
        return Data(output)
    }

    private static func stored(_ reader: inout BitReader, _ output: inout [UInt8]) throws {
        reader.alignToByte()
        guard reader.position + 4 <= reader.bytes.count else { throw Error.unexpectedEnd }
        let b = reader.bytes
        let p = reader.position
        let length = Int(b[p]) | Int(b[p + 1]) << 8
        let complement = Int(b[p + 2]) | Int(b[p + 3]) << 8
        guard length == (~complement & 0xFFFF) else { throw Error.invalidStoredLength }
        reader.position += 4
        guard reader.position + length <= b.count else { throw Error.unexpectedEnd }
        output.append(contentsOf: b[reader.position..<(reader.position + length)])
        reader.position += length
        guard output.count <= maxOutput else { throw Error.outputTooLarge }
    }

    private static func codes(_ reader: inout BitReader, _ output: inout [UInt8], _ lengthCodes: Huffman, _ distanceCodes: Huffman) throws {
        while true {
            let symbol = try lengthCodes.decode(&reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < lengthBase.count else { throw Error.invalidCode }
                let length = lengthBase[index] + (try reader.bits(lengthExtra[index]))
                let distanceSymbol = try distanceCodes.decode(&reader)
                guard distanceSymbol < distanceBase.count else { throw Error.invalidDistance }
                let distance = distanceBase[distanceSymbol] + (try reader.bits(distanceExtra[distanceSymbol]))
                guard distance <= output.count else { throw Error.invalidDistance }
                let start = output.count - distance
                for offset in 0..<length {
                    output.append(output[start + offset])
                }
            }
            if output.count > maxOutput { throw Error.outputTooLarge }
        }
    }

    private static func dynamicTables(_ reader: inout BitReader) throws -> (Huffman, Huffman) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw Error.invalidCode }

        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeCount {
            codeLengths[codeLengthOrder[index]] = try reader.bits(3)
        }
        let lengthCode = Huffman(lengths: codeLengths)

        var lengths = [Int](repeating: 0, count: literalCount + distanceCount)
        var index = 0
        while index < literalCount + distanceCount {
            var symbol = try lengthCode.decode(&reader)
            if symbol < 16 {
                lengths[index] = symbol
                index += 1
            } else {
                var length = 0
                if symbol == 16 {
                    guard index > 0 else { throw Error.invalidCode }
                    length = lengths[index - 1]
                    symbol = 3 + (try reader.bits(2))
                } else if symbol == 17 {
                    symbol = 3 + (try reader.bits(3))
                } else {
                    symbol = 11 + (try reader.bits(7))
                }
                guard index + symbol <= literalCount + distanceCount else { throw Error.invalidCode }
                for _ in 0..<symbol {
                    lengths[index] = length
                    index += 1
                }
            }
        }
        guard lengths[256] != 0 else { throw Error.invalidCode }
        return (Huffman(lengths: Array(lengths[0..<literalCount])), Huffman(lengths: Array(lengths[literalCount...])))
    }
}
