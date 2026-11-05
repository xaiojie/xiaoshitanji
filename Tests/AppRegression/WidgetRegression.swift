import Foundation
import NutritionCore

@main struct WidgetRegression {
    @MainActor static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        let now = date("2026-11-05T07:36:00Z")
        let legacy: [String: Any] = [
            "calories": 566, "targetCalories": 1800, "protein": 34,
            "carbohydrate": 58, "fat": 22, "mealCount": 2,
            "updatedAt": now.timeIntervalSinceReferenceDate
        ]
        let old = try JSONDecoder().decode(DiaryWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.meals == nil && old.calories == 566 && old.mealCount == 2)
        precondition(old.isCurrent(on: now, calendar: calendar))
        print("PASS — legacy widget JSON retains totals and unknown meal breakdown")

        let breakfast = MealRecord(date: date("2026-11-05T00:45:00Z"), kind: .breakfast,
                                   foods: [FoodItem(name: "早餐", per100g: Nutrition(calories: 208, protein: 13, carbohydrates: 10, fat: 12))])
        let lunch = MealRecord(date: date("2026-11-05T04:00:00Z"), kind: .lunch,
                               foods: [FoodItem(name: "午餐", per100g: Nutrition(calories: 358, protein: 21, carbohydrates: 48, fat: 10))])
        let moreLunch = MealRecord(date: date("2026-11-05T04:10:00Z"), kind: .lunch,
                                   foods: [FoodItem(name: "无糖茶", per100g: .zero)])
        let yesterday = MealRecord(date: date("2026-11-04T12:00:00Z"), kind: .dinner,
                                   foods: [FoodItem(name: "昨天的饭", per100g: Nutrition(calories: 999))])
        let document = DiaryDocument(records: [breakfast, lunch, moreLunch, yesterday])
        let snapshot = WidgetSnapshotBuilder.make(document: document, targetCalories: 1800, on: now, calendar: calendar)
        precondition(snapshot.calories == 566 && snapshot.protein == 34 && snapshot.carbohydrate == 58 && snapshot.fat == 22)
        precondition(snapshot.mealCount == 3 && snapshot.updatedAt == now)
        precondition(snapshot.meals?.map(\.kind) == [.breakfast, .lunch, .dinner, .snack])
        precondition(snapshot.meals?[0].calories == 208 && snapshot.meals?[1].calories == 358)
        precondition(snapshot.meals?[1].recordCount == 2 && snapshot.meals?[2].recordCount == 0)
        precondition(WidgetMealKind.islandKinds == [.breakfast, .lunch, .dinner])
        precondition(!WidgetMealKind.islandKinds.contains(.snack))
        precondition(snapshot.remaining == 1234 && abs(snapshot.progress! - 566.0 / 1800) < 0.00001)
        let reopened = try JSONDecoder().decode(DiaryWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(reopened == snapshot)
        print("PASS — actual diary aggregates today's macros and all four meal kinds, preserving recorded zero-calorie meals")

        var invalidGoal = snapshot
        invalidGoal.targetCalories = nil
        precondition(invalidGoal.remaining == nil && invalidGoal.progress == nil)
        invalidGoal.targetCalories = 0
        precondition(invalidGoal.remaining == nil && invalidGoal.progress == nil)
        invalidGoal.targetCalories = .infinity
        precondition(invalidGoal.remaining == nil && invalidGoal.progress == nil)
        invalidGoal.targetCalories = 100
        precondition(invalidGoal.remaining == -466 && invalidGoal.progress == 1)
        let empty = WidgetSnapshotBuilder.make(document: DiaryDocument(), targetCalories: nil, on: now, calendar: calendar)
        precondition(empty.calories == 0 && empty.mealCount == 0 && empty.remaining == nil)
        precondition(empty.meals?.allSatisfy { $0.recordCount == 0 } == true)
        print("PASS — no target stays unknown, exceeded progress is bounded, empty diary remains usable")

        let midnight = date("2026-11-05T16:00:00Z")
        precondition(DiaryWidgetTimeline.nextMidnight(after: now, calendar: calendar) == midnight)
        precondition(snapshot.isCurrent(on: midnight.addingTimeInterval(-1), calendar: calendar))
        precondition(!snapshot.isCurrent(on: midnight, calendar: calendar))
        precondition(DiaryWidgetTimeline.nextRefresh(after: midnight.addingTimeInterval(-20), calendar: calendar) == midnight)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        precondition(DiaryWidgetTimeline.nextMidnight(after: date("2026-03-08T05:00:00Z"), calendar: newYork) == date("2026-03-09T04:00:00Z"))
        var changedZone = calendar
        changedZone.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        precondition(!snapshot.isCurrent(on: now, calendar: changedZone))
        print("PASS — midnight refresh and stale-data filtering respect local dates and daylight saving")

        let navigation = WidgetNavigation()
        precondition(navigation.receive(DiaryWidgetRoute.newMeal.url))
        precondition(navigation.pendingRoute == .newMeal)
        precondition(navigation.takeRequest(canPresent: false) == nil && navigation.pendingRoute == .newMeal)
        precondition(navigation.receive(DiaryWidgetRoute.newMeal.url))
        precondition(navigation.takeRequest(canPresent: true)?.route == .newMeal)
        precondition(navigation.takeRequest(canPresent: true) == nil)
        navigation.mealPresentationEnded()
        precondition(navigation.receive(DiaryWidgetRoute.today.url))
        precondition(!navigation.receive(URL(string: "https://example.com/meal/new")!))
        precondition(navigation.pendingRoute == .today)
        precondition(navigation.takeRequest(canPresent: true)?.route == .today)
        for text in ["xiaoshitanji://meal/unknown", "xiaoshitanji://meal/new?overwrite=true", "xiaoshitanji://unexpected", "xiaoshitanji://today/old"] {
            precondition(!navigation.receive(URL(string: text)!))
        }
        print("PASS — meal deep links wait behind existing drafts, coalesce repeated taps and consume once; unrelated URLs are ignored")

        let repeated = WidgetNavigation()
        precondition(repeated.receive(DiaryWidgetRoute.newMeal.url, at: now))
        precondition(repeated.takeRequest(canPresent: true)?.route == .newMeal)
        precondition(repeated.receive(DiaryWidgetRoute.newMeal.url, at: now.addingTimeInterval(60)))
        precondition(repeated.pendingRequest == nil, "A repeated tap must reuse the already-open widget composer")
        repeated.mealPresentationEnded()
        precondition(repeated.takeRequest(canPresent: true) == nil, "Closing a widget composer must not create another empty draft")
        precondition(repeated.receive(DiaryWidgetRoute.newMeal.url, at: now.addingTimeInterval(120)))
        precondition(repeated.takeRequest(canPresent: true)?.route == .newMeal)
        repeated.mealPresentationEnded()
        print("PASS — taps while a widget composer is already open do not queue a second draft")

        let delayed = WidgetNavigation()
        let beforeLunch = date("2026-11-05T02:59:00Z")
        precondition(delayed.receive(DiaryWidgetRoute.newMeal.url, at: beforeLunch))
        precondition(delayed.takeRequest(canPresent: false) == nil)
        precondition(delayed.receive(DiaryWidgetRoute.newMeal.url, at: beforeLunch.addingTimeInterval(180)))
        let breakfastRequest = delayed.takeRequest(canPresent: true)!
        let requestedBreakfast = breakfastRequest.mealDraft(calendar: calendar)!
        precondition(breakfastRequest.receivedAt == beforeLunch)
        precondition(requestedBreakfast.kind == .breakfast && requestedBreakfast.date == date("2026-11-05T00:45:00Z"))
        delayed.mealPresentationEnded()
        let beforeMidnight = date("2026-11-04T15:59:00Z")
        precondition(delayed.receive(DiaryWidgetRoute.newMeal.url, at: beforeMidnight))
        precondition(delayed.takeRequest(canPresent: false) == nil)
        let requestedSnack = delayed.takeRequest(canPresent: true)!.mealDraft(calendar: calendar)!
        precondition(requestedSnack.kind == .snack && requestedSnack.date == beforeMidnight)
        print("PASS — queued requests preserve the original meal time and date across meal boundaries and midnight")

        let directory = FileManager.default.temporaryDirectory.appending(path: "widget-model-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults.standard
        let previousGoal = defaults.object(forKey: "dailyCalorieGoal")
        defer {
            if let previousGoal { defaults.set(previousGoal, forKey: "dailyCalorieGoal") }
            else { defaults.removeObject(forKey: "dailyCalorieGoal") }
        }
        defaults.set(1800.0, forKey: "dailyCalorieGoal")
        let model = DiaryModel(fileURL: directory.appending(path: "diary.json"))
        model.refreshWidgetSnapshot(healthWorkoutCalories: nil)
        precondition(WidgetSnapshotWriter.latest?.targetCalories == 1800)
        defaults.set(2100.0, forKey: "dailyCalorieGoal")
        model.refreshWidgetSnapshot(healthWorkoutCalories: nil)
        precondition(WidgetSnapshotWriter.latest?.targetCalories == 2100)
        defaults.set(0.0, forKey: "dailyCalorieGoal")
        model.refreshWidgetSnapshot(healthWorkoutCalories: nil)
        precondition(WidgetSnapshotWriter.latest?.targetCalories == nil)
        print("PASS — actual DiaryModel publishes reference-goal changes and clearing without inventing a default")

        let modelDate = Date.now
        let settings = EnergySettings(sex: .male, birthYear: 1990, activity: .light, goalMode: .maintain)
        let workout = WorkoutRecord(date: modelDate, kind: .cardio, title: "手动训练", durationMinutes: 30,
                                    caloriesBurned: 200, cardio: CardioDetail(activity: .walk))
        let trainingDocument = DiaryDocument(profile: HealthProfile(heightCM: 170),
            weights: [WeightRecord(date: modelDate, kilograms: 70)], workouts: [workout], energy: settings)
        try model.replaceDocument(trainingDocument)
        let budget = model.energyBudget(on: modelDate)!
        model.refreshWidgetSnapshot(healthWorkoutCalories: 400, on: modelDate)
        precondition(WidgetSnapshotWriter.latest?.targetCalories == budget.targetCalories + 400)
        let meal = MealRecord(date: modelDate, kind: .lunch,
                             foods: [FoodItem(name: "测试餐", per100g: Nutrition(calories: 100))])
        try model.save(meal)
        precondition(WidgetSnapshotWriter.latest?.targetCalories == budget.targetCalories + 400)
        precondition(WidgetSnapshotWriter.latest?.calories == 100)
        model.refreshWidgetSnapshot(healthWorkoutCalories: 400, on: modelDate.addingTimeInterval(-86_400))
        try model.save(meal)
        precondition(WidgetSnapshotWriter.latest?.targetCalories == budget.targetCalories + 200)
        print("PASS — actual save retains today's Health workout priority, excludes double counting and expires yesterday's burn")
    }
}

// Replace only platform output boundaries; DiaryModel and the snapshot builder are production code.
@MainActor enum WidgetSnapshotWriter {
    static var latest: DiaryWidgetSnapshot?
    static func write(document: DiaryDocument, targetCalories: Double?, on date: Date) {
        latest = WidgetSnapshotBuilder.make(document: document, targetCalories: targetCalories, on: date)
    }
}

@MainActor final class IntakeActivityManager {
    static let shared = IntakeActivityManager()
    let isRunning = false
    static func state(for document: DiaryDocument, targetCalories: Double?, on date: Date) -> Int { 0 }
    func update(state: Int) {}
}
