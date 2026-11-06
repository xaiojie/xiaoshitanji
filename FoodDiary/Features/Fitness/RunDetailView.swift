import Charts
import NutritionCore
import SwiftUI

struct RunDetailView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(RunTrackingModel.self) private var running
    @Environment(\.dismiss) private var dismiss
    @State private var record: RunRecord
    @State private var notes = ""
    @State private var effort = 0
    @State private var errorMessage: String?
    @State private var readingHeart = false
    @State private var confirmDelete = false
    @State private var includeHeart = false
    @State private var includeDiet = true
    @State private var advice: RunAdvice?
    @State private var aiConsent = AIConsent()
    @State private var analysisTask: Task<Void, Never>?
    @State private var requestID: UUID?
    @AppStorage(AIConsent.storageKey) private var consentVersion = 0

    init(record: RunRecord) { _record = State(initialValue: record) }

    private var workout: WorkoutRecord? { diary.document.workouts.first { $0.id == record.id } }
    private var isDraft: Bool { running.session?.id == record.id }
    private var canDelete: Bool { workout != nil || isDraft || running.pendingRemovals.contains(record.id) }
    private var weight: Double? {
        diary.document.weights.filter { $0.date <= record.session.startedAt }.max { $0.date < $1.date }?.kilograms
    }
    private var matches: [HealthWorkout] {
        guard let workout else { return [] }
        return WorkoutTimeline.candidates(for: workout, health: health.workouts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RunFrogHeader(title: workout == nil ? "跑完，喝口水。" : "这一程，记下了。",
                    detail: record.session.startedAt.formatted(date: .abbreviated, time: .shortened),
                    artwork: "FitnessFrogFinish")
                if !record.session.points.isEmpty {
                    RunRouteMap(points: record.session.points)
                        .frame(height: 250).clipShape(.rect(cornerRadius: 26))
                    Text("地图按暂停与定位中断分段显示，精确轨迹保存在本机。")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                summary
                if !record.session.splits.isEmpty { splits }
                heart
                if workout != nil || isDraft { feelings }
                if !matches.isEmpty { healthLink }
                if workout != nil { analysis }
                if let errorMessage { ErrorNotice(message: errorMessage).contentCard() }
                if canDelete {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text(workout == nil ? "放弃这次草稿" : "删除这次跑步").frame(maxWidth: .infinity, minHeight: 44)
                    }.padding(.top, 8)
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("跑步总结").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if workout != nil || isDraft {
                Button(action: save) {
                    Text(isDraft ? "保存这次跑步" : "保存体感与备注")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.glassProminent).tint(Theme.ink).foregroundStyle(Theme.surface)
                .disabled(readingHeart || diary.loadError != nil)
                .padding(20).background(Theme.background)
            }
        }
        .confirmationDialog(workout == nil ? "放弃草稿及本次轨迹？" : "删除跑步记录及本机轨迹？",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("确认删除", role: .destructive, action: delete)
            Button("保留", role: .cancel) { }
        }
        .onAppear {
            notes = workout?.notes ?? ""
            effort = workout?.perceivedEffort ?? 0
        }
        .task { if health.accessRequested { await refreshHeart() } }
        .onChange(of: includeHeart) { _, _ in cancelAnalysis() }
        .onChange(of: includeDiet) { _, _ in cancelAnalysis() }
        .onChange(of: diary.revision) { _, _ in cancelAnalysis() }
        .onChange(of: consentVersion) { _, value in if value != AIConsent.currentVersion { cancelAnalysis() } }
        .onDisappear { cancelAnalysis() }
        .aiDataConsent(aiConsent)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                RunMetric(title: "有效距离", value: record.session.usesGPS ? RunFormat.distance(record.session.distanceMeters) : "—", unit: "公里")
                RunMetric(title: "运动时长", value: RunFormat.duration(record.session.activeSeconds(at: record.session.lastCheckpoint)))
            }
            HStack {
                RunMetric(title: "平均配速", value: RunFormat.pace(record.session.averagePace), unit: "/公里")
                RunMetric(title: "估算活动消耗", value: (workout?.effectiveCalories ?? record.session.estimatedCalories(weightKG: weight))
                    .map { Theme.number($0) } ?? "—", unit: "千卡")
            }
            if let target = record.session.targetMeters {
                Label("目标 \(Theme.number(target / 1000, decimals: 1)) 公里 · " + (record.session.goalReached ? "已完成" : "本次已结束"),
                      systemImage: record.session.goalReached ? "checkmark.seal.fill" : "flag")
                    .font(.subheadline).foregroundStyle(Theme.olive)
            }
            if weight == nil && workout?.effectiveCalories == nil {
                Text("记录体重后，可按距离估算活动消耗。").font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }.contentCard()
    }

    private var splits: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("每公里分段").font(.headline)
            ForEach(record.session.splits) { split in
                HStack {
                    Text(split.distanceMeters >= 999 ? "第 \(split.kilometer) 公里" : "最后 \(RunFormat.distance(split.distanceMeters)) 公里")
                    Spacer()
                    Text(RunFormat.pace(split.pace) + " /公里").monospacedDigit().bold()
                }.font(.subheadline)
                if split.id != record.session.splits.last?.id { Divider() }
            }
        }.contentCard()
    }

    private var heart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("本次跑步心率", systemImage: "heart.fill").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                if readingHeart { ProgressView() }
                else {
                    Button("刷新") { Task { await refreshHeart() } }
                        .font(.subheadline.bold()).disabled(!health.accessRequested)
                }
            }
            if let summary = record.heartRate {
                HStack {
                    RunMetric(title: "样本平均", value: Theme.number(summary.average), unit: "次/分")
                    RunMetric(title: "样本最高", value: Theme.number(summary.maximum), unit: "次/分")
                }
                if summary.points.count > 1 {
                    Chart(summary.points) { point in
                        LineMark(x: .value("时间", point.date), y: .value("心率", point.bpm))
                            .foregroundStyle(Theme.gold).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartYScale(domain: .automatic(includesZero: false)).frame(height: 150)
                    .accessibilityLabel("本次跑步心率曲线")
                }
                Text("Apple 健康 · \(summary.source)\n\(summary.points.count) 次测量，最近一次 \(summary.points.last!.date.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                Text("统计覆盖已返回的有效运动时段样本，设备同步后可再次刷新。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            } else {
                Text("尚无本次运动期间的可用心率。佩戴支持的设备并同步到 Apple 健康后，可在这里刷新。")
                    .font(.subheadline).foregroundStyle(Theme.mutedInk)
                if !health.accessRequested {
                    Button("连接 Apple 健康") { Task { await health.connect(); await refreshHeart() } }.yellowAction()
                }
            }
        }.contentCard()
    }

    private var feelings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今天跑起来怎么样？").font(.headline)
            Picker("体感", selection: $effort) {
                Text("未记录").tag(0)
                Text("轻松").tag(2)
                Text("适中").tag(5)
                Text("吃力").tag(8)
            }.pickerStyle(.segmented)
            TextField("记一句感受，可不填", text: $notes, axis: .vertical).lineLimit(2...4)
                .padding(12).background(Theme.background, in: .rect(cornerRadius: 14))
                .onChange(of: notes) { _, value in if value.count > 500 { notes = String(value.prefix(500)) } }
        }.contentCard()
    }

    private var healthLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("核对 Apple 健康来源").font(.headline)
            Text("同一场运动关联后在运动列表合并展示。").font(.caption).foregroundStyle(Theme.mutedInk)
            Picker("对应的训练", selection: $record.linkedHealthWorkoutID) {
                Text("按时间与距离自动识别").tag(nil as UUID?)
                ForEach(matches) { value in
                    Text("\(value.title) · \(value.date.formatted(date: .omitted, time: .shortened)) · \(value.durationMinutes) 分钟")
                        .tag(value.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: record.linkedHealthWorkoutID) { _, _ in
                do { try running.save(record, preservingDetails: false) } catch { errorMessage = error.localizedDescription }
            }
        }.contentCard()
    }

    private var analysis: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("奶蛙跑后建议", systemImage: "sparkles").font(.headline)
            Toggle("参考当日已记录饮食与体重", isOn: $includeDiet).tint(Theme.olive)
            Toggle("包含本次心率统计", isOn: $includeHeart).tint(Theme.olive)
                .disabled(record.heartRate == nil || requestID != nil)
            Text("发送本次距离、时长、配速、目标，以及你选中的营养与心率统计，经小食痰记后端交给 DeepSeek 解读。")
                .font(.caption).foregroundStyle(Theme.mutedInk)
            Button(action: analyze) {
                HStack {
                    if requestID != nil { ProgressView() }
                    Text(requestID == nil ? "分析这次跑步" : "奶蛙正在看记录…")
                }.frame(maxWidth: .infinity, minHeight: 40)
            }
            .yellowAction().disabled(requestID != nil || readingHeart)
            if let advice {
                Text(advice.summary).font(.subheadline).lineSpacing(4)
                ForEach(Array(advice.suggestions.enumerated()), id: \.offset) { _, text in
                    Label(text, systemImage: "checkmark.circle").font(.subheadline)
                }
                ForEach(Array(advice.limitations.enumerated()), id: \.offset) { _, text in
                    Text(text).font(.caption).foregroundStyle(Theme.mutedInk)
                }
            }
        }.contentCard()
    }

    private func save() {
        do {
            record = try running.save(record)
            let summary = try record.workout(weightKG: weight, notes: notes, effort: effort == 0 ? nil : effort)
            try diary.saveWorkout(summary)
            if isDraft { try running.completeSave() }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete() {
        do {
            try running.beginRemoval(id: record.id)
            if let workout { try diary.deleteWorkout(workout) }
            try running.remove(id: record.id)
            if isDraft { try running.discard() }
            dismiss()
        } catch { errorMessage = "删除尚未完成，可再次操作。\(error.localizedDescription)" }
    }

    private func refreshHeart() async {
        guard !readingHeart, health.accessRequested else { return }
        readingHeart = true
        defer { readingHeart = false }
        do {
            let samples = try await health.heartRates(for: record.session)
            try Task.checkCancellation()
            guard !samples.isEmpty else {
                if record.heartRate != nil {
                    errorMessage = "本次没有读到新的心率，已保留原测量。请确认设备同步及健康访问权限。"
                }
                return
            }
            record.heartRates = samples
            cancelAnalysis()
            if var current = workout {
                try running.save(record)
                current.cardio?.averageHeartRate = record.heartRate.flatMap {
                    (30...240).contains($0.average) ? Int($0.average.rounded()) : nil
                }
                current.runMetrics = current.runMetrics?.updatingHeartRate(record.heartRate)
                try diary.saveWorkout(current)
            }
        } catch is CancellationError { }
        catch { errorMessage = "心率暂未刷新，已有记录仍可查看。请解锁设备后重试。" }
    }

    private func analyze() {
        cancelAnalysis()
        let id = UUID()
        requestID = id
        errorMessage = nil
        analysisTask = Task { @MainActor in
            defer { if requestID == id { requestID = nil } }
            do {
                try await aiConsent.requirePermission()
                try Task.checkCancellation()
                guard requestID == id, workout != nil else { return }
                let revision = diary.revision
                let context = RunAnalysisContext(record: record, document: diary.document,
                    includesHeartRate: includeHeart, includesDietAndBody: includeDiet)
                let result = try await DeepSeekClient().analyzeRun(context)
                try Task.checkCancellation()
                guard requestID == id, revision == diary.revision, aiConsent.isAuthorized else { return }
                advice = result
            } catch is CancellationError { }
            catch { if requestID == id { errorMessage = error.localizedDescription } }
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        requestID = nil
        advice = nil
        aiConsent.cancelPending()
    }
}
