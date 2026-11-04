import SwiftUI
import NutritionCore

struct WellnessReviewView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyCalorieGoal") private var calorieGoal = 0.0
    @State private var period = WellnessPeriod.week
    @State private var includesHealth = false
    @State private var initialized = false
    @State private var snapshot: WellnessSummary?
    @State private var preparing = false
    @State private var readToken: UUID?
    @State private var requestID: UUID?
    @State private var reviewTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showingData = false
    @State private var confirmingSend = false
    @State private var pendingSummary: WellnessSummary?

    private var report: WellnessReview? { diary.document.wellnessReviews.first { $0.snapshot.period == period } }
    private var selectionID: String { "\(period.rawValue)-\(includesHealth)-\(calorieGoal)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: "把记录放在一起看看", detail: "吃的、抽的、动的，还有身体的变化。")
                    BrandSegments(options: WellnessPeriod.allCases.map { ($0, $0.title) }, selection: $period)
                        .disabled(requestID != nil)
                    healthSelection
                    if let error = diary.loadError ?? errorMessage {
                        ErrorNotice(message: error).contentCard()
                        Button("打开通用设置", systemImage: "gearshape") { showingSettings = true }.font(.subheadline)
                    }
                    if preparing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在按所选日期整理记录…").font(.subheadline)
                        }.contentCard()
                    }
                    if let report { WellnessReportCards(report: report) }
                    if let snapshot {
                        if report != nil {
                            DisclosureGroup("本次待分析的数据", isExpanded: $showingData) {
                                WellnessSnapshotCards(snapshot: snapshot).padding(.top, 16)
                            }.font(.headline)
                        } else {
                            WellnessSnapshotCards(snapshot: snapshot)
                        }
                        if !snapshot.hasData {
                            Text("先记一餐、一次身体测量，或连接健康数据，再来看看整体情况。")
                                .font(.subheadline).foregroundStyle(Theme.mutedInk).contentCard()
                        }
                    }
                    Text("生成前会确认发送范围。汇总数值与报告保存在本机，并随记录 JSON 导出。")
                        .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3).padding(.horizontal, 4)
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle("汇总分析").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { cancelReview(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新汇总数据", systemImage: "arrow.clockwise") { Task { await prepare() } }
                        .labelStyle(.iconOnly).disabled(preparing || requestID != nil)
                }
            }
            .safeAreaInset(edge: .bottom) { primaryAction }
            .sheet(isPresented: $showingSettings, onDismiss: { Task { await prepare() } }) {
                GeneralSettingsView(isPresented: true)
            }
            .alert("生成汇总分析？", isPresented: $confirmingSend, presenting: pendingSummary) { summary in
                Button("发送并生成") { generate(summary) }
                Button("继续查看", role: .cancel) { pendingSummary = nil }
            } message: { summary in
                Text("将\(summary.period.title)的饮食、吸烟和身体测量汇总\(summary.includesHealth ? "，以及可读取的 Apple 健康活动数值" : "数值")发送给 DeepSeek。费用由你的 API 账户承担。生成后保存这次报告和汇总数值。")
            }
            .onAppear {
                if !initialized { includesHealth = health.accessRequested; initialized = true }
            }
            .task(id: selectionID) { await prepare() }
            .refreshable { await prepare() }
            .onDisappear { readToken = nil; cancelReview() }
        }
    }

    private var healthSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includesHealth) {
                Label("包含 Apple 健康", systemImage: "heart.fill").font(.subheadline.bold())
            }
            .tint(Theme.gold).disabled(!health.accessRequested || !health.isAvailable || requestID != nil)
            Text(health.accessRequested ? "读取同一日期范围内的步数、活动能量、锻炼时长、距离，以及身体测量。" : "目前使用本机记录，可在通用设置中连接 Apple 健康。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }.padding(16).background(Theme.softGreen, in: .rect(cornerRadius: 22))
    }

    private var primaryAction: some View {
        VStack(spacing: 10) {
            if requestID != nil {
                HStack {
                    ProgressView()
                    Text("AI 正在综合分析这些记录…").font(.caption)
                    Spacer()
                    Button("取消", action: cancelReview).font(.caption)
                }
            }
            Button {
                pendingSummary = snapshot
                confirmingSend = true
            } label: {
                Label(report == nil ? "生成汇总分析" : "根据最新数据重新分析", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .yellowAction().disabled(preparing || requestID != nil || snapshot?.hasData != true || diary.loadError != nil)
            .accessibilityIdentifier("generateWellnessReview")
        }.padding(.horizontal, 20).padding(.vertical, 12).background(Theme.background)
    }

    private func prepare() async {
        let token = UUID()
        readToken = token
        preparing = true
        snapshot = nil
        errorMessage = nil
        let document = diary.document
        let date = Date.now
        let selectedPeriod = period
        let useHealth = includesHealth && health.accessRequested && health.isAvailable
        defer { if readToken == token { preparing = false } }
        do {
            guard diary.loadError == nil else { throw DiaryError.unreadableDiary }
            let data = useHealth ? try await health.loadWellnessData(period: selectedPeriod, document: document, endDate: date) : WellnessHealthData()
            try Task.checkCancellation()
            guard readToken == token else { return }
            snapshot = try WellnessSummary.make(document: document, period: selectedPeriod, endDate: date,
                activityDays: data.days, healthWeights: data.weights, healthHeightCM: data.heightCM,
                healthHeightDate: data.heightDate, calorieGoal: calorieGoal > 0 ? calorieGoal : nil,
                earliestHealthDate: data.earliestDate, includesHealth: useHealth)
        } catch is CancellationError {
        } catch {
            guard readToken == token else { return }
            errorMessage = useHealth ? "汇总数据读取失败，请解锁手机后刷新重试。也可以关闭「包含 Apple 健康」，仅分析本机记录。" : error.localizedDescription
        }
    }

    private func generate(_ summary: WellnessSummary) {
        guard requestID == nil else { return }
        let id = UUID()
        requestID = id
        errorMessage = nil
        pendingSummary = nil
        reviewTask = Task { @MainActor in
            defer { if requestID == id { requestID = nil } }
            do {
                let key = try KeychainStore.load()
                let result = try await DeepSeekClient().reviewWellness(summary: summary, apiKey: key)
                try Task.checkCancellation()
                guard requestID == id else { return }
                try diary.saveWellnessReview(result)
            } catch is CancellationError {
            } catch { if requestID == id { errorMessage = error.localizedDescription } }
        }
    }

    private func cancelReview() { requestID = nil; reviewTask?.cancel() }
}
