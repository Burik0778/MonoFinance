import SwiftUI
import MonoCore

/// Курсы валют: официальные курсы ЦБ РУз (к суму) и ручные курсы. Без курса операции в валюте не входят в общие итоги.
/// При основной валюте не в сумах курсы ЦБ пересчитываются через сум (кросс-курс) автоматически.
struct ExchangeRatesView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language
    @Environment(\.moneyFormatter) private var formatter

    @State private var loading = false
    @State private var manualCurrency: Currency = .usd
    /// В какой валюте указан ручной курс: «1 USD = 12 500 сум».
    @State private var manualQuote: Currency?
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
                                Text(verbatim: baseRateText(currency: currency, rate: rate))
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
                .tint(Color.mono.positive)
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
                .disabled(loading)
                if store.baseCurrency != .uzs {
                    Text("Курсы ЦБ публикуются к суму. Для основной валюты \(store.baseCurrency.code) они пересчитываются через сум автоматически.")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textSecondary)
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
                HStack(spacing: 8) {
                    Text(verbatim: "1")
                        .monoFont(.body, digits: true)
                        .foregroundStyle(Color.mono.textSecondary)
                    CurrencyMenu(selection: $manualCurrency, options: Currency.common)
                    Text(verbatim: "=")
                        .monoFont(.body)
                        .foregroundStyle(Color.mono.textSecondary)
                    TextField("Курс", text: $manualRate)
                        .keyboardType(.decimalPad)
                        .monoFont(.body, digits: true)
                    CurrencyMenu(selection: Binding(get: { quoteCurrency }, set: { manualQuote = $0 }),
                                 options: Currency.common.filter { $0 != manualCurrency })
                }
                Button("Добавить курс") { addManual() }
                    .disabled(parsedManualRate == nil || quoteCurrency == manualCurrency)
            } header: {
                Kicker("Ручной курс")
            } footer: {
                Text("Например: 1 USD = 12 500 UZS. Ручной курс не перезаписывается курсом ЦБ. Удалите его, чтобы снова использовать официальный.")
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

    /// Валюта, в которой указан ручной курс: по умолчанию основная, а для самой основной — сум (или доллар).
    private var quoteCurrency: Currency {
        if let manualQuote, manualQuote != manualCurrency { return manualQuote }
        if manualCurrency != store.baseCurrency { return store.baseCurrency }
        return manualCurrency == .uzs ? .usd : .uzs
    }

    private var parsedManualRate: Decimal? {
        let cleaned = manualRate.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        guard let value = DecimalMath.parse(cleaned), value > 0 else { return nil }
        return value
    }

    /// Курс к основной валюте в удобном виде: «1 USD = 12 000 сум» или, если валюта дешевле, «1 $ = 12 000 UZS».
    private func baseRateText(currency: Currency, rate: Decimal) -> String {
        if rate >= 1 { return rateText(currency: currency, rate: rate) }
        return rateText(currency: store.baseCurrency, rate: 1 / rate, base: currency)
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
        guard let value = parsedManualRate, quoteCurrency != manualCurrency else { return }
        let rate = ExchangeRate(currency: manualCurrency, baseCurrency: quoteCurrency, rate: value, date: Date(), source: .manual)
        do {
            try store.saveRates([rate], keepManual: false)
            manualRate = ""
            Haptics.success()
        } catch {
            self.error = AppError(error).message
        }
    }
}
