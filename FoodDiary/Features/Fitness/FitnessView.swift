import NutritionCore
import SwiftUI

struct FitnessView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(RunTrackingModel.self) private var running
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRun = false
    @State private var showManual = false
    @State private var showSummary = false
    @State private var selectedDay: Date?
    @State private var today = Date.now
    @State private var errorMessage: String?
    @State private var preserveDraft = false

    private var entries: [WorkoutTimelineEntry] { fitnessEntries(diary: diary, health: health, running: running) }
    private var week: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var weeklyRuns: [WorkoutTimelineEntry] {
        guard let start = week.first, let last = week.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return [] }
        return entries.filter { $0.isRunning && $0.date >= start && $0.date < end }
    }
    private var visibleEntries: [WorkoutTimelineEntry] {
        let values = selectedDay.map { day in entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) } } ?? entries
        return Array(values.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    if let error = diary.loadError ?? running.archiveError ?? errorMessage {
                        ErrorNotice(message: error).contentCard()
                    }
                    if running.archiveError != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("重新读取跑步草稿") { running.reloadArchive() }
                            Button("保留异常草稿并重新开始") { preserveDraft = true }
                        }.contentCard()
                    }
                    if let warning = running.archiveWarning {
                        Text(warning).font(.caption).foregroundStyle(Theme.mutedInk).contentCard()
                    }
                    if !running.pendingRemovals.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("还有 \(running.pendingRemovals.count) 条跑步待清理").font(.headline)
                            Text("已申请删除的本机路线会在完成清理后移除。").font(.caption).foregroundStyle(Theme.mutedInk)
                            Button("完成删除") {
                                do { try running.retryRemovals(diary: diary) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }.contentCard()
                    }
                    HStack {
                        Text(selectedDay.map { $0.formatted(.dateTime.month().day()) + "的运动" } ?? "最近运动")
                            .font(.title2.bold())
                        Spacer()
                        NavigationLink { WorkoutHistoryView() } label: { Label("全部", systemImage: "chevron.right") }
                            .font(.subheadline).foregroundStyle(Theme.mutedInk)
                    }
                    if visibleEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(selectedDay == nil ? "从第一次跑步开始" : "这天还没有运动记录").font(.headline)
                            Text("带上手机，奶蛙陪你记下每一公里。")
                                .font(.subheadline).foregroundStyle(Theme.mutedInk)
                            if selectedDay != nil { Button("查看最近记录") { selectedDay = nil } }
                        }.contentCard()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(visibleEntries) { entry in
                                WorkoutEntryLink(entry: entry)
                                if entry.id != visibleEntries.last?.id { Divider().padding(.leading, 76) }
                            }
                        }
                        .padding(.horizontal, 16).background(Theme.surface, in: .rect(cornerRadius: 28))
                    }
                    advice
                    Text("GPS 轨迹和详细心率保存在这台设备，运动摘要可随日记同步。")
                        .font(.caption).foregroundStyle(Theme.mutedInk).padding(.horizontal, 4)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button { showRun = true } label: {
                    Label(running.session == nil ? "开始跑步" : "查看本次跑步",
                          systemImage: running.session == nil ? "figure.run" : "location.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.glassProminent).tint(Theme.ink).foregroundStyle(Theme.surface)
                .disabled(diary.loadError != nil || running.archiveError != nil)
                .padding(.horizontal, 24).padding(.vertical, 8).background(Theme.background.opacity(0.94))
            }
            .fullScreenCover(isPresented: $showRun) { RunFlowView() }
            .sheet(isPresented: $showManual) {
                WorkoutEditorView(workout: nil, onSave: { workout in
                    do { try diary.saveWorkout(workout) } catch { errorMessage = error.localizedDescription }
                }, onSavePlan: { plan in
                    do { try diary.savePlan(plan) } catch { errorMessage = error.localizedDescription }
                })
            }
            .sheet(isPresented: $showSummary) { WellnessReviewView() }
            .confirmationDialog("保留异常草稿并重新开始？", isPresented: $preserveDraft, titleVisibility: .visible) {
                Button("保留原文件并重新开始") {
                    do { try running.preserveUnreadableDraft() }
                    catch { errorMessage = error.localizedDescription }
                }
                Button("稍后处理", role: .cancel) { }
            } message: {
                Text("原草稿会以恢复副本保存在本机，随后可以开始新的跑步。")
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = .now } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = .now }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("健身").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    Text(today.formatted(.dateTime.month().day().weekday(.wide))).font(.subheadline.bold())
                }
                Spacer()
                Menu {
                    Button("补记运动", systemImage: "plus") { showManual = true }
                    NavigationLink("训练与计划") { WorkoutLogView() }
                    Button("连接或刷新 Apple 健康", systemImage: "heart") {
                        Task { if health.accessRequested { await health.refresh() } else { await health.connect() } }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.title3.bold()).frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("健身选项")
            }
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("本周，慢慢来。").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(weeklyRuns.count)").font(.system(size: 52, weight: .heavy, design: .rounded))
                        Text("次跑步").font(.subheadline.bold())
                    }
                    Text("累计 \(RunFormat.distance(weeklyRuns.reduce(0) { $0 + ($1.distanceMeters ?? 0) })) 公里")
                        .font(.subheadline.bold())
                    Text("\(weeklyRuns.reduce(0) { $0 + $1.minutes }) 分钟")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    Text("歇会儿，也算正事。").font(.caption.bold()).padding(10)
                        .background(Theme.surface, in: .rect(cornerRadius: 16))
                    Image("FitnessFrogRest").resizable().scaledToFit()
                        .frame(width: 158, height: 150).accessibilityHidden(true)
                }
            }
            HStack(spacing: 3) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                    let completed = entries.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
                    let selected = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? Calendar.current.isDate(date, inSameDayAs: today)
                    Button {
                        selectedDay = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ? nil : date
                    } label: {
                        VStack(spacing: 7) {
                            Text(["一", "二", "三", "四", "五", "六", "日"][index]).font(.caption)
                            Text("\(Calendar.current.component(.day, from: date))").font(.headline)
                            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                .font(.caption).foregroundStyle(completed ? Theme.olive : Theme.mutedInk.opacity(0.25))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(selected ? Theme.softYellow : .clear, in: .capsule)
                    }
                    .buttonStyle(.plain).disabled(Calendar.current.startOfDay(for: date) > today)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (completed ? "，有运动记录" : ""))
                }
            }.padding(8).background(Theme.surface.opacity(0.9), in: .rect(cornerRadius: 24))
        }
        .padding(20).background(Theme.yellowGradient, in: .rect(cornerRadius: 32))
    }

    private var advice: some View {
        Button { showSummary = true } label: {
            HStack(spacing: 14) {
                Image("MilkFrogPortrait").resizable().scaledToFit().frame(width: 66, height: 68).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("奶蛙陪你看变化").font(.headline)
                    Text(weeklyRuns.isEmpty ? "先记一次，慢慢积累自己的节奏。"
                         : "这周记录了 \(weeklyRuns.count) 次跑步，点开一起看看饮食与运动。")
                        .font(.caption).foregroundStyle(Theme.mutedInk).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption)
            }
            .padding(16).frame(maxWidth: .infinity).background(Theme.softGreen, in: .rect(cornerRadius: 24))
        }.buttonStyle(.plain)
    }
}

