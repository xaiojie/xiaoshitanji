import NutritionCore
import SwiftUI

struct ActiveRunView: View {
    @Environment(RunTrackingModel.self) private var running
    @Environment(HealthDataModel.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmFinish = false
    @State private var heartError: String?

    var body: some View {
        if let session = running.session {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if running.recovered {
                        Label("找回了上次草稿，已暂停在最近保存的时刻。", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).padding(16).background(Theme.softYellow, in: .rect(cornerRadius: 20))
                    }
                    if session.usesGPS {
                        RunRouteMap(points: session.points, followsUser: running.isTracking)
                            .frame(height: 260).clipShape(.rect(cornerRadius: 28))
                    }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.state == .paused ? "歇一下，再出发。" : "一步一步，往前跑。").font(.headline)
                            Text(session.usesGPS ? running.locationMessage : "本次仅计时")
                                .font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                        Spacer()
                        Image(session.state == .paused ? "FitnessFrogRest" : "FitnessFrogRun")
                            .resizable().scaledToFit().frame(width: 88, height: 78).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(session.usesGPS ? RunFormat.distance(session.distanceMeters) : "—")
                                .font(.system(size: 62, weight: .heavy, design: .rounded)).monospacedDigit()
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text("公里").font(.headline)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack {
                                RunMetric(title: "运动时长", value: RunFormat.duration(session.activeSeconds(at: context.date)))
                                RunMetric(title: "当前配速", value: RunFormat.pace(session.currentPace(at: context.date)), unit: "/公里")
                            }
                        }
                        HStack {
                            RunMetric(title: "平均配速", value: RunFormat.pace(session.averagePace), unit: "/公里")
                            heartMetric(session)
                        }
                        if let target = session.targetMeters {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("目标 \(Theme.number(target / 1000, decimals: 1)) 公里")
                                    Spacer()
                                    Text(session.goalReached ? "已达成" : "还差 \(RunFormat.distance(max(0, target - session.distanceMeters))) 公里")
                                }.font(.caption.bold())
                                ProgressView(value: min(1, session.distanceMeters / target)).tint(Theme.olive)
                            }
                        }
                    }.contentCard()
                    if let heartError { Text(heartError).font(.caption).foregroundStyle(Theme.mutedInk) }
                    if let error = running.errorMessage { ErrorNotice(message: error).contentCard() }
                    if let warning = running.locationWarning {
                        Text(warning).font(.subheadline).foregroundStyle(Theme.mutedInk).contentCard()
                    }
                }.padding(20)
            }
            .background(Theme.background).navigationTitle(session.state == .paused ? "跑步已暂停" : "正在跑步")
            .safeAreaInset(edge: .bottom) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        Button {
                            if session.state == .paused { running.resume() } else { running.pause() }
                        } label: {
                            Label(session.state == .paused ? "继续" : "暂停",
                                  systemImage: session.state == .paused ? "play.fill" : "pause.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.glassProminent).tint(Theme.ink).foregroundStyle(Theme.surface)
                        if session.state == .paused {
                            Button { confirmFinish = true } label: {
                                Label("结束", systemImage: "stop.fill").font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.glassProminent).tint(Theme.accent).foregroundStyle(Theme.ink)
                        }
                    }
                }.padding(20).background(Theme.background)
            }
            .confirmationDialog("结束这次跑步？", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("结束并查看总结") { running.finish() }
                Button("继续休息", role: .cancel) { }
            }
            .alert("目标里程已完成", isPresented: Bindable(running).goalNotice) {
                Button("继续跑") { }
                Button("暂停") { running.pause() }
            } message: { Text("已经记下这一段，可以继续跑，也可以暂停后结束。") }
            .task(id: health.accessRequested) {
                while !Task.isCancelled && running.session?.state != .finished {
                    await refreshHeart()
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshHeart() } }
                else { running.checkpoint() }
            }
        }
    }

    private func heartMetric(_ session: RunSession) -> some View {
        let latest = RunHeartRateSummary.make(points: running.heartRates, session: session)?.points.last
        return VStack(alignment: .leading, spacing: 5) {
            RunMetric(title: "最近心率", value: latest.map { Theme.number($0.bpm) } ?? "—", unit: "次/分")
            if let latest {
                Text("Apple 健康 · \(latest.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
            } else {
                Text(health.accessRequested ? "等待本次测量同步" : "尚未连接 Apple 健康")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshHeart() async {
        guard let session = running.session, health.accessRequested else { return }
        do {
            let points = try await health.heartRates(for: session)
            guard !Task.isCancelled, running.session?.id == session.id else { return }
            running.heartRates = points
            heartError = nil
        } catch is CancellationError { }
        catch { heartError = "本次心率暂未刷新，跑后可以再次读取。" }
    }
}
