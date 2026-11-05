import SwiftUI
import NutritionCore

private enum ProfileSheet: String, Identifiable {
    case editor, settings, wellness, observation, sync, keepGoing, workouts
    var id: Self { self }
}

struct ProfileView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: ProfileSheet?

    private var profile: HealthProfile { diary.document.profile }
    private var latestWeight: WeightRecord? { WeightRecord.latest(in: diary.document.weights + health.weights) }
    private var height: Double? { profile.heightCM ?? health.heightCM }
    private var bmi: Double? { HealthProfile(heightCM: height).bmi(weightKG: latestWeight?.kilograms) }
    private var mealCount: Int { diary.document.records(on: .now).count }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileHeader
                    if let error = diary.loadError { ErrorNotice(message: error).contentCard() }
                    wellnessEntry
                    todayOverview
                    healthCategories
                    tools
                    healthConnection
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 22)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .editor: ProfileEditorView(profile: profile, effectiveHeight: height, weight: latestWeight, healthHeightDate: health.heightDate)
                case .settings: GeneralSettingsView(isPresented: true)
                case .wellness: WellnessReviewView()
                case .observation: ObservationView()
                case .keepGoing: KeepGoingView()
                case .workouts: WorkoutLogView()
                case .sync: CloudSyncView()
                }
            }
            .refreshable { await health.refresh() }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Button { sheet = .editor } label: {
                    HStack(spacing: 13) {
                        ProfileAvatar(data: profile.avatarJPEG, size: 66)
                            .overlay { Circle().strokeBorder(Theme.surface, lineWidth: 3) }
                        VStack(alignment: .leading, spacing: 7) {
                            Text(profile.nickname.isEmpty ? "蛙的搭子" : profile.nickname)
                                .font(.system(.title2, design: .rounded, weight: .heavy)).lineLimit(2)
                            Text("编辑个人资料").font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                    }.foregroundStyle(Theme.ink)
                }.buttonStyle(.plain).accessibilityIdentifier("editProfile")
                Spacer(minLength: 0)
                Button { sheet = .settings } label: { ObjectIcon("ProfileSettings", size: 42) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("通用设置").accessibilityIdentifier("generalSettings")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: 14) {
                headerMetric("身高", value: height, unit: "厘米")
                headerMetric("体重", value: latestWeight?.kilograms, unit: "公斤")
                headerMetric("BMI", value: bmi, unit: "自动计算")
                headerMetric("目标", value: profile.targetWeightKG, unit: "公斤")
            }
            .padding(14).background(Theme.surface.opacity(0.88), in: .rect(cornerRadius: 20))
        }
        .padding(18).background(Theme.yellowGradient, in: .rect(cornerRadius: 30))
    }

    private func headerMetric(_ title: String, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.mutedInk)
            Text(value.map { Theme.number($0, decimals: 1) } ?? "—")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.caption2).foregroundStyle(Theme.mutedInk)
        }.accessibilityElement(children: .combine)
    }

    private var wellnessEntry: some View {
        Button { sheet = .wellness } label: {
            HStack(spacing: 14) {
                ObjectIcon("MilkFrogPeek", size: 66)
                VStack(alignment: .leading, spacing: 7) {
                    Text("汇总分析").font(.headline)
                    Text("把饮食、吸烟、身体与运动，放在一起看看。")
                        .font(.caption).foregroundStyle(Theme.surface.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Theme.surface).padding(.horizontal, 17).padding(.vertical, 12)
            .background(Theme.darkGradient, in: .rect(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityIdentifier("wellnessReview")
    }

    private var todayOverview: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("今日概况", subtitle: "只看关键数字，点开查看详情")
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink { DietHealthDetailView() } label: {
                    ProfileStatTile(title: "饮食摄入", artwork: "FoodLunch",
                        value: diary.loadError == nil && mealCount > 0 ? Theme.number(diary.document.total(on: .now).calories) : "—",
                        unit: "千卡", detail: diary.loadError == nil ? (mealCount > 0 ? "已记录 \(mealCount) 餐" : "尚未记餐") : "记录读取失败")
                }.accessibilityIdentifier("profileDietIntake")
                overviewMetric(.steps)
                overviewMetric(.calories)
                overviewMetric(.sleep)
            }.buttonStyle(.plain)
        }
    }

    private func overviewMetric(_ metric: ActivityMetric) -> some View {
        NavigationLink { HealthMetricDetailView(metric: metric) } label: {
            ProfileStatTile(title: metric.title, artwork: metric.artworkName,
                value: metric.formatted(metric.value(in: health.today)), unit: metric.unit,
                detail: metric.value(in: health.today) == nil ? "等待健康数据" : "来自 Apple 健康")
        }.accessibilityIdentifier("profileOverview-\(metric.rawValue)")
    }

    private var healthCategories: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("健康档案", subtitle: "分门别类，把身体的变化慢慢看清")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ProfileHealthCategory.allCases) { category in
                    NavigationLink { ProfileHealthCategoryView(category: category) } label: {
                        ProfileCategoryTile(category: category)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("profileCategory-\(category.rawValue)")
                }
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("奶蛙的工具箱", subtitle: "记录、观察和数据管理，都在这里")
            LazyVGrid(columns: columns, spacing: 12) {
                toolButton("训练记录", detail: "力量与有氧", artwork: "HealthWorkout", destination: .workouts, identifier: "workoutsEntry")
                toolButton("蛙的观察", detail: "找模式 · 自由追问", artwork: "ProfileObservation", destination: .observation, identifier: "observationInsight")
                toolButton("奶蛙的坚持", detail: "连续记录与里程碑", artwork: "ProfileAchievement", destination: .keepGoing, identifier: "keepGoingEntry")
                NavigationLink {
                    EnergyGoalView(settings: diary.document.energy).toolbar(.visible, for: .navigationBar)
                } label: {
                    ProfileToolTile(title: "能量目标", detail: "热量与营养目标", artwork: "HealthEnergy")
                }.buttonStyle(.plain).accessibilityIdentifier("profileEnergyGoal")
                toolButton("云端同步", detail: "备份与多设备记录", artwork: "ProfileCloud", destination: .sync, identifier: "cloudSyncEntry")
                toolButton("通用设置", detail: "AI · 健康 · 数据", artwork: "ProfileSettings", destination: .settings, identifier: "profileSettingsEntry")
            }
        }
    }

    private func toolButton(_ title: String, detail: String, artwork: String,
                            destination: ProfileSheet, identifier: String) -> some View {
        Button { sheet = destination } label: { ProfileToolTile(title: title, detail: detail, artwork: artwork) }
            .buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private var healthConnection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ObjectIcon("HealthHeart", size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple 健康").font(.subheadline.bold())
                    Text(health.accessRequested ? (health.hasData ? "已连接，分类中查看详细记录" : "已请求访问，等待可读取的数据") : "连接身体、活动、睡眠与心率数据")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer(minLength: 0)
                if health.isLoading { ProgressView() }
            }
            if let error = health.errorMessage { Text(error).font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3) }
            if let refreshed = health.lastRefresh {
                Text("最近刷新 \(refreshed.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
            }
            Button(health.accessRequested ? "健康连接与数据设置" : "连接 Apple 健康") {
                if health.accessRequested { sheet = .settings }
                else { Task { await health.connect() } }
            }
            .font(.caption.weight(.semibold)).disabled(health.isLoading || !health.isAvailable)
        }
        .padding(16).background(Theme.softGreen, in: .rect(cornerRadius: 22))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(Theme.mutedInk)
        }.padding(.horizontal, 3)
    }
}

struct ProfileCategoryTile: View {
    let category: ProfileHealthCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ObjectIcon(category.artworkName, size: 64)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Text(category.title).font(.headline)
            Text(category.subtitle).font(.caption).foregroundStyle(Theme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Theme.surface, in: .rect(cornerRadius: 23))
    }
}

struct ProfileStatTile: View {
    let title: String
    let artwork: String
    let value: String
    let unit: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                ObjectIcon(artwork, size: 35)
                Text(title).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(.title2, design: .rounded, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(Theme.mutedInk)
            }
            Text(detail).font(.caption2).foregroundStyle(Theme.mutedInk).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .padding(14).background(Theme.surface, in: .rect(cornerRadius: 23))
        .accessibilityElement(children: .combine)
    }
}

struct ProfileToolTile: View {
    let title: String
    let detail: String
    let artwork: String

    var body: some View {
        HStack(spacing: 10) {
            ObjectIcon(artwork, size: 43)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(Theme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(13).background(Theme.surface, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}
