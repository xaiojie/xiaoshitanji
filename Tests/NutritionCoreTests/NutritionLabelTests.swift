import Foundation
import Testing
@testable import NutritionCore

struct NutritionLabelTests {
    @Test func kilojoulesAndMillilitersUseLabelBasisLocally() throws {
        let label = NutritionLabel(basisAmount: 100, unit: .milliliters, energy: 418.4, energyUnit: .kilojoules,
            protein: 3, carbohydrates: 12, fat: 2, consumedAmount: 250, portionIsEstimated: false)
        try label.validate()
        #expect(abs(label.nutrition.calories - 250) < 0.00001)
        #expect(label.nutrition.protein == 7.5)
        let food = FoodItem(name: "牛奶", grams: 250, per100g: .zero, nutritionLabel: label)
        let half = try food.scaledPortion(by: 0.5, description: "喝了一半")
        #expect(abs(half.nutrition.calories - 125) < 0.00001)
        #expect(half.nutritionLabel?.consumedAmount == 125)
    }

    @Test func servingAndPackageLabelsPreserveBasisAndRejectInvalidAmounts() throws {
        var label = NutritionLabel(basisAmount: 1, unit: .serving, energy: 200, energyUnit: .kilocalories,
            protein: 4, carbohydrates: 30, fat: 7, consumedAmount: 2, portionIsEstimated: false)
        #expect(label.nutrition.calories == 400)
        label.unit = .package
        label.consumedAmount = 0.5
        #expect(label.nutrition.calories == 100)
        label.basisAmount = 0
        #expect(throws: DiaryError.self) { try label.validate() }
    }

    @Test func labelResponseUsesRawLabelValuesInsteadOfAIGuessedDensity() throws {
        let content = #"{"summary":"半包饼干","assumptions":[],"foods":[{"name":"饼干","portionDescription":"半包","grams":50,"per100g":{"calories":999,"protein":0,"carbohydrates":0,"fat":0},"nutritionLabel":{"basisAmount":1,"unit":"package","energy":400,"energyUnit":"kcal","protein":6,"carbohydrates":60,"fat":15,"consumedAmount":0.5,"portionIsEstimated":false}}]}"#
        let result = try DeepSeekClient.parseResponse(data: response(content), statusCode: 200)
        #expect(result.foods[0].nutrition.calories == 200)
        #expect(result.foods[0].per100g.calories == 400)
        #expect(result.foods[0].nutritionLabel?.unit == .package)
        let reopened = try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(result.foods[0]))
        #expect(reopened.nutrition.calories == 200)
    }

    @Test func foodModesCarryBowlAndLabelInstructionsThroughRefinement() throws {
        let request = try DeepSeekClient.makeRequest(text: "一碗米饭", imageJPEG: nil, mode: .meal)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("碗"))
        #expect(body.contains("4.184"))
        let record = MealRecord(foods: [FoodItem(name: "米饭")], analysisMode: .label)
        let refinement = try DeepSeekClient.makeRefinementRequest(record: record, instruction: "只喝一半")
        #expect(String(decoding: try #require(refinement.httpBody), as: UTF8.self).contains("营养标签"))
    }

    @Test func modeChangeInvalidatesAnEarlierAnalysisAndRefinementCarriesLabelBasis() throws {
        let label = NutritionLabel(basisAmount: 100, unit: .grams, energy: 400, energyUnit: .kilocalories,
            protein: 5, carbohydrates: 50, fat: 20, consumedAmount: 50, portionIsEstimated: false)
        var record = MealRecord(foods: [FoodItem(name: "饼干", nutritionLabel: label)], originalText: "吃半包", source: .photo)
        let request = try DeepSeekClient.makeRefinementRequest(record: record, instruction: "再吃四分之一包")
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self).contains("nutritionLabel"))
        record.updateInput(text: record.originalText, photoJPEG: record.photoJPEG, analysisMode: .label)
        #expect(record.foods.isEmpty)
        #expect(record.analysisMode == .label)
    }

    @Test func refinementCannotLoseAnExistingLabelWhenResponseOmitsIt() throws {
        let label = NutritionLabel(basisAmount: 100, unit: .milliliters, energy: 418.4, energyUnit: .kilojoules,
            protein: 3, carbohydrates: 12, fat: 2, consumedAmount: 250, portionIsEstimated: false)
        let milk = FoodItem(name: "牛奶", grams: 250, nutritionLabel: label)
        let record = MealRecord(foods: [milk], source: .photo)
        let content = #"{"summary":"喝半盒","assumptions":[],"foods":[{"name":"牛奶","grams":125,"per100g":{"calories":999,"protein":0,"carbohydrates":0,"fat":0}}]}"#
        let result = try DeepSeekClient.parseRefinementResponse(data: response(content), statusCode: 200, record: record)
        #expect(result.foods[0].id == milk.id)
        #expect(result.foods[0].nutritionLabel?.consumedAmount == 125)
        #expect(abs(result.foods[0].nutrition.calories - 125) < 0.00001)
    }

    @Test func choosingAWholePackageClearsTheEstimatedFlag() throws {
        let label = NutritionLabel(basisAmount: 100, unit: .grams, energy: 1955, energyUnit: .kilojoules,
            protein: 7.6, carbohydrates: 55.8, fat: 23.7, consumedAmount: 100, portionIsEstimated: true)
        let whole = label.withConsumedAmount(140)
        #expect(whole.portionIsEstimated == false)
        #expect(whole.consumedAmount == 140)
        #expect(abs(whole.nutrition.calories - 654.1) < 0.5)
    }

    private func response(_ content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]])
    }
}
