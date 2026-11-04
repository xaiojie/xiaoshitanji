import Foundation
import Testing
@testable import NutritionCore

struct RedesignTests {
    private func meal(date: Date = .now) -> MealRecord {
        MealRecord(date: date, foods: [FoodItem(name: "米饭", grams: 150,
            per100g: Nutrition(calories: 116, protein: 2.6, carbohydrates: 25.9, fat: 0.3),
            portionDescription: "一小碗")], originalText: "一小碗米饭", source: .text)
    }

    @Test func naturalPortionScalesFromCurrentFoodWithoutWeighing() throws {
        let food = meal().foods[0]
        #expect(food.portionLabel == "一小碗")
        let half = try food.scaledPortion(by: 0.5, description: "原份量的一半")
        #expect(half.id == food.id)
        #expect(half.nutrition.calories == 87)
        #expect(half.portionLabel == "原份量的一半")
        #expect(throws: DiaryError.self) { try food.scaledPortion(by: 0, description: "") }
        #expect(throws: DiaryError.self) { try food.scaledPortion(by: .infinity, description: "") }
    }

    @Test func oldDocumentsDecodeWithoutNewPortionOrReviewFields() throws {
        let original = DiaryDocument(records: [meal()])
        let encoded = try JSONEncoder().encode(original)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "reviews")
        var records = try #require(json["records"] as? [[String: Any]])
        records[0].removeValue(forKey: "adjustments")
        var foods = try #require(records[0]["foods"] as? [[String: Any]])
        foods[0].removeValue(forKey: "portionDescription")
        records[0]["foods"] = foods
        json["records"] = records
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: JSONSerialization.data(withJSONObject: json))
        try decoded.validate()
        #expect(decoded.records[0].nutrition.calories == 174)
        #expect(decoded.records[0].foods[0].portionLabel == "一份")
        #expect(decoded.reviews.isEmpty)
    }

    @Test func changedMealsInvalidateOnlyRelatedDayReviews() throws {
        let today = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        var record = meal(date: today)
        let other = meal(date: yesterday)
        var document = DiaryDocument(records: [record, other])
        try document.saveReview(review(for: today), snapshot: [record])
        try document.saveReview(review(for: yesterday), snapshot: [other])
        record.foods[0].grams = 75
        try document.upsert(record)
        #expect(document.review(on: today) == nil)
        #expect(document.review(on: yesterday) != nil)
        document.remove(id: other.id)
        #expect(document.reviews.isEmpty)
    }

    @Test func staleReviewSnapshotCannotBeSaved() throws {
        let record = meal()
        var document = DiaryDocument(records: [record])
        var changed = record
        changed.foods[0].grams = 75
        try document.upsert(changed)
        #expect(throws: DiaryError.self) {
            try document.saveReview(review(for: record.date), snapshot: [record])
        }
        #expect(document.reviews.isEmpty)
    }

    @Test func reviewScoresAllowMissingButRejectOutOfBounds() throws {
        var value = review(for: .now)
        value.score = nil
        try value.validate()
        value.score = 101
        #expect(throws: DiaryError.self) { try value.validate() }
    }

    private func review(for date: Date) -> DietReview {
        DietReview(date: date, recordCount: 1, summary: "仅基于已记录的一餐", score: nil,
                   highlights: ["已记录主食"], suggestions: ["下一餐搭配蔬菜"], model: "deepseek-flash")
    }
}
