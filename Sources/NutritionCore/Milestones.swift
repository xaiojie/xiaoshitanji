import Foundation

/// 记录成果：连续天数、累计餐数、戒烟天数与里程碑。
public struct DiaryStats: Sendable, Equatable {
    public var totalMeals: Int
    public var recordedDays: Int
    public var currentStreak: Int
    public var longestStreak: Int
    public var firstRecordDate: Date?
    public var weightRecords: Int
    public var templateCount: Int
    public var smokeFreeDays: Int?

    public init(totalMeals: Int = 0, recordedDays: Int = 0, currentStreak: Int = 0,
                longestStreak: Int = 0, firstRecordDate: Date? = nil, weightRecords: Int = 0,
                templateCount: Int = 0, smokeFreeDays: Int? = nil) {
        self.totalMeals = totalMeals
        self.recordedDays = recordedDays
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.firstRecordDate = firstRecordDate
        self.weightRecords = weightRecords
        self.templateCount = templateCount
        self.smokeFreeDays = smokeFreeDays
    }
}

public struct Achievement: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let achievedAt: Date?

    public var isAchieved: Bool { achievedAt != nil }

    public init(id: String, title: String, detail: String, symbol: String, achievedAt: Date?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.achievedAt = achievedAt
    }
}

public enum Milestones {
    /// 连续记录：今天或昨天有记录才算「还在连」，断一天就归零。
    public static func stats(for document: DiaryDocument, now: Date = .now,
                             calendar: Calendar = .current) -> DiaryStats {
        let days = Set(document.records.map { calendar.startOfDay(for: $0.date) }).sorted()
        let meals = document.records.reduce(0) { $0 + $1.foods.count }

        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        var streak = 0
        if let last = days.last {
            let today = calendar.startOfDay(for: now)
            let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0
            if gap <= 1 {
                streak = run
            }
        }

        return DiaryStats(totalMeals: meals,
                          recordedDays: days.count,
                          currentStreak: streak,
                          longestStreak: longest,
                          firstRecordDate: days.first,
                          weightRecords: document.weights.count,
                          templateCount: document.templates.count,
                          smokeFreeDays: smokeFreeDays(document: document, now: now, calendar: calendar))
    }

    /// 抽过烟才算戒烟；从最后一根到现在满几天。
    public static func smokeFreeDays(document: DiaryDocument, now: Date = .now,
                                     calendar: Calendar = .current) -> Int? {
        let smoked = document.smoking.events.filter { $0.kind == .smoked }
        guard let last = smoked.map(\.date).max() else { return nil }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                              to: calendar.startOfDay(for: now)).day ?? 0)
    }

    public static func achievements(for document: DiaryDocument, now: Date = .now,
                                    calendar: Calendar = .current) -> [Achievement] {
        let days = Set(document.records.map { calendar.startOfDay(for: $0.date) }).sorted()

        func firstDay(reaching count: Int) -> Date? {
            var best: Date?
            var run = 0
            var previous: Date?
            for day in days {
                if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
                   calendar.isDate(next, inSameDayAs: day) {
                    run += 1
                } else {
                    run = 1
                }
                if run >= count, best == nil { best = day }
                previous = day
            }
            return best
        }

        func dayOfNthMeal(_ count: Int) -> Date? {
            var total = 0
            for record in document.records.sorted(by: { $0.date < $1.date }) {
                total += record.foods.count
                if total >= count { return record.date }
            }
            return nil
        }

        var items: [Achievement] = [
            Achievement(id: "first-meal", title: "第一餐", detail: "开始记录，就已经比凭感觉吃强。",
                        symbol: "fork.knife", achievedAt: document.records.min { $0.date < $1.date }?.date),
            Achievement(id: "streak-3", title: "连记 3 天", detail: "连续三天有记录。",
                        symbol: "flame", achievedAt: firstDay(reaching: 3)),
            Achievement(id: "streak-7", title: "连记一周", detail: "七天不断档，习惯在成形。",
                        symbol: "flame.fill", achievedAt: firstDay(reaching: 7)),
            Achievement(id: "streak-30", title: "连记一月", detail: "三十天，足够看出趋势了。",
                        symbol: "crown.fill", achievedAt: firstDay(reaching: 30)),
            Achievement(id: "meals-30", title: "30 餐", detail: "累计记录三十餐。",
                        symbol: "list.bullet", achievedAt: dayOfNthMeal(30)),
            Achievement(id: "meals-100", title: "100 餐", detail: "累计记录一百餐。",
                        symbol: "list.bullet.rectangle", achievedAt: dayOfNthMeal(100)),
            Achievement(id: "meals-365", title: "365 餐", detail: "一整年的饭都在册。",
                        symbol: "trophy.fill", achievedAt: dayOfNthMeal(365)),
            Achievement(id: "weights-10", title: "体重十次", detail: "十次称重，趋势才可信。",
                        symbol: "scalemass", achievedAt: weightDayNth(document, count: 10)),
            Achievement(id: "template", title: "第一个常吃", detail: "把常吃的存成组合，下次一键记录。",
                        symbol: "square.stack", achievedAt: document.templates.map(\.createdAt).min()),
            Achievement(id: "smoke-free-7", title: "七天没点烟", detail: "从最后一根算起满七天。",
                        symbol: "lungs", achievedAt: smokeFreeDay(document, days: 7, now: now, calendar: calendar)),
            Achievement(id: "smoke-free-30", title: "三十天没点烟", detail: "一个月，身体会记得。",
                        symbol: "lungs.fill", achievedAt: smokeFreeDay(document, days: 30, now: now, calendar: calendar))
        ]
        items.sort {
            switch ($0.achievedAt, $1.achievedAt) {
            case let (left?, right?): return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.id < $1.id
            }
        }
        return items
    }

    static func weightDayNth(_ document: DiaryDocument, count: Int) -> Date? {
        let sorted = document.weights.map(\.date).sorted()
        return sorted.count >= count ? sorted[count - 1] : nil
    }

    static func smokeFreeDay(_ document: DiaryDocument, days: Int, now: Date,
                             calendar: Calendar) -> Date? {
        guard let free = smokeFreeDays(document: document, now: now, calendar: calendar),
              free >= days, let last = document.smoking.events.filter({ $0.kind == .smoked }).map(\.date).max() else {
            return nil
        }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: last))
    }
}
