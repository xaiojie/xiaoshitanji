import Foundation
import Observation
import SwiftUI
import PhotosUI
import NutritionCore

@MainActor
@Observable
final class MealDraft {
    let original: MealRecord
    let aiConsent = AIConsent()
    let isEditing: Bool
    var record: MealRecord
    var reviewing: Bool
    var correction = ""
    var errorMessage: String?
    /// 这一餐附带的照片，最多 `DeepSeekClient.maxPhotos` 张：正面、营养表、剩下的食物。
    /// 只把第一张存进记录（历史数据是单图），其余只参与这次分析。
    private(set) var photos: [Data] = []
    private(set) var isAnalyzing = false
    private(set) var isRefining = false
    private(set) var photoLoadID: UUID?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var photoTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?

    var busy: Bool { isAnalyzing || photoLoadID != nil }
    var dirty: Bool { record != original || !correction.isEmpty }

    init(record: MealRecord, isEditing: Bool) {
        original = record
        self.record = record
        self.isEditing = isEditing
        reviewing = isEditing
        photos = record.photoJPEG.map { [$0] } ?? []
    }

    func updateText(_ text: String) { record.updateInput(text: text, photoJPEG: photos.first) }
    func updateMode(_ mode: FoodAnalysisMode) {
        record.updateInput(text: record.originalText, photoJPEG: photos.first, analysisMode: mode)
    }
    func removePhoto() {
        photos = []
        record.updateInput(text: record.originalText, photoJPEG: nil)
    }
    func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        record.updateInput(text: record.originalText, photoJPEG: photos.first)
        invalidateEstimateIfNeeded()
    }

    private func invalidateEstimateIfNeeded() {
        guard !record.foods.isEmpty else { return }
        record.clearEstimate()
        reviewing = false
        errorMessage = nil
    }
    func analyze() { performAnalysis(instruction: nil) }

    func refine(_ instruction: String) {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        correction = instruction
        performAnalysis(instruction: instruction)
    }

    func addFood(_ food: FoodItem) {
        do {
            try record.addFood(food)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceFood(_ food: FoodItem) {
        do {
            try record.replaceFood(food)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 套用常吃组合或复制最近的一餐：保留食物与营养，标记为手动来源。
    func copyContent(from other: MealRecord, note: String) {
        record.foods = other.foods
        record.source = .manual
        record.model = nil
        record.summary = other.summary
        record.assumptions = []
        record.originalText = ""
        record.photoJPEG = nil
        record.photoFileName = nil
        photos = []
        record.adjustments = (record.adjustments ?? []) + [note]
        reviewing = true
        errorMessage = nil
    }

    func apply(template: MealTemplate) {
        copyContent(from: template.makeRecord(on: record.date, kind: record.kind),
                    note: "套用常吃组合「\(template.name)」")
    }

    func copy(record other: MealRecord) {
        copyContent(from: other,
                    note: "复制自 \(other.date.formatted(.dateTime.month().day().hour().minute())) 的\(other.kind.title)")
    }

    func removeFood(_ food: FoodItem) {
        record.foods.removeAll { $0.id == food.id }
        record.adjustments = (record.adjustments ?? []) + ["移除\(food.name)"]
    }

    func cancelAnalysis() {
        requestID = nil
        analysisTask?.cancel()
        isAnalyzing = false
        isRefining = false
    }

    func cancelAll() {
        cancelAnalysis()
        photoLoadID = nil
        photoTask?.cancel()
    }

    func choosePhoto(_ selection: PhotosPickerItem) {
        startPhotoLoad {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw DiaryError.invalidInput("无法读取这张照片，请重新选择。")
            }
            return data
        }
    }

    func loadPhotoData(_ data: Data) { startPhotoLoad { data } }

    private func performAnalysis(instruction: String?) {
        guard !busy else { return }
        let id = UUID()
        let snapshot = record
        requestID = id
        errorMessage = nil
        isAnalyzing = true
        isRefining = instruction != nil
        analysisTask = Task { @MainActor in
            defer {
                if requestID == id {
                    isAnalyzing = false
                    isRefining = false
                    requestID = nil
                }
            }
            do {
                try await aiConsent.requirePermission()
                let client = DeepSeekClient()
                let estimate: FoodEstimate
                if let instruction {
                    estimate = try await client.refine(record: snapshot, instruction: instruction)
                } else {
                    estimate = try await client.analyze(text: snapshot.originalText, images: photos, mode: snapshot.analysisMode ?? .automatic)
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                record.applyEstimate(estimate, adjustment: instruction)
                correction = ""
                reviewing = true
            } catch is CancellationError {
                // Cancellation preserves the previous estimate and all editable input.
            } catch {
                if requestID == id { errorMessage = error.localizedDescription }
            }
        }
    }

    private func startPhotoLoad(_ load: @escaping @Sendable () async throws -> Data) {
        guard !isAnalyzing else { return }
        photoTask?.cancel()
        let id = UUID()
        photoLoadID = id
        errorMessage = nil
        photoTask = Task { @MainActor in
            defer { if photoLoadID == id { photoLoadID = nil } }
            do {
                let data = try await load()
                try Task.checkCancellation()
                let jpeg = try await Task.detached(priority: .userInitiated) { try PhotoInput.prepareJPEG(data) }.value
                try Task.checkCancellation()
                guard photoLoadID == id else { return }
                if photos.count >= DeepSeekClient.maxPhotos {
                    photos.removeLast()
                }
                photos.append(jpeg)
                record.updateInput(text: record.originalText, photoJPEG: photos.first)
                invalidateEstimateIfNeeded()
            } catch is CancellationError {
                // A newer selection owns the loading state and image preview.
            } catch {
                if photoLoadID == id { errorMessage = error.localizedDescription }
            }
        }
    }
}
