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

    @Test func namedMealsUseMidpointsOfPreferredWindows() {
        let day = date("2026-11-04T00:00:00Z")
        let currentTime = date("2026-11-04T09:32:47Z")
        let breakfast = MealRecord.draft(on: day, kind: .breakfast, now: currentTime, calendar: calendar)
        let lunch = MealRecord.draft(on: day, kind: .lunch, now: currentTime, calendar: calendar)
        let dinner = MealRecord.draft(on: day, kind: .dinner, now: currentTime, calendar: calendar)
        #expect(breakfast.date == date("2026-11-04T00:45:00Z"))
        #expect(lunch.date == date("2026-11-04T04:00:00Z"))
        #expect(dinner.date == date("2026-11-04T12:00:00Z"))
        #expect(breakfast.kind == .breakfast)
        #expect(lunch.kind == .lunch)
        #expect(dinner.kind == .dinner)
    }

    @Test func changingMealKindUsesItsPresetAndPreservesFoodAndDate() {
        let id = UUID()
        let food = FoodItem(name: "鸡蛋", grams: 50, per100g: Nutrition(calories: 144))
        var record = MealRecord(id: id, date: date("2026-11-03T01:10:00Z"), kind: .breakfast, foods: [food])
        record.usePresetTime(for: .dinner, now: date("2026-11-04T08:00:00Z"), calendar: calendar)
        #expect(record.id == id)
        #expect(record.foods == [food])
        #expect(record.kind == .dinner)
        #expect(record.date == date("2026-11-03T12:00:00Z"))
    }

    @Test func snacksUseCurrentClockTimeOnSelectedDay() {
        let selectedDay = date("2026-11-02T04:00:00Z")
        let currentTime = date("2026-11-04T08:15:23Z")
        let snack = MealRecord.draft(on: selectedDay, kind: .snack, now: currentTime, calendar: calendar)
        #expect(snack.date == date("2026-11-02T08:15:23Z"))
    }

    @Test func presetsFollowCalendarTimeZone() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let selectedDay = date("2026-11-04T16:00:00Z")
        let breakfast = MealRecord.draft(on: selectedDay, kind: .breakfast, calendar: calendar)
        #expect(breakfast.date == date("2026-11-04T13:45:00Z"))
    }

    @Test func decodingSavedRecordPreservesItsActualTime() throws {
        let original = MealRecord(date: date("2026-11-04T00:37:00Z"), kind: .breakfast,
                                  foods: [FoodItem(name: "鸡蛋", grams: 50)])
        let reopened = try JSONDecoder().decode(MealRecord.self, from: JSONEncoder().encode(original))
        #expect(reopened.date == original.date)
    }
}
