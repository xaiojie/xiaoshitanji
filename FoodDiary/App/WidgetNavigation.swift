import Foundation
import Observation
import NutritionCore

struct WidgetNavigationRequest: Equatable {
    let route: DiaryWidgetRoute
    let receivedAt: Date

    func mealDraft(calendar: Calendar = .current) -> MealRecord? {
        guard route == .newMeal else { return nil }
        return MealRecord.draft(on: receivedAt, now: receivedAt, calendar: calendar)
    }
}

/// 路由由 App 持有，等现有表单正常关闭后消费，不能替换用户未保存的草稿。
@MainActor
@Observable
final class WidgetNavigation {
    private(set) var pendingRequest: WidgetNavigationRequest?
    private var isPresentingWidgetMeal = false
    var pendingRoute: DiaryWidgetRoute? { pendingRequest?.route }

    @discardableResult
    func receive(_ url: URL, at date: Date = .now) -> Bool {
        guard let route = DiaryWidgetRoute(url: url) else { return false }
        if route == .newMeal, isPresentingWidgetMeal { return true }
        if pendingRequest?.route == route { return true }
        pendingRequest = WidgetNavigationRequest(route: route, receivedAt: date)
        return true
    }

    func takeRequest(canPresent: Bool) -> WidgetNavigationRequest? {
        guard canPresent, let request = pendingRequest else { return nil }
        pendingRequest = nil
        if request.route == .newMeal { isPresentingWidgetMeal = true }
        return request
    }

    func mealPresentationEnded() {
        isPresentingWidgetMeal = false
    }
}
