import Foundation
import UserNotifications
import NutritionCore

enum ReminderStore {
    static let key = "reminders"

    static func load() -> [Reminder] {
        var reminders: [Reminder]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = decoded
        } else {
            reminders = ReminderPlanner.defaults()
        }
        for kind in ReminderKind.allCases where !reminders.contains(where: { $0.kind == kind }) {
            reminders.append(Reminder(kind: kind))
        }
        return reminders.sorted { lhs, rhs in
            ReminderKind.allCases.firstIndex(of: lhs.kind)! < ReminderKind.allCases.firstIndex(of: rhs.kind)!
        }
    }

    static func save(_ reminders: [Reminder]) {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum ReminderScheduler {
    static var authorizationStatus: UNAuthorizationStatus {
        get async { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    /// 重新排期：先清掉旧的四条，再按开启的提醒装回系统。
    static func reschedule(_ reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ReminderKind.allCases.map { "reminder.\($0.rawValue)" })
        guard await requestAuthorization() else { return }
        for reminder in ReminderPlanner.scheduled(reminders) {
            let content = UNMutableNotificationContent()
            content.title = "小食痰记 · \(reminder.kind.title)"
            content.body = reminder.kind.message
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.dateComponents, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "reminder.\(reminder.kind.rawValue)",
                                                        content: content, trigger: trigger))
        }
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }
}
