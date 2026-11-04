import SwiftUI
import NutritionCore

struct SettingsView: View {
    @Environment(DiaryModel.self) private var diary
    @AppStorage("dailyCalorieGoal") private var goal = 0.0
    @State private var apiKey = ""
    @State private var revealKey = false
    @State private var keyLoaded = false
    @State private var goalEnabled = false
    @State private var goalText = ""
    @State private var errorMessage: String?
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 30)).foregroundStyle(Theme.accent)
                            .frame(width: 58, height: 58)
                            .background(Theme.sage.opacity(0.15), in: .rect(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("食记").font(.title2.bold())
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
                    Text("Key 保存在这台 iPhone 的钥匙串中。点击 AI 分析时，输入的饮食文字与压缩后的照片会发送到 DeepSeek 官方接口，费用由你的 API 账户承担。清空后保存可移除 Key。")
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
                    LabeledContent("已保存", value: "\(diary.document.records.count) 餐")
                    ShareLink(item: diary.fileURL) { Label("导出饮食记录 JSON", systemImage: "square.and.arrow.up") }
                        .disabled(!FileManager.default.fileExists(atPath: diary.fileURL.path))
                        .accessibilityIdentifier("exportDiary")
                    if let error = diary.loadError {
                        ErrorNotice(message: error)
                        Button("重新读取记录", action: diary.reload)
                    }
                } header: {
                    Text("本机数据")
                } footer: {
                    Text("饮食记录与照片保存在本机。导出的 JSON 包含完整记录和照片，不包含 API Key。也可在「文件」App 的食记目录中找到 FoodDiary/diary.json。")
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
                    LabeledContent("版本", value: "0.1.0 MVP")
                    Text("AI 营养数值为估算，可在保存前修改食物、重量和每 100 克营养。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我的")
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
            feedback = apiKey.isEmpty ? "API Key 已移除，仍可手动记餐。" : "API Key 已保存，可前往「今天」分析饮食。"
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
