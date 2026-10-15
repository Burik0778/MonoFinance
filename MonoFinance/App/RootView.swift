import SwiftUI
import MonoCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        let store = environment.store
        let language = AppLanguage.current

        ZStack {
            Color.mono.background.ignoresSafeArea()
            if let error = environment.startupError {
                StartupErrorView(message: error)
            } else if !settings.onboardingCompleted {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .environment(store)
        .environment(\.hideAmounts, settings.hideAmounts)
        .environment(\.moneyFormatter, MoneyFormatter(language: language))
        .environment(\.appLanguage, language)
        .overlay { ToastOverlay(center: toasts) }
        .overlay {
            if settings.privacyShield && scenePhase != .active && !lock.isLocked {
                PrivacyShieldView().transition(.opacity)
            }
        }
        .overlay {
            if lock.isLocked && settings.appLockEnabled {
                LockScreenView().transition(.opacity)
            }
        }
        .sheet(item: $router.sheet) { sheet in
            SheetContainer(sheet: sheet)
                .environment(store)
                .environment(\.hideAmounts, settings.hideAmounts)
                .environment(\.moneyFormatter, MoneyFormatter(language: language))
                .environment(\.appLanguage, language)
        }
        .preferredColorScheme(colorScheme)
        .tint(Color.mono.accentText)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.didEnterBackground()
            case .inactive:
                break
            case .active:
                lock.willEnterForeground()
                Task { await refreshOnActivation() }
            @unknown default:
                break
            }
        }
        .task {
            if lock.isLocked && settings.appLockEnabled {
                await lock.unlock(reason: String(localized: "Разблокируйте MONO, чтобы увидеть финансы"))
            }
            await refreshOnActivation()
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    /// При возвращении в приложение: курсы ЦБ (если включено и устарели), напоминания о платежах.
    private func refreshOnActivation() async {
        let store = environment.store
        guard settings.onboardingCompleted, !store.isDemo else { return }
        if settings.cbuRatesEnabled {
            let stale = settings.lastRatesUpdate.map { Date().timeIntervalSince($0) > 6 * 3600 } ?? true
            let needsRates = store.activeAccounts.contains { $0.currency != store.baseCurrency }
            // Курсы ЦБ даются к суму; при другой основной валюте пересчёт идёт через сум (кросс-курс).
            if stale && needsRates {
                if let rates = try? await ExchangeRateService().fetchLatest(calendar: store.periods.calendar) {
                    try? store.saveRates(rates)
                    settings.lastRatesUpdate = Date()
                }
            }
        }
        if settings.remindersEnabled {
            await NotificationService.reschedule(
                rules: store.recurring,
                enabled: true,
                includeAmounts: !settings.appLockEnabled && !settings.hideAmounts,
                formatter: MoneyFormatter(language: .current),
                calendar: store.periods.calendar
            )
        }
    }
}

/// Плашка демо-режима: данные не настоящие. Нейтральная, с тёплой точкой-статусом — заметная, но не кричащая.
struct DemoBanner: View {
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.mono.warning)
                .frame(width: 6, height: 6)
            Text("Демо-режим · данные не настоящие")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textSecondary)
            Button("Выйти", action: onExit)
                .monoFont(.caption)
                .foregroundStyle(Color.mono.accentText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.mono.surface1))
        .overlay(Capsule().strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Экран при свёрнутом приложении: суммы не попадают в снимок переключателя приложений.
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color.mono.background.ignoresSafeArea()
            MonoBackdrop()
            VStack(spacing: 12) {
                Text(verbatim: "MONO")
                    .font(.system(size: 44, weight: .bold, design: .default).width(.expanded))
                    .foregroundStyle(Color.mono.textPrimary)
                Kicker("Личные финансы")
            }
        }
    }
}

struct LockScreenView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            MonoBackdrop()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Color.mono.accentText)
                VStack(spacing: 8) {
                    Text("MONO заблокировано")
                        .monoFont(.display)
                        .foregroundStyle(Color.mono.textPrimary)
                    Text("Ваши финансы видны только вам")
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                }
                if let error = lock.lastError {
                    Text(verbatim: error)
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.negative)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task { await lock.unlock(reason: String(localized: "Разблокируйте MONO, чтобы увидеть финансы")) }
                } label: {
                    Label("Разблокировать", systemImage: symbol)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(lock.isAuthenticating)
            }
        }
    }

    private var symbol: String {
        switch lock.biometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }
}

struct StartupErrorView: View {
    let message: String

    var body: some View {
        EmptyStateView(symbol: "externaldrive.badge.exclamationmark",
                       title: "Не удалось открыть данные",
                       message: "Файл базы не изменён. Перезапустите приложение; если ошибка повторится, восстановите резервную копию.")
            .overlay(alignment: .bottom) {
                Text(verbatim: message)
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
                    .padding()
            }
    }
}
