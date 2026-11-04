import Foundation
import Observation
import SwiftUI
import PhotosUI
import NutritionCore

@MainActor
@Observable
final class MealDraft {
    let original: MealRecord
    let isEditing: Bool
    var record: MealRecord
    var reviewing: Bool
    var correction = ""
    var errorMessage: String?
    private(set) var requiresKey = false
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
    }

    func updateText(_ text: String) { record.updateInput(text: text, photoJPEG: record.photoJPEG) }
    func removePhoto() { record.updateInput(text: record.originalText, photoJPEG: nil) }
    func analyze() { performAnalysis(instruction: nil) }

    func refine(_ instruction: String) {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        correction = instruction
        performAnalysis(instruction: instruction)
    }

    func replaceFood(_ food: FoodItem) {
        guard let index = record.foods.firstIndex(where: { $0.id == food.id }) else { return }
        record.foods[index] = food
        record.adjustments = (record.adjustments ?? []) + ["\(food.name)调整为\(food.portionLabel)"]
        errorMessage = nil
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
        requiresKey = false
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
                let key = try KeychainStore.load()
                guard !key.isEmpty else {
                    requiresKey = true
                    throw DiaryError.missingAPIKey
                }
                let client = DeepSeekClient()
                let estimate: FoodEstimate
                if let instruction {
                    estimate = try await client.refine(record: snapshot, instruction: instruction, apiKey: key)
                } else {
                    estimate = try await client.analyze(text: snapshot.originalText, imageJPEG: snapshot.photoJPEG, apiKey: key)
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
                record.updateInput(text: record.originalText, photoJPEG: jpeg)
            } catch is CancellationError {
                // A newer selection owns the loading state and image preview.
            } catch {
                if photoLoadID == id { errorMessage = error.localizedDescription }
            }
        }
    }
}
