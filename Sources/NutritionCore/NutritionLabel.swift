import Foundation

public enum FoodAnalysisMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic, meal, label
    public var id: Self { self }
    public var title: String {
        switch self {
        case .automatic: "自动识别"
        case .meal: "碗装餐食"
        case .label: "营养标签"
        }
    }
    var instruction: String {
        switch self {
        case .automatic: "自动判断照片是营养成分表还是实际餐食，可读营养标签优先。"
        case .meal: "本次重点分析碗装餐食，根据具体食物、碗形与盛装程度估算实际吃下的份量。"
        case .label: "本次优先读取商品营养标签，明确标签基准与食用量；如果标签只有每100克，就同时找包装上的净含量，读不到净含量时按该品类常见包装量估算整份并说明；无法读清时说明并提示补拍。"
        }
    }
}

public enum NutritionLabelUnit: String, Codable, Sendable {
    case grams = "g", milliliters = "mL", serving, package
    public var title: String {
        switch self {
        case .grams: "克"
        case .milliliters: "毫升"
        case .serving: "份"
        case .package: "包"
        }
    }
}

public enum LabelEnergyUnit: String, Codable, Sendable {
    case kilojoules = "kJ", kilocalories = "kcal"
}

public struct NutritionLabel: Codable, Equatable, Sendable {
    public var basisAmount: Double
    public var unit: NutritionLabelUnit
    public var energy: Double
    public var energyUnit: LabelEnergyUnit
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double
    public var consumedAmount: Double
    public var portionIsEstimated: Bool

    public init(basisAmount: Double, unit: NutritionLabelUnit, energy: Double, energyUnit: LabelEnergyUnit,
                protein: Double, carbohydrates: Double, fat: Double, consumedAmount: Double, portionIsEstimated: Bool) {
        self.basisAmount = basisAmount
        self.unit = unit
        self.energy = energy
        self.energyUnit = energyUnit
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.consumedAmount = consumedAmount
        self.portionIsEstimated = portionIsEstimated
    }

    public var nutrition: Nutrition {
        let calories = energyUnit == .kilojoules ? energy / 4.184 : energy
        return Nutrition(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat)
            .scaled(by: consumedAmount / basisAmount)
    }

    /// 用户手动指定「整包 / 整桶」的食用量：份量不再是估的。
    public func withConsumedAmount(_ amount: Double) -> NutritionLabel {
        var copy = self
        copy.consumedAmount = amount
        copy.portionIsEstimated = false
        return copy
    }

    public func validate() throws {
        guard basisAmount.isFinite, basisAmount > 0, consumedAmount.isFinite, consumedAmount > 0 else {
            throw DiaryError.invalidInput("营养标签的计量基准或食用份量无效，请补充描述或重新拍摄。")
        }
        try Nutrition(calories: energy, protein: protein, carbohydrates: carbohydrates, fat: fat).validate()
        try nutrition.validate()
    }
}
