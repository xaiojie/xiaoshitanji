import Foundation
import Testing
@testable import NutritionCore

@Suite("CSV 导出")
struct DiaryCSVTests {
    private func document() -> DiaryDocument {
        var document = DiaryDocument(records: [
            MealRecord(date: Date(timeIntervalSince1970: 1_700_000_000), kind: .lunch,
                       foods: [
                        .manual(name: "米饭, 一碗", nutrition: Nutrition(calories: 232, protein: 4, carbohydrates: 52, fat: 0.6),
                                grams: 150, portionDescription: "一碗"),
                        .manual(name: "带\"引号\"的菜", nutrition: Nutrition(calories: 100, protein: 10, carbohydrates: 5, fat: 4),
                                grams: 100)
                       ], source: .manual, summary: "自己做的\n两行备注")
        ])
        document.weights = [WeightRecord(date: Date(timeIntervalSince1970: 1_700_000_000), kilograms: 70.4)]
        return document
    }

    @Test("餐次表包含表头与逐食物行")
    func exportsMeals() {
        let csv = DiaryCSV.meals(document())
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.first == DiaryCSV.mealsHeader)
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("2023-11-1"))
        #expect(lines[1].contains("午餐"))
        #expect(lines[1].contains("232"))
        #expect(lines[1].contains("52.0"))
    }

    @Test("逗号、引号与换行会加引号转义")
    func escapesFields() {
        let csv = DiaryCSV.meals(document())
        #expect(csv.contains("\"米饭, 一碗\""))
        #expect(csv.contains("\"带\"\"引号\"\"的菜\""))
        #expect(csv.contains("\"自己做的\n两行备注\""))
    }

    @Test("公式开头的字段会加单引号，纯数字保持原样")
    func escapesFormulaInjection() {
        let diary = DiaryDocument(records: [
            MealRecord(foods: [.manual(name: "=1+1", nutrition: Nutrition(calories: 100))]),
            MealRecord(foods: [.manual(name: "-3.5", nutrition: Nutrition(calories: 200))]),
        ])
        let csv = DiaryCSV.meals(diary)
        // Excel/Numbers 会把 = 开头的单元格当公式执行。
        #expect(csv.contains("'=1+1"))
        // 数值列里的负数不是公式，保持原样交给表格软件解析。
        #expect(csv.contains(",-3.5,"))
    }

    @Test("体重与抽烟表")
    func exportsWeightsAndSmoking() throws {
        var document = document()
        try document.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试烟"),
                                                   openedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try document.smoking.record(.smoked, count: 1, date: Date(timeIntervalSince1970: 1_700_000_500))

        let weights = DiaryCSV.weights(document)
        #expect(weights.contains(DiaryCSV.weightsHeader))
        #expect(weights.contains("70.4"))
        #expect(weights.contains("手动"))

        let smoking = DiaryCSV.smoking(document)
        #expect(smoking.contains(DiaryCSV.smokingHeader))
        #expect(smoking.contains("自己抽了"))
        #expect(smoking.contains("测试烟"))
    }

    @Test("文件名与写盘")
    func writesFile() throws {
        let url = try DiaryCSV.write(document())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent.hasSuffix(".csv"))
        #expect(url.lastPathComponent.hasPrefix("小食痰记-记录-"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(DiaryCSV.mealsHeader))
    }

    @Test("空文档只有表头")
    func emptyDocument() {
        let empty = DiaryDocument()
        #expect(DiaryCSV.meals(empty).components(separatedBy: "\r\n").filter { !$0.isEmpty } == [DiaryCSV.mealsHeader])
        #expect(DiaryCSV.document(empty).contains(DiaryCSV.smokingHeader))
    }
}
