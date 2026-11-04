import Foundation
import Testing
@testable import NutritionCore

struct HealthProfileTests {
    @Test func bmiUsesKilogramsAndHeightInCentimeters() {
        let profile = HealthProfile(nickname: "Jay", heightCM: 175, targetWeightKG: 68)
        #expect(abs((profile.bmi(weightKG: 70) ?? 0) - 22.857142857142858) < 0.000001)
        #expect(profile.bmi(weightKG: nil) == nil)
        #expect(HealthProfile().bmi(weightKG: 70) == nil)
        #expect(HealthProfile(heightCM: 0).bmi(weightKG: 70) == nil)
    }

    @Test func invalidProfileAndWeightValuesAreRejected() {
        #expect(throws: DiaryError.self) { try HealthProfile(heightCM: .infinity).validate() }
        #expect(throws: DiaryError.self) { try HealthProfile(heightCM: 0).validate() }
        #expect(throws: DiaryError.self) { try HealthProfile(targetWeightKG: -1).validate() }
        #expect(throws: DiaryError.self) { try WeightRecord(kilograms: .nan).validate() }
        #expect(throws: DiaryError.self) { try WeightRecord(kilograms: 0).validate() }
    }

    @Test func profileAndWeightPersistWithoutDuplicatingUnchangedWeight() throws {
        var document = DiaryDocument()
        var profile = HealthProfile(nickname: "我的昵称", avatarJPEG: Data([1, 2]), heightCM: 175, targetWeightKG: 68)
        try document.updateProfile(profile, weightKG: 70)
        profile.nickname = "新昵称"
        try document.updateProfile(profile)
        #expect(document.weights.count == 1)
        try document.updateProfile(profile, weightKG: 69.5)
        #expect(document.weights.count == 2)
        let reopened = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(document))
        try reopened.validate()
        #expect(reopened.profile.nickname == "新昵称")
        #expect(reopened.profile.avatarJPEG == Data([1, 2]))
        #expect(reopened.profile.targetWeightKG == 68)
        #expect(WeightRecord.latest(in: reopened.weights)?.kilograms == 69.5)
    }

    @Test func legacyDiaryLoadsAnEmptyProfileAndWeightHistory() throws {
        let data = Data(#"{"schemaVersion":1,"records":[]}"#.utf8)
        let document = try JSONDecoder().decode(DiaryDocument.self, from: data)
        try document.validate()
        #expect(document.profile.nickname.isEmpty)
        #expect(document.profile.heightCM == nil)
        #expect(document.weights.isEmpty)
    }

    @Test func latestWeightUsesDateAndPrefersManualOnExactTie() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let older = WeightRecord(date: date.addingTimeInterval(-100), kilograms: 75, source: .manual)
        let imported = WeightRecord(date: date, kilograms: 72, source: .appleHealth)
        let manual = WeightRecord(date: date, kilograms: 71.5, source: .manual)
        #expect(WeightRecord.latest(in: [manual, older, imported])?.id == manual.id)
        #expect(WeightRecord.latest(in: [older, imported])?.id == imported.id)
    }

    @Test func manualMeasurementCanBeEditedAndRemovedByIdentity() throws {
        var document = DiaryDocument()
        var weight = WeightRecord(kilograms: 70)
        try document.saveWeight(weight)
        weight.kilograms = 69
        try document.saveWeight(weight)
        #expect(document.weights.count == 1)
        #expect(document.weights.first?.kilograms == 69)
        document.removeWeight(id: weight.id)
        #expect(document.weights.isEmpty)
    }

    @Test func explicitProfileWeightCanRepeatAnOlderManualValueAfterHealthImport() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var document = DiaryDocument(weights: [WeightRecord(date: date, kilograms: 70)])
        let imported = WeightRecord(date: date.addingTimeInterval(100), kilograms: 72, source: .appleHealth)
        try document.updateProfile(HealthProfile(), weightKG: 70, date: date.addingTimeInterval(200))
        #expect(document.weights.count == 2)
        #expect(WeightRecord.latest(in: document.weights + [imported])?.kilograms == 70)
    }

    @Test func absentHealthReadingsStayDistinctFromRecordedZero() {
        let missing = HealthActivityDay(date: .now)
        let recorded = HealthActivityDay(date: .now, steps: 0, activeCalories: 0)
        #expect(missing.steps == nil)
        #expect(missing.activeCalories == nil)
        #expect(recorded.steps == 0)
        #expect(recorded.activeCalories == 0)
    }

    @Test func measurementInputAcceptsDecimalCommaAndRoundTripsPrefilledValues() throws {
        let localized = 70.5.formatted(.number.locale(Locale(identifier: "de_DE")).grouping(.never))
        #expect(try HealthMeasurementInput.parse(localized) == 70.5)
        #expect(try HealthMeasurementInput.parse(" 175,5 ") == 175.5)
        #expect(try HealthMeasurementInput.parse(HealthMeasurementInput.format(70.5)) == 70.5)
        #expect(HealthMeasurementInput.format(70.5) == "70.5")
        #expect(try HealthMeasurementInput.parse("  ") == nil)
        #expect(throws: DiaryError.self) { try HealthMeasurementInput.parse("NaN") }
        #expect(throws: DiaryError.self) { try HealthMeasurementInput.parse("1,2,3") }
    }

    @Test func profilePreservesHeightMeasurementDateWhenReopened() throws {
        let data = Data(#"{"nickname":"Jay","heightCM":175,"heightUpdatedAt":100}"#.utf8)
        let profile = try JSONDecoder().decode(HealthProfile.self, from: data)
        let reopened = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        #expect(reopened["heightUpdatedAt"] as? Double == 100)
    }
}
