import SwiftUI
import UIKit
import UserNotifications
import MonoCore

/// Настройки: данные, голос, импорт и банки, курсы, приватность, ИИ, напоминания, оформление, копии.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language
    @State private var confirmsDemo = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                NavigationLink(value: Route.accounts) {
                    FormRow(icon: "creditcard.fill", tint: Color.mono.accent, title: "Счета",
                            subtitle: Text("\(store.activeAccounts.count) активных"))
                }
                NavigationLink(value: Route.categories) {
                    FormRow(icon: "square.grid.2x2.fill", tint: Color.mono.accent, title: "Категории")
                }
                NavigationLink(value: Route.recurringList) {
                    FormRow(icon: "repeat", tint: Color.mono.accent, title: "Регулярные платежи")
                }
                Menu {
                    ForEach(baseCurrencyOptions, id: \.self) { currency in
                        Button(currency.code) { setBase(currency) }
                    }
                } label: {
                    FormRow(icon: "dollarsign.circle.fill", tint: Color.mono.positive, title: "Основная валюта",
                            subtitle: Text("Итоги и аналитика пересчитываются в неё")) {
                        Text(verbatim: store.baseCurrency.code)
                            .monoFont(.headline)
                            .foregroundStyle(Color.mono.textSecondary)
                    }
                }
                Menu {
                    Button("Не выбран") { try? store.setDefaultAccount(nil) }
                    ForEach(store.activeAccounts) { account in
                        Button(account.displayName) { try? store.setDefaultAccount(account) }
                    }
                } label: {
                    FormRow(icon: "star.circle.fill", tint: Color.mono.warning, title: "Счёт по умолчанию",
                            subtitle: Text("Для голосового ввода, если счёт не назван")) {
                        Text(verbatim: store.defaultAccount?.displayName ?? "—")
                            .monoFont(.subhead)
                            .foregroundStyle(Color.mono.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: 120, alignment: .trailing)
                    }
                }
            } header: {
                Kicker("Данные")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                NavigationLink(value: Route.speechSettings) {
                    FormRow(icon: "waveform", tint: Color.mono.accent, title: "Голосовой ввод",
                            subtitle: Text(verbatim: settings.speechLanguage.nativeName))
                }
                NavigationLink(value: Route.aiSettings) {
                    FormRow(icon: "sparkles", tint: Color.mono.accent, title: "Нейросеть",
                            subtitle: settings.llmReady ? Text("Подключена: \(settings.llmCandidates.first?.name ?? "")") : Text("Только на устройстве"))
                }
            } header: {
                Kicker("Голос и ассистент")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Button {
                    router.present(.importStatement(nil))
                } label: {
                    FormRow(icon: "square.and.arrow.down.on.square.fill", tint: Color.mono.textSecondary, title: "Импорт выписки",
                            subtitle: Text(verbatim: "CSV · XLSX"))
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.bankSync) {
                    FormRow(icon: "building.columns.fill", tint: Color.mono.accent, title: "Банки",
                            subtitle: Text("Статус подключений"))
                }
                NavigationLink(value: Route.exchangeRates) {
                    FormRow(icon: "arrow.left.arrow.right.circle.fill", tint: Color.mono.positive, title: "Курсы валют",
                            subtitle: ratesSubtitle)
                }
            } header: {
                Kicker("Импорт, банки и курсы")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                NavigationLink(value: Route.securitySettings) {
                    FormRow(icon: "lock.shield.fill", tint: Color.mono.accent, title: "Приватность и защита",
                            subtitle: settings.appLockEnabled ? Text("Блокировка включена") : Text("Блокировка выключена"))
                }
                Toggle(isOn: Binding(get: { settings.remindersEnabled }, set: { value in Task { await setReminders(value) } })) {
                    FormRow(icon: "bell.badge.fill", tint: Color.mono.warning, title: "Напоминания о платежах")
                }
                .tint(Color.mono.positive)
                NavigationLink(value: Route.backup) {
                    FormRow(icon: "externaldrive.fill.badge.checkmark", tint: Color.mono.accent, title: "Резервные копии и экспорт")
                }
            } header: {
                Kicker("Безопасность")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Picker(selection: $settings.appearance) {
                    Text("Тёмная").tag(Appearance.dark)
                    Text("Светлая").tag(Appearance.light)
                    Text("Как в системе").tag(Appearance.system)
                } label: {
                    FormRow(icon: "circle.lefthalf.filled", tint: Color.mono.neutral, title: "Тема")
                }
                Toggle(isOn: $settings.haptics) {
                    FormRow(icon: "hand.tap.fill", tint: Color.mono.neutral, title: "Тактильный отклик")
                }
                .tint(Color.mono.positive)
            } header: {
                Kicker("Оформление")
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                Toggle(isOn: Binding(get: { store.isDemo }, set: { _ in confirmsDemo = true })) {
                    FormRow(icon: "theatermasks.fill", tint: Color.mono.accent, title: "Демо-режим",
                            subtitle: Text("Отдельная база с примером данных. Ваши данные не затрагиваются."))
                }
                .tint(Color.mono.positive)
                NavigationLink(value: Route.about) {
                    FormRow(icon: "info.circle.fill", tint: Color.mono.neutral, title: "О приложении")
                }
            } footer: {
                Text(verbatim: "MONO \(Bundle.main.shortVersion)")
                    .monoFont(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .listRowBackground(Color.mono.surface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Настройки"))
        .confirmationDialog(store.isDemo ? "Выйти из демо-режима?" : "Включить демо-режим?", isPresented: $confirmsDemo, titleVisibility: .visible) {
            Button(store.isDemo ? "Выйти" : "Включить") {
                environment.setDemoMode(!store.isDemo)
            }
        } message: {
            Text(store.isDemo ? "Откроются ваши настоящие данные." : "Откроется отдельная база с вымышленными операциями. Она пересоздаётся при каждом включении и никогда не смешивается с вашими данными.")
        }
    }

    private var baseCurrencyOptions: [Currency] {
        var list: [Currency] = [.uzs, .usd, .eur, .rub]
        for account in store.activeAccounts where !list.contains(account.currency) { list.append(account.currency) }
        return list
    }

    private var ratesSubtitle: Text {
        if let date = settings.lastRatesUpdate {
            return Text("ЦБ РУз · \(DateFormatting.short(date, calendar: store.periods.calendar, language: language))")
        }
        return Text("Официальные курсы ЦБ и ручные")
    }

    private func setBase(_ currency: Currency) {
        guard currency != store.baseCurrency else { return }
        do {
            try store.setBaseCurrency(currency)
            if settings.cbuRatesEnabled && !store.isDemo {
                // Сразу подтягиваем курсы ЦБ: при основной валюте не в сумах они пересчитываются через сум.
                Task {
                    if let rates = try? await ExchangeRateService().fetchLatest(calendar: store.periods.calendar) {
                        try? store.saveRates(rates)
                        settings.lastRatesUpdate = Date()
                    }
                }
            }
        } catch {
            toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
        }
    }

    private func setReminders(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationService.requestAuthorization()
            guard granted else {
                settings.remindersEnabled = false
                toasts.show(ToastMessage(text: String(localized: "Уведомления запрещены в настройках iOS."), symbol: "bell.slash.fill", tint: Color.mono.warning))
                return
            }
        }
        settings.remindersEnabled = enabled
        await NotificationService.reschedule(rules: store.recurring, enabled: enabled,
                                             includeAmounts: !settings.appLockEnabled && !settings.hideAmounts,
                                             formatter: MoneyFormatter(language: language), calendar: store.periods.calendar)
    }
}

extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
