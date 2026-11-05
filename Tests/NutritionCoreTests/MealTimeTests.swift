import Foundation
import Testing
@testable import NutritionCore

struct MealTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func namedMealsStartAtTheCurrentClockTime() {
        let day = date("2026-11-03T16:00:00Z")          // 11-04 00:00 +08
        let currentTime = date("2026-11-04T10:20:35Z")  // 11-04 18:20 +08
        let breakfast = MealRecord.draft(on: day, kind: .breakfast, now: currentTime, calendar: calendar)
        let lunch = MealRecord.draft(on: day, kind: .lunch, now: currentTime, calendar: calendar)
        let dinner = MealRecord.draft(on: day, kind: .dinner, now: currentTime, calendar: calendar)
        for record in [breakfast, lunch, dinner] {
            #expect(record.date == currentTime)
        }
        #expect(breakfast.kind == .breakfast)
        #expect(lunch.kind == .lunch)
        #expect(dinner.kind == .dinner)
    }

    @Test func dinnerNoLongerJumpsToTheEvening() {
        // 回归：以前 18:20 点晚餐会写成 20:00。
        let day = date("2026-11-03T16:00:00Z")
        let dinner = MealRecord.draft(on: day, kind: .dinner, now: date("2026-11-04T10:20:00Z"), calendar: calendar)
        #expect(dinner.date == date("2026-11-04T10:20:00Z"))
    }

    @Test func changingMealKindKeepsTimeAndFoods() {
        let id = UUID()
        let food = FoodItem(name: "鸡蛋", grams: 50, per100g: Nutrition(calories: 144))
        var record = MealRecord(id: id, date: date("2026-11-03T01:10:00Z"), kind: .breakfast, foods: [food])
        record.applyKind(.dinner)
        #expect(record.id == id)
        #expect(record.foods == [food])
        #expect(record.kind == .dinner)
        #expect(record.date == date("2026-11-03T01:10:00Z"))
    }

    @Test func pastDaysKeepTheCurrentClockTime() {
        let selectedDay = date("2026-11-02T00:00:00Z")
        let currentTime = date("2026-11-04T08:15:23Z")
        let snack = MealRecord.draft(on: selectedDay, kind: .snack, now: currentTime, calendar: calendar)
        #expect(snack.date == date("2026-11-02T08:15:23Z"))
    }

    @Test func clockTimeFollowsCalendarTimeZone() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let selectedDay = date("2026-11-04T05:00:00Z")   // 11-04 00:00 -05
        let now = date("2026-11-04T13:45:00Z")           // 11-04 08:45 -05
        let breakfast = MealRecord.draft(on: selectedDay, kind: .breakfast, now: now, calendar: calendar)
        #expect(breakfast.date == now)
    }

    @Test func suggestedKindFollowsTheCurrentWindow() {
        func kind(at hour: Int) -> MealKind {
            let time = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: 0))!
            return MealKind.suggested(for: time, calendar: calendar)
        }
        #expect(kind(at: 4) == .snack)
        #expect(kind(at: 5) == .breakfast)
        #expect(kind(at: 10) == .breakfast)
        #expect(kind(at: 11) == .lunch)
        #expect(kind(at: 14) == .lunch)
        #expect(kind(at: 15) == .snack)
        #expect(kind(at: 16) == .snack)
        #expect(kind(at: 17) == .dinner)
        #expect(kind(at: 21) == .dinner)
        #expect(kind(at: 22) == .snack)
    }

    @Test func decodingSavedRecordPreservesItsActualTime() throws {
        let original = MealRecord(date: date("2026-11-04T00:37:00Z"), kind: .breakfast,
                                  foods: [FoodItem(name: "鸡蛋", grams: 50)])
        let reopened = try JSONDecoder().decode(MealRecord.self, from: JSONEncoder().encode(original))
        #expect(reopened.date == original.date)
    }
}
