import Foundation

/// 本地模式识别结论：完全由记录算出，不依赖 AI，可关闭。
public struct HealthPattern: Identifiable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case attention
        case notice
    }

    public let id: String
    public let title: String
    public let detail: String
    public let evidence: String
    public let severity: Severity
    public let symbol: String

    public init(id: String, title: String, detail: String, evidence: String,
                severity: Severity, symbol: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.evidence = evidence
        self.severity = severity
        self.symbol = symbol
    }
}

public struct PatternOptions: Equatable, Sendable {
    /// 每公斤目标体重的蛋白下限（克）。
    public var proteinPerKG: Double
    /// 没有体重时使用的蛋白下限（克）。
    public var proteinFloorGrams: Double
    /// 抽烟时段聚合窗口（小时）。
    public var smokeWindowHours: Int
    /// 同一窗口内占比达到多少算「集中」。
    public var smokeConcentration: Double
    /// 至少几根烟才判断时段。
    public var minimumCigarettes: Int
    /// 至少几天饮食记录才判断蛋白与热量。
    public var minimumRecordedDays: Int
    /// 连续多少天没有记录算断档。
    public var gapDays: Int
    /// 体重判断的最短跨度（天）。
    public var weightStallDays: Int
    /// 体重变化小于多少公斤算「不明显」。
    public var weightStallKG: Double
    /// 日均热量高于目标多少比例算偏高。
    public var calorieOvershoot: Double

    public init() {
        proteinPerKG = 1.2
        proteinFloorGrams = 60
        smokeWindowHours = 4
        smokeConcentration = 0.6
        minimumCigarettes = 5
        minimumRecordedDays = 3
        gapDays = 3
        weightStallDays = 14
        weightStallKG = 0.3
        calorieOvershoot = 1.15
    }
}

