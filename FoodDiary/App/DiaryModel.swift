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
}
