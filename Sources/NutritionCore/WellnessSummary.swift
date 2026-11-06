import Foundation

public enum WellnessPeriod: String, Codable, CaseIterable, Sendable, Identifiable {
    case week, month, all
    public var id: Self { self }
    public var title: String {
        switch self {
        case .week: "近7天"
        case .month: "近30天"
        case .all: "全部记录"
        }
    }

    public func startDate(document: DiaryDocument, endDate: Date, earliestHealthDate: Date? = nil,
                          calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: endDate)
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .all:
            let dates = document.records.map(\.date) + document.smoking.events.map(\.date)
                + document.weights.map(\.date) + document.workouts.map(\.date)
                + [document.profile.heightUpdatedAt, earliestHealthDate].compactMap { $0 }
            return calendar.startOfDay(for: dates.min().map { min($0, endDate) } ?? endDate)
        }
    }
}

public struct WellnessMetric: Codable, Equatable, Sendable {
    public let total: Double?
    public let observedDays: Int
    public var average: Double? { total.map { $0 / Double(max(1, observedDays)) } }

    init(_ values: [Double?]) {
        let available = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        observedDays = available.count
        total = available.isEmpty ? nil : available.reduce(0, +)
    }
}

public struct WellnessActivity: Codable, Equatable, Sendable {
    public let steps: WellnessMetric
    public let activeCalories: WellnessMetric
    public let exerciseMinutes: WellnessMetric
    public let distanceMeters: WellnessMetric
    public let sleepHours: WellnessMetric
    public let averageHeartRate: WellnessMetric
    public let restingHeartRate: WellnessMetric
    public let heartRateVariability: WellnessMetric
    public let vo2Max: WellnessMetric
    public let headphoneAudioMinutes: WellnessMetric
    public let workoutSessions: WellnessMetric
    public let workoutMinutes: WellnessMetric
    public let workoutCalories: WellnessMetric

    init(days: [HealthActivityDay]) {
        steps = WellnessMetric(days.map(\.steps))
        activeCalories = WellnessMetric(days.map(\.activeCalories))
        exerciseMinutes = WellnessMetric(days.map(\.exerciseMinutes))
        distanceMeters = WellnessMetric(days.map(\.distanceMeters))
        sleepHours = WellnessMetric(days.map(\.sleepHours))
        averageHeartRate = WellnessMetric(days.map(\.averageHeartRate))
        restingHeartRate = WellnessMetric(days.map(\.restingHeartRate))
        heartRateVariability = WellnessMetric(days.map(\.heartRateVariabilityMS))
        vo2Max = WellnessMetric(days.map(\.vo2Max))
        headphoneAudioMinutes = WellnessMetric(days.map(\.headphoneAudioMinutes))
        workoutSessions = WellnessMetric(days.map(\.workoutSessions))
        workoutMinutes = WellnessMetric(days.map(\.workoutMinutes))
        workoutCalories = WellnessMetric(days.map(\.workoutCalories))
    }

    private enum CodingKeys: String, CodingKey {
        case steps, activeCalories, exerciseMinutes, distanceMeters
        case sleepHours, averageHeartRate, restingHeartRate, heartRateVariability, vo2Max
        case headphoneAudioMinutes, workoutSessions, workoutMinutes, workoutCalories
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        steps = try values.decode(WellnessMetric.self, forKey: .steps)
        activeCalories = try values.decode(WellnessMetric.self, forKey: .activeCalories)
        exerciseMinutes = try values.decode(WellnessMetric.self, forKey: .exerciseMinutes)
        distanceMeters = try values.decode(WellnessMetric.self, forKey: .distanceMeters)
        // 旧报告的新增健康指标保持未知，观察天数为零。
        let unknown = WellnessMetric([])
        sleepHours = try values.decodeIfPresent(WellnessMetric.self, forKey: .sleepHours) ?? unknown
        averageHeartRate = try values.decodeIfPresent(WellnessMetric.self, forKey: .averageHeartRate) ?? unknown
        restingHeartRate = try values.decodeIfPresent(WellnessMetric.self, forKey: .restingHeartRate) ?? unknown
        heartRateVariability = try values.decodeIfPresent(WellnessMetric.self, forKey: .heartRateVariability) ?? unknown
        vo2Max = try values.decodeIfPresent(WellnessMetric.self, forKey: .vo2Max) ?? unknown
        headphoneAudioMinutes = try values.decodeIfPresent(WellnessMetric.self, forKey: .headphoneAudioMinutes) ?? unknown
        workoutSessions = try values.decodeIfPresent(WellnessMetric.self, forKey: .workoutSessions) ?? unknown
        workoutMinutes = try values.decodeIfPresent(WellnessMetric.self, forKey: .workoutMinutes) ?? unknown
        workoutCalories = try values.decodeIfPresent(WellnessMetric.self, forKey: .workoutCalories) ?? unknown
    }

