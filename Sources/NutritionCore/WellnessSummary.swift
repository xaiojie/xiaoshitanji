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
                + document.weights.map(\.date) + [document.profile.heightUpdatedAt, earliestHealthDate].compactMap { $0 }
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

    init(days: [HealthActivityDay]) {
        steps = WellnessMetric(days.map(\.steps))
        activeCalories = WellnessMetric(days.map(\.activeCalories))
        exerciseMinutes = WellnessMetric(days.map(\.exerciseMinutes))
        distanceMeters = WellnessMetric(days.map(\.distanceMeters))
    }

    public var hasData: Bool {
        [steps, activeCalories, exerciseMinutes, distanceMeters].contains { $0.observedDays > 0 }
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
    public let activity: WellnessActivity
}

public struct WellnessSummary: Codable, Equatable, Sendable {
    public let period: WellnessPeriod
    public let startDate: Date
    public let endDate: Date
    public let dayCount: Int
    public let timeZone: String
    public let includesHealth: Bool
    public let calorieGoal: Double?
    public let diet: WellnessDiet
    public let smoking: WellnessSmoking
    public let body: WellnessBody
    public let activity: WellnessActivity
    public let timelineUnit: String
    public let timeline: [WellnessTrend]

    public var hasData: Bool { diet.recordCount > 0 || smoking.eventDays > 0 || body.hasData || activity.hasData }

    public static func make(document: DiaryDocument, period: WellnessPeriod, endDate: Date,
                            activityDays: [HealthActivityDay] = [], healthWeights: [WeightRecord] = [],
                            healthHeightCM: Double? = nil, healthHeightDate: Date? = nil,
                            calorieGoal: Double? = nil, earliestHealthDate: Date? = nil,
                            includesHealth: Bool = false, calendar: Calendar = .current) throws -> Self {
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
        let dates = Set(mealGroups.keys).union(eventGroups.keys).union(activityGroups.keys).sorted()
        let timeline = dates.map { date in
            let meals = mealGroups[date] ?? []
            let events = eventGroups[date] ?? []
            return WellnessTrend(date: date, meals: meals.count,
                calories: meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.nutrition.calories },
                smoked: events.isEmpty ? nil : events.filter { $0.kind == .smoked }.reduce(0) { $0 + $1.count },
                shared: events.isEmpty ? nil : events.filter { $0.kind == .shared }.reduce(0) { $0 + $1.count },
                activity: WellnessActivity(days: activityGroups[date] ?? []))
        }
        let result = Self(period: period, startDate: start, endDate: endDate,
            dayCount: (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1,
            timeZone: calendar.timeZone.identifier, includesHealth: includesHealth, calorieGoal: calorieGoal,
            diet: WellnessDiet(records: records, calendar: calendar),
            smoking: WellnessSmoking(journal: document.smoking, start: start, until: localEnd, calendar: calendar),
            body: body, activity: WellnessActivity(days: days), timelineUnit: period == .all ? "month" : "day", timeline: timeline)
        try result.validate()
        return result
    }

    public func validate() throws {
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
        let metrics = [activity.steps, activity.activeCalories, activity.exerciseMinutes, activity.distanceMeters]
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
              calorieGoal.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw DiaryError.invalidInput("身体测量或参考目标无效，请重新读取记录。")
        }
    }
}
