import SwiftUI
import NutritionCore

/// 「蛙的观察」：本地模式识别 + 基于聚合数据的自由追问。
struct ObservationView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var aiConsent = AIConsent()
    @AppStorage("showHealthPatterns") private var showPatterns = true
    @State private var period = WellnessPeriod.week
    @State private var context: ObservationContext?
    @State private var patterns: [HealthPattern] = []
    @State private var includesHealth = false
    @State private var initialized = false
    @State private var preparing = true
    @State private var question = ""
    @State private var asking = false
    @State private var requestID: UUID?
    @State private var errorMessage: String?
    @State private var readToken: UUID?
    @FocusState private var questionFocused: Bool

    private var answers: [AnalysisAnswer] { diary.document.observations(for: period) }
    private var selectionID: String { "\(period.rawValue)-\(includesHealth)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: "问问蛙，也看看它发现的事", detail: "数字来自你的记录，解读可以追问。")
                    BrandSegments(options: WellnessPeriod.allCases.map { ($0, $0.title) }, selection: $period)
                        .disabled(requestID != nil || asking)
                    healthSelection
                    if let error = diary.loadError ?? errorMessage {
                        ErrorNotice(message: error).contentCard()
                    }
                    if preparing {
                        HStack(spacing: 12) { ProgressView(); Text("正在整理这段记录…").font(.subheadline) }
                            .contentCard()
                    }
                    if let context {
                        contextCard(context)
                        patternsSection
                        askSection(context)
                        historySection(context)
                    }
                    Text("追问只发送聚合数值，不发送照片、原始输入或昵称。回答保存在本机。")
                        .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3).padding(.horizontal, 4)
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle("蛙的观察").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await prepare() } }
                        .labelStyle(.iconOnly).disabled(preparing || asking)
                }
            }
            .onAppear {
                if !initialized { includesHealth = health.accessRequested; initialized = true }
            }
            .task(id: selectionID) { await prepare() }
            .onDisappear { readToken = nil; requestID = nil }
        }
        .aiDataConsent(aiConsent)
    }

    private var healthSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includesHealth) {
                Label("包含 Apple 健康", systemImage: "heart.fill").font(.subheadline.bold())
            }
            .tint(Theme.gold).disabled(!health.accessRequested || !health.isAvailable || asking)
            Text(health.accessRequested
                 ? "追问时会带上同范围的步数、活动能量与锻炼时长。"
                 : "目前只使用本机记录，可在通用设置里连接 Apple 健康。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }.padding(16).background(Theme.softGreen, in: .rect(cornerRadius: 22))
    }

    private func contextCard(_ context: ObservationContext) -> some View {
        let facts = context.facts
        return VStack(alignment: .leading, spacing: 12) {
            Label("这段记录", systemImage: "chart.bar.doc.horizontal").font(.headline)
            HStack(spacing: 8) {
                metric("记录", facts.meals, unit: "餐")
                metric("记录日", facts.recordedDays, unit: "天")
                metric("日均", facts.averageCalories, unit: "千卡", fraction: 0)
                metric("蛋白", facts.averageProtein, unit: "克/天", fraction: 0)
            }
            if let change = facts.weightChangeKG {
                Text("体重变化 \(String(format: "%+.1f", change)) 公斤")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            if facts.smoked > 0 {
                Text("自己抽了 \(facts.smoked) 根烟")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Text(context.evidence).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
            if !facts.gaps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(facts.gaps, id: \.self) { gap in
                        Label(gap, systemImage: "circle.dashed").font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                }
            }
        }.contentCard()
    }

    private func metric(_ title: String, _ value: Double?, unit: String, fraction: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { String(format: "%.\(fraction)f", $0) } ?? "—")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.mutedInk)
            Text(unit).font(.system(size: 9)).foregroundStyle(Theme.mutedInk.opacity(0.7))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: Int, unit: String) -> some View {
        metric(title, Double(value), unit: unit)
    }

    @ViewBuilder private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("蛙自己发现的", systemImage: "sparkle.magnifyingglass").font(.headline)
                Spacer()
                Toggle("", isOn: $showPatterns).labelsHidden().tint(Theme.gold)
                    .accessibilityLabel("显示本地模式")
            }
            if showPatterns {
                if patterns.isEmpty {
                    Text(preparing ? "正在找…" : "这段记录还没有明显的模式。多记几天再来看看。")
                        .font(.subheadline).foregroundStyle(Theme.mutedInk)
                } else {
                    ForEach(patterns) { pattern in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: pattern.symbol)
                                .font(.title3).foregroundStyle(pattern.severity == .attention ? Theme.gold : Theme.accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pattern.title).font(.subheadline.bold())
                                Text(pattern.detail).font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
                                Text(pattern.evidence).font(.caption2).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: .rect(cornerRadius: 18))
                    }
                }
            } else {
                Text("已关闭。打开后会根据记录找出蛋白、抽烟时段、断档等线索，全部在本机计算。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }.contentCard()
    }

    private func askSection(_ context: ObservationContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("问蛙", systemImage: "bubble.left.and.text.bubble.right").font(.headline)
            HStack(spacing: 8) {
                TextField("比如：晚饭怎么改？", text: $question, axis: .vertical)
                    .lineLimit(1...3).focused($questionFocused)
                    .padding(12).background(Theme.background, in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("observationQuestion")
                Button {
                    send(context)
                } label: {
                    if asking { ProgressView() } else { Image(systemName: "paperplane.fill") }
                }
                .frame(width: 44, height: 44)
                .background(Theme.gold, in: .circle)
                .foregroundStyle(Theme.ink)
                .disabled(asking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("sendObservationQuestion")
            }
            Text("回答会给出具体数字和今天能做的做法；推算会标成估算。")
                .font(.caption).foregroundStyle(Theme.mutedInk)
        }.contentCard()
    }

    private func historySection(_ context: ObservationContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !answers.isEmpty {
                Label("之前的追问", systemImage: "clock.arrow.circlepath").font(.headline)
                ForEach(answers) { answer in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(answer.question).font(.subheadline.bold())
                        Text(answer.answer).font(.subheadline).lineSpacing(4)
                        HStack(spacing: 8) {
                            Text(answer.createdAt.formatted(date: .abbreviated, time: .shortened))
                            if answer.fingerprint != context.fingerprint {
                                Text("按当时的记录").padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.gold.opacity(0.2), in: .capsule)
                            }
                        }.font(.caption2).foregroundStyle(Theme.mutedInk)
                        Text(answer.evidence).font(.caption2).foregroundStyle(Theme.accent)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: .rect(cornerRadius: 18))
                    .contextMenu {
                        Button(role: .destructive) { diary.deleteObservation(id: answer.id) } label: {
                            Label("删除这条回答", systemImage: "trash")
                        }
                    }
                }
            }
        }.contentCard()
    }

    private func send(_ context: ObservationContext) {
        guard requestID == nil else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = UUID()
        requestID = id
        asking = true
        errorMessage = nil
        questionFocused = false
        Task { @MainActor in
            defer { if requestID == id { requestID = nil; asking = false } }
            do {
                try await aiConsent.requirePermission()
                let answer = try await DeepSeekClient().ask(question: text, context: context)
                try Task.checkCancellation()
                guard requestID == id else { return }
                try diary.saveObservation(answer)
                question = ""
            } catch is CancellationError {
            } catch { if requestID == id { errorMessage = error.localizedDescription } }
        }
    }

    private func prepare() async {
        let token = UUID()
        readToken = token
        preparing = true
        errorMessage = nil
        let document = diary.document
        let date = Date.now
        let selectedPeriod = period
        let useHealth = includesHealth && health.accessRequested && health.isAvailable
        defer { if readToken == token { preparing = false } }
        do {
            guard diary.loadError == nil else { throw DiaryError.unreadableDiary }
            let data = useHealth
                ? try await health.loadWellnessData(period: selectedPeriod, document: document, endDate: date)
                : WellnessHealthData()
            try Task.checkCancellation()
            guard readToken == token else { return }
            let built = try ObservationFacts.make(
                document: document, period: selectedPeriod, endDate: date,
                activityDays: data.days, healthWeights: data.weights, healthHeightCM: data.heightCM,
                healthHeightDate: data.heightDate,
                budget: diary.energyBudget(on: date), includesHealth: useHealth)
            context = built
            patterns = HealthPatternDetector.detect(document: document, context: built, now: date)
        } catch is CancellationError {
        } catch {
            guard readToken == token else { return }
            errorMessage = useHealth
                ? "健康数据读取失败，请解锁手机后刷新。也可以关闭「包含 Apple 健康」，只用本机记录。"
                : error.localizedDescription
        }
    }
}