    public var hasData: Bool {
        [steps, activeCalories, exerciseMinutes, distanceMeters, sleepHours, averageHeartRate,
         restingHeartRate, heartRateVariability, vo2Max, headphoneAudioMinutes,
         workoutSessions, workoutMinutes, workoutCalories].contains { $0.observedDays > 0 }
    }
}

public struct WellnessDiet: Codable, Equatable, Sendable {
    public let recordCount: Int
    public let recordedDays: Int
    public let total: Nutrition?
    public let foodNames: [String]
    public var average: Nutrition? { total?.scaled(by: 1 / Double(max(1, recordedDays))) }

    init(records: [MealRecord], calendar: Calendar) {
        recordCount = records.count
        recordedDays = Set(records.map { calendar.startOfDay(for: $0.date) }).count
        total = records.isEmpty ? nil : records.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let names = records.flatMap(\.foods).map { String($0.name.prefix(80)) }
        let groups = Dictionary(grouping: names, by: { $0 })
        foodNames = groups.keys.sorted {
            let leftCount = groups[$0]?.count ?? 0
            let rightCount = groups[$1]?.count ?? 0
            return leftCount == rightCount ? $0 < $1 : leftCount > rightCount
        }.prefix(20).map { $0 }
    }
}

public struct WellnessCost: Codable, Equatable, Sendable {
    public let currency: SmokingCurrency
    public let amount: Double
}

public struct WellnessSmoking: Codable, Equatable, Sendable {
    public let eventDays: Int
    public let smoked: Int
    public let shared: Int
    public let knownNicotineMG: Double
    public let unknownNicotineCount: Int
    public let costs: [WellnessCost]
    public let unpricedCount: Int

    init(journal: SmokingDiary, start: Date, until end: Date, calendar: Calendar) {
        let events = journal.events.filter { $0.date >= start && $0.date < end }
        eventDays = Set(events.map { calendar.startOfDay(for: $0.date) }).count
        let summary = journal.summary(from: start, until: end)
        smoked = summary.smoked
        shared = summary.shared
        knownNicotineMG = summary.knownNicotineMG
        unknownNicotineCount = summary.unknownNicotineCount
        unpricedCount = summary.unpricedCount
        costs = SmokingCurrency.allCases.compactMap { currency in
            summary.costs[currency].map { WellnessCost(currency: currency, amount: $0) }
        }
    }
}

public struct WellnessBody: Codable, Equatable, Sendable {
    public let heightCM: Double?
    public let heightDate: Date?
    public let heightSource: WeightSource?
    public let latestWeight: WeightRecord?
    public let firstWeightInRange: WeightRecord?
    public let targetWeightKG: Double?
    public let bmi: Double?
    public var weightChangeKG: Double? {
        guard let firstWeightInRange, let latestWeight, firstWeightInRange.date < latestWeight.date else { return nil }
        return latestWeight.kilograms - firstWeightInRange.kilograms
    }

    init(profile: HealthProfile, weights: [WeightRecord], healthHeightCM: Double?, healthHeightDate: Date?,
         start: Date, end: Date) {
        let manualHeight = profile.heightUpdatedAt.map { $0 <= end } ?? true
        heightCM = manualHeight ? (profile.heightCM ?? healthHeightCM) : healthHeightCM
        heightDate = manualHeight && profile.heightCM != nil ? profile.heightUpdatedAt : healthHeightDate
        heightSource = heightCM == nil ? nil : (manualHeight && profile.heightCM != nil ? .manual : .appleHealth)
        let measurements = weights.filter { $0.date <= end }
        latestWeight = WeightRecord.latest(in: measurements)
        let byDate = Dictionary(grouping: measurements.filter { $0.date >= start }, by: \.date)
        firstWeightInRange = byDate.values.compactMap { WeightRecord.latest(in: $0) }.min { $0.date < $1.date }
        targetWeightKG = profile.targetWeightKG
        bmi = HealthProfile(heightCM: heightCM).bmi(weightKG: latestWeight?.kilograms)
    }

