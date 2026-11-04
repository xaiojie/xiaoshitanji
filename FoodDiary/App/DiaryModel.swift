import Foundation
import Observation
import NutritionCore

@MainActor
@Observable
final class DiaryModel {
    private(set) var document = DiaryDocument()
    private(set) var loadError: String?
    @ObservationIgnored private let store: DiaryStore

    var fileURL: URL { store.fileURL }

    init() {
        store = DiaryStore(fileURL: URL.documentsDirectory.appending(path: "FoodDiary/diary.json"))
        reload()
    }

    func reload() {
        do {
            document = try store.load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func save(_ record: MealRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.upsert(record)
        try store.save(next)
        document = next
    }

    func delete(_ record: MealRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.remove(id: record.id)
        try store.save(next)
        document = next
    }

    func saveReview(_ review: DietReview, snapshot: [MealRecord]) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveReview(review, snapshot: snapshot)
        try store.save(next)
        document = next
    }

    func saveWellnessReview(_ report: WellnessReview) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveWellnessReview(report)
        try store.save(next)
        document = next
    }

    func saveTemplate(_ template: MealTemplate) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveTemplate(template)
        try store.save(next)
        document = next
    }

    func deleteTemplate(id: UUID) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.removeTemplate(id: id)
        try store.save(next)
        document = next
    }

    /// 使用次数只影响排序，记录失败时不影响用户继续套用。
    func markTemplateUsed(id: UUID) {
        guard var template = document.templates.first(where: { $0.id == id }) else { return }
        template.markUsed()
        try? saveTemplate(template)
    }

    func saveProfile(_ profile: HealthProfile, weightKG: Double?) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.updateProfile(profile, weightKG: weightKG)
        try store.save(next)
        document = next
    }

    func saveEnergySettings(_ settings: EnergySettings) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try settings.validate()
        next.energy = settings
        try store.save(next)
        document = next
    }

    /// 某天的体重：优先取该天及以前最近的一次，没有历史就用最新一次。
    func weightKG(on date: Date) -> Double? {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        let past = document.weights.filter { $0.date < dayEnd }
        return WeightRecord.latest(in: past.isEmpty ? document.weights : past)?.kilograms
    }

    /// 有连续体重记录与足够饮食记录时，给出校准建议。
    func calibrationSuggestion() -> MaintenanceCalibration? {
        EnergyCalculator.calibrate(weights: document.weights,
                                   dailyIntakes: document.dailyCalories())
    }

    /// 已配置能量目标时给出当天预算；缺身高/体重时返回 nil。
    func energyBudget(on date: Date) -> EnergyBudget? {
        guard let settings = document.energy, let height = document.profile.heightCM,
              let weight = weightKG(on: date) else { return nil }
        return try? EnergyCalculator.budget(settings: settings, weightKG: weight, heightCM: height)
    }

    func saveWeight(_ weight: WeightRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveWeight(weight)
        try store.save(next)
        document = next
    }

    func deleteWeight(_ weight: WeightRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.removeWeight(id: weight.id)
        try store.save(next)
        document = next
    }

    func openSmokingPack(_ pack: CigarettePack) throws {
        try updateSmoking { try $0.openPack(pack) }
    }

    func activateSmokingPack(_ id: UUID) throws {
        try updateSmoking { try $0.activatePack(id: id) }
    }

    func openAnotherSmokingPack(like id: UUID) throws {
        try updateSmoking { try $0.openAnotherPack(like: id) }
    }

    func updateSmokingPack(_ pack: CigarettePack) throws {
        try updateSmoking { try $0.updatePack(pack) }
    }

    func recordSmoking(_ kind: SmokingEventKind, count: Int) throws {
        try updateSmoking { try $0.record(kind, count: count) }
    }

    func removeSmokingEvent(_ id: UUID) throws {
        try updateSmoking { try $0.removeEvent(id: id) }
    }

    private func updateSmoking(_ update: (inout SmokingDiary) throws -> Void) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try update(&next.smoking)
        try store.save(next)
        document = next
    }
}
