import Foundation

/// App 与小组件共用的今日快照；只读 App Group 里的一个 JSON 文件。
public struct DiaryWidgetSnapshot: Codable, Equatable, Sendable {
    public var calories: Double
    public var targetCalories: Double?
    public var protein: Double
    public var carbohydrate: Double
    public var fat: Double
    public var mealCount: Int
    public var updatedAt: Date
    /// nil 表示旧快照没有分餐信息，不等同于每餐均未记录。
    public var meals: [DiaryWidgetMeal]?
    public var timeZoneIdentifier: String?

    public init(calories: Double, targetCalories: Double?, protein: Double, carbohydrate: Double,
                fat: Double, mealCount: Int, updatedAt: Date = .now,
                meals: [DiaryWidgetMeal]? = nil, timeZoneIdentifier: String? = nil) {
        self.calories = calories
        self.targetCalories = targetCalories
        self.protein = protein
        self.carbohydrate = carbohydrate
        self.fat = fat
        self.mealCount = mealCount
        self.updatedAt = updatedAt
        self.meals = meals
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var remaining: Double? {
        guard let targetCalories, targetCalories.isFinite, targetCalories > 0,
              calories.isFinite, calories >= 0 else { return nil }
        return targetCalories - calories
    }

    public var progress: Double? {
        guard let targetCalories, remaining != nil else { return nil }
        return min(1, max(0, calories / targetCalories))
    }

    public func isCurrent(on date: Date, calendar: Calendar = .current) -> Bool {
        if let timeZoneIdentifier, timeZoneIdentifier != calendar.timeZone.identifier { return false }
        return calendar.isDate(updatedAt, inSameDayAs: date)
    }
}

public enum WidgetMealKind: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack
    public var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        }
    }

    /// 灵动岛上的三餐节点；加餐只出现在 App 和小组件里。
    public static var islandKinds: [WidgetMealKind] { [.breakfast, .lunch, .dinner] }
}

public struct DiaryWidgetMeal: Codable, Hashable, Sendable {
    public var kind: WidgetMealKind
    public var calories: Double
    public var recordCount: Int

    public init(kind: WidgetMealKind, calories: Double, recordCount: Int) {
        self.kind = kind
        self.calories = calories
        self.recordCount = recordCount
    }
}

public enum DiaryWidgetTimeline {
    public static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }

    public static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        min(date.addingTimeInterval(30 * 60), nextMidnight(after: date, calendar: calendar))
    }
}

public enum DiaryWidgetRoute: Equatable, Sendable {
    case today, newMeal

    public var url: URL {
        switch self {
        case .today: URL(string: "xiaoshitanji://today")!
        case .newMeal: URL(string: "xiaoshitanji://meal/new")!
        }
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "xiaoshitanji",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        switch (url.host?.lowercased(), url.path) {
        case ("today", ""), ("today", "/"): self = .today
        case ("meal", "/new"): self = .newMeal
        default: return nil
        }
    }
}

public enum DiaryWidgetStore {
    public static let appGroup = "group.com.jay.fooddiary"
    public static let fileName = "widget-snapshot.json"

    public static var directory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        let library = base.appending(path: "Library", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: library.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        }
        return library
    }

    public static var fileURL: URL? {
        directory?.appending(path: fileName)
    }

    public static func load() -> DiaryWidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiaryWidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func save(_ snapshot: DiaryWidgetSnapshot) -> Bool {
        guard let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