    public var hasData: Bool { heightCM != nil || latestWeight != nil || targetWeightKG != nil }
}

public struct WellnessTrend: Codable, Equatable, Sendable {
    public let date: Date
    public let meals: Int
    public let calories: Double?
    public let smoked: Int?
    public let shared: Int?
    /// 该日（或该月）最后一次体重，单位公斤。旧报告没有这个字段，解码为 nil。
    public let weightKG: Double?
    public let activity: WellnessActivity
}

/// 记录覆盖度：窗口有多少天，其中饮食/吸烟/体重/活动各有几天有数据。
/// 用来替代「数据太少」这类含糊说法，让「2/30 天」变成一个能显示的数字。
public struct WellnessCoverage: Equatable, Sendable {
    public let windowDays: Int
    public let dietDays: Int
    public let smokingDays: Int
    public let weightDays: Int
    public let activityDays: Int
    public var trainingDays: Int = 0

    /// 本机记录意义上的覆盖天数，不含只来自 Apple 健康的活动。
    public var recordedDays: Int { max(trainingDays, max(dietDays, max(smokingDays, weightDays))) }
}

public struct WellnessTraining: Codable, Equatable, Sendable {
    public let sessions: Int
    public let recordedDays: Int
    public let minutes: Int
    public let runningSessions: Int
    public let runningDistanceMeters: Double?
    public let estimatedCalories: Double?
    public let heartRateRecordedSessions: Int
    public let averageSessionHeartRate: Double?

    init(workouts: [WorkoutRecord], includeHeartRate: Bool, calendar: Calendar) {
        sessions = workouts.count
        recordedDays = Set(workouts.map { calendar.startOfDay(for: $0.date) }).count
        minutes = workouts.reduce(0) { $0 + max(1, Int(ceil($1.effectiveDurationSeconds / 60))) }
        let runs = workouts.filter { $0.cardio?.activity == .run }
        runningSessions = runs.count
        let distances = runs.compactMap(\.effectiveDistanceMeters)
        runningDistanceMeters = distances.isEmpty ? nil : distances.reduce(0, +)
        let calories = workouts.compactMap(\.effectiveCalories)
        estimatedCalories = calories.isEmpty ? nil : calories.reduce(0, +)
        let heart = includeHeartRate ? workouts.compactMap(\.effectiveHeartRate) : []
        heartRateRecordedSessions = heart.count
        averageSessionHeartRate = heart.isEmpty ? nil : heart.reduce(0, +) / Double(heart.count)
    }

    func validate(dayCount: Int) throws {
        guard sessions >= 0, recordedDays >= 0, recordedDays <= min(dayCount, sessions), minutes >= 0,
              runningSessions >= 0, runningSessions <= sessions,
              runningDistanceMeters.map({ $0.isFinite && $0 >= 0 }) ?? true,
              estimatedCalories.map({ $0.isFinite && $0 >= 0 }) ?? true,
              heartRateRecordedSessions >= 0, heartRateRecordedSessions <= sessions,
              averageSessionHeartRate.map({ $0.isFinite && (20...300).contains($0) }) ?? true else {
            throw DiaryError.invalidInput("本机训练汇总无效，请重新读取记录。")
        }
    }
}

public struct WellnessSummary: Codable, Equatable, Sendable {
    public let period: WellnessPeriod
    public let startDate: Date
    public let endDate: Date
    public let dayCount: Int
    public let timeZone: String
    public let includesHealth: Bool
    public let calorieGoal: Double?
    /// 没有设置参考目标时，本地按个人资料算出的建议摄入，只作为估算参考。
    public let suggestedTarget: Double?
    public let diet: WellnessDiet
    public let smoking: WellnessSmoking
    public let body: WellnessBody
    public let activity: WellnessActivity
    public var training: WellnessTraining? = nil
    public let timelineUnit: String
    public let timeline: [WellnessTrend]

    public var hasData: Bool {
        diet.recordCount > 0 || smoking.eventDays > 0 || body.hasData || activity.hasData || (training?.sessions ?? 0) > 0
    }

