import Foundation
import LocalAuthentication
import Observation

/// Блокировка приложения Face ID / Touch ID / код-паролем устройства.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?
    private var backgroundedAt: Date?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.isLocked = settings.appLockEnabled
    }

    enum Biometry {
        case faceID
        case touchID
        case opticID
        case passcode
        case none
    }

    var biometry: Biometry {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? .passcode : .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    var canProtect: Bool { biometry != Biometry.none }

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func willEnterForeground() {
        guard settings.appLockEnabled else {
            isLocked = false
            return
        }
        let elapsed = backgroundedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if elapsed >= Double(settings.lockTimeout.rawValue) {
            isLocked = true
        }
    }

    func lockNow() {
        if settings.appLockEnabled { isLocked = true }
    }

    /// Проверка владельца устройства. При недоступности биометрии iOS предложит код-пароль.
    func unlock(reason: String) async {
        guard settings.appLockEnabled else {
            isLocked = false
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedFallbackTitle = nil
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = (error as? LAError).flatMap(Self.message(for:))
        }
    }

    /// Включение защиты требует успешной проверки — чтобы не заблокировать приложение на устройстве без код-пароля.
    func enable(reason: String) async -> Bool {
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success { settings.appLockEnabled = true }
            return success
        } catch {
            lastError = (error as? LAError).flatMap(Self.message(for:))
            return false
        }
    }

    func disable() {
        settings.appLockEnabled = false
        isLocked = false
    }

    private static func message(for error: LAError) -> String? {
        switch error.code {
        case .userCancel, .systemCancel, .appCancel: return nil
        case .biometryLockout: return String(localized: "Биометрия заблокирована. Используйте код-пароль устройства.")
        case .passcodeNotSet: return String(localized: "На устройстве не задан код-пароль.")
        default: return String(localized: "Не удалось подтвердить личность.")
        }
    }
}
