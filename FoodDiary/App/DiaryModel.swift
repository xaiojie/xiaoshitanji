import Foundation
import Observation
import NutritionCore

@MainActor
@Observable
final class DiaryModel {
    private(set) var document = DiaryDocument() {
        didSet { revision = UUID() }
    }
    @ObservationIgnored private(set) var revision = UUID()
    private(set) var loadError: String?
    @ObservationIgnored private let store: DiaryStore

    var fileURL: URL { store.fileURL }
    var photosDirectory: URL { fileURL.deletingLastPathComponent().appending(path: PhotoArchive.directoryName) }

    /// 记录的照片：新数据写在 Photos/ 里，旧数据还内嵌在文档里时直接给内存数据。
    func photoData(for record: MealRecord) -> Data? {
        if let data = record.photoJPEG { return data }
        guard let name = record.photoFileName else { return nil }
        return PhotoArchive.load(name: name, in: photosDirectory)
    }

    func photoData(for pack: CigarettePack) -> Data? {
        if let data = pack.photoJPEG { return data }
        guard let name = pack.photoFileName else { return nil }
        return PhotoArchive.load(name: name, in: photosDirectory)
    }

    init() {
        store = DiaryStore(fileURL: URL.documentsDirectory.appending(path: "FoodDiary/diary.json"))
        reload()
    }

    func reload() {
        do {
            var loaded = try store.load()
            if try loaded.externalizePhotos(in: photosDirectory) {
                try store.save(loaded)
            }
            document = loaded
            loadError = nil
            publishWidgetSnapshot()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 落盘、更新内存、再刷新小组件；所有写路径都走这里。
    private func commit(_ next: DiaryDocument) throws {
        try store.save(next)
        document = next
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot(on date: Date = .now) {
        let budget = energyBudget(on: date)
        WidgetSnapshotWriter.write(document: document, budget: budget, on: date)
        if IntakeActivityManager.shared.isRunning {
            IntakeActivityManager.shared.update(
                state: IntakeActivityManager.state(for: document, budget: budget, on: date))
        }
    }

    func save(_ record: MealRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var record = record
        if let data = record.photoJPEG {
            record.photoFileName = try PhotoArchive.save(data, name: PhotoArchive.transferName(for: data),
                                                         in: photosDirectory)
            record.photoJPEG = nil
        }
        var next = document
        try next.upsert(record)
        try commit(next)
    }

    func delete(_ record: MealRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.remove(id: record.id)
        try commit(next)
    }

    func saveReview(_ review: DietReview, snapshot: [MealRecord]) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveReview(review, snapshot: snapshot)
        try commit(next)
    }

    func saveWellnessReview(_ report: WellnessReview) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveWellnessReview(report)
        try commit(next)
    }

    /// 当天训练记录里填的消耗热量；没填就算 0，不猜。
    func burnedCalories(on date: Date) -> Double {
        document.workouts(on: date).reduce(0) { $0 + ($1.caloriesBurned ?? 0) }
    }

    func saveWorkout(_ workout: WorkoutRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveWorkout(workout)
        try commit(next)
    }

    func deleteWorkout(_ workout: WorkoutRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.removeWorkout(id: workout.id)
        try commit(next)
    }

    func savePlan(_ plan: WorkoutPlan) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.savePlan(plan)
        try commit(next)
    }

    func deletePlan(_ plan: WorkoutPlan) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.removePlan(id: plan.id)
        try commit(next)
    }

    /// 从计划开练，返回刚生成的训练（用于提示）。
    @discardableResult
    func startWorkout(from plan: WorkoutPlan, on date: Date = .now) throws -> WorkoutRecord? {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        let workout = try next.startWorkout(fromPlan: plan.id, on: date)
        try commit(next)
        return workout
    }

    func saveTemplate(_ template: MealTemplate) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveTemplate(template)
        try commit(next)
    }

    func deleteTemplate(id: UUID) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.removeTemplate(id: id)
        try commit(next)
    }

    func saveObservation(_ answer: AnalysisAnswer) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveObservation(answer)
        try commit(next)
    }

    func deleteObservation(id: UUID) {
        var next = document
        next.removeObservation(id: id)
        try? commit(next)
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
        try commit(next)
    }

    func saveEnergySettings(_ settings: EnergySettings) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try settings.validate()
        next.energy = settings
        try commit(next)
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

    /// 同步下载或合并后整体替换本机文档。
    func replaceDocument(_ document: DiaryDocument) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.schemaVersion = DiaryDocument.currentSchemaVersion
        _ = try next.externalizePhotos(in: photosDirectory)
        try next.validate()
        try commit(next)
    }

    func saveWeight(_ weight: WeightRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        try next.saveWeight(weight)
        try commit(next)
    }

    func deleteWeight(_ weight: WeightRecord) throws {
        guard loadError == nil else { throw DiaryError.unreadableDiary }
        var next = document
        next.removeWeight(id: weight.id)
        try commit(next)
    }

    func openSmokingPack(_ pack: CigarettePack) throws {
        var pack = pack
        if let data = pack.photoJPEG {
            pack.photoFileName = try PhotoArchive.save(data, name: PhotoArchive.transferName(for: data),
                                                       in: photosDirectory)
            pack.photoJPEG = nil
        }
        try updateSmoking { try $0.openPack(pack) }
    }

    func activateSmokingPack(_ id: UUID) throws {
        try updateSmoking { try $0.activatePack(id: id) }
    }

    func openAnotherSmokingPack(like id: UUID) throws {
        try updateSmoking { try $0.openAnotherPack(like: id) }
    }

    func updateSmokingPack(_ pack: CigarettePack) throws {
        var pack = pack
        if let data = pack.photoJPEG {
            pack.photoFileName = try PhotoArchive.save(data, name: PhotoArchive.transferName(for: data),
                                                       in: photosDirectory)
            pack.photoJPEG = nil
        }
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
        try commit(next)
    }
}
