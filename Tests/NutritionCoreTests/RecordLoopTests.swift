import Foundation
import Testing
@testable import NutritionCore

struct RecordLoopTests {
    private func rice(grams: Double = 150) -> FoodItem {
        FoodItem(name: "米饭", grams: grams,
                 per100g: Nutrition(calories: 116, protein: 2.6, carbohydrates: 25.9, fat: 0.3),
                 portionDescription: "一小碗")
    }

    private func label() -> NutritionLabel {
        NutritionLabel(basisAmount: 100, unit: .grams, energy: 520, energyUnit: .kilocalories,
                       protein: 6, carbohydrates: 60, fat: 26, consumedAmount: 100,
                       portionIsEstimated: false)
    }

    // MARK: 手动录入

    @Test func manualInputConvertsTotalsToPerHundredGrams() throws {
        var input = ManualFoodInput()
        input.name = "便利店三明治"
        input.gramsText = "200"
        input.caloriesText = "410"
        input.proteinText = "18"
        input.carbohydratesText = "42"
        input.fatText = "19,5"
        let food = try input.food()
        #expect(food.isManual)
        #expect(food.grams == 200)
        #expect(food.nutritionLabel == nil)
        #expect(abs(food.per100g.calories - 205) < 0.0001)
        #expect(abs(food.nutrition.calories - 410) < 0.0001)
        #expect(abs(food.nutrition.fat - 19.5) < 0.0001)
    }

    @Test func manualInputDefaultsToHundredGramsWhenBlank() throws {
        var input = ManualFoodInput()
        input.name = "拿铁"
        input.caloriesText = "180"
        let food = try input.food()
        #expect(food.grams == 100)
        #expect(food.nutrition.calories == 180)
        #expect(food.portionLabel == "一份")
    }

    @Test func manualInputRejectsMissingOrInvalidValues() {
        var input = ManualFoodInput()
        input.caloriesText = "300"
        #expect(throws: DiaryError.self) { try input.food() }

        input.name = "面条"
        input.caloriesText = ""
        #expect(throws: DiaryError.self) { try input.food() }

        input.caloriesText = "300"
        input.proteinText = "-2"
        #expect(throws: DiaryError.self) { try input.food() }
    }

