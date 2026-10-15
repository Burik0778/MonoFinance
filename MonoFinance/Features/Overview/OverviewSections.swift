import SwiftUI
import MonoCore
import MonoAnalytics
import MonoIntelligence

extension Money {
    /// Значение для графиков (основные единицы). Только для отображения — расчёты остаются в `Money`.
    var chartValue: Double { NSDecimalNumber(decimal: majorValue).doubleValue }
}

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Пространство имён для zoom-перехода «карта → экран счёта».
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

/// Источник zoom-перехода, если пространство имён доступно.
struct ZoomSource: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct ZoomDestination: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

// MARK: - Регулярные платежи к подтверждению

struct DueRecurringSection: View {
    let now: Date
    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let due = store.dueRecurring(now: now)
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(Color.mono.warning).frame(width: 6, height: 6)
                    Kicker("Ожидают подтверждения")
                }
                VStack(spacing: 0) {
                    ForEach(due) { rule in
                        HStack(spacing: 12) {
                            CategoryGlyph(category: rule.categoryID.flatMap { store.categoryMap[$0] }, kind: rule.kind, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: rule.title).monoFont(.body).foregroundStyle(Color.mono.textPrimary).lineLimit(1)
                                MoneyText(money: rule.amount, token: .footnote, color: Color.mono.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Button("Пропустить") {
                                do { try store.skipRecurring(rule) } catch { toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative)) }
                            }
                            .buttonStyle(ChipStyle())
                            Button("Записать") {
                                do {
                                    try store.confirmRecurring(rule)
                                    Haptics.success()
                                    toasts.show(ToastMessage(text: String(localized: "Платёж записан")))
                                } catch {
                                    toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                                }
                            }
                            .buttonStyle(ChipStyle(isSelected: true))
                        }
                        .padding(.vertical, 8)
                        if rule.id != due.last?.id { Hairline(inset: 50) }
                    }
                }
            }
            .monoSurface(radius: MonoTokens.Radius.xl, padding: 16)
        }
    }
}

// MARK: - Выбор счёта

/// Лист выбора счёта на главной: «Все счета» или один счёт. Отсюда же — управление картами и новый счёт.
struct AccountScopeSheet: View {
    @Binding var selection: String

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Счета")
                    .monoFont(.title)
                    .foregroundStyle(Color.mono.textPrimary)
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    row(id: "", thumbnail: AnyView(Image(systemName: "square.stack")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.mono.textSecondary)
                            .frame(width: 40, height: 26)),
                        title: Phrase(ru: "Все счета", uz: "Barcha hisoblar", en: "All accounts")(language),
                        subtitle: nil,
                        money: store.totalBalance.total)
                    ForEach(store.activeAccounts) { account in
                        Hairline(inset: 68)
                        row(id: account.id.uuidString,
                            thumbnail: AnyView(CardThumbnail(skin: account.skin, width: 40)),
                            title: account.displayName,
                            subtitle: [account.bank.isBank ? account.bank.shortName : account.kind.title(language), account.maskedNumber].compactMap { $0 }.joined(separator: " · "),
                            money: store.balance(of: account))
                    }
                }
                .monoSurface(radius: MonoTokens.Radius.lg, padding: 0)

                HStack(spacing: 10) {
                    Button {
                        close { router.open(.accounts) }
                    } label: {
                        Label("Карты", systemImage: "creditcard")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        close { router.present(.account(nil)) }
                    } label: {
                        Label("Новый счёт", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func row(id: String, thumbnail: AnyView, title: String, subtitle: String?, money: Money) -> some View {
        let selected = selection == id
        return Button {
            Haptics.selection()
            selection = id
            dismiss()
        } label: {
            HStack(spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .monoFont(.body)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .monoFont(.caption)
                            .foregroundStyle(Color.mono.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                MoneyText(money: money, token: .amountRow)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.mono.accentText)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Закрывает лист и выполняет переход, когда анимация закрытия закончится.
    private func close(then action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            action()
        }
    }
}

// MARK: - Инсайты

struct InsightsSection: View {
    let insights: [Insight]
    @State private var page: Int? = 0

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Kicker("Наблюдения")
                    Spacer()
                    if insights.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<insights.count, id: \.self) { index in
                                Capsule()
                                    .fill(index == (page ?? 0) ? Color.mono.textPrimary : Color.mono.strokeStrong)
                                    .frame(width: index == (page ?? 0) ? 14 : 5, height: 5)
                            }
                        }
                        .monoAnimation(.quick, value: page)
                        .accessibilityHidden(true)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            InsightQuoteView(insight: insight)
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
            }
        }
    }
}
