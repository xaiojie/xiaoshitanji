import SwiftUI

@main
struct FoodDiaryApp: App {
    @State private var diary = DiaryModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("今天", systemImage: "calendar") { TodayView() }
                Tab("趋势", systemImage: "chart.bar.xaxis") { TrendsView() }
                Tab("我的", systemImage: "person.crop.circle") { SettingsView() }
            }
            .tint(Theme.accent)
            .environment(diary)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}
