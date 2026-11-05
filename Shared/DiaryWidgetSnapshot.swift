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

    public init(calories: Double, targetCalories: Double?, protein: Double, carbohydrate: Double,
                fat: Double, mealCount: Int, updatedAt: Date = .now) {
        self.calories = calories
        self.targetCalories = targetCalories
        self.protein = protein
        self.carbohydrate = carbohydrate
        self.fat = fat
        self.mealCount = mealCount
        self.updatedAt = updatedAt
    }

    public var remaining: Double? {
        guard let targetCalories else { return nil }
        return targetCalories - calories
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
