import Foundation
import NutritionCore

/// 组件所需的事实从同一个自然日生成，不读取照片、AI 或同步账号。
enum WidgetSnapshotBuilder {
    static func make(document: DiaryDocument, targetCalories: Double?, on date: Date = .now,
                     calendar: Calendar = .current) -> DiaryWidgetSnapshot {
        let records = document.records(on: date, calendar: calendar)
        let nutrition = records.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let meals = WidgetMealKind.allCases.map { kind in
            let matching = records.filter { $0.kind.rawValue == kind.rawValue }
            return DiaryWidgetMeal(kind: kind,
                                   calories: matching.reduce(0) { $0 + $1.nutrition.calories },
                                   recordCount: matching.count)
        }
        let validTarget = targetCalories.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return DiaryWidgetSnapshot(calories: nutrition.calories, targetCalories: validTarget,
                                   protein: nutrition.protein, carbohydrate: nutrition.carbohydrates,
                                   fat: nutrition.fat, mealCount: records.count, updatedAt: date,
                                   meals: meals, timeZoneIdentifier: calendar.timeZone.identifier)
    }
}
