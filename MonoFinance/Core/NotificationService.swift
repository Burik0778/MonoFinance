import Foundation
import UserNotifications
import MonoCore

/// Напоминания о регулярных платежах. Операции по напоминанию не создаются — только после подтверждения в приложении.
@MainActor
enum NotificationService {
    static let prefix = "recurring-"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Пересоздаёт напоминания. Если суммы скрыты или включена блокировка, сумма в тексте не показывается.
    static func reschedule(rules: [RecurringRule], enabled: Bool, includeAmounts: Bool, formatter: MoneyFormatter, calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard enabled else { return }
        let now = Date()
        for rule in rules where rule.isActive && rule.reminderEnabled && rule.nextDueDate > calendar.startOfDay(for: now) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Регулярный платёж")
            if includeAmounts {
                content.body = "\(rule.title) — \(formatter.string(rule.amount)). " + String(localized: "Подтвердите в MONO.")
            } else {
                content.body = rule.title + ". " + String(localized: "Подтвердите в MONO.")
            }
            content.sound = .default
            var components = calendar.dateComponents([.year, .month, .day], from: rule.nextDueDate)
            components.hour = 10
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + rule.id.uuidString, content: content, trigger: trigger))
        }
    }
}
