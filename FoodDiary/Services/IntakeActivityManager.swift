@preconcurrency import ActivityKit
import Foundation
import NutritionCore
import Observation

/// 灵动岛 / 锁屏的「今日摄入」实时活动；只在用户主动打开时运行。
@MainActor
@Observable
final class IntakeActivityManager {
    static let shared = IntakeActivityManager()

    private(set) var activity: Activity<IntakeActivityAttributes>?
    private(set) var errorMessage: String?

    var isRunning: Bool { activity != nil }

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(state: IntakeActivityAttributes.ContentState) {
        errorMessage = nil
        guard activitiesEnabled else {
            errorMessage = "系统设置里没有允许实时活动。"
            return
        }
        end()
        do {
            activity = try Activity.request(attributes: IntakeActivityAttributes(),
                                            content: .init(state: state, staleDate: nil),
                                            pushType: nil)
        } catch {
            errorMessage = "实时活动没启动成功，稍后再试。"
        }
    }

    func update(state: IntakeActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    /// 从本地文档里取今天的状态。
    static func state(for document: DiaryDocument, budget: EnergyBudget?, on date: Date = .now) -> IntakeActivityAttributes.ContentState {
        let nutrition = document.total(on: date)
        return .init(calories: nutrition.calories, targetCalories: budget?.targetCalories,
                     mealCount: document.records(on: date).count)
    }
}
