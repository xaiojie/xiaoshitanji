import SwiftUI

@main
struct FoodDiaryApp: App {
    @State private var diary = DiaryModel()
    @State private var health = HealthDataModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("饮食", systemImage: "fork.knife") { TodayView() }
                Tab("趋势", systemImage: "chart.bar.xaxis") { TrendsView() }
                Tab("戒烟", systemImage: "lungs") { SmokingView() }
                Tab("我的", systemImage: "person.crop.circle") { ProfileView() }
            }
            .tint(Theme.accent)
            .environment(diary)
            .environment(health)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .task { await health.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await health.refresh() } }
            }
        }
    }
}
