import Foundation
import CryptoKit
import CommonCrypto
import MonoStorage

/// Зашифрованные резервные копии: PBKDF2-SHA256 (310 000 итераций) + AES-256-GCM.
///
/// Формат файла: «MONOBK01» (8 байт) | число итераций (UInt32, big-endian) | соль (16 байт) | AES.GCM combined (nonce + шифртекст + тег).
enum BackupService {
    static let magic = Data("MONOBK01".utf8)
    static let iterations: UInt32 = 310_000
    static let fileExtension = "monobackup"

    enum BackupError: Error, LocalizedError {
        case weakPassword
        case notABackup
        case wrongPasswordOrCorrupted
        case keyDerivationFailed

        var errorDescription: String? {
            switch self {
            case .weakPassword: return String(localized: "Пароль должен быть не короче 8 символов.")
            case .notABackup: return String(localized: "Это не резервная копия MONO.")
            case .wrongPasswordOrCorrupted: return String(localized: "Неверный пароль или файл повреждён.")
            case .keyDerivationFailed: return String(localized: "Не удалось подготовить ключ шифрования.")
            }
        }
    }

    static func encrypt(_ snapshot: LedgerSnapshot, password: String) throws -> Data {
        guard password.count >= 8 else { throw BackupError.weakPassword }
        let plaintext = try snapshot.encoded()
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw BackupError.keyDerivationFailed }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw BackupError.keyDerivationFailed }
        var output = magic
        var bigEndian = iterations.bigEndian
        output.append(Data(bytes: &bigEndian, count: 4))
        output.append(salt)
        output.append(combined)
        return output
    }

    static func decrypt(_ data: Data, password: String) throws -> LedgerSnapshot {
        guard data.count > 8 + 4 + 16 + 28, data.prefix(8) == magic else { throw BackupError.notABackup }
        let iterationBytes = data.subdata(in: 8..<12)
        let iterations = iterationBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard iterations >= 100_000, iterations <= 5_000_000 else { throw BackupError.notABackup }
        let salt = data.subdata(in: 12..<28)
        let combined = data.subdata(in: 28..<data.count)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key)
        } catch {
            throw BackupError.wrongPasswordOrCorrupted
        }
        return try LedgerSnapshot.decode(plaintext)
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "MONO-\(formatter.string(from: now)).\(fileExtension)"
    }
}
