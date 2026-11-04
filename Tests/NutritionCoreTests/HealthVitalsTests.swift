import Foundation
import Testing
@testable import NutritionCore

struct HealthVitalsTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ day: Int, hour: Int = 12, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func meal(_ date: Date, calories: Double = 100) -> MealRecord {
        MealRecord(date: date, foods: [FoodItem(name: "米饭", grams: 100, per100g: Nutrition(calories: calories))])
    }

    @Test func activityCarriesSleepHeartRateAndWorkoutMetrics() throws {
        let day = HealthActivityDay(date: date(3), steps: 8000, sleepHours: 7.5, averageHeartRate: 72,
            restingHeartRate: 58, heartRateVariabilityMS: 42, vo2Max: 44.5,
            headphoneAudioMinutes: 95, workoutSessions: 1, workoutMinutes: 48, workoutCalories: 320)
        let snapshot = try WellnessSummary.make(document: DiaryDocument(), period: .week, endDate: date(4),
            activityDays: [day], includesHealth: true, calendar: calendar)
        #expect(snapshot.activity.sleepHours.total == 7.5)
        #expect(snapshot.activity.restingHeartRate.average == 58)
        #expect(snapshot.activity.averageHeartRate.average == 72)
        #expect(snapshot.activity.heartRateVariability.average == 42)
        #expect(snapshot.activity.vo2Max.average == 44.5)
        #expect(snapshot.activity.headphoneAudioMinutes.average == 95)
        #expect(snapshot.activity.workoutSessions.total == 1)
        #expect(snapshot.activity.workoutMinutes.total == 48)
        #expect(snapshot.activity.workoutCalories.total == 320)
    }

    @Test func sleepOnlyDayStillCountsAsHealthData() throws {
        let day = HealthActivityDay(date: date(3), sleepHours: 6.25)
        let activity = WellnessActivity(days: [day])
        #expect(activity.hasData)
        #expect(activity.steps.observedDays == 0)
    }

    @Test func observationFactsIncludeVitalsAndWorkoutTotals() throws {
        let document = DiaryDocument(records: [meal(date(3))])
        let day = HealthActivityDay(date: date(3), steps: 9000, sleepHours: 8, averageHeartRate: 70,
            restingHeartRate: 55, heartRateVariabilityMS: 40, vo2Max: 46,
            headphoneAudioMinutes: 60, workoutSessions: 2, workoutMinutes: 75, workoutCalories: 500)
        let context = try ObservationFacts.make(document: document, period: .week, endDate: date(4),
            activityDays: [day], includesHealth: true, calendar: calendar)
        let facts = context.facts
        #expect(facts.averageSleepHours == 8)
        #expect(facts.restingHeartRateBPM == 55)
        #expect(facts.averageHeartRateBPM == 70)
        #expect(facts.heartRateVariabilityMS == 40)
        #expect(facts.latestVO2Max == 46)
        #expect(facts.averageHeadphoneAudioMinutes == 60)
        #expect(facts.healthWorkoutSessions == 2)
        #expect(facts.healthWorkoutMinutes == 75)
        #expect(facts.healthWorkoutCalories == 500)
        #expect(!facts.gaps.contains("没有睡眠数据"))
        #expect(!facts.gaps.contains("区间内没有体能训练记录"))
        let json = try context.promptJSON()
        #expect(json.contains("averageSleepHours"))
        #expect(json.contains("healthWorkoutMinutes"))
        #expect(context.evidence.contains("睡眠"))
    }

    @Test func missingVitalsAreListedAsGaps() throws {
        let document = DiaryDocument(records: [meal(date(3))])
        let context = try ObservationFacts.make(document: document, period: .week, endDate: date(4),
            activityDays: [HealthActivityDay(date: date(3), steps: 1000)], includesHealth: true, calendar: calendar)
        let gaps = context.facts.gaps
        #expect(gaps.contains("没有睡眠数据"))
        #expect(gaps.contains("没有心率数据"))
        #expect(gaps.contains("没有有氧适能（最大摄氧量）数据"))
        #expect(gaps.contains("区间内没有体能训练记录"))
    }

    @Test func healthWorkoutsAggregateByDayAndValidate() throws {
        let workouts = [
            HealthWorkout(date: date(3, hour: 8), kind: .cardio, title: "跑步", durationMinutes: 30,
                          activeCalories: 280, averageHeartRate: 148, distanceMeters: 5000),
            HealthWorkout(date: date(3, hour: 19), kind: .strength, title: "力量训练", durationMinutes: 45,
                          activeCalories: 200),
            HealthWorkout(date: date(2, hour: 19), kind: .cardio, title: "骑行", durationMinutes: 60,
                          activeCalories: 400, distanceMeters: 20_000)
        ]
        try workouts.forEach { try $0.validate() }
        let totals = HealthWorkoutSummary.dailyTotals(workouts, calendar: calendar)
        let day = totals[calendar.startOfDay(for: date(3))]
        #expect(day?.sessions == 2)
        #expect(day?.minutes == 75)
        #expect(day?.calories == 480)
        let stats = HealthWorkoutSummary.stats(workouts)
        #expect(stats.sessions == 3)
        #expect(stats.minutes == 135)
        #expect(stats.lastDate == date(3, hour: 19))
    }

    @Test func invalidHealthWorkoutIsRejected() {
        #expect(throws: DiaryError.self) {
            try HealthWorkout(durationMinutes: 0).validate()
        }
        #expect(throws: DiaryError.self) {
            try HealthWorkout(durationMinutes: 30, averageHeartRate: 300).validate()
        }
    }

    @Test func workoutSummaryLineShowsDurationCaloriesAndDistance() {
        let workout = HealthWorkout(durationMinutes: 30, activeCalories: 280, distanceMeters: 5000)
        #expect(workout.summaryLine == "30 分钟 · 280 千卡 · 5.0 km")
        let strength = HealthWorkout(kind: .strength, durationMinutes: 45)
        #expect(strength.summaryLine == "45 分钟")
    }

    @Test func healthWorkoutTotalsOnlyCountTheRequestedDay() {
        let workouts = [
            HealthWorkout(date: date(3, hour: 8), durationMinutes: 30, activeCalories: 280),
            HealthWorkout(date: date(3, hour: 19), kind: .strength, durationMinutes: 45, activeCalories: 200),
            HealthWorkout(date: date(2, hour: 19), durationMinutes: 60, activeCalories: 400)
        ]
        let today = HealthWorkoutSummary.totals(workouts, on: date(3), calendar: calendar)
        #expect(today.sessions == 2)
        #expect(today.minutes == 75)
        #expect(today.calories == 480)
        #expect(today.hasWorkout)
        let empty = HealthWorkoutSummary.totals(workouts, on: date(4), calendar: calendar)
        #expect(!empty.hasWorkout)
        #expect(empty.calories == 0)
    }

    @Test func activityBurnPrefersHealthAndFallsBackToManual() {
        #expect(ActivityBurn.resolve(manual: 500, health: 320) == 320)
        #expect(ActivityBurn.resolve(manual: 500, health: 0) == 500)
        #expect(ActivityBurn.resolve(manual: -10, health: 0) == 0)
        #expect(ActivityBurn.resolve(manual: 0, health: 0) == 0)
    }
}