    public var coverage: WellnessCoverage {
        WellnessCoverage(windowDays: dayCount, dietDays: diet.recordedDays, smokingDays: smoking.eventDays,
                         weightDays: timeline.reduce(0) { $0 + ($1.weightKG == nil ? 0 : 1) },
                         activityDays: activity.steps.observedDays, trainingDays: training?.recordedDays ?? 0)
    }

    public static func make(document: DiaryDocument, period: WellnessPeriod, endDate: Date,
                            activityDays: [HealthActivityDay] = [], healthWeights: [WeightRecord] = [],
                            healthHeightCM: Double? = nil, healthHeightDate: Date? = nil,
                            calorieGoal: Double? = nil, earliestHealthDate: Date? = nil,
                            includesHealth: Bool = false, energySettings: EnergySettings? = nil,
                            calendar: Calendar = .current) throws -> Self {
        try document.validate()
        guard endDate.timeIntervalSinceReferenceDate.isFinite,
              calorieGoal.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw DiaryError.invalidInput("分析时间或参考目标无效，请重新打开汇总分析。")
        }
        let healthDates = activityDays.map(\.date) + healthWeights.map(\.date)
            + [earliestHealthDate, healthHeightDate].compactMap { $0 }
        let start = period.startDate(document: document, endDate: endDate,
            earliestHealthDate: includesHealth ? healthDates.min() : nil, calendar: calendar)
        let today = calendar.startOfDay(for: endDate)
        let localEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? endDate
        // Meal presets may be later than the clock on the current local day.
        let records = document.records.filter { $0.date >= start && $0.date < localEnd }
        let workouts = document.workouts.filter { $0.date >= start && $0.date <= endDate }
        let activityByDay = Dictionary(grouping: includesHealth ? activityDays : [], by: { calendar.startOfDay(for: $0.date) })
        let days = activityByDay.keys.sorted().compactMap { day -> HealthActivityDay? in
            guard day >= start, day <= today else { return nil }
            guard let value = activityByDay[day]?.last, WellnessActivity(days: [value]).hasData else { return nil }
            return value
        }
        let weights = document.weights + (includesHealth ? healthWeights : [])
        let readableHeight = includesHealth && (healthHeightDate.map { $0 <= endDate } ?? true)
        let body = WellnessBody(profile: document.profile, weights: weights,
            healthHeightCM: readableHeight ? healthHeightCM : nil, healthHeightDate: readableHeight ? healthHeightDate : nil,
            start: start, end: endDate)
        let events = document.smoking.events.filter { $0.date >= start && $0.date < localEnd }
        let granularity: Calendar.Component = period == .all ? .month : .day
        func bucket(_ date: Date) -> Date { calendar.dateInterval(of: granularity, for: date)?.start ?? date }
        let mealGroups = Dictionary(grouping: records, by: { bucket($0.date) })
        let eventGroups = Dictionary(grouping: events, by: { bucket($0.date) })
        let activityGroups = Dictionary(grouping: days, by: { bucket($0.date) })
        let weightGroups = Dictionary(grouping: weights.filter { $0.date >= start && $0.date <= endDate },
                                       by: { bucket($0.date) })
        let dates = Set(mealGroups.keys).union(eventGroups.keys).union(activityGroups.keys)
            .union(weightGroups.keys).union(workouts.map { bucket($0.date) }).sorted()
        let timeline = dates.map { date in
            let meals = mealGroups[date] ?? []
            let events = eventGroups[date] ?? []
            return WellnessTrend(date: date, meals: meals.count,
                calories: meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.nutrition.calories },
                smoked: events.isEmpty ? nil : events.filter { $0.kind == .smoked }.reduce(0) { $0 + $1.count },
                shared: events.isEmpty ? nil : events.filter { $0.kind == .shared }.reduce(0) { $0 + $1.count },
                weightKG: WeightRecord.latest(in: weightGroups[date] ?? [])?.kilograms,
                activity: WellnessActivity(days: activityGroups[date] ?? []))
        }
        let suggestedTarget = calorieGoal == nil
            ? Self.estimatedTarget(settings: energySettings, body: body, now: endDate, calendar: calendar) : nil
        let result = Self(period: period, startDate: start, endDate: endDate,
            dayCount: (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1,
            timeZone: calendar.timeZone.identifier, includesHealth: includesHealth, calorieGoal: calorieGoal,
            suggestedTarget: suggestedTarget,
            diet: WellnessDiet(records: records, calendar: calendar),
            smoking: WellnessSmoking(journal: document.smoking, start: start, until: localEnd, calendar: calendar),
            body: body, activity: WellnessActivity(days: days),
            training: WellnessTraining(workouts: workouts, includeHeartRate: includesHealth, calendar: calendar),
            timelineUnit: period == .all ? "month" : "day", timeline: timeline)
        try result.validate()
        return result
    }

    /// 只用于「没有设目标」时给模型一个可引用的估算区间中点，不替代用户的设置。
    private static func estimatedTarget(settings: EnergySettings?, body: WellnessBody,
                                        now: Date, calendar: Calendar) -> Double? {
        guard let settings, let weight = body.latestWeight?.kilograms, let height = body.heightCM,
              let budget = try? EnergyCalculator.budget(settings: settings, weightKG: weight, heightCM: height,
                                                        now: now, calendar: calendar) else { return nil }
        let rounded = (budget.targetCalories / 10).rounded() * 10
        guard rounded.isFinite, rounded >= EnergyCalculator.minimumCalories else { return nil }
        return rounded
    }

    public func validate() throws {
        try training?.validate(dayCount: dayCount)
        guard startDate.timeIntervalSinceReferenceDate.isFinite, endDate.timeIntervalSinceReferenceDate.isFinite,
              startDate <= endDate, dayCount > 0, diet.recordCount >= 0, diet.recordedDays >= 0,
              (diet.recordCount == 0 ? diet.total == nil && diet.recordedDays == 0 : diet.total != nil && diet.recordedDays > 0),
              diet.recordedDays <= dayCount, smoking.eventDays >= 0, smoking.eventDays <= dayCount,
              smoking.smoked >= 0, smoking.shared >= 0,
              smoking.unknownNicotineCount >= 0, smoking.unknownNicotineCount <= smoking.smoked,
              smoking.unpricedCount >= 0, smoking.unpricedCount <= smoking.smoked,
              smoking.knownNicotineMG.isFinite, smoking.knownNicotineMG >= 0 else {
            throw DiaryError.invalidInput("汇总数值无效，请重新读取记录。")
        }
        try diet.total?.validate()
        let metrics = [activity.steps, activity.activeCalories, activity.exerciseMinutes, activity.distanceMeters,
                       activity.sleepHours, activity.averageHeartRate, activity.restingHeartRate,
                       activity.heartRateVariability, activity.vo2Max, activity.headphoneAudioMinutes,
                       activity.workoutSessions, activity.workoutMinutes, activity.workoutCalories]
        guard metrics.allSatisfy({
            $0.observedDays >= 0 && $0.observedDays <= dayCount
                && ($0.observedDays == 0 ? $0.total == nil : $0.total.map { $0.isFinite && $0 >= 0 } == true)
        }),
              smoking.costs.allSatisfy({ $0.amount.isFinite && $0.amount >= 0 }) else {
            throw DiaryError.invalidInput("活动或费用汇总无效，请重新读取记录。")
        }
        try body.latestWeight?.validate()
        try body.firstWeightInRange?.validate()
        try HealthProfile(heightCM: body.heightCM, targetWeightKG: body.targetWeightKG, heightUpdatedAt: body.heightDate).validate()
        guard body.latestWeight.map({ $0.date <= endDate }) ?? true,
              body.firstWeightInRange.map({ $0.date >= startDate && $0.date <= endDate }) ?? true,
              body.bmi == HealthProfile(heightCM: body.heightCM).bmi(weightKG: body.latestWeight?.kilograms),
              calorieGoal.map({ $0.isFinite && $0 > 0 }) ?? true,
              suggestedTarget.map({ $0.isFinite && $0 >= EnergyCalculator.minimumCalories }) ?? true else {
            throw DiaryError.invalidInput("身体测量或参考目标无效，请重新读取记录。")
        }
        guard timeline.allSatisfy({ $0.weightKG.map({ $0.isFinite && (20...400).contains($0) }) ?? true }) else {
            throw DiaryError.invalidInput("时间线体重无效，请重新读取记录。")
        }
    }
}
