import ActivityKit
import Foundation

public struct IntakeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var calories: Double
        public var targetCalories: Double?
        public var mealCount: Int
        public var updatedAt: Date

        public init(calories: Double, targetCalories: Double?, mealCount: Int, updatedAt: Date = .now) {
            self.calories = calories
            self.targetCalories = targetCalories
            self.mealCount = mealCount
            self.updatedAt = updatedAt
        }

        public var remaining: Double? {
            guard let targetCalories else { return nil }
            return targetCalories - calories
        }
    }

    public var startedAt: Date

    public init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }
}
