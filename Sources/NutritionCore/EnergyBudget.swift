import Foundation

/// 生理性别只用于 Mifflin-St Jeor 的基础代谢计算。
public enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female, male
    public var id: String { rawValue }
    public var title: String { self == .male ? "男" : "女" }
}

/// 一周内的日常活动水平。系数取自常见的 TDEE 活动系数表。
public enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, active, veryActive

    public var id: String { rawValue }

    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    public var title: String {
        switch self {
        case .sedentary: "久坐"
        case .light: "轻度活动"
        case .moderate: "中等活动"
        case .active: "高强度活动"
        case .veryActive: "运动员级"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary: "几乎不额外运动，每天少于 4000 步"
        case .light: "每周运动 1–3 次，或每天 4000–8000 步"
        case .moderate: "每周运动 3–5 次，或每天 8000–12000 步"
        case .active: "每周运动 6–7 次，或体力工作"
        case .veryActive: "每天高强度训练，或重体力工作"
        }
    }
}

public enum GoalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose, maintain, gain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lose: "减脂"
        case .maintain: "维持"
        case .gain: "增肌"
        }
    }

    public var symbol: String {
        switch self {
        case .lose: "arrow.down.right"
        case .maintain: "equal"
        case .gain: "arrow.up.right"
        }
    }
}

/// 能量目标设置。存在 `DiaryDocument.energy` 里，为空时 App 退回旧的「参考热量」。
public struct EnergySettings: Codable, Equatable, Sendable {
    public var sex: BiologicalSex
    public var birthYear: Int
    public var activity: ActivityLevel
    public var goalMode: GoalMode
    /// 每周希望变化的公斤数，仅减脂/增肌有意义。
    public var weeklyRate: Double
    /// 由 2–4 周体重变化校准出的维持热量，优先于公式估算。
    public var calibratedMaintenance: Double?
    public var updatedAt: Date

    public init(sex: BiologicalSex = .male, birthYear: Int = 1995, activity: ActivityLevel = .moderate,
                goalMode: GoalMode = .maintain, weeklyRate: Double = 0.25,
                calibratedMaintenance: Double? = nil, updatedAt: Date = .now) {
        self.sex = sex
        self.birthYear = birthYear
        self.activity = activity
        self.goalMode = goalMode
        self.weeklyRate = weeklyRate
        self.calibratedMaintenance = calibratedMaintenance
        self.updatedAt = updatedAt
    }

    public var usesCalibration: Bool {
        guard let calibratedMaintenance else { return false }
        return (800...6000).contains(calibratedMaintenance)
    }

    public func validate(now: Date = .now, calendar: Calendar = .current) throws {
        let year = calendar.component(.year, from: now)
        guard (1900...year).contains(birthYear) else {
            throw DiaryError.invalidInput("请填写有效的出生年份。")
        }
        guard EnergyCalculator.age(birthYear: birthYear, now: now, calendar: calendar) >= 14 else {
            throw DiaryError.invalidInput("能量目标只适用于 14 岁以上。")
        }
        guard weeklyRate.isFinite, (0...1.5).contains(weeklyRate) else {
            throw DiaryError.invalidInput("每周变化请控制在 0 到 1.5 公斤之间。")
        }
        if let calibratedMaintenance {
            guard calibratedMaintenance.isFinite, (800...6000).contains(calibratedMaintenance) else {
                throw DiaryError.invalidInput("校准后的维持热量看起来不合理，请重新校准。")
            }
        }
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DiaryError.invalidInput("目标设置的时间无效。")
        }
    }
}

/// 用体重趋势反推维持热量的结果。
public struct MaintenanceCalibration: Equatable, Sendable {
    public var maintenance: Double
    public var averageIntake: Double
    public var weightChangeKG: Double
    public var days: Double
}

/// 一次算好的能量与宏量目标，只读展示用。
public struct EnergyBudget: Equatable, Sendable {
    public var bmr: Double
    public var maintenance: Double
    public var targetCalories: Double
    public var proteinGrams: Double
    public var carbGrams: Double
    public var fatGrams: Double
    /// 每日缺口/盈余，负数表示吃得更少。
    public var dailyDelta: Double
    public var age: Int
    public var usedCalibration: Bool

    public var proteinCalories: Double { proteinGrams * 4 }
    public var carbCalories: Double { carbGrams * 4 }
    public var fatCalories: Double { fatGrams * 9 }
}

public enum EnergyCalculator {
    /// 一公斤脂肪约 7700 千卡。
    public static let kilocaloriesPerKilogram = 7700.0
    /// 安全下限：绝不把目标压到基础代谢附近以下。
    public static let minimumCalories = 1200.0

