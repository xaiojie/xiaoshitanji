import Foundation
import NutritionCore
import WidgetKit

/// 每次保存后把今日数字写进 App Group，小组件只读这一份快照。
enum WidgetSnapshotWriter {
    static func write(document: DiaryDocument, budget: EnergyBudget?, on date: Date = .now) {
        let nutrition = document.total(on: date)
        let snapshot = DiaryWidgetSnapshot(calories: nutrition.calories,
                                           targetCalories: budget?.targetCalories,
                                           protein: nutrition.protein,
                                           carbohydrate: nutrition.carbohydrates,
                                           fat: nutrition.fat,
                                           mealCount: document.records(on: date).count)
        if DiaryWidgetStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
