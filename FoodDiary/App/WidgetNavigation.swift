import Foundation
import Observation

/// 路由由 App 持有，等现有表单正常关闭后消费，不能替换用户未保存的草稿。
@MainActor
@Observable
final class WidgetNavigation {
    private(set) var pendingRoute: DiaryWidgetRoute?

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let route = DiaryWidgetRoute(url: url) else { return false }
        pendingRoute = route
        return true
    }

    func takeRoute(canPresent: Bool) -> DiaryWidgetRoute? {
        guard canPresent else { return nil }
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