@MainActor
func fitnessEntries(diary: DiaryModel, health: HealthDataModel, running: RunTrackingModel) -> [WorkoutTimelineEntry] {
    let links = Dictionary(uniqueKeysWithValues: running.records.compactMap { record in
        record.linkedHealthWorkoutID.map { (record.id, $0) }
    })
    return WorkoutTimeline.make(local: diary.document.workouts, health: health.workouts, links: links)
}

private struct WorkoutEntryLink: View {
    @Environment(RunTrackingModel.self) private var running
    let entry: WorkoutTimelineEntry

    var body: some View {
        NavigationLink {
            if let local = entry.local, let run = running.records.first(where: { $0.id == local.id }) {
                RunDetailView(record: run)
            } else {
                WorkoutSummaryDetail(entry: entry)
            }
        } label: {
            HStack(spacing: 14) {
                ObjectIcon(entry.isRunning ? "HealthShoe" : "HealthWorkout", size: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title).font(.headline)
                    Text(entry.date.formatted(.dateTime.month().day().hour().minute())).font(.caption).foregroundStyle(Theme.mutedInk)
                    Text("\(entry.minutes) 分钟" + (entry.distanceMeters.map { " · \(RunFormat.distance($0)) 公里" } ?? ""))
                        .font(.subheadline.bold())
                    Text(entry.needsReview ? "来源可能重复，请点开核对" : entry.sourceText)
                        .font(.caption2).foregroundStyle(Theme.mutedInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.mutedInk)
            }.padding(.vertical, 18).foregroundStyle(Theme.ink)
        }.buttonStyle(.plain)
    }
}

private struct WorkoutHistoryView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(RunTrackingModel.self) private var running

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(fitnessEntries(diary: diary, health: health, running: running)) { entry in
                    WorkoutEntryLink(entry: entry)
                    Divider()
                }
                Text("本机运动显示全部记录，Apple 健康显示最近 7 天已读取的数据。")
                    .font(.caption).foregroundStyle(Theme.mutedInk).padding(.vertical, 20)
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("运动记录").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct WorkoutSummaryDetail: View {
    @Environment(DiaryModel.self) private var diary
    let entry: WorkoutTimelineEntry
    @State private var editing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RunFrogHeader(title: entry.title, detail: entry.sourceText, artwork: "FitnessFrogFinish")
                HStack {
                    RunMetric(title: "运动时长", value: "\(entry.minutes)", unit: "分钟")
                    RunMetric(title: "距离", value: entry.distanceMeters.map(RunFormat.distance) ?? "—", unit: "公里")
                }.contentCard()
                HStack {
                    RunMetric(title: "运动消耗", value: entry.calories.map { Theme.number($0) } ?? "—", unit: "千卡")
                    RunMetric(title: "平均心率", value: entry.averageHeartRate.map { Theme.number($0) } ?? "—", unit: "次/分")
                }.contentCard()
                Text("此记录提供运动摘要，GPS 路线可在原记录设备的跑步详情中查看。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                if entry.local != nil && entry.local?.runMetrics == nil {
                    Button("编辑本机记录") { editing = true }.yellowAction()
                }
                if let errorMessage { ErrorNotice(message: errorMessage) }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("运动详情").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $editing) {
            WorkoutEditorView(workout: entry.local, onSave: { workout in
                do { try diary.saveWorkout(workout) } catch { errorMessage = error.localizedDescription }
            }, onSavePlan: { plan in
                do { try diary.savePlan(plan) } catch { errorMessage = error.localizedDescription }
            })
        }
    }
}
