import Foundation
import NutritionCore
import WidgetKit

/// 每次保存后把今日数字写进 App Group，小组件只读这一份快照。
enum WidgetSnapshotWriter {
    static func write(document: DiaryDocument, targetCalories: Double?, on date: Date = .now) {
        let snapshot = WidgetSnapshotBuilder.make(document: document, targetCalories: targetCalories, on: date)
        if DiaryWidgetStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
