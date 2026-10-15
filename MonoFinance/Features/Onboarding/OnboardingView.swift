import SwiftUI
import MonoCore

/// Первый запуск: знакомство → основная валюта → реальные счета с настоящими остатками → защита.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(\.appLanguage) private var language

    @State private var step = 0
    @State private var currency: Currency = .uzs
    @State private var lockEnabled = false

    var body: some View {
        ZStack {
            MonoBackdrop(haze: true)
            VStack(spacing: 0) {
                if step > 0 {
                    HStack(spacing: 6) {
                        ForEach(1..<4, id: \.self) { index in
                            Capsule()
                                .fill(index <= step ? Color.mono.textPrimary : Color.mono.surface3)
                                .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity)
                }
                Group {
                    switch step {
                    case 0: welcome
                    case 1: currencyStep
                    case 2: accountsStep
                    default: securityStep
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .monoAnimation(.emphasized, value: step)
    }

    // MARK: - Знакомство

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)
            CardStackIllustration()
                .frame(height: 190)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: "MONO")
                    .font(.system(size: 22, weight: .heavy).width(.expanded))
                    .tracking(2)
                    .foregroundStyle(Color.mono.accentText)
                    .accessibilityAddTraits(.isHeader)
                Text("Все ваши деньги — в одной ясной картине.")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .tracking(-1)
                    .foregroundStyle(Color.mono.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    promise("waveform", "Скажите «потратил 85 тысяч на обед» — операция готова к подтверждению.")
                    promise("chart.pie.fill", "Куда уходят деньги, сколько удастся накопить — по вашим реальным данным.")
                    promise("lock.shield.fill", "Всё хранится на этом iPhone. Без аккаунтов и паролей от банков.")
                }
                .padding(.top, 8)
            }
            Spacer()
            VStack(spacing: 10) {
                Button("Начать") { next() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Посмотреть на демо-данных") {
                    environment.setDemoMode(true)
                    settings.onboardingCompleted = true
                }
                .buttonStyle(SecondaryButtonStyle())
                Text("Демо открывается в отдельной базе и всегда помечено.")
                    .monoFont(.caption)
                    .foregroundStyle(Color.mono.textTertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func promise(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.mono.accentText)
                .frame(width: 26)
            Text(text)
                .monoFont(.callout)
                .foregroundStyle(Color.mono.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Валюта

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle(kicker: "Шаг 1 из 3", title: "Основная валюта", text: "В ней показываются общий баланс и аналитика. Счета в других валютах пересчитываются по курсу ЦБ или вашему курсу.")
            VStack(spacing: 10) {
                ForEach([Currency.uzs, .usd, .eur, .rub], id: \.self) { option in
                    Button {
                        Haptics.selection()
                        withMonoAnimation(.quick) { currency = option }
                    } label: {
                        HStack(spacing: 14) {
                            Text(verbatim: option.code)
                                .font(.system(size: 20, weight: .bold).width(.expanded))
                                .foregroundStyle(Color.mono.textPrimary)
                                .frame(width: 70, alignment: .leading)
                            Text(verbatim: currencyName(option))
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textSecondary)
                            Spacer()
                            Image(systemName: currency == option ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(currency == option ? Color.mono.accentText : Color.mono.textTertiary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 62)
                        .background(
                            RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous)
                                .fill(currency == option ? Color.mono.accentWash : Color.mono.surface1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous)
                                .strokeBorder(currency == option ? Color.mono.accent.opacity(0.6) : Color.mono.strokeSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .accessibilityAddTraits(currency == option ? .isSelected : [])
                }
            }
            Spacer()
            Button("Дальше") {
                try? store.setBaseCurrency(currency)
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func currencyName(_ currency: Currency) -> String {
        switch currency {
        case .uzs: return Phrase(ru: "Узбекский сум", uz: "O‘zbek so‘mi", en: "Uzbek som")(language)
        case .usd: return Phrase(ru: "Доллар США", uz: "AQSH dollari", en: "US dollar")(language)
        case .eur: return Phrase(ru: "Евро", uz: "Yevro", en: "Euro")(language)
        case .rub: return Phrase(ru: "Российский рубль", uz: "Rossiya rubli", en: "Russian ruble")(language)
        default: return currency.code
        }
    }

    // MARK: - Счета

    private var accountsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(kicker: "Шаг 2 из 3", title: "Ваши счета", text: "Добавьте карты, вклады и наличные с реальными остатками на сегодня. Дальше баланс будет считаться из операций.")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.activeAccounts) { account in
                        VirtualCardView(account: account, balance: store.balance(of: account), style: .compact)
                            .frame(height: 110)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        router.present(.account(nil))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.mono.accentText)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.mono.accent.opacity(0.14)))
                            Text(store.activeAccounts.isEmpty ? "Добавить первый счёт" : "Добавить ещё счёт")
                                .monoFont(.headline)
                                .foregroundStyle(Color.mono.textPrimary)
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: MonoTokens.Radius.lg, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                .foregroundStyle(Color.mono.strokeStrong)
                        )
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
                .monoAnimation(.standard, value: store.activeAccounts.count)
            }
            .scrollIndicators(.hidden)
            Text("Карты в MONO — оформление ваших счетов, а не банковские продукты. Подключения к банкам нет: операции добавляются вручную, голосом или импортом выписки.")
                .monoFont(.caption)
                .foregroundStyle(Color.mono.textTertiary)
            Button(store.activeAccounts.isEmpty ? "Пропустить" : "Дальше") {
                if store.defaultAccount == nil, let first = store.activeAccounts.first { try? store.setDefaultAccount(first) }
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Защита

    private var securityStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(kicker: "Шаг 3 из 3", title: "Защита и приватность", text: "Финансы видны только вам. Эти настройки можно поменять в любой момент.")
            VStack(spacing: 10) {
                if lock.canProtect {
                    Toggle(isOn: Binding(get: { lockEnabled }, set: { value in Task { await setLock(value) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Блокировка Face ID / код-паролем")
                                .monoFont(.body)
                                .foregroundStyle(Color.mono.textPrimary)
                            Text("При открытии и возвращении в приложение")
                                .monoFont(.footnote)
                                .foregroundStyle(Color.mono.textSecondary)
                        }
                    }
                    .tint(Color.mono.accent)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface1))
                }
                ToggleRow(title: "Скрывать суммы при запуске", subtitle: "Удобно, если показываете экран другим", isOn: Binding(get: { settings.hideAmountsOnLaunch }, set: { settings.hideAmountsOnLaunch = $0 }), tint: Color.mono.accent)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(Color.mono.accentText)
                        .frame(width: 24)
                    Text("Доступ к микрофону и распознаванию речи iOS спросит при первой голосовой записи. Речь по возможности распознаётся прямо на iPhone.")
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface1))
            }
            Spacer()
            Button("Готово") {
                Haptics.success()
                settings.onboardingCompleted = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func stepTitle(kicker: LocalizedStringKey, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(kicker)
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .default))
                .foregroundStyle(Color.mono.textPrimary)
            Text(text)
                .monoFont(.callout)
                .foregroundStyle(Color.mono.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func next() {
        Haptics.tap()
        withMonoAnimation(.emphasized) { step += 1 }
    }

    private func setLock(_ enabled: Bool) async {
        if enabled {
            lockEnabled = await lock.enable(reason: String(localized: "Подтвердите, чтобы включить блокировку MONO"))
        } else {
            lock.disable()
            lockEnabled = false
        }
    }
}

/// Веер из трёх абстрактных карт для экрана знакомства: материалы MONO без цифр и логотипов.
private struct CardStackIllustration: View {
    @State private var spread = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            card(.graphite, angle: -14, x: -46, y: 18)
            card(.lagoon, angle: -4, x: 0, y: 4)
            card(.aurora, angle: 8, x: 48, y: -10)
        }
        .onAppear {
            withAnimation(Motion.animation(.gentle, reduceMotion: reduceMotion).delay(0.15)) { spread = true }
        }
        .accessibilityHidden(true)
    }

    private func card(_ skin: CardSkin, angle: Double, x: CGFloat, y: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return CardSkinBackground(skin: skin)
            .frame(width: 220, height: 220 / 1.586)
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                CardChip().padding(18).padding(.top, 26)
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 12)
            .rotationEffect(.degrees(spread || reduceMotion ? angle : 0))
            .offset(x: spread || reduceMotion ? x : 0, y: spread || reduceMotion ? y : 0)
    }
}
