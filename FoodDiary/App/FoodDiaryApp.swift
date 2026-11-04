import SwiftUI

@main
struct FoodDiaryApp: App {
    @State private var diary = DiaryModel()
    @State private var health = HealthDataModel()
    @State private var selectedTab = AppTab.diet
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoBackupEnabled") private var autoBackup = true

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    Tab("饮食", systemImage: "fork.knife", value: AppTab.diet) { TodayView().toolbar(.hidden, for: .tabBar) }
                    Tab("趋势", systemImage: "chart.bar.xaxis", value: AppTab.trends) { TrendsView().toolbar(.hidden, for: .tabBar) }
                    Tab("戒烟", systemImage: "lungs", value: AppTab.smoking) { SmokingView().toolbar(.hidden, for: .tabBar) }
                    Tab("我的", systemImage: "person.crop.circle", value: AppTab.profile) { ProfileView().toolbar(.hidden, for: .tabBar) }
                }
                BrandTabBar(selection: $selectedTab)
            }
            .background(Theme.background).tint(Theme.ink).foregroundStyle(Theme.ink)
            .preferredColorScheme(.light)
            .environment(diary)
            .environment(health)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .task {
                await health.refresh()
                if autoBackup { BackupService.backupIfNeeded(diary.document) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await health.refresh() }
                    if autoBackup { BackupService.backupIfNeeded(diary.document) }
                }
            }
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case diet, trends, smoking, profile
    var id: Self { self }
    var title: String {
        switch self {
        case .diet: "饮食"
        case .trends: "趋势"
        case .smoking: "戒烟"
        case .profile: "我的"
        }
    }
    var symbol: String {
        switch self {
        case .diet: "fork.knife"
        case .trends: "chart.bar.xaxis"
        case .smoking: "lungs"
        case .profile: "person.crop.circle"
        }
    }
}

private struct BrandTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 5) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { selection = tab }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol).font(.system(size: 21, weight: .medium))
                            Text(tab.title).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background {
                            if selection == tab { Capsule().fill(Theme.yellowGradient).shadow(color: Theme.gold.opacity(0.20), radius: 3, y: 2) }
                        }
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("tab-\(tab.rawValue)")
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(6).glassEffect(.regular.tint(Theme.softYellow.opacity(0.28)), in: .capsule)
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 5)
    }
}
