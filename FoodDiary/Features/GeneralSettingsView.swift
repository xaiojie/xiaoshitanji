import SwiftUI
import NutritionCore

struct GeneralSettingsView: View {
    /// 直接读 Bundle 里的版本，避免这里写死后和实际安装包对不上。
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "版本 \(short) (\($0))" } ?? "版本 \(short)"
    }

    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(\.dismiss) private var dismiss
    let isPresented: Bool
    @AppStorage("dailyCalorieGoal") private var goal = 0.0
    @State private var apiKey = ""
    @State private var revealKey = false
    @State private var keyLoaded = false
    @State private var goalEnabled = false
    @State private var goalText = ""
    @State private var errorMessage: String?
    @State private var feedback: String?
    @State private var csvText = ""
    @State private var exportingCSV = false
    @AppStorage("autoBackupEnabled") private var autoBackup = true
    @State private var reminders = ReminderStore.load()

    init(isPresented: Bool = false) { self.isPresented = isPresented }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: "蛙的工具箱", detail: "AI、个人目标和数据，都在这里安排。")
                    apiSettings
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
                    HStack(spacing: 13) {
                        Image("BrandMark").resizable().scaledToFill().frame(width: 46, height: 46)
                            .clipShape(.rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("小食痰记").font(.headline)
                            Text(versionText).font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                    }.frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
                }.padding(20)
            }
            .background(Theme.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("通用设置").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
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
            .task { await ReminderScheduler.reschedule(reminders) }
            .onAppear {
                loadKey()
                goalEnabled = goal > 0
                goalText = goal > 0 ? String(goal) : ""
            }
        }
    }

    private var apiSettings: some View {
        BrandSection("DeepSeek", symbol: "sparkles") {
            HStack(spacing: 6) {
                Group {
                    if revealKey { TextField("填写 API Key", text: $apiKey) }
                    else { SecureField("填写 API Key", text: $apiKey) }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("deepSeekKey")
                Button(revealKey ? "隐藏密钥" : "显示密钥", systemImage: revealKey ? "eye.slash" : "eye") {
                    revealKey.toggle()
                }.labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 44, height: 44)
            }
            .padding(.leading, 13).background(Theme.softYellow.opacity(0.35), in: .rect(cornerRadius: 15))
            LabeledContent("当前模型", value: DeepSeekClient.defaultModel).foregroundStyle(Theme.mutedInk)
            Button { saveKey() } label: {
                Label("保存 API Key", systemImage: "key.fill").frame(maxWidth: .infinity, minHeight: 38)
            }.yellowAction().disabled(!keyLoaded).accessibilityIdentifier("saveAPIKey")
            Link(destination: URL(string: "https://platform.deepseek.com/api_keys")!) {
                Label("打开 DeepSeek 开放平台", systemImage: "arrow.up.right.square").font(.caption)
            }
            Text("密钥保存在这台 iPhone 的钥匙串。饮食和烟盒识别会发送对应文字及处理后的照片，汇总分析在确认后发送所选数据的汇总数值。调用费用由你的 API 账户承担。清空后保存可移除密钥。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
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
            ShareLink(item: diary.fileURL) { Label("导出记录 JSON", systemImage: "square.and.arrow.up") }
                .disabled(!FileManager.default.fileExists(atPath: diary.fileURL.path)).accessibilityIdentifier("exportDiary")
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
            Text("导出包含饮食、照片、个人资料、手动体重、烟包、抽烟和分烟记录，以及已保存的汇总报告和分析数值。API Key 保存在钥匙串。也可在「文件」App 中找到小食痰记的 FoodDiary/diary.json。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }
    }

    private func loadKey() {
        do {
            apiKey = try KeychainStore.load()
            keyLoaded = true
        } catch {
            keyLoaded = false
            errorMessage = error.localizedDescription
        }
    }

    private func saveKey() {
        do {
            try KeychainStore.save(apiKey)
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            feedback = apiKey.isEmpty ? "API Key 已移除，已有饮食记录保留在本机。" : "API Key 已保存，可前往「饮食」分析这一餐。"
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription; feedback = nil }
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
