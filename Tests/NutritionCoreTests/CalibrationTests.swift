import Foundation
import Testing
@testable import NutritionCore

/// 校准维持热量的输入窗口：只统计窗口内有记录的那些天，且不含未来记录。
@Suite("热量校准窗口")
struct CalibrationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 20))!
    }

    private func meal(daysAgo: Int, calories: Double) -> MealRecord {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return MealRecord(date: day.addingTimeInterval(12 * 3600), kind: .lunch,
                          foods: [.manual(name: "饭", nutrition: Nutrition(calories: calories))])
    }

    @Test("只统计窗口内有记录的那些天，每天热量加总")
    func averagesOnlyRecordedDaysInWindow() {
        var document = DiaryDocument(records: [
            meal(daysAgo: 0, calories: 600), meal(daysAgo: 0, calories: 400),
            meal(daysAgo: 1, calories: 1000),
            meal(daysAgo: 5, calories: 2000),
        ])
        document.records[0].kind = .lunch

        let values = document.dailyCalories(withinDays: 2, now: now, calendar: calendar).sorted()
        #expect(values.count == 2)
        #expect(values == [1000, 1000])
    }

    @Test("排除未来记录与空白天")
    func excludesFutureAndEmptyDays() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        var document = DiaryDocument(records: [
            meal(daysAgo: 1, calories: 500),
            MealRecord(date: tomorrow, kind: .breakfast,
                       foods: [.manual(name: "早餐", nutrition: Nutrition(calories: 900))]),
        ])

        let values = document.dailyCalories(withinDays: 7, now: now, calendar: calendar)
        #expect(values == [500])
        // 空白天不算 0 卡，否则会把校准维持热量整体拉低。
        #expect(!values.contains(0))

        document.records.removeAll()
        #expect(document.dailyCalories(withinDays: 7, now: now, calendar: calendar).isEmpty)
    }
}
