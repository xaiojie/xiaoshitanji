import NutritionCore
import SwiftUI
import UIKit

struct RunFlowView: View {
    @Environment(RunTrackingModel.self) private var running
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let session = running.session {
                    if session.state == .finished {
                        RunDetailView(record: running.pendingRecord ?? RunRecord(session: session))
                    } else {
                        ActiveRunView()
                    }
                } else {
                    RunSetupView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(running.session == nil ? "关闭" : "收起") { dismiss() }
                }
            }
        }
        .tint(Theme.ink).foregroundStyle(Theme.ink).background(Theme.background)
        .onChange(of: running.session?.id) { old, new in
            if old != nil && new == nil { dismiss() }
        }
    }
}

private enum RunMode: String { case free, target }

struct RunSetupView: View {
    @Environment(RunTrackingModel.self) private var running
    @Environment(HealthDataModel.self) private var health
    @State private var mode = RunMode.free
    @State private var kilometers = "5"
    @State private var usesGPS = true
    @State private var countdown: Int?
    @State private var startTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var targetFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RunFrogHeader(title: "先伸个懒腰。", detail: "按自己的节奏，跑一段就记一段。", artwork: "FitnessFrogStretch")
                RunRouteMap(points: [], followsUser: running.locationAllowed)
                    .frame(height: 180).clipShape(.rect(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 14) {
                    BrandSegments(options: [(RunMode.free, "自由跑"), (.target, "目标跑")], selection: $mode)
                    if mode == .target {
                        HStack(alignment: .firstTextBaseline) {
                            TextField("目标公里数", text: $kilometers).keyboardType(.decimalPad)
                                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                                .focused($targetFocused).accessibilityIdentifier("runTargetKilometers")
                            Text("公里").font(.headline).foregroundStyle(Theme.mutedInk)
                        }
                        HStack(spacing: 12) {
                            ForEach(["3", "5", "10"], id: \.self) { value in
                                Button("\(value) 公里") { kilometers = value; targetFocused = false }.buttonStyle(.bordered)
                            }
                        }
                        Text("到达目标时提醒，之后可以继续跑或结束。").font(.caption).foregroundStyle(Theme.mutedInk)
                    } else {
                        Text("距离随你，记录每一步。").font(.subheadline).foregroundStyle(Theme.mutedInk)
                    }
                }.contentCard().disabled(countdown != nil)
                VStack(alignment: .leading, spacing: 12) {
                    Label(running.locationMessage, systemImage: running.gpsReady ? "location.fill" : "location.slash")
                        .font(.subheadline).foregroundStyle(running.gpsReady ? Theme.olive : Theme.mutedInk)
                    if !running.gpsReady {
                        Button(running.locationAllowed ? "重新定位 / 开启精确位置" : "允许定位") { running.prepare() }
                            .buttonStyle(.bordered)
                        if running.authorization == .denied || running.authorization == .restricted {
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                    if mode == .free {
                        Toggle("使用 GPS 记录距离与路线", isOn: $usesGPS).tint(Theme.olive)
                        if !usesGPS { Text("本次保存运动时长和可用心率。").font(.caption).foregroundStyle(Theme.mutedInk) }
                    }
                }.contentCard()
                HStack(alignment: .top, spacing: 12) {
                    ObjectIcon("HealthHeart", size: 36)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("一起记下心率").font(.headline)
                        Text("读取手表或手环同步到 Apple 健康的测量，显示测量时间，跑后可刷新补齐。")
                            .font(.caption).foregroundStyle(Theme.mutedInk)
                        if !health.accessRequested {
                            Button("连接 Apple 健康") { Task { await health.connect() } }.font(.subheadline.bold())
                        }
                    }
                }.contentCard()
                Text("开始后会使用后台定位，在锁屏或切换应用时继续记录。原始路线保存在本机，跑步结束后停止定位。")
                    .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
                if let error = errorMessage ?? running.errorMessage { ErrorNotice(message: error) }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("准备跑步")
        .safeAreaInset(edge: .bottom) {
            Button(action: beginCountdown) {
                Text(countdown.map { "准备出发 · \($0)" } ?? "开始跑步")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glassProminent).tint(Theme.ink).foregroundStyle(Theme.surface)
            .disabled(countdown != nil || running.archiveError != nil)
            .padding(20).background(Theme.background)
        }
        .onAppear { running.prepare() }
        .onChange(of: mode) { _, value in if value == .target { usesGPS = true } }
        .onDisappear {
            startTask?.cancel()
            running.stopPreparing()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { targetFocused = false } }
        }
    }

    private func beginCountdown() {
        targetFocused = false
        errorMessage = nil
        do {
            let target = mode == .target ? try RunSession.targetMeters(from: kilometers) : nil
            guard !usesGPS || running.gpsReady else { throw DiaryError.invalidInput(running.locationMessage) }
            startTask = Task { @MainActor in
                do {
                    for value in (1...3).reversed() {
                        if value == 3, target != nil {
                            countdown = value
                            await running.requestGoalNotifications()
                            try Task.checkCancellation()
                        }
                        countdown = value
                        try await Task.sleep(for: .seconds(1))
                    }
                    try Task.checkCancellation()
                    try running.start(targetMeters: target, usesGPS: usesGPS)
                } catch is CancellationError { }
                catch { errorMessage = error.localizedDescription }
                countdown = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
