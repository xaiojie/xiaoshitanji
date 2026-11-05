import SwiftUI
import NutritionCore

struct GeneralSettingsView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var aiConsent = AIConsent()
    @AppStorage(AIConsent.storageKey) private var aiConsentVersion = 0
    let isPresented: Bool
    @AppStorage("dailyCalorieGoal") private var goal = 0.0
    @State private var goalEnabled = false
    @State private var goalText = ""
    @State private var errorMessage: String?
    @State private var feedback: String?
    @State private var csvText = ""
    @State private var exportingCSV = false
    @State private var exportingJSON = false
    @State private var importingJSON = false
    @State private var jsonData = Data()
    @State private var pendingRestore: DiaryDocument?
    @State private var confirmingRestore = false
    @State private var dataBusy = false
    @AppStorage("autoBackupEnabled") private var autoBackup = true
    @State private var reminders = ReminderStore.load()

    init(isPresented: Bool = false) { self.isPresented = isPresented }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: "蛙的工具箱", detail: "个人目标、提醒和本机数据，都在这里安排。")
                    aiPrivacySettings
                    goalSettings
                    healthSettings
                    reminderSettings
                    dataSettings
                    if let errorMessage { ErrorNotice(message: errorMessage).contentCard() }
                    if let feedback {
                        Label(feedback, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Theme.olive).contentCard()
                            .accessibilityIdentifier("settingsFeedback")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack(spacing: 13) {
                            Image("BrandMark").resizable().scaledToFill().frame(width: 46, height: 46)
                                .clipShape(.rect(cornerRadius: 14)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("关于小食痰记").font(.headline)
                                Text(AppInformation.versionText).font(.caption).foregroundStyle(Theme.mutedInk)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                .foregroundStyle(Theme.mutedInk)
                        }
                        .foregroundStyle(Theme.ink).contentCard()
                    }
                    .buttonStyle(.plain).disabled(dataBusy).accessibilityIdentifier("aboutApp")
                }.padding(20)
            }
            .background(Theme.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("通用设置").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(dataBusy) }
                }
            }
            .fileExporter(isPresented: $exportingCSV,
                          document: CSVFileDocument(text: csvText),
                          contentType: .commaSeparatedText,
                          defaultFilename: "小食痰记-记录") { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $exportingJSON,
                          document: JSONBackupDocument(data: jsonData), contentType: .json,
                          defaultFilename: "小食痰记-完整备份") { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .alert("恢复这份备份？", isPresented: $confirmingRestore, presenting: pendingRestore) { document in
                Button("恢复备份", role: .destructive) { restoreBackup(document) }
                Button("继续查看", role: .cancel) { pendingRestore = nil }
            } message: { document in
                Text("将恢复这份备份中的\(document.records.count)餐饮食与\(document.workouts.count)次训练，并替换当前记录。恢复前会完整保留当前数据及照片。")
            }
            .interactiveDismissDisabled(dataBusy)
            .task { await ReminderScheduler.reschedule(reminders) }
            .onAppear {
                goalEnabled = goal > 0
                goalText = goal > 0 ? String(goal) : ""
            }
        }
        .aiDataConsent(aiConsent)
    }

    private var aiPrivacySettings: some View {
        BrandSection("AI 与隐私", symbol: "hand.raised.fill") {
            LabeledContent("AI 数据授权", value: aiConsentVersion == AIConsent.currentVersion ? "已允许" : "等待确认")
            Text("使用 AI 时，本次分析所需的文字、所选照片或经你确认的健康汇总，会经小食痰记服务器转交 DeepSeek 处理。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
            if aiConsentVersion == AIConsent.currentVersion {
                Button("撤回 AI 数据授权", role: .destructive) {
                    aiConsentVersion = 0
                    feedback = "AI 数据授权已撤回，下次分析时会重新确认。"
                }
                .accessibilityIdentifier("revokeAIDataSharing")
            } else {
                Button("查看并授权") {
                    feedback = nil
                    Task {
                        do {
                            try await aiConsent.requirePermission()
                            feedback = "AI 数据授权已允许。"
                        } catch is CancellationError {
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                .disabled(aiConsent.isPresented)
                .accessibilityIdentifier("manageAIDataSharing")
            }
            Link("小食痰记隐私政策", destination: URL(string: "https://xiaoshitanji.papaclaoud.top/privacy")!)
            Link("DeepSeek 隐私政策", destination: URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!)
        }
    }

    private var goalSettings: some View {
        BrandSection("个人参考", symbol: "flag.fill") {
            Toggle("每日参考热量", isOn: $goalEnabled).tint(Theme.gold).accessibilityIdentifier("enableGoal")
            if goalEnabled {
                HStack {
                    Text("参考热量")
                    Spacer()
                    TextField("自行填写", text: $goalText).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 110).accessibilityLabel("每日参考热量")
                    Text("千卡").foregroundStyle(Theme.mutedInk)
                }
            }
            Button("保存目标", action: saveGoal).buttonStyle(.glass)
            Text("按自己的需要设置，用于对照每日记录。关闭后首页展示实际摄入。")
                .font(.caption).foregroundStyle(Theme.mutedInk)
        }
    }

    private var healthSettings: some View {
        BrandSection("Apple 健康", symbol: "heart.fill") {
            LabeledContent("访问状态", value: health.accessRequested ? "已请求访问" : "尚未连接")
            if let date = health.lastRefresh {
                LabeledContent("最近刷新", value: date.formatted(.dateTime.month().day().hour().minute()))
            }
            if health.accessRequested && !health.hasData {
                Text("暂无可读取数据。可在健康 App 的个人资料 → App → 小食痰记中检查各项访问权限。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Button(health.isLoading ? "正在读取…" : "连接 / 管理访问", systemImage: "heart") {
                Task { await health.connect() }
            }.buttonStyle(.glass).disabled(health.isLoading || !health.isAvailable)
            if health.accessRequested {
                Button("刷新健康数据", systemImage: "arrow.clockwise") { Task { await health.refresh() } }
                    .disabled(health.isLoading)
            }
            if let error = health.errorMessage { ErrorNotice(message: error) }
            Text("按所选权限读取步数、活动能量、锻炼分钟、步行跑步距离、睡眠、心率、静息心率、心率变异性、有氧适能、耳机音量、体能训练，以及体重和身高。汇总分析可以选择包含这些数值，发送前会再次确认。可在健康 App 中调整访问权限。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }
    }

    private var reminderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提醒").font(.headline)
            ForEach($reminders) { $reminder in
                HStack(spacing: 12) {
                    Image(systemName: reminder.kind.symbol)
                        .frame(width: 26).foregroundStyle(reminder.isEnabled ? Theme.accent : Theme.mutedInk)
                    Text(reminder.kind.title).font(.subheadline)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { reminder.date },
                        set: { newValue in
                            reminder.setTime(from: newValue)
                            saveReminders()
                        }
                    ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!reminder.isEnabled)
                        .accessibilityIdentifier("reminderTime-\(reminder.kind.rawValue)")
                    Toggle("", isOn: Binding(
                        get: { reminder.isEnabled },
                        set: { newValue in
                            reminder.isEnabled = newValue
                            saveReminders()
                        }
                    ))
                        .labelsHidden()
                        .accessibilityIdentifier("reminderToggle-\(reminder.kind.rawValue)")
                }
                if reminder.kind != reminders.last?.kind { Divider().opacity(0.4) }
            }
            Text("关闭后不再提醒；系统里关掉通知开关也会一并静音。")
                .font(.caption).foregroundStyle(Theme.mutedInk)
        }
        .contentCard()
    }

    private func saveReminders() {
        ReminderStore.save(reminders)
        let snapshot = reminders
        Task { await ReminderScheduler.reschedule(snapshot) }
    }

    private var dataSettings: some View {
        BrandSection("本机数据", symbol: "externaldrive.fill") {
            LabeledContent("饮食记录", value: "\(diary.document.records.count) 餐")
            Button("导出完整 JSON 备份", systemImage: "square.and.arrow.up", action: exportBackup)
                .disabled(dataBusy || diary.loadError != nil).accessibilityIdentifier("exportDiary")
            Button("从 JSON 备份恢复", systemImage: "arrow.counterclockwise") { importingJSON = true }
                .disabled(dataBusy).accessibilityIdentifier("importDiary")
            if dataBusy { ProgressView("正在处理记录和照片…").font(.caption) }
            Toggle(isOn: $autoBackup) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每天自动备份")
                    Text("保留最近 14 份，存在本机，不上传。").font(.caption).foregroundStyle(Theme.mutedInk)
                }
            }
            .accessibilityIdentifier("autoBackupToggle")
            if let date = BackupService.latestBackupDate {
                Label("最近备份：\(date.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                    .accessibilityIdentifier("latestBackup")
            }
            Button {
                csvText = DiaryCSV.document(diary.document)
                exportingCSV = true
            } label: {
                Label("导出 CSV（表格）", systemImage: "tablecells")
            }
            .disabled(diary.document.records.isEmpty)
            .accessibilityIdentifier("exportCSV")
            if let error = diary.loadError {
                ErrorNotice(message: error)
                Button("重新读取记录", action: diary.reload)
            }
            Text("导出包含饮食、照片、个人资料、手动体重、烟包、抽烟和分烟记录，以及已保存的汇总报告和分析数值。完整 JSON 包含照片内容，可在其他设备恢复。本机 FoodDiary/diary.json 使用外置 Photos 目录，需与照片一起保留。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }
    }

    private func exportBackup() {
        dataBusy = true
        errorMessage = nil
        let document = diary.document
        let photos = diary.photosDirectory
        Task { @MainActor in
            defer { dataBusy = false }
            do {
                jsonData = try await Task.detached { try DiaryBackup.data(for: document, photosDirectory: photos) }.value
                exportingJSON = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func importBackup(_ result: Result<URL, any Error>) {
        Task { @MainActor in
            dataBusy = true
            errorMessage = nil
            defer { dataBusy = false }
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let photos = diary.photosDirectory
                pendingRestore = try await Task.detached { try DiaryBackup.restore(from: url, photosDirectory: photos) }.value
                confirmingRestore = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func restoreBackup(_ document: DiaryDocument) {
        dataBusy = true
        errorMessage = nil
        let original = diary.document
        let revision = diary.revision
        let photos = diary.photosDirectory
        let directory = BackupService.directory
        let canReadOriginal = diary.loadError == nil
        pendingRestore = nil
        Task { @MainActor in
            defer { dataBusy = false }
            do {
                if canReadOriginal {
                    _ = try await Task.detached {
                        try DiaryBackup.makeRestorePoint(original, in: directory, photosDirectory: photos)
                    }.value
                }
                guard diary.revision == revision else {
                    throw DiaryError.invalidInput("本机记录刚刚发生变化，请重新选择备份并恢复。")
                }
                try diary.restoreBackup(document)
                feedback = "备份已恢复，恢复前的数据保存在本机 Backups 目录。"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func saveGoal() {
        guard !goalEnabled || (Double(goalText).map { $0.isFinite && $0 > 0 && $0 <= 100_000 } == true) else {
            errorMessage = "请填写 0 至 100,000 范围内的正数，或关闭每日参考目标。"
            feedback = nil
            return
        }
        goal = goalEnabled ? (Double(goalText) ?? 0) : 0
        errorMessage = nil
        feedback = goalEnabled ? "每日参考目标已保存。" : "每日参考目标已关闭。"
    }
}
