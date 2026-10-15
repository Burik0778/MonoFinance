import SwiftUI
import MonoCore
import MonoAnalytics

/// Экран цели: прогресс-кольцо, план по месяцам, история взносов.
struct GoalDetailView: View {
    let goal: Goal

    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language

    private var current: Goal { store.goals.first { $0.id == goal.id } ?? goal }

    var body: some View {
        let goal = current
        let now = Date()
        let status = store.analytics().goalStatuses([goal], contributions: store.contributions, balances: store.balances, now: now).first
        let contributions = store.contributions.filter { $0.goalID == goal.id }.sorted { $0.date > $1.date }
        let color = Color.mono.accent

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 18) {
                    ZStack {
                        ProgressRing(progress: status?.progress ?? 0, tint: color, lineWidth: 16)
                            .frame(width: 210, height: 210)
                        VStack(spacing: 6) {
                            Image(systemName: goal.icon)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(color)
                            if let status {
                                MoneyText(money: status.saved, token: .title, compact: true)
                                Text(verbatim: PercentFormatting.string(status.progress, language: language))
                                    .monoFont(.footnote, digits: true)
                                    .foregroundStyle(Color.mono.textSecondary)
                            }
                        }
                        .frame(maxWidth: 150)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(spacing: 4) {
                        Text(verbatim: goal.name)
                            .monoFont(.display)
                            .foregroundStyle(Color.mono.textPrimary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            Text("Цель")
                            MoneyText(money: goal.target, token: .callout, color: Color.mono.textSecondary)
                        }
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let status {
                    HStack(alignment: .top, spacing: 12) {
                        figure("Осталось", money: status.remaining, color: Color.mono.textPrimary)
                        if let monthly = status.monthlyNeeded {
                            figure("В месяц", money: monthly, color: color)
                        }
                        if let deadline = goal.deadline {
                            VStack(alignment: .leading, spacing: 6) {
                                Kicker("Срок")
                                Text(verbatim: DateFormatting.short(deadline, calendar: store.periods.calendar, language: language))
                                    .monoFont(.headline)
                                    .foregroundStyle(deadline < now && !status.isCompleted ? Color.mono.negative : Color.mono.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .monoSurface(radius: MonoTokens.Radius.xl, padding: 18)

                    if status.isCompleted {
                        Label("Цель достигнута", systemImage: "checkmark.seal.fill")
                            .monoFont(.headline)
                            .foregroundStyle(Color.mono.positive)
                            .frame(maxWidth: .infinity)
                    }
                }

                if let accountID = goal.linkedAccountID, let account = store.accountMap[accountID] {
                    Button {
                        router.open(.account(account.id))
                    } label: {
                        FormRow(icon: "link", tint: color, title: "Считается по счёту", subtitle: Text(verbatim: account.displayName)) {
                            Image(systemName: "chevron.right").foregroundStyle(Color.mono.textTertiary)
                        }
                        .monoSurface(radius: MonoTokens.Radius.lg, padding: 12)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(kicker: "Взносы", title: contributions.isEmpty ? nil : "История") {
                            Button {
                                router.present(.contribution(goal))
                            } label: {
                                Label("Взнос", systemImage: "plus")
                            }
                            .buttonStyle(ChipStyle(isSelected: true, tint: color))
                        }
                        if contributions.isEmpty {
                            Text("Отмечайте, сколько откладываете на эту цель — прогресс обновится сразу.")
                                .monoFont(.callout)
                                .foregroundStyle(Color.mono.textTertiary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(contributions) { contribution in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: DateFormatting.dayTitle(contribution.date, now: now, calendar: store.periods.calendar, language: language))
                                                .monoFont(.body)
                                                .foregroundStyle(Color.mono.textPrimary)
                                            if let note = contribution.note {
                                                Text(verbatim: note)
                                                    .monoFont(.caption)
                                                    .foregroundStyle(Color.mono.textTertiary)
                                            }
                                        }
                                        Spacer()
                                        MoneyText(money: contribution.amount, token: .amountRow, sign: .always,
                                                  color: contribution.amount.isNegative ? Color.mono.negative : Color.mono.positive)
                                    }
                                    .padding(.vertical, 10)
                                    .hairlineDivider()
                                    .contextMenu {
                                        Button("Удалить взнос", systemImage: "trash", role: .destructive) {
                                            delete(contribution)
                                        }
                                    }
                                }
                            }
                            .monoSurface(radius: MonoTokens.Radius.xl, padding: 14)
                        }
                    }
                }

                Button("Изменить цель") { router.present(.goal(goal)) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(MonoBackdrop())
        .navigationTitle(Text(verbatim: goal.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figure(_ title: LocalizedStringKey, money: Money, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(title)
            MoneyText(money: money, token: .headline, color: color, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func delete(_ contribution: GoalContribution) {
        do {
            try store.deleteContribution(contribution)
            Haptics.warning()
            toasts.show(ToastMessage(text: String(localized: "Взнос удалён"), symbol: "trash.fill", tint: Color.mono.negative,
                                     actionTitle: String(localized: "Вернуть")) {
                try? store.addContribution(contribution)
            })
        } catch {
            toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
        }
    }
}
