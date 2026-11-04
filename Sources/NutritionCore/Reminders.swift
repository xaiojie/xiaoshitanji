import Foundation

public enum ReminderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, weight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .weight: "称重"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: "sun.horizon"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars"
        case .weight: "scalemass"
        }
    }

    public var defaultHour: Int {
        switch self {
        case .breakfast: 8
        case .lunch: 12
        case .dinner: 18
        case .weight: 7
        }
    }

    public var defaultMinute: Int {
        switch self {
        case .lunch: 30
        case .weight: 30
        default: 0
        }
    }

    /// 默认只开三餐，称重留给用户自己决定。
    public var isEnabledByDefault: Bool { self != .weight }

    public var message: String {
        switch self {
        case .breakfast: "吃了什么？记一句，午饭前还能补。"
        case .lunch: "中午这顿记一下，晚上的回顾才准。"
        case .dinner: "晚饭记完，今天的数字就齐了。"
        case .weight: "顺手称个体重，趋势才有得看。"
        }
    }
}

public struct Reminder: Codable, Sendable, Equatable, Identifiable {
    public var kind: ReminderKind
    public var hour: Int
    public var minute: Int
    public var isEnabled: Bool

    public var id: ReminderKind { kind }

    public init(kind: ReminderKind, hour: Int? = nil, minute: Int? = nil, isEnabled: Bool? = nil) {
        self.kind = kind
        self.hour = hour ?? kind.defaultHour
        self.minute = minute ?? kind.defaultMinute
        self.isEnabled = isEnabled ?? kind.isEnabledByDefault
    }

    public func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw DiaryError.invalidInput("提醒时间不合法。")
        }
    }

    public var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    public var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public mutating func setTime(from date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? hour
        minute = parts.minute ?? minute
    }

    public var date: Date {
        Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? .now
    }
}

public enum ReminderPlanner {
    public static func defaults() -> [Reminder] {
        ReminderKind.allCases.map { Reminder(kind: $0) }
    }

    /// 只有开启且时间合法的提醒才排进系统通知。
    public static func scheduled(_ reminders: [Reminder]) -> [Reminder] {
        reminders.filter { $0.isEnabled && (try? $0.validate()) != nil }
    }

    /// 最靠近现在的一条，用来在设置里提示「下一次」。
    public static func next(from reminders: [Reminder], now: Date = .now, calendar: Calendar = .current) -> (Reminder, Date)? {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutesNow = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = scheduled(reminders).sorted {
            ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute)
        }
        guard !today.isEmpty else { return nil }
        if let upcoming = today.first(where: { $0.hour * 60 + $0.minute > minutesNow }) {
            return (upcoming, date(for: upcoming, now: now, calendar: calendar))
        }
        guard let first = today.first else { return nil }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return (first, date(for: first, now: tomorrow, calendar: calendar))
    }

    static func date(for reminder: Reminder, now: Date, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = reminder.hour
        parts.minute = reminder.minute
        parts.second = 0
        return calendar.date(from: parts) ?? now
    }
}
