import Foundation
import Testing
@testable import NutritionCore

struct WellnessCompatibilityTests {
    private let addedFields = [
        "sleepHours", "averageHeartRate", "restingHeartRate", "heartRateVariability", "vo2Max",
        "headphoneAudioMinutes", "workoutSessions", "workoutMinutes", "workoutCalories"
    ]

    private func legacyDocument(isoDates: Bool = false) throws -> (DiaryDocument, Data) {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var document = DiaryDocument(records: [MealRecord(date: date, foods: [
            .manual(name: "测试餐", nutrition: Nutrition(calories: 200))
        ])])
        try document.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试烟"), openedAt: date))
        try document.smoking.record(.smoked, count: 1, date: date)
        let summary = try WellnessSummary.make(document: document, period: .week, endDate: date,
            activityDays: [HealthActivityDay(date: date, steps: 1200)], includesHealth: true)
        let report = WellnessReview(id: UUID(), snapshot: summary, summary: "旧版汇总报告",
            observations: WellnessArea.allCases.map { WellnessObservation(area: $0, text: "保留旧分析") },
            actions: [WellnessAction(title: "继续记录", detail: "按实际情况记录")], limitations: [],
            model: "fixture", generatedAt: date)
        try document.saveWellnessReview(report)
        let encoder = JSONEncoder()
        if isoDates { encoder.dateEncodingStrategy = .iso8601 }
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(document)) as? [String: Any])
        var reports = try #require(object["wellnessReviews"] as? [[String: Any]])
        var snapshot = try #require(reports[0]["snapshot"] as? [String: Any])
        func legacyActivity(_ object: Any?) throws -> [String: Any] {
            var activity = try #require(object as? [String: Any])
            for field in addedFields { activity.removeValue(forKey: field) }
            return activity
        }
        snapshot["activity"] = try legacyActivity(snapshot["activity"])
        var timeline = try #require(snapshot["timeline"] as? [[String: Any]])
        for index in timeline.indices { timeline[index]["activity"] = try legacyActivity(timeline[index]["activity"]) }
        snapshot["timeline"] = timeline
        reports[0]["snapshot"] = snapshot
        object["wellnessReviews"] = reports
        return (document, try JSONSerialization.data(withJSONObject: object))
    }

    @Test func legacyReportKeepsTheWholeDiaryReadableAndRoundTrips() throws {
        let (expected, data) = try legacyDocument()
        let directory = FileManager.default.temporaryDirectory.appending(path: "legacy-wellness-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "diary.json")
        try data.write(to: url)
        let store = DiaryStore(fileURL: url)
        let restored = try store.load()
        #expect(restored.records == expected.records)
        #expect(restored.smoking == expected.smoking)
        #expect(restored.wellnessReviews == expected.wellnessReviews)
        #expect(restored.wellnessReviews[0].snapshot.activity.sleepHours.total == nil)
        #expect(restored.wellnessReviews[0].snapshot.activity.sleepHours.observedDays == 0)
        try store.save(restored)
        #expect(try store.load().wellnessReviews == expected.wellnessReviews)
        #expect(try DiaryBackup.restore(from: url).records == expected.records)
    }

    @Test func legacyReportIsCompatibleWithPortableBackupsAndCloudSnapshots() throws {
        let (expected, data) = try legacyDocument(isoDates: true)
        let url = FileManager.default.temporaryDirectory.appending(path: "legacy-backup-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        #expect(try DiaryBackup.restore(from: url).wellnessReviews == expected.wellnessReviews)
        let payload = try JSONSerialization.jsonObject(with: data)
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 1, "checksum": "fixture", "payload": payload])
        let snapshot = try CloudSyncClient.parseSnapshot(data: envelope, statusCode: 200)
        #expect(snapshot.document.records == expected.records)
        #expect(snapshot.document.smoking == expected.smoking)
        #expect(snapshot.document.wellnessReviews == expected.wellnessReviews)
    }

    @Test func malformedPresentMetricsAndMissingOriginalMetricsStillFailDecoding() throws {
        let activity = WellnessActivity(days: [HealthActivityDay(date: .now, steps: 0, sleepHours: 7)])
        #expect(try JSONDecoder().decode(WellnessActivity.self, from: JSONEncoder().encode(activity)) == activity)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any])
        object["sleepHours"] = "invalid"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WellnessActivity.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object.removeValue(forKey: "sleepHours")
        object.removeValue(forKey: "steps")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WellnessActivity.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}
