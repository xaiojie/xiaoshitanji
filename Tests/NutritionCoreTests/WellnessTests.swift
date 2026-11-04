import Foundation
import Testing
@testable import NutritionCore

struct WellnessTests {
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

    private func summary(_ document: DiaryDocument = DiaryDocument(), period: WellnessPeriod = .week,
                         days: [HealthActivityDay] = [], weights: [WeightRecord] = [],
                         includesHealth: Bool = true) throws -> WellnessSummary {
        try WellnessSummary.make(document: document, period: period, endDate: date(4), activityDays: days,
            healthWeights: weights, includesHealth: includesHealth, calendar: calendar)
    }

    private var resultJSON: String {
        #"{"summary":"基于已记录的数据综合回顾。","observations":[{"area":"diet","text":"仅覆盖已记录餐食。"},{"area":"smoking","text":"分烟单独统计。"},{"area":"body","text":"根据已有测量观察。"},{"area":"activity","text":"以可读取活动数据为准。"}],"actions":[{"title":"连续记录","detail":"接下来一周继续记录日常饮食与活动。"}],"limitations":["部分日期没有记录。"]}"#
    }

    private func response(_ content: String, reason: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["model": "deepseek-flash", "choices": [
            ["finish_reason": reason, "message": ["content": content]]
        ]])
    }

    @Test func missingActivityIsDistinctFromAnObservedZero() throws {
        let snapshot = try summary(days: [HealthActivityDay(date: date(3), steps: 0)])
        #expect(snapshot.activity.steps.total == 0)
        #expect(snapshot.activity.steps.observedDays == 1)
        #expect(snapshot.activity.activeCalories.total == nil)
        #expect(snapshot.activity.activeCalories.observedDays == 0)
        #expect(snapshot.diet.total == nil)
        #expect(snapshot.diet.average == nil)
        #expect(!snapshot.timeline.isEmpty)
    }

    @Test func periodUsesLocalDaysAndRetainsTodaysPresetMealTimes() throws {
        let document = DiaryDocument(records: [meal(date(28, month: 10)), meal(date(29, month: 10)),
            meal(date(4, hour: 20)), meal(date(5))])
        let snapshot = try summary(document)
        #expect(snapshot.dayCount == 7)
        #expect(snapshot.startDate == calendar.startOfDay(for: date(29, month: 10)))
        #expect(snapshot.diet.recordCount == 2)
        #expect(snapshot.diet.recordedDays == 2)
        #expect(snapshot.diet.total?.calories == 200)
        #expect(snapshot.diet.average?.calories == 100)
    }

    @Test func allHistoryIncludesEarlierReadableHealthDatesAndUsesMonthlyTimeline() throws {
        let document = DiaryDocument(records: (1...30).map { meal(date($0, month: 10)) })
        let snapshot = try WellnessSummary.make(document: document, period: .all, endDate: date(4),
            activityDays: [HealthActivityDay(date: date(1, month: 9), steps: 500)],
            earliestHealthDate: date(1, month: 9), includesHealth: true, calendar: calendar)
        #expect(snapshot.startDate == calendar.startOfDay(for: date(1, month: 9)))
        #expect(snapshot.diet.recordCount == 30)
        #expect(snapshot.timelineUnit == "month")
        #expect(snapshot.timeline.count == 2)
    }

    @Test func summaryExcludesSharedAndCalibrationFromPersonalIntake() throws {
        var journal = SmokingDiary()
        try journal.openPack(CigarettePack(product: CigaretteProduct(name: "已知", nicotineMG: 0.6,
            pricePerPack: 30, currency: .cny), openedAt: date(1)))
        try journal.record(.smoked, count: 2, date: date(2))
        try journal.record(.shared, count: 3, date: date(2))
        try journal.record(.stockCheck, count: 10, date: date(3))
        try journal.openPack(CigarettePack(product: CigaretteProduct(name: "未知"), openedAt: date(3)))
        try journal.record(.smoked, count: 1, date: date(3))
        let snapshot = try summary(DiaryDocument(smoking: journal))
        #expect(snapshot.smoking.smoked == 3)
        #expect(snapshot.smoking.shared == 3)
        #expect(snapshot.smoking.knownNicotineMG == 1.2)
        #expect(snapshot.smoking.unknownNicotineCount == 1)
        #expect(snapshot.smoking.unpricedCount == 1)
        #expect(snapshot.smoking.costs.first?.amount == 3)
    }

    @Test func optingOutOfHealthExcludesItsMeasurementsAndActivity() throws {
        let snapshot = try summary(DiaryDocument(profile: HealthProfile(heightCM: 175)),
            days: [HealthActivityDay(date: date(3), steps: 1234)],
            weights: [WeightRecord(date: date(3), kilograms: 70, source: .appleHealth)], includesHealth: false)
        #expect(snapshot.body.heightCM == 175)
        #expect(snapshot.body.latestWeight == nil)
        #expect(snapshot.body.bmi == nil)
        #expect(snapshot.activity.steps.total == nil)
    }

    @Test func bodyChangeUsesRangeMeasurementsAndManualTiePreference() throws {
        let document = DiaryDocument(profile: HealthProfile(heightCM: 175, targetWeightKG: 68),
            weights: [WeightRecord(date: date(1, month: 10), kilograms: 80),
                WeightRecord(date: date(1), kilograms: 72), WeightRecord(date: date(4), kilograms: 70)])
        let snapshot = try summary(document, weights: [WeightRecord(date: date(4), kilograms: 71, source: .appleHealth)])
        #expect(snapshot.body.latestWeight?.kilograms == 70)
        #expect(snapshot.body.firstWeightInRange?.kilograms == 72)
        #expect(snapshot.body.weightChangeKG == -2)
        #expect(abs((snapshot.body.bmi ?? 0) - 22.857142857) < 0.0001)
        let oldOnly = try summary(DiaryDocument(weights: [WeightRecord(date: date(1, month: 10), kilograms: 80)]))
        #expect(oldOnly.body.latestWeight?.kilograms == 80)
        #expect(oldOnly.body.weightChangeKG == nil)
    }

    @Test func requestSendsAggregatesWithoutImagesOrIdentity() throws {
        var record = meal(date(4))
        record.photoJPEG = Data("PRIVATE_PHOTO".utf8)
        record.originalText = "PRIVATE_DESCRIPTION"
        let document = DiaryDocument(records: [record], profile: HealthProfile(nickname: "PRIVATE_NAME", avatarJPEG: Data([1, 2, 3])),
            weights: [WeightRecord(date: date(3), kilograms: 71), WeightRecord(date: date(4), kilograms: 70)])
        let snapshot = try summary(document)
        let request = try DeepSeekClient.makeWellnessRequest(summary: snapshot, apiKey: "test-key")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("PRIVATE_"))
        #expect(!text.contains("image_url"))
        #expect(!text.contains("avatarJPEG"))
        #expect(text.contains("recordedDays"))
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        let context = try #require(parts.first?["text"] as? String)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any])
        let measurements = try #require(payload["body"] as? [String: Any])
        #expect((measurements["latestWeight"] as? [String: Any])?["id"] == nil)
        #expect((measurements["firstWeightInRange"] as? [String: Any])?["id"] == nil)
        #expect(throws: DiaryError.self) { try DeepSeekClient.makeWellnessRequest(summary: snapshot, apiKey: " ") }
        #expect(throws: DiaryError.self) { try DeepSeekClient.makeWellnessRequest(summary: summary(), apiKey: "key") }
    }

    @Test func reportRequiresAllFourAreasAndCompleteOutput() throws {
        let snapshot = try summary(DiaryDocument(records: [meal(date(4))]))
        let report = try DeepSeekClient.parseWellnessResponse(data: response(resultJSON), statusCode: 200, summary: snapshot)
        #expect(report.observations.count == 4)
        #expect(report.snapshot == snapshot)
        #expect(report.actions.count == 1)
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.parseWellnessResponse(data: response(resultJSON, reason: "length"), statusCode: 200, summary: snapshot)
        }
        let missingArea = resultJSON.replacingOccurrences(of: "\"activity\"", with: "\"diet\"")
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.parseWellnessResponse(data: response(missingArea), statusCode: 200, summary: snapshot)
        }
    }

    @Test func savedReportsRoundTripAndOldDocumentsRemainReadable() throws {
        let old = Data(#"{"schemaVersion":1,"records":[]}"#.utf8)
        #expect(try JSONDecoder().decode(DiaryDocument.self, from: old).wellnessReviews.isEmpty)
        var document = DiaryDocument(records: [meal(date(4))])
        let snapshot = try summary(document)
        let report = try DeepSeekClient.parseWellnessResponse(data: response(resultJSON), statusCode: 200, summary: snapshot)
        try document.saveWellnessReview(report)
        try document.saveWellnessReview(report)
        #expect(document.wellnessReviews.count == 1)
        let url = FileManager.default.temporaryDirectory.appending(path: "wellness-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DiaryStore(fileURL: url)
        try store.save(document)
        let reopened = try store.load()
        #expect(reopened.wellnessReviews == [report])
        #expect(reopened.records == document.records)
    }

    @Test func allHistoryFindsEarliestProvidedHealthObservationWithoutExtraHint() throws {
        let snapshot = try summary(period: .all, days: [HealthActivityDay(date: date(1, month: 9), steps: 500)])
        #expect(snapshot.startDate == calendar.startOfDay(for: date(1, month: 9)))
        #expect(snapshot.activity.steps.total == 500)
    }

    @Test func emptyHealthRowsDoNotPretendThereAreObservations() throws {
        let snapshot = try summary(days: [HealthActivityDay(date: date(3))])
        #expect(snapshot.timeline.isEmpty)
        #expect(!snapshot.hasData)
    }

    @Test func summaryKeepsDifferentCurrenciesSeparate() throws {
        var journal = SmokingDiary()
        try journal.openPack(CigarettePack(product: CigaretteProduct(name: "甲", pricePerPack: 20, currency: .cny), openedAt: date(1)))
        try journal.record(.smoked, count: 1, date: date(2))
        try journal.openPack(CigarettePack(product: CigaretteProduct(name: "乙", pricePerPack: 40, currency: .usd), openedAt: date(2)))
        try journal.record(.smoked, count: 1, date: date(3))
        let snapshot = try summary(DiaryDocument(smoking: journal))
        #expect(snapshot.smoking.costs.count == 2)
        #expect(snapshot.smoking.costs.first { $0.currency == .cny }?.amount == 1)
        #expect(snapshot.smoking.costs.first { $0.currency == .usd }?.amount == 2)
    }

    @Test func savingAnotherRangePreservesItsReportAndNewerDiaryEdits() throws {
        var document = DiaryDocument(records: [meal(date(4))])
        let week = try DeepSeekClient.parseWellnessResponse(data: response(resultJSON), statusCode: 200, summary: summary(document))
        let month = try DeepSeekClient.parseWellnessResponse(data: response(resultJSON), statusCode: 200, summary: summary(document, period: .month))
        try document.upsert(meal(date(3)))
        try document.saveWellnessReview(week)
        try document.saveWellnessReview(month)
        #expect(document.records.count == 2)
        #expect(document.wellnessReviews.count == 2)
        #expect(document.wellnessReviews[0].snapshot.diet.recordCount == 1)
    }


    @Test func persistedMetricTotalsRequireMatchingObservationCoverage() throws {
        let snapshot = try summary(DiaryDocument(records: [meal(date(4))]))
        let report = try DeepSeekClient.parseWellnessResponse(data: response(resultJSON), statusCode: 200, summary: snapshot)
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        var saved = try #require(payload["snapshot"] as? [String: Any])
        var activity = try #require(saved["activity"] as? [String: Any])
        activity["steps"] = ["observedDays": 0, "total": 1234]
        saved["activity"] = activity
        payload["snapshot"] = saved
        let decoded = try JSONDecoder().decode(WellnessReview.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(throws: DiaryError.self) { try decoded.validate() }
    }

}
