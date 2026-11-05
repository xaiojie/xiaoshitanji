import Foundation
import Testing
@testable import NutritionCore

struct DiaryTests {
    private func meal(date: Date = .now) -> MealRecord {
        MealRecord(
            date: date,
            kind: .lunch,
            foods: [FoodItem(name: "米饭", grams: 150,
                             per100g: Nutrition(calories: 116, protein: 2.6, carbohydrates: 25.9, fat: 0.3))],
            originalText: "一小碗米饭"
        )
    }

    @Test func portionScalingUsesEdibleGrams() throws {
        var record = meal()
        #expect(record.nutrition.calories == 174)
        #expect(abs(record.nutrition.protein - 3.9) < 0.0001)
        record.foods[0].grams = 75
        #expect(record.nutrition.calories == 87)
        try record.validate()
    }

    @Test func invalidValuesAndDuplicateFoodsAreRejected() {
        var record = meal()
        record.foods[0].grams = 0
        #expect(throws: DiaryError.self) { try record.validate() }
        record.foods[0].grams = .infinity
        #expect(throws: DiaryError.self) { try record.validate() }
        record.foods[0].grams = 100
        record.foods[0].per100g.fat = -1
        #expect(throws: DiaryError.self) { try record.validate() }
        record.foods[0].per100g.fat = 0
        record.foods[0].name = "  "
        #expect(throws: DiaryError.self) { try record.validate() }
        record.foods[0].name = "米饭"
        record.foods.append(record.foods[0])
        #expect(throws: DiaryError.self) { try record.validate() }
        record.foods = []
        #expect(throws: DiaryError.self) { try record.validate() }
    }

    @Test func saveReopenEditAndDeletePreserveIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "diary.json")
        let store = DiaryStore(fileURL: url)
        #expect(try store.load().records.isEmpty)
        var record = meal()
        record.photoJPEG = Data([1, 2, 3])
        var document = DiaryDocument()
        try document.upsert(record)
        try store.save(document)

        var reopened = try DiaryStore(fileURL: url).load()
        #expect(reopened.records.count == 1)
        #expect(reopened.records[0].id == record.id)
        #expect(reopened.records[0].photoJPEG == Data([1, 2, 3]))
        #expect(reopened.records[0].originalText == "一小碗米饭")
        record.foods[0].grams = 100
        try reopened.upsert(record)
        try store.save(reopened)
        #expect(try store.load().records.count == 1)
        #expect(try store.load().records[0].nutrition.calories == 116)

        reopened.remove(id: record.id)
        try store.save(reopened)
        #expect(try store.load().records.isEmpty)
    }

    @Test func corruptedOrNewerFilesCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "diary.json")
        let broken = Data("broken diary".utf8)
        try broken.write(to: url)
        let store = DiaryStore(fileURL: url)
        #expect(throws: DiaryError.self) { try store.load() }
        #expect(throws: DiaryError.self) { try store.save(DiaryDocument()) }
        #expect(try Data(contentsOf: url) == broken)

        let future = Data(#"{"schemaVersion":999,"records":[]}"#.utf8)
        try future.write(to: url)
        #expect(throws: DiaryError.self) { try store.save(DiaryDocument()) }
        #expect(try Data(contentsOf: url) == future)
    }

    @Test func dayGroupingUsesLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let formatter = ISO8601DateFormatter()
        let beforeMidnight = formatter.date(from: "2026-11-04T15:59:00Z")!
        let afterMidnight = formatter.date(from: "2026-11-04T16:01:00Z")!
        let document = DiaryDocument(records: [meal(date: beforeMidnight), meal(date: afterMidnight)])
        #expect(document.records(on: beforeMidnight, calendar: calendar).count == 1)
        #expect(document.total(on: beforeMidnight, calendar: calendar).calories == 174)
        #expect(document.total(on: afterMidnight, calendar: calendar).calories == 174)
    }

    @Test func automaticMealDraftUsesCurrentClockTimeOnSelectedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let formatter = ISO8601DateFormatter()
        let staleSelection = formatter.date(from: "2026-11-04T00:00:00Z")!
        let currentLunchTime = formatter.date(from: "2026-11-04T05:20:00Z")!
        let draft = MealRecord.draft(on: staleSelection, now: currentLunchTime, calendar: calendar)
        #expect(draft.date == formatter.date(from: "2026-11-04T05:20:00Z"))
        #expect(draft.kind == .lunch)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: staleSelection)!
        let pastDraft = MealRecord.draft(on: previousDay, now: currentLunchTime, calendar: calendar)
        #expect(pastDraft.date == formatter.date(from: "2026-11-03T05:20:00Z"))
    }

    @Test func changingAnalyzedInputInvalidatesPriorNutrition() {
        var record = meal()
        record.source = .photo
        record.model = "deepseek-flash"
        record.summary = "旧照片的米饭"
        record.assumptions = ["旧份量"]
        record.photoJPEG = Data([1])
        record.updateInput(text: "新的食物", photoJPEG: Data([2]))
        #expect(record.foods.isEmpty)
        #expect(record.model == nil)
        #expect(record.summary.isEmpty)
        #expect(record.assumptions.isEmpty)
        #expect(record.source == .manual)
        #expect(record.originalText == "新的食物")
        #expect(record.photoJPEG == Data([2]))
    }

    @Test func unchangedInputAndManualFoodsRemainEditable() {
        var record = meal()
        record.source = .text
        record.updateInput(text: "一小碗米饭", photoJPEG: nil)
        #expect(record.foods.count == 1)
        record.source = .manual
        record.updateInput(text: "手动补充说明", photoJPEG: nil)
        #expect(record.foods.count == 1)
        #expect(record.originalText == "手动补充说明")
    }
}
