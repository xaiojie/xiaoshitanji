import SwiftUI
import NutritionCore

struct GeneralSettingsView: View {
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

    init(isPresented: Bool = false) { self.isPresented = isPresented }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image("BrandMark").resizable().scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(.rect(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("小食痰记").font(.title2.bold())
                            Text("随手记下，好好吃饭").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    HStack {
                        Group {
                            if revealKey { TextField("填写 DeepSeek API Key", text: $apiKey) }
                            else { SecureField("填写 DeepSeek API Key", text: $apiKey) }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("deepSeekKey")
                        Button(revealKey ? "隐藏密钥" : "显示密钥", systemImage: revealKey ? "eye.slash" : "eye") {
                            revealKey.toggle()
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                    Button("保存 API Key", action: saveKey)
                        .disabled(!keyLoaded)
                        .accessibilityIdentifier("saveAPIKey")
                    LabeledContent("模型", value: DeepSeekClient.defaultModel)
                        .font(.subheadline)
                    Link("打开 DeepSeek 开放平台", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                } header: {
                    Text("DeepSeek")
                } footer: {
                    Text("Key 保存在这台 iPhone 的钥匙串中。点击饮食或烟盒的 AI 识别时，对应文字和处理后的照片会发送到 DeepSeek 官方接口，费用由你的 API 账户承担。清空后保存可移除 Key。")
                }

                Section {
                    Toggle("显示每日参考目标", isOn: $goalEnabled)
                        .accessibilityIdentifier("enableGoal")
                    if goalEnabled {
                        HStack {
                            Text("参考热量")
                            Spacer()
                            TextField("自行填写", text: $goalText)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                                .accessibilityLabel("每日参考热量")
                            Text("千卡").foregroundStyle(.secondary)
                        }
                    }
                    Button("保存目标", action: saveGoal)
                } header: {
                    Text("个人参考")
                } footer: {
                    Text("按自己的需要设置，仅用于对照每日记录。关闭后首页只展示实际摄入。")
                }

                Section {
                    LabeledContent("访问状态", value: health.accessRequested ? "已请求访问" : "尚未连接")
                    if let date = health.lastRefresh {
                        LabeledContent("最近刷新", value: date.formatted(.dateTime.month().day().hour().minute()))
                    }
                    if health.accessRequested && !health.hasData {
                        Text("暂无可读取数据。可在健康 App 的个人资料 → App → 小食痰记中检查各项访问权限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(health.isLoading ? "正在读取…" : "连接 Apple 健康 / 管理访问") {
                        Task { await health.connect() }
                    }
                    .disabled(health.isLoading || !health.isAvailable)
                    if health.accessRequested {
                        Button("刷新健康数据") { Task { await health.refresh() } }
                            .disabled(health.isLoading)
                    }
                    if let error = health.errorMessage { ErrorNotice(message: error) }
                } header: {
                    Text("Apple 健康")
                } footer: {
                    Text("按你选择的权限读取步数、活动能量、锻炼时长、步行跑步距离、体重和身高。活动能量包含运动与日常活动。读取的数据仅用于本机展示。可在健康 App 中随时调整权限。")
                }

                Section {
                    LabeledContent("已保存", value: "\(diary.document.records.count) 餐")
                    ShareLink(item: diary.fileURL) { Label("导出本机记录 JSON", systemImage: "square.and.arrow.up") }
                        .disabled(!FileManager.default.fileExists(atPath: diary.fileURL.path))
                        .accessibilityIdentifier("exportDiary")
                    if let error = diary.loadError {
                        ErrorNotice(message: error)
                        Button("重新读取记录", action: diary.reload)
                    }
                } header: {
                    Text("本机数据")
                } footer: {
                    Text("导出的 JSON 包含饮食、照片、个人资料、手动体重、烟包及抽烟和分烟记录。API Key 单独保存在钥匙串中。Apple 健康读取数据按需刷新。也可在「文件」App 的小食痰记目录中找到 FoodDiary/diary.json。")
                }

                if let errorMessage { Section { ErrorNotice(message: errorMessage) } }
                if let feedback {
                    Section {
                        Label(feedback, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("settingsFeedback")
                    }
                }

                Section {
                    LabeledContent("版本", value: "0.4.2 奶蛙版")
                    Text("描述日常份量或拍张照片，AI 会估算热量和营养。识别结果可通过自然语言或份量选项继续修正。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("通用设置")
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
            }
            .onAppear {
                loadKey()
                goalEnabled = goal > 0
                goalText = goal > 0 ? String(goal) : ""
            }
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
