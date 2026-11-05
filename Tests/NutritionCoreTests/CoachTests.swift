import Foundation
import Testing
@testable import NutritionCore

struct CoachTests {
    private var meal: MealRecord {
        MealRecord(foods: [FoodItem(name: "米饭", grams: 75, per100g: Nutrition(calories: 116), portionDescription: "半碗")],
                   originalText: "一碗米饭", source: .text, adjustments: ["米饭只吃了一半"])
    }

    private func content(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        let text = try #require(parts.first?["text"] as? String)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func envelope(_ content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": "deepseek-flash", "choices": [["finish_reason": "stop", "message": ["content": content]]]
        ])
    }

    @Test func refinementIncludesAlreadyAdjustedFoodsAndNewInstruction() throws {
        let request = try DeepSeekClient.makeRefinementRequest(record: meal, instruction: "再加一个鸡蛋")
        let payload = try content(of: request)
        #expect(payload["instruction"] as? String == "再加一个鸡蛋")
        let foods = try #require(payload["current_foods"] as? [[String: Any]])
        #expect(foods[0]["grams"] as? Double == 75)
        #expect(payload["already_applied_adjustments"] as? [String] == ["米饭只吃了一半"])
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.makeRefinementRequest(record: meal, instruction: " ")
        }
    }

    @Test func estimateParsesEverydayPortionsAndAppliesCorrectionHistory() throws {
        let json = #"{"summary":"半碗饭和一个鸡蛋","assumptions":["按常见家常份量估算"],"foods":[{"name":"米饭","grams":75,"portionDescription":"半碗","per100g":{"calories":116,"protein":2.6,"carbohydrates":25.9,"fat":0.3}},{"name":"鸡蛋","grams":50,"portionDescription":"一个","per100g":{"calories":144,"protein":13,"carbohydrates":1.5,"fat":9}}]}"#
        let estimate = try DeepSeekClient.parseResponse(data: envelope(json), statusCode: 200)
        var record = meal
        let id = record.id
        record.applyEstimate(estimate, adjustment: "再加一个鸡蛋")
        #expect(record.id == id)
        #expect(record.foods[0].portionLabel == "半碗")
        #expect(record.nutrition.calories == 159)
        #expect(record.originalText == "一碗米饭")
        #expect(record.adjustments == ["米饭只吃了一半", "再加一个鸡蛋"])
    }

    @Test func dailyReviewRequestUsesRecordedNutritionAndOptionalGoal() throws {
        let request = try DeepSeekClient.makeReviewRequest(records: [meal], calorieGoal: nil)
        let payload = try content(of: request)
        let meals = try #require(payload["meals"] as? [[String: Any]])
        let nutrition = try #require(meals[0]["nutrition"] as? [String: Any])
        #expect(nutrition["calories"] as? Double == 87)
        #expect(payload["calorie_goal"] == nil)
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.makeReviewRequest(records: [], calorieGoal: nil)
        }
    }

    @Test func reviewOutputSupportsUnscoredLimitedRecords() throws {
        let json = #"{"summary":"当前仅记录一餐，先回顾这餐的搭配。","score":null,"highlights":["有主食"],"suggestions":["补充蛋白质和蔬菜"]}"#
        let review = try DeepSeekClient.parseReviewResponse(data: envelope(json), statusCode: 200, date: .now, recordCount: 1)
        #expect(review.score == nil)
        #expect(review.recordCount == 1)
        #expect(review.suggestions == ["补充蛋白质和蔬菜"])
        let invalid = json.replacingOccurrences(of: "null", with: "120")
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.parseReviewResponse(data: envelope(invalid), statusCode: 200, date: .now, recordCount: 1)
        }
    }

    @Test func refinementCanReplaceTheLastRemovedFood() throws {
        var empty = meal
        empty.foods = []
        let request = try DeepSeekClient.makeRefinementRequest(record: empty, instruction: "其实只有一个鸡蛋")
        let payload = try content(of: request)
        let foods = try #require(payload["current_foods"] as? [[String: Any]])
        #expect(foods.isEmpty)
    }

    @Test func singleRecordedMealCannotReceiveWholeDayScore() throws {
        let json = #"{"summary":"仅记录一餐","score":88,"highlights":[],"suggestions":[]}"#
        let review = try DeepSeekClient.parseReviewResponse(data: envelope(json), statusCode: 200, date: .now, recordCount: 1)
        #expect(review.score == nil)
    }

    @Test func reviewKeepsTheGoalUsedForItsAnalysis() throws {
        let json = #"{"summary":"基于已记录的两餐","score":78,"highlights":[],"suggestions":[]}"#
        let review = try DeepSeekClient.parseReviewResponse(data: envelope(json), statusCode: 200,
            date: .now, recordCount: 2, calorieGoal: 1800)
        #expect(review.calorieGoal == 1800)
        #expect(review.score == 78)
        let reopened = try JSONDecoder().decode(DietReview.self, from: JSONEncoder().encode(review))
        #expect(reopened.calorieGoal == 1800)
    }
}
