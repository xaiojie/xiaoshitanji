import ActivityKit
import Foundation

public struct IntakeActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var calories: Double
        public var targetCalories: Double?
        public var mealCount: Int
        public var updatedAt: Date
        /// Optional 使升级前仍在运行的实时活动可以继续解码；nil 不代表摄入为零。
        public var protein: Double?
        public var carbohydrate: Double?
        public var fat: Double?
        public var meals: [DiaryWidgetMeal]?
        public var timeZoneIdentifier: String?

        public init(calories: Double, targetCalories: Double?, mealCount: Int, updatedAt: Date = .now,
                    protein: Double? = nil, carbohydrate: Double? = nil, fat: Double? = nil,
                    meals: [DiaryWidgetMeal]? = nil, timeZoneIdentifier: String? = nil) {
            self.calories = calories
            self.targetCalories = targetCalories
            self.mealCount = mealCount
            self.updatedAt = updatedAt
            self.protein = protein
            self.carbohydrate = carbohydrate
            self.fat = fat
            self.meals = meals
            self.timeZoneIdentifier = timeZoneIdentifier
        }

        public init(snapshot: DiaryWidgetSnapshot) {
            self.init(calories: snapshot.calories, targetCalories: snapshot.targetCalories,
                      mealCount: snapshot.mealCount, updatedAt: snapshot.updatedAt,
                      protein: snapshot.protein, carbohydrate: snapshot.carbohydrate, fat: snapshot.fat,
                      meals: snapshot.meals, timeZoneIdentifier: snapshot.timeZoneIdentifier)
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

    public var startedAt: Date

    public init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }
}
