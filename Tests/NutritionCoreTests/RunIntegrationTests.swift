import Foundation
import Testing
@testable import NutritionCore

struct RunIntegrationTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func uniqueSameRunMergesAndSeparateRunRemains() {
        let local = WorkoutRecord(date: date, kind: .cardio, title: "户外跑步", durationMinutes: 30,
                                  cardio: CardioDetail(activity: .run, distanceMeters: 5000))
        let health = HealthWorkout(date: date.addingTimeInterval(10), title: "跑步", durationMinutes: 30,
                                   activeCalories: 300, distanceMeters: 5020)
        let separate = HealthWorkout(date: date.addingTimeInterval(7200), title: "跑步", durationMinutes: 20,
                                     distanceMeters: 3000)
        let entries = WorkoutTimeline.make(local: [local], health: [health, separate])
        #expect(entries.count == 2)
        #expect(entries.first { $0.local?.id == local.id }?.health?.id == health.id)
        #expect(entries.first { $0.local?.id == local.id }?.calories == 300)
    }

    @Test func ambiguousMatchesRequireExplicitLink() {
        let local = WorkoutRecord(date: date, kind: .cardio, durationMinutes: 30,
                                  cardio: CardioDetail(activity: .run, distanceMeters: 5000))
        let one = HealthWorkout(date: date, title: "跑步", durationMinutes: 30, distanceMeters: 5000)
        let two = HealthWorkout(date: date, title: "跑步", durationMinutes: 30, distanceMeters: 5000)
        #expect(WorkoutTimeline.make(local: [local], health: [one, two]).count == 3)
        let linked = WorkoutTimeline.make(local: [local], health: [one, two], links: [local.id: one.id])
        #expect(linked.first { $0.local != nil }?.health?.id == one.id)
    }

    @Test func runRequestUsesStatisticsAndExplicitHeartRateChoice() throws {
        var session = RunSession(startedAt: date)
        session.ingest(RunLocation(latitude: 22.123456, longitude: 113.654321,
                                   timestamp: date, horizontalAccuracy: 5), receivedAt: date)
        session.finish(at: date.addingTimeInterval(60))
        let record = RunRecord(session: session, heartRates: [
            RunHeartRatePoint(date: date.addingTimeInterval(30), bpm: 155, source: "PRIVATE_DEVICE")
        ])
        var document = DiaryDocument(profile: HealthProfile(nickname: "PRIVATE_NAME"))
        document.weights = [WeightRecord(date: date.addingTimeInterval(3600), kilograms: 70)]
        let context = RunAnalysisContext(record: record, document: document, includesHeartRate: false,
                                         includesDietAndBody: true)
        let request = try DeepSeekClient.makeRunAnalysisRequest(context)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains("22.123456"))
        #expect(!body.contains("113.654321"))
        #expect(!body.contains("PRIVATE_DEVICE"))
        #expect(!body.contains("PRIVATE_NAME"))
        #expect(context.averageHeartRate == nil)
        #expect(context.weightKG == nil)
        let approved = RunAnalysisContext(record: record, document: document, includesHeartRate: true,
                                          includesDietAndBody: false)
        #expect(approved.averageHeartRate == 155)
        #expect(approved.maximumHeartRate == 155)
        #expect(approved.heartRateSampleCount == 1)
    }

    @Test func wellnessIncludesLocalRunsAndRespectsHeartScope() throws {
        let workout = WorkoutRecord(date: date.addingTimeInterval(-3600), kind: .cardio, durationMinutes: 30,
            caloriesBurned: 250, cardio: CardioDetail(activity: .run, distanceMeters: 5000, averageHeartRate: 150))
        let document = DiaryDocument(workouts: [workout])
        let local = try WellnessSummary.make(document: document, period: .week, endDate: date, includesHealth: false)
        #expect(local.hasData)
        #expect(local.training?.runningSessions == 1)
        #expect(local.training?.runningDistanceMeters == 5000)
        #expect(local.training?.averageSessionHeartRate == nil)
        let health = try WellnessSummary.make(document: document, period: .week, endDate: date, includesHealth: true)
        #expect(health.training?.averageSessionHeartRate == 150)
        let facts = ObservationFacts.make(summary: local, budget: nil)
        #expect(facts.facts.training?.sessions == 1)
        let data = try JSONEncoder().encode(local)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "training")
        let old = try JSONDecoder().decode(WellnessSummary.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.training == nil)
    }
}
