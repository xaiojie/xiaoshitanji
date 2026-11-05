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

    private init() {
        // App 重启后继续更新用户已开启的活动，不自动创建新的活动。
        activity = Activity<IntakeActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    var isRunning: Bool {
        guard let activity else { return false }
        return activity.activityState == .active || activity.activityState == .stale
    }

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
                                            content: Self.content(for: state),
                                            pushType: nil)
        } catch {
            errorMessage = "实时活动没启动成功，稍后再试。"
        }
    }

    func update(state: IntakeActivityAttributes.ContentState) {
        guard isRunning, let activity else { return }
        Task { await activity.update(Self.content(for: state)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private static func content(for state: IntakeActivityAttributes.ContentState) -> ActivityContent<IntakeActivityAttributes.ContentState> {
        // 系统在零点标记过期，锁屏和灵动岛不再把昨天的数字显示成今日摄入。
        .init(state: state, staleDate: DiaryWidgetTimeline.nextMidnight(after: state.updatedAt))
    }

    /// 与桌面组件共用今日快照，目标由今日页面同一套能量计算结果传入。
    static func state(for document: DiaryDocument, targetCalories: Double?, on date: Date = .now) -> IntakeActivityAttributes.ContentState {
        .init(snapshot: WidgetSnapshotBuilder.make(document: document, targetCalories: targetCalories, on: date))
    }
}
