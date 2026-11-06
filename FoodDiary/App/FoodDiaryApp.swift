import SwiftUI

@main
struct FoodDiaryApp: App {
    @State private var diary = DiaryModel()
    @State private var health = HealthDataModel()
    @State private var running = RunTrackingModel()
    @State private var selectedTab = AppTab.diet
    @State private var widgetNavigation = WidgetNavigation()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoBackupEnabled") private var autoBackup = true
    @AppStorage("dailyCalorieGoal") private var referenceCalorieGoal = 0.0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("饮食", systemImage: "fork.knife", value: AppTab.diet) { TodayView() }
                Tab("趋势", systemImage: "chart.bar.xaxis", value: AppTab.trends) { TrendsView() }
                Tab("健身", systemImage: "figure.run", value: AppTab.fitness) { FitnessView() }
                Tab("戒烟", systemImage: "lungs", value: AppTab.smoking) { SmokingView() }
                Tab("我的", systemImage: "person.crop.circle", value: AppTab.profile) { ProfileView() }
            }
            // iOS 26 的液态玻璃标签栏，向下一滑就收成一条玻璃。
            .tabBarMinimizeBehavior(.onScrollDown)
            .background(Theme.background).tint(Theme.ink).foregroundStyle(Theme.ink)
            .preferredColorScheme(.light)
            .environment(diary)
            .environment(health)
            .environment(running)
            .environment(widgetNavigation)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .onAppear {
                #if DEBUG
                // 真机截图与演示时可显式指定起始页面。
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count,
                   let tab = AppTab(rawValue: arguments[index + 1]) {
                    selectedTab = tab
                }
                #endif
            }
            .task { await refreshAppData() }
            .onOpenURL { url in
                if widgetNavigation.receive(url) { selectedTab = .diet }
            }
            .onChange(of: referenceCalorieGoal) { _, _ in refreshWidgets() }
            .onChange(of: health.lastRefresh) { _, _ in refreshWidgets() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                Task { await refreshAppData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await refreshAppData() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { running.checkpoint() }
                if phase == .active {
                    running.refreshMotionAuthorization()
                    Task {
                        await refreshAppData()
                    }
                }
            }
        }
    }

    private func refreshWidgets() {
        diary.refreshWidgetSnapshot(healthWorkoutCalories: health.workoutTotals(on: .now).calories)
    }

    private func refreshAppData() async {
        await health.refresh()
        refreshWidgets()
        if autoBackup { await BackupService.backupIfNeeded(diary.document) }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case diet, trends, fitness, smoking, profile
    var id: Self { self }
    var title: String {
        switch self {
        case .diet: "饮食"
        case .trends: "趋势"
        case .fitness: "健身"
        case .smoking: "戒烟"
        case .profile: "我的"
        }
    }
    var symbol: String {
        switch self {
        case .diet: "fork.knife"
        case .trends: "chart.bar.xaxis"
        case .fitness: "figure.run"
        case .smoking: "lungs"
        case .profile: "person.crop.circle"
        }
    }
}