    public static func age(birthYear: Int, now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.component(.year, from: now) - birthYear)
    }

    public static func bmr(sex: BiologicalSex, weightKG: Double, heightCM: Double, age: Int) -> Double {
        let base = 10 * weightKG + 6.25 * heightCM - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// 用一段时间内的平均摄入与体重变化反推维持热量。
    /// 增重时实际维持热量低于平均摄入，减重时高于平均摄入。
    public static func calibratedMaintenance(averageIntake: Double, weightChangeKG: Double, days: Double) -> Double? {
        guard averageIntake.isFinite, averageIntake > 0, days >= 7 else { return nil }
        guard weightChangeKG.isFinite, abs(weightChangeKG) <= 15 else { return nil }
        let value = averageIntake - weightChangeKG * kilocaloriesPerKilogram / days
        guard value.isFinite, (800...6000).contains(value) else { return nil }
        return value
    }

    /// 用一段时间的体重变化与记录到的平均摄入做校准。
    /// - Parameters:
    ///   - weights: 体重记录，取最近一次与更早的一次。
    ///   - dailyIntakes: 有记录的那些天的热量，空/缺失的天不参与平均。
    public static func calibrate(weights: [WeightRecord], dailyIntakes: [Double],
                                 windowDays: Int = 28) -> MaintenanceCalibration? {
        guard let latest = weights.max(by: { $0.date < $1.date }) else { return nil }
        let earliestDate = Calendar.current.date(byAdding: .day, value: -windowDays, to: latest.date) ?? latest.date
        let candidates = weights.filter { $0.date < latest.date && $0.date >= earliestDate }
        guard let first = candidates.min(by: { $0.date < $1.date }) else { return nil }
        let days = latest.date.timeIntervalSince(first.date) / 86_400
        guard (7...Double(windowDays)).contains(days) else { return nil }

        let validIntakes = dailyIntakes.filter { $0.isFinite && (200...8000).contains($0) }
        guard validIntakes.count >= 5 else { return nil }
        let average = validIntakes.reduce(0, +) / Double(validIntakes.count)
        guard let maintenance = calibratedMaintenance(averageIntake: average,
                                                      weightChangeKG: latest.kilograms - first.kilograms,
                                                      days: days) else { return nil }
        return MaintenanceCalibration(maintenance: maintenance, averageIntake: average,
                                      weightChangeKG: latest.kilograms - first.kilograms, days: days)
    }

    public static func budget(settings: EnergySettings, weightKG: Double, heightCM: Double,
                              now: Date = .now, calendar: Calendar = .current) throws -> EnergyBudget {
        try settings.validate(now: now, calendar: calendar)
        guard weightKG.isFinite, (20...400).contains(weightKG) else {
            throw DiaryError.invalidInput("请先记录体重，才能计算能量目标。")
        }
        guard heightCM.isFinite, (50...250).contains(heightCM) else {
            throw DiaryError.invalidInput("请先填写身高，才能计算能量目标。")
        }

        let age = age(birthYear: settings.birthYear, now: now, calendar: calendar)
        let bmr = bmr(sex: settings.sex, weightKG: weightKG, heightCM: heightCM, age: age)
        let formula = bmr * settings.activity.factor
        let maintenance = settings.usesCalibration ? settings.calibratedMaintenance! : formula

        let dailyDelta: Double
        switch settings.goalMode {
        case .lose: dailyDelta = -settings.weeklyRate * kilocaloriesPerKilogram / 7
        case .gain: dailyDelta = settings.weeklyRate * kilocaloriesPerKilogram / 7 * 0.5
        case .maintain: dailyDelta = 0
        }

        let floor = max(minimumCalories, bmr * 1.1)
        let target = min(max(maintenance + dailyDelta, floor), maintenance * 1.35)
        let effectiveDelta = target - maintenance

        let proteinPerKG = switch settings.goalMode {
        case .lose: 2.0
        case .maintain: 1.6
        case .gain: 1.8
        }
        let protein = weightKG * proteinPerKG
        let fat = max(0.7 * weightKG, target * 0.25 / 9)
        let carbs = max(0, (target - protein * 4 - fat * 9) / 4)

        return EnergyBudget(bmr: bmr, maintenance: maintenance, targetCalories: target,
                            proteinGrams: protein, carbGrams: carbs, fatGrams: fat,
                            dailyDelta: effectiveDelta, age: age, usedCalibration: settings.usesCalibration)
    }
}