public enum HealthPatternDetector {
    public static func detect(document: DiaryDocument, context: ObservationContext,
                              options: PatternOptions = PatternOptions(),
                              now: Date = .now, calendar: Calendar = .current) -> [HealthPattern] {
        let facts = context.facts
        var patterns: [HealthPattern] = []
        let start = calendar.startOfDay(for: facts.startDate)
        let end = calendar.startOfDay(for: min(facts.endDate, now))

        if let protein = detectLowProtein(document: document, facts: facts, options: options, calendar: calendar) {
            patterns.append(protein)
        }
        if let smoking = detectSmokingWindow(document: document, start: start, end: end,
                                             options: options, calendar: calendar) {
            patterns.append(smoking)
        }
        if let gap = detectRecordGap(document: document, start: start, end: end,
                                     options: options, calendar: calendar) {
            patterns.append(gap)
        }
        if let weight = detectWeightStall(document: document, start: start, end: end,
                                          options: options, calendar: calendar) {
            patterns.append(weight)
        }
        if let calories = detectCalorieOvershoot(facts: facts, options: options) {
            patterns.append(calories)
        }
        return patterns.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == .attention }
            return lhs.id < rhs.id
        }
    }

    private static func detectLowProtein(document: DiaryDocument, facts: ObservationFacts,
                                         options: PatternOptions, calendar: Calendar) -> HealthPattern? {
        guard facts.recordedDays >= options.minimumRecordedDays, let average = facts.averageProtein else { return nil }
        let weight = facts.latestWeightKG
        let floor = max(options.proteinFloorGrams, (weight ?? 0) * options.proteinPerKG)
        guard average < floor else { return nil }
        let target = weight == nil
            ? String(format: "%.0f 克", floor)
            : String(format: "%.0f 克（每公斤 %.1f 克）", floor, options.proteinPerKG)
        return HealthPattern(
            id: "protein-low",
            title: "蛋白质可能吃少了",
            detail: "这段区间平均每天约 \(Int(average.rounded())) 克蛋白质，低于建议下限 \(target)。可以在正餐里固定加一份蛋、奶、豆制品或瘦肉。",
            evidence: "\(facts.recordedDays) 个记录日，日均蛋白质 \(Int(average.rounded())) 克",
            severity: .attention,
            symbol: "figure.strengthtraining.traditional")
    }

    private static func detectSmokingWindow(document: DiaryDocument, start: Date, end: Date,
                                            options: PatternOptions, calendar: Calendar) -> HealthPattern? {
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end)!
        let events = document.smoking.events.filter {
            $0.kind == .smoked && $0.date >= start && $0.date < dayAfterEnd
        }
        let cigarettes = events.reduce(0) { $0 + $1.count }
        guard cigarettes >= options.minimumCigarettes else { return nil }
        let hours = events.flatMap { event in
            Array(repeating: calendar.component(.hour, from: event.date), count: event.count)
        }
        let window = max(1, min(12, options.smokeWindowHours))
        var bestStart = 0
        var bestCount = -1
        for candidate in 0..<24 {
            let count = hours.filter { hour in
                let offset = (hour - candidate + 24) % 24
                return offset < window
            }.count
            if count > bestCount {
                bestCount = count
                bestStart = candidate
            }
        }
        let share = Double(bestCount) / Double(cigarettes)
        guard share >= options.smokeConcentration else { return nil }
        let range = String(format: "%02d:00–%02d:00", bestStart, (bestStart + window) % 24)
        return HealthPattern(
            id: "smoking-window",
            title: "抽烟集中在固定时段",
            detail: "\(cigarettes) 根里有 \(bestCount) 根落在 \(range)。这个时段可以换成一个固定的小动作，比如喝水、出门走一圈，打断习惯链条。",
            evidence: "\(cigarettes) 根烟中 \(bestCount) 根（\(Int((share * 100).rounded()))%）在 \(range)",
            severity: .notice,
            symbol: "clock.badge.exclamationmark")
    }

    private static func detectRecordGap(document: DiaryDocument, start: Date, end: Date,
                                        options: PatternOptions, calendar: Calendar) -> HealthPattern? {
        let days = Set(document.records
            .map { calendar.startOfDay(for: $0.date) }
            .filter { $0 >= start && $0 <= end })
        guard let first = days.min(), let last = days.max(), first < last else { return nil }
        var longest = 0
        var longestStart: Date?
        var cursor = calendar.date(byAdding: .day, value: 1, to: first)!
        while cursor < last {
            if days.contains(cursor) {
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
                continue
            }
            var run = 0
            let runStart = cursor
            while cursor < last, !days.contains(cursor) {
                run += 1
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }
            if run > longest {
                longest = run
                longestStart = runStart
            }
        }
        guard longest >= options.gapDays, let gapStart = longestStart else { return nil }
        let gapEnd = calendar.date(byAdding: .day, value: longest - 1, to: gapStart)!
        return HealthPattern(
            id: "record-gap",
            title: "记录断档了 \(longest) 天",
            detail: "断档本身不是问题，但连续记录更容易看出趋势。可以只补一餐最容易记的，比如早餐或晚餐。",
            evidence: "\(dateText(gapStart, calendar))–\(dateText(gapEnd, calendar)) 没有饮食记录",
            severity: .notice,
            symbol: "calendar.badge.exclamationmark")
    }

    private static func detectWeightStall(document: DiaryDocument, start: Date, end: Date,
                                          options: PatternOptions, calendar: Calendar) -> HealthPattern? {
        let weights = document.weights
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        guard let first = weights.first, let last = weights.last else { return nil }
        let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: first.date),
                                           to: calendar.startOfDay(for: last.date)).day ?? 0
        guard span >= options.weightStallDays else { return nil }
        let change = last.kilograms - first.kilograms
        guard abs(change) < options.weightStallKG else { return nil }
        return HealthPattern(
            id: "weight-stall",
            title: "体重暂时没有明显变化",
            detail: "\(span) 天里体重变化不到 \(String(format: "%.1f", options.weightStallKG)) 公斤。短期波动很常见，先确认记录是否连续，再考虑调整热量或活动量。",
            evidence: "\(dateText(first.date, calendar)) \(String(format: "%.1f", first.kilograms)) 公斤 → \(dateText(last.date, calendar)) \(String(format: "%.1f", last.kilograms)) 公斤",
            severity: .notice,
            symbol: "scalemass")
    }

    private static func detectCalorieOvershoot(facts: ObservationFacts, options: PatternOptions) -> HealthPattern? {
        guard let target = facts.targetCalories, target > 0,
              facts.recordedDays >= options.minimumRecordedDays,
              let average = facts.averageCalories,
              average > target * options.calorieOvershoot else { return nil }
        return HealthPattern(
            id: "calorie-over",
            title: "日均热量高于目标",
            detail: "记录日的日均比目标高约 \(Int((average - target).rounded())) 千卡。可以先调整一到两餐的份量，不必一次改很多。",
            evidence: "记录日日均 \(Int(average.rounded())) 千卡，目标 \(Int(target.rounded())) 千卡",
            severity: .attention,
            symbol: "flame")
    }

    private static func dateText(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}
