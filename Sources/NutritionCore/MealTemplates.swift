import Foundation

/// 常吃组合：一组已经确认过的食物，可以一键套用到新的一餐。
public struct MealTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: MealKind?
    public var foods: [FoodItem]
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int

    public init(id: UUID = UUID(), name: String, kind: MealKind? = nil, foods: [FoodItem],
                createdAt: Date = .now, lastUsedAt: Date = .now, useCount: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.foods = foods
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    public init(record: MealRecord, name: String? = nil, now: Date = .now) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(name: trimmed.isEmpty ? record.foodNames : trimmed, kind: record.kind,
                  foods: record.foods, createdAt: now, lastUsedAt: now)
    }

    public mutating func markUsed(now: Date = .now) {
        lastUsedAt = now
        useCount += 1
    }

    /// 套用时生成新的记录与食物身份，避免和历史记录共用 id。
    public func makeRecord(on day: Date, kind: MealKind? = nil, now: Date = .now,
                           calendar: Calendar = .current) -> MealRecord {
        var record = MealRecord.draft(on: day, kind: kind ?? self.kind, now: now, calendar: calendar)
        record.foods = foods.map { food in
            var copy = food
            copy.id = UUID()
            return copy
        }
        record.source = .manual
        record.summary = "常吃组合「\(name)」"
        record.originalText = ""
        record.assumptions = []
        record.adjustments = nil
        return record
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiaryError.invalidInput("常吃组合需要有一个名字。")
        }
        guard !foods.isEmpty && foods.count <= 50 else {
            throw DiaryError.invalidInput("常吃组合需要包含 1 至 50 种食物。")
        }
        guard Set(foods.map(\.id)).count == foods.count else {
            throw DiaryError.invalidInput("常吃组合里的食物重复了，请重新保存。")
        }
        for food in foods { try food.validate() }
    }
}

/// 手动录入表单的纯数据部分：解析、校验、折算都在这里完成，界面只负责输入。
public struct ManualFoodInput: Sendable {
    public var name: String
    public var portionDescription: String
    public var gramsText: String
    public var caloriesText: String
    public var proteinText: String
    public var carbohydratesText: String
    public var fatText: String

    public init(name: String = "", portionDescription: String = "", gramsText: String = "",
                caloriesText: String = "", proteinText: String = "", carbohydratesText: String = "",
                fatText: String = "") {
        self.name = name
        self.portionDescription = portionDescription
        self.gramsText = gramsText
        self.caloriesText = caloriesText
        self.proteinText = proteinText
        self.carbohydratesText = carbohydratesText
        self.fatText = fatText
    }

    public init(food: FoodItem) {
        let nutrition = food.nutrition
        self.init(name: food.name,
                  portionDescription: food.portionDescription ?? "",
                  gramsText: HealthMeasurementInput.format(food.grams),
                  caloriesText: HealthMeasurementInput.format(nutrition.calories),
                  proteinText: HealthMeasurementInput.format(nutrition.protein),
                  carbohydratesText: HealthMeasurementInput.format(nutrition.carbohydrates),
                  fatText: HealthMeasurementInput.format(nutrition.fat))
    }

    public var isEmpty: Bool {
        [name, portionDescription, gramsText, caloriesText, proteinText, carbohydratesText, fatText]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 克数留空时按 100 克处理：用户只填了「这一份 520 千卡」也能直接记录。
    public func food() throws -> FoodItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DiaryError.invalidInput("请填写食物名称。")
        }
        guard let calories = try HealthMeasurementInput.parse(caloriesText), calories >= 0, calories.isFinite else {
            throw DiaryError.invalidInput("请填写这一份的热量（千卡）。")
        }
        let grams = try HealthMeasurementInput.parse(gramsText) ?? 100
        guard grams > 0, grams.isFinite else {
            throw DiaryError.invalidInput("克数需要大于 0。")
        }
        let nutrition = Nutrition(
            calories: calories,
            protein: try decimal(proteinText),
            carbohydrates: try decimal(carbohydratesText),
            fat: try decimal(fatText))
        try nutrition.validate()
        let portion = portionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = FoodItem.manual(name: trimmedName, nutrition: nutrition, grams: grams,
                                   portionDescription: portion.isEmpty ? nil : portion)
        try food.validate()
        return food
    }

    private func decimal(_ text: String) throws -> Double {
        guard let value = try HealthMeasurementInput.parse(text) else { return 0 }
        guard value >= 0, value.isFinite else {
            throw DiaryError.invalidInput("营养值不能是负数。")
        }
        return value
    }
}