    @Test func manualNutritionEditKeepsIdentityAndDropsLabel() throws {
        var food = rice()
        food.nutritionLabel = label()
        let edited = try food.withManualNutrition(
            Nutrition(calories: 260, protein: 5, carbohydrates: 50, fat: 3),
            grams: 200, portionDescription: "两小碗")
        #expect(edited.id == food.id)
        #expect(edited.isManual)
        #expect(edited.nutritionLabel == nil)
        #expect(edited.portionDescription == "两小碗")
        #expect(edited.grams == 200)
        #expect(abs(edited.nutrition.calories - 260) < 0.0001)
        #expect(abs(edited.per100g.calories - 130) < 0.0001)
        #expect(throws: DiaryError.self) {
            _ = try food.withManualNutrition(Nutrition(calories: -1))
        }
    }

    // MARK: 餐内增改

    @Test func addingAndReplacingFoodsKeepsRecordValid() throws {
        var record = MealRecord(foods: [rice()], originalText: "一碗米饭", source: .photo)
        let egg = FoodItem.manual(name: "煎蛋", nutrition: Nutrition(calories: 90, protein: 7, fat: 7), grams: 50)
        try record.addFood(egg)
        #expect(record.foods.count == 2)
        #expect(throws: DiaryError.self) { try record.addFood(egg) }

        var heavier = egg
        heavier = try heavier.withManualNutrition(Nutrition(calories: 180, protein: 14, fat: 14), grams: 100)
        try record.replaceFood(heavier)
        #expect(record.foods.count == 2)
        #expect(record.adjustments?.last?.contains("煎蛋") == true)
        #expect(abs(record.nutrition.calories - 354) < 0.0001)
        #expect(throws: DiaryError.self) {
            try record.replaceFood(FoodItem(name: "不存在", grams: 10, per100g: Nutrition(calories: 1)))
        }
    }

    // MARK: 常吃组合

    @Test func templatesRoundTripAndTrackUsage() throws {
        let record = MealRecord(date: .now, kind: .breakfast, foods: [rice()], source: .photo)
        var template = MealTemplate(record: record, name: "工作日早餐")
        template.markUsed()
        template.markUsed()

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(MealTemplate.self, from: data)
        #expect(decoded.name == "工作日早餐")
        #expect(decoded.useCount == 2)
        #expect(decoded.kind == .breakfast)
        #expect(decoded.foods == record.foods)

        let made = decoded.makeRecord(on: .now, now: .now)
        #expect(made.kind == .breakfast)
        #expect(made.source == .manual)
        #expect(made.foods.map(\.name) == ["米饭"])
        #expect(made.foods[0].id != record.foods[0].id)
    }

    @Test func templatesAreValidatedAndCapped() throws {
        #expect(throws: DiaryError.self) {
            try MealTemplate(name: "  ", foods: [rice()]).validate()
        }
        #expect(throws: DiaryError.self) {
            try MealTemplate(name: "空", foods: []).validate()
        }

        var document = DiaryDocument()
        for index in 0..<55 {
            var template = MealTemplate(name: "组合\(index)", foods: [rice()])
            template.lastUsedAt = Date(timeIntervalSinceReferenceDate: Double(index))
            try document.saveTemplate(template)
        }
        #expect(document.templates.count == 50)
        let names = Set(document.templates.map(\.name))
        #expect(!names.contains("组合0"))
        #expect(names.contains("组合54"))
    }

    @Test func recentTemplatesAreSortedByUsage() throws {
        var document = DiaryDocument()
        var old = MealTemplate(name: "旧", foods: [rice()])
        old.lastUsedAt = Date(timeIntervalSinceReferenceDate: 1)
        var recent = MealTemplate(name: "新", foods: [rice()])
        recent.lastUsedAt = Date(timeIntervalSinceReferenceDate: 2)
        try document.saveTemplate(old)
        try document.saveTemplate(recent)
        #expect(document.recentTemplates().map(\.name) == ["新", "旧"])
        #expect(document.recentTemplates(limit: 1).map(\.name) == ["新"])
    }

    // MARK: 复用与搜索

    @Test func recentRecordsAndFoodSearchWorkNewestFirst() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let records = [
            MealRecord(date: yesterday, foods: [rice(), FoodItem(name: "煎蛋", grams: 50,
                                                                 per100g: Nutrition(calories: 180))]),
            MealRecord(date: now, foods: [FoodItem(name: "米饭", grams: 100,
                                                   per100g: Nutrition(calories: 116))])
        ]
        let document = DiaryDocument(records: records)
        #expect(document.recentRecords(limit: 1).map(\.date) == [now])
        #expect(document.recentRecords(limit: 5).count == 2)
        #expect(document.recentRecords(before: now).count == 1)

        let foods = document.matchingFoods()
        #expect(foods.count == 2)
        #expect(foods.first?.name == "米饭")
        #expect(foods.first?.grams == 100)
        #expect(document.matchingFoods(query: "蛋").map(\.name) == ["煎蛋"])
        #expect(document.matchingFoods(query: "米饭", limit: 1).count == 1)
        #expect(document.matchingFoods(query: "没有这个").isEmpty)
    }

    // MARK: 文档版本

    @Test func currentVersionLoadsOlderFilesAndRejectsNewerOnes() throws {
        let old = try JSONDecoder().decode(DiaryDocument.self,
                                           from: Data(#"{"schemaVersion":1,"records":[]}"#.utf8))
        #expect(old.schemaVersion == 1)
        #expect(old.templates.isEmpty)
        try old.validate()

        let current = DiaryDocument()
        #expect(current.schemaVersion == 4)
        try current.validate()

        let newer = try JSONDecoder().decode(DiaryDocument.self,
                                             from: Data(#"{"schemaVersion":5,"records":[]}"#.utf8))
        #expect(throws: DiaryError.self) { try newer.validate() }
    }

    @Test func savingAlwaysWritesCurrentSchemaVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryStore(fileURL: directory.appending(path: "diary.json"))

        var document = DiaryDocument()
        document.schemaVersion = 1
        try document.saveTemplate(MealTemplate(name: "早餐", foods: [rice()]))
        try store.save(document)

        let data = try Data(contentsOf: store.fileURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == 4)
        let reloaded = try store.load()
        #expect(reloaded.schemaVersion == 4)
        #expect(reloaded.templates.count == 1)
        #expect(reloaded.templates[0].foods[0].isManual == false)
    }

    @Test func oldFilesWithoutManualFlagStillDecode() throws {
        let food = FoodItem(name: "苹果", grams: 150, per100g: Nutrition(calories: 52))
        var data = try JSONEncoder().encode(food)
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        object?.removeValue(forKey: "isManual")
        data = try JSONSerialization.data(withJSONObject: object!)
        let decoded = try JSONDecoder().decode(FoodItem.self, from: data)
        #expect(decoded.isManual == false)
        #expect(decoded.name == "苹果")
    }
}
