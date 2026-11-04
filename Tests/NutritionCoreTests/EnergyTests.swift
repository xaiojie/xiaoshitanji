import Foundation
import Testing
@testable import NutritionCore

struct EnergyTests {
    private func settings(_ change: (inout EnergySettings) -> Void = { _ in }) -> EnergySettings {
        var settings = EnergySettings(sex: .male, birthYear: 1996, activity: .moderate,
                                      goalMode: .maintain, weeklyRate: 0.25)
        change(&settings)
        return settings
    }

    private let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!

    // MARK: 基础代谢

    @Test func maleBMRMatchesMifflinStJeor() {
        #expect(EnergyCalculator.bmr(sex: .male, weightKG: 80, heightCM: 180, age: 30) == 1780)
    }

    @Test func femaleBMRUsesFemaleOffset() {
        #expect(EnergyCalculator.bmr(sex: .female, weightKG: 60, heightCM: 165, age: 30) == 1320.25)
    }

    // MARK: 维持与目标

    @Test func maintainTargetEqualsMaintenance() throws {
        let budget = try EnergyCalculator.budget(settings: settings(), weightKG: 80, heightCM: 180, now: now)
        #expect(abs(budget.maintenance - 1780 * 1.55) < 0.001)
        #expect(abs(budget.targetCalories - budget.maintenance) < 0.001)
        #expect(budget.dailyDelta == 0)
        #expect(!budget.usedCalibration)
        #expect(budget.age == 30)
    }

    @Test func loseAppliesWeeklyRateAsDailyDeficit() throws {
        let budget = try EnergyCalculator.budget(settings: settings { $0.goalMode = .lose; $0.weeklyRate = 0.5 },
                                                 weightKG: 80, heightCM: 180, now: now)
        // 0.5 公斤/周 ≈ 550 千卡/天
        #expect(abs(budget.dailyDelta + 550) < 0.001)
        #expect(budget.targetCalories < budget.maintenance)
    }

    @Test func gainUsesHalfOfTheWeeklyRate() throws {
        let budget = try EnergyCalculator.budget(settings: settings { $0.goalMode = .gain; $0.weeklyRate = 0.4 },
                                                 weightKG: 70, heightCM: 175, now: now)
        #expect(abs(budget.dailyDelta - 0.4 * 7700 / 7 * 0.5) < 0.001)
        #expect(budget.targetCalories > budget.maintenance)
    }

    @Test func targetNeverDropsBelowSafeFloor() throws {
        let budget = try EnergyCalculator.budget(settings: settings { $0.goalMode = .lose; $0.weeklyRate = 1.5 },
                                                 weightKG: 45, heightCM: 150, now: now)
        #expect(budget.targetCalories >= EnergyCalculator.minimumCalories)
        #expect(budget.targetCalories >= budget.bmr * 1.1)
        #expect(budget.targetCalories > 0)
    }

    @Test func macrosFollowGoalMode() throws {
        let loss = try EnergyCalculator.budget(settings: settings { $0.goalMode = .lose }, weightKG: 80, heightCM: 180, now: now)
        #expect(abs(loss.proteinGrams - 160) < 0.001)
        #expect(loss.fatGrams >= 0.7 * 80)
        #expect(loss.proteinCalories + loss.carbCalories + loss.fatCalories <= loss.targetCalories + 1)

        let maintain = try EnergyCalculator.budget(settings: settings(), weightKG: 80, heightCM: 180, now: now)
        #expect(abs(maintain.proteinGrams - 128) < 0.001)
    }

    // MARK: 校准

    @Test func calibrationOverridesFormula() throws {
        let budget = try EnergyCalculator.budget(settings: settings { $0.calibratedMaintenance = 2600 },
                                                 weightKG: 80, heightCM: 180, now: now)
        #expect(budget.usedCalibration)
        #expect(budget.maintenance == 2600)
    }

    @Test func calibrationIgnoresOutOfRangeValues() {
        #expect(!EnergySettings(calibratedMaintenance: 100).usesCalibration)
        #expect(!EnergySettings(calibratedMaintenance: 20_000).usesCalibration)
    }

    @Test func calibrationFromWeightTrend() {
        // 两周平均吃 2000 千卡、增重 1 公斤：维持热量约 2000 - 550 = 1450
        let value = EnergyCalculator.calibratedMaintenance(averageIntake: 2000, weightChangeKG: 1, days: 14)
        #expect(value != nil)
        #expect(abs((value ?? 0) - 1450) < 0.001)
        #expect(EnergyCalculator.calibratedMaintenance(averageIntake: 2000, weightChangeKG: 1, days: 3) == nil)
    }

    // MARK: 校验

    @Test func rejectsFutureBirthYear() {
        #expect(throws: DiaryError.self) {
            try settings { $0.birthYear = 2030 }.validate(now: now)
        }
    }

    @Test func rejectsTooYoung() {
        #expect(throws: DiaryError.self) {
            try settings { $0.birthYear = 2015 }.validate(now: now)
        }
    }

    @Test func budgetRequiresWeightAndHeight() {
        #expect(throws: DiaryError.self) {
            try EnergyCalculator.budget(settings: settings(), weightKG: 0, heightCM: 180, now: now)
        }
        #expect(throws: DiaryError.self) {
            try EnergyCalculator.budget(settings: settings(), weightKG: 80, heightCM: 0, now: now)
        }
    }

    @Test func calibrateFromWeightsAndIntakes() {
        let first = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let weights = [WeightRecord(date: first, kilograms: 80), WeightRecord(date: now, kilograms: 81)]
        let result = EnergyCalculator.calibrate(weights: weights, dailyIntakes: Array(repeating: 2000, count: 10))
        #expect(result != nil)
        #expect(abs((result?.maintenance ?? 0) - 1450) < 0.001)
        #expect(abs((result?.days ?? 0) - 14) < 0.001)
        #expect(EnergyCalculator.calibrate(weights: [], dailyIntakes: [2000]) == nil)
        #expect(EnergyCalculator.calibrate(weights: weights, dailyIntakes: [2000, 2100]) == nil)
    }

    // MARK: 持久化

    @Test func documentRoundTripsEnergySettings() throws {
        var document = DiaryDocument(energy: settings { $0.goalMode = .lose; $0.calibratedMaintenance = 2500 })
        try document.validate()
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.energy?.goalMode == .lose)
        #expect(decoded.energy?.calibratedMaintenance == 2500)
    }

    @Test func oldDocumentWithoutEnergyDecodesNil() throws {
        let legacy = #"{"schemaVersion":2,"records":[],"reviews":[],"weights":[],"templates":[]}"#
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: Data(legacy.utf8))
        #expect(decoded.energy == nil)
        #expect(decoded.templates.isEmpty)
    }
}
