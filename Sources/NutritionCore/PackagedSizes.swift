import Foundation

/// 常见包装食品的整份容量，用来把「按每 100 克估的份量」一键改成整包的量。
///
/// 只在用户确认时使用，不参与默认计算：AI 仍然要先给一个估算，这里提供的是
/// 「整桶 140 克」这种一眼能对上的候选值。
public struct PackageSizeSuggestion: Identifiable, Equatable, Sendable {
    public let title: String
    public let amount: Double
    public let unit: NutritionLabelUnit

    public var id: String { "\(title)|\(amount)|\(unit.rawValue)" }

    public init(title: String, amount: Double, unit: NutritionLabelUnit = .grams) {
        self.title = title
        self.amount = amount
        self.unit = unit
    }
}

public enum PackagedSizes {
    private struct Rule {
        let keywords: [String]
        let sizes: [PackageSizeSuggestion]
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["方便面", "泡面", "杯面", "牛肉面", "拉面", "火鸡面", "拌面", "刀削面"], sizes: [
            PackageSizeSuggestion(title: "整桶 120 克", amount: 120),
            PackageSizeSuggestion(title: "整桶 140 克", amount: 140),
            PackageSizeSuggestion(title: "整袋 105 克", amount: 105),
            PackageSizeSuggestion(title: "整袋 80 克", amount: 80)
        ]),
        Rule(keywords: ["可乐", "雪碧", "汽水", "气泡水", "果汁", "奶茶", "柠檬茶"], sizes: [
            PackageSizeSuggestion(title: "罐装 330 毫升", amount: 330, unit: .milliliters),
            PackageSizeSuggestion(title: "瓶装 500 毫升", amount: 500, unit: .milliliters),
            PackageSizeSuggestion(title: "大瓶 600 毫升", amount: 600, unit: .milliliters)
        ]),
        Rule(keywords: ["牛奶", "酸奶", "豆奶", "豆浆", "咖啡"], sizes: [
            PackageSizeSuggestion(title: "小盒 200 毫升", amount: 200, unit: .milliliters),
            PackageSizeSuggestion(title: "利乐包 250 毫升", amount: 250, unit: .milliliters),
            PackageSizeSuggestion(title: "大瓶 950 毫升", amount: 950, unit: .milliliters)
        ]),
        Rule(keywords: ["饼干", "薯片", "薯条", "坚果", "巧克力", "面包", "蛋糕"], sizes: [
            PackageSizeSuggestion(title: "小袋 40 克", amount: 40),
            PackageSizeSuggestion(title: "常规袋 70 克", amount: 70),
            PackageSizeSuggestion(title: "大袋 110 克", amount: 110)
        ])
    ]

    private static let soupKeywords = ["汤", "面", "粉", "米线", "粥", "麻辣烫", "关东煮", "馄饨", "饺子"]

    /// 按食物名给出常见整包份量的候选；没有匹配时返回空数组。
    public static func suggestions(for name: String) -> [PackageSizeSuggestion] {
        let text = name.lowercased()
        for rule in rules where rule.keywords.contains(where: { text.contains($0.lowercased()) }) {
            return rule.sizes
        }
        return []
    }

    /// 带汤的食物：默认按「固体吃完、汤不喝」折算。
    public static func isSoupy(_ name: String) -> Bool {
        let text = name.lowercased()
        return soupKeywords.contains { text.contains($0) }
    }

    /// 不喝汤时保留的能量比例：油留在汤里，营养素基本不变。
    public static let withoutSoupRatio = 0.9
}
