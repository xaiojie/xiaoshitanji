import Foundation

/// 一天的训练总量（来自 Apple 健康）。
public struct HealthWorkoutTotals: Sendable, Equatable {
    public var sessions: Int
    public var minutes: Int
    public var calories: Double

    public init(sessions: Int = 0, minutes: Int = 0, calories: Double = 0) {
        self.sessions = sessions
        self.minutes = minutes
        self.calories = calories
    }

    public var hasWorkout: Bool { sessions > 0 }
}

/// 从 Apple 健康读取到的体能训练。只做展示与分析，不回写日记。
public struct HealthWorkout: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: WorkoutKind
    public var title: String
    public var durationMinutes: Int
    public var activeCalories: Double?
    public var averageHeartRate: Double?
    public var distanceMeters: Double?

    public init(id: UUID = UUID(), date: Date = .now, kind: WorkoutKind = .cardio,
                title: String = "", durationMinutes: Int = 0, activeCalories: Double? = nil,
                averageHeartRate: Double? = nil, distanceMeters: Double? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.averageHeartRate = averageHeartRate
        self.distanceMeters = distanceMeters
    }

    public func validate() throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw DiaryError.invalidInput("训练时间不合法。")
        }
        guard (1...600).contains(durationMinutes) else {
            throw DiaryError.invalidInput("训练时长需要在 1–600 分钟之间。")
        }
        if let activeCalories, !(0...5000).contains(activeCalories) {
            throw DiaryError.invalidInput("训练消耗热量不合法。")
        }
        if let averageHeartRate, !(30...240).contains(averageHeartRate) {
            throw DiaryError.invalidInput("训练平均心率不合法。")
        }
        if let distanceMeters, !(0...200_000).contains(distanceMeters) {
            throw DiaryError.invalidInput("训练距离不合法。")
        }
    }

    public var durationText: String { "\(durationMinutes) 分钟" }

    /// 每次训练单行的汇总，供列表展示。
    public var summaryLine: String {
        var parts = [durationText]
        if let activeCalories, activeCalories > 0 {
            parts.append("\(Int(activeCalories.rounded())) 千卡")
        }
        if let distanceMeters, distanceMeters > 0 {
            parts.append(String(format: "%.1f km", distanceMeters / 1000))
        }
        return parts.joined(separator: " · ")
    }
}

public enum HealthWorkoutSummary {
    /// 把训练按天聚合成 `HealthActivityDay` 上的三个字段，便于走同一条汇总/分析链路。
    public static func dailyTotals(_ workouts: [HealthWorkout],
                                   calendar: Calendar = .current) -> [Date: (sessions: Double, minutes: Double, calories: Double?)] {
        var totals: [Date: (sessions: Double, minutes: Double, calories: Double?)] = [:]
        for workout in workouts where workout.durationMinutes > 0 {
            let day = calendar.startOfDay(for: workout.date)
            var entry = totals[day] ?? (0, 0, nil)
            entry.sessions += 1
            entry.minutes += Double(workout.durationMinutes)
            if let calories = workout.activeCalories {
                entry.calories = (entry.calories ?? 0) + calories
            }
            totals[day] = entry
        }
        return totals
    }

    /// 某一天的训练总量；今天有没有练、练了多久、消耗多少，都从这里取。
    public static func totals(_ workouts: [HealthWorkout], on date: Date,
                              calendar: Calendar = .current) -> HealthWorkoutTotals {
        let day = calendar.startOfDay(for: date)
        var totals = HealthWorkoutTotals()
        for workout in workouts where calendar.startOfDay(for: workout.date) == day {
            totals.sessions += 1
            totals.minutes += workout.durationMinutes
            totals.calories += workout.activeCalories ?? 0
        }
        return totals
    }

    public static func stats(_ workouts: [HealthWorkout]) -> WorkoutStats {
        var stats = WorkoutStats()
        for workout in workouts {
            stats.sessions += 1
            stats.minutes += workout.durationMinutes
            stats.passedCalories += workout.activeCalories ?? 0
            stats.cardioMeters += workout.distanceMeters ?? 0
            if stats.lastDate == nil || workout.date > stats.lastDate! { stats.lastDate = workout.date }
        }
        return stats
    }
}
