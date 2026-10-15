import SwiftUI
import MonoCore

/// Курсы валют: официальные курсы ЦБ РУз (к суму) и ручные курсы. Без курса операции в валюте не входят в общие итоги.
struct ExchangeRatesView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter

    @State private var loading = false
    @State private var manualCurrency: Currency = .usd
    @State private var manualRate = ""
    @State private var error: String?

    private var neededCurrencies: [Currency] {
        Array(Set(store.activeAccounts.map(\.currency)).subtracting([store.baseCurrency])).sorted()
    }

    var body: some View {
        @Bindable var settings = settings
        let converter = store.converter
        List {
            if !neededCurrencies.isEmpty {
                Section {
                    ForEach(neededCurrencies, id: \.self) { currency in
                        HStack {
                            Text(verbatim: currency.code)
                                .monoFont(.headline)
                                .foregroundStyle(Color.mono.textPrimary)
                            Spacer()
                            if let rate = converter.rate(for: currency) {
                                Text(verbatim: rateText(currency: currency, rate: rate))
                                    .monoFont(.callout, digits: true)
                                    .foregroundStyle(Color.mono.textSecondary)
                            } else {
                                Label("Нет курса", systemImage: "exclamationmark.triangle.fill")
                                    .monoFont(.caption)
                                    .foregroundStyle(Color.mono.warning)
                            }
                        }
                    }
                } header: {
                    Kicker("Валюты ваших счетов")
                } footer: {
                    Text("Основная валюта — \(store.baseCurrency.code). Счета в других валютах пересчитываются в неё для общего баланса и аналитики.")
                        .monoFont(.caption)
                }
                .listRowBackground(Color.mono.surface1)
            }

            Section {
                Toggle(isOn: $settings.cbuRatesEnabled) {
                    FormRow(icon: "building.columns", tint: Color.mono.positive, title: "Курсы ЦБ РУз",
                            subtitle: Text("Обновляются автоматически при открытии приложения"))
                }
                .tint(Color.mono.accent)
                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        if loading { ProgressView().controlSize(.small) }
                        Text(loading ? "Загрузка…" : "Обновить сейчас")
                        Spacer()
                        if let date = settings.lastRatesUpdate {
                            Text(verbatim: DateFormatting.full(date, calendar: store.periods.calendar, language: language))
                                .monoFont(.caption)
                                .foregroundStyle(Color.mono.textTertiary)
                        }
                    }
                }
                .disabled(loading || store.baseCurrency != .uzs)
                if store.baseCurrency != .uzs {
                    Text("Курсы ЦБ публикуются к суму. При основной валюте \(store.baseCurrency.code) добавьте курсы вручную.")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.warning)
                }
                if let error {
                    Text(verbatim: error)
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.negative)
                }
            } header: {
                Kicker("Официальные курсы")
            } footer: {
                Text("Источник: cbu.uz. В запросе нет ваших данных. Курс банка при покупке валюты может отличаться — для переводов между валютами указывайте фактическую сумму зачисления.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            Section {
                HStack(spacing: 10) {
                    CurrencyMenu(selection: $manualCurrency, options: Currency.common.filter { $0 != store.baseCurrency })
                    TextField("Курс", text: $manualRate)
                        .keyboardType(.decimalPad)
                        .monoFont(.body, digits: true)
                    Text(verbatim: formatter.symbol(for: store.baseCurrency).text)
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                    Button("Добавить") { addManual() }
                        .disabled(DecimalMath.parse(manualRate.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) == nil)
                }
            } header: {
                Kicker("Ручной курс")
            } footer: {
                Text("Ручной курс не перезаписывается курсом ЦБ. Удалите его, чтобы снова использовать официальный.")
                    .monoFont(.caption)
            }
            .listRowBackground(Color.mono.surface1)

            if !store.rates.isEmpty {
                Section {
                    ForEach(store.rates.sorted { lhs, rhs in
                        let priority: [Currency] = [.usd, .eur, .rub]
                        let l = priority.firstIndex(of: lhs.currency) ?? 99
                        let r = priority.firstIndex(of: rhs.currency) ?? 99
                        return l != r ? l < r : lhs.currency < rhs.currency
                    }) { rate in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: rate.currency.code)
                                    .monoFont(.body)
                                    .foregroundStyle(Color.mono.textPrimary)
                                Text(verbatim: "\(rate.source == .cbu ? "ЦБ" : Phrase(ru: "вручную", uz: "qo‘lda", en: "manual")(language)) · \(DateFormatting.short(rate.date, calendar: store.periods.calendar, language: language))")
                                    .monoFont(.caption)
                                    .foregroundStyle(rate.source == .manual ? Color.mono.accent : Color.mono.textTertiary)
                            }
                            Spacer()
                            Text(verbatim: rateText(currency: rate.currency, rate: rate.rate, base: rate.baseCurrency))
                                .monoFont(.callout, digits: true)
                                .foregroundStyle(Color.mono.textSecondary)
                        }
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                try? store.deleteRate(rate.currency)
                            }
                        }
                    }
                } header: {
                    Kicker("Все курсы")
                }
                .listRowBackground(Color.mono.surface1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text("Курсы валют"))
    }

    private func rateText(currency: Currency, rate: Decimal, base: Currency? = nil) -> String {
        let baseCurrency = base ?? store.baseCurrency
        let value = Money(major: rate, currency: baseCurrency, rounding: .halfEven).map { formatter.string($0, fraction: .always) } ?? "\(rate)"
        return "1 \(currency.code) = \(value)"
    }

    private func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let rates = try await ExchangeRateService().fetchLatest(calendar: store.periods.calendar)
            try store.saveRates(rates)
            settings.lastRatesUpdate = Date()
            Haptics.success()
            toasts.show(ToastMessage(text: String(localized: "Курсы обновлены"), symbol: "arrow.triangle.2.circlepath"))
        } catch {
            self.error = String(localized: "Не удалось загрузить курсы. Проверьте подключение к интернету.")
        }
    }

    private func addManual() {
        let cleaned = manualRate.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{202F}", with: "")
        guard let value = DecimalMath.parse(cleaned), value > 0 else { return }
        let rate = ExchangeRate(currency: manualCurrency, baseCurrency: store.baseCurrency, rate: value, date: Date(), source: .manual)
        do {
            try store.saveRates([rate], keepManual: false)
            manualRate = ""
            Haptics.success()
        } catch {
            self.error = AppError(error).message
        }
    }
}
