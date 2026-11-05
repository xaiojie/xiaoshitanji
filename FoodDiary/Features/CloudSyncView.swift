import SwiftUI
import NutritionCore

/// 云端同步：登录自己搭的同步服务，上传/下载整份日记，冲突自动合并。
struct CloudSyncView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var sync = SyncModel()
    @State private var username = ""
    @State private var password = ""
    @State private var confirmRestore: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: "数据放在你自己的服务器", detail: "日记以快照保存，餐食与烟盒照片独立同步并校验完整性。")
                    if sync.isLoggedIn { accountCard } else { loginForm }
                    if let error = sync.errorText ?? diary.loadError {
                        ErrorNotice(message: error).contentCard()
                    }
                    if let notice = sync.noticeText {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Theme.olive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(Theme.softGreen, in: .rect(cornerRadius: 20))
                    }
                    if sync.isLoggedIn { versionsSection }
                    Text("同步连接上方配置的服务器。密码用于登录，令牌保存在钥匙串。")
                        .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3).padding(.horizontal, 4)
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle("云端同步").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            }
            .task {
                await sync.refreshVersions()
            }
            .confirmationDialog("把第 \(confirmRestore ?? 0) 版合并回本机？",
                                isPresented: Binding(get: { confirmRestore != nil },
                                                     set: { if !$0 { confirmRestore = nil } }),
                                titleVisibility: .visible) {
                Button("恢复并合并") {
                    if let version = confirmRestore {
                        Task { await sync.restore(version: version, diary: diary) }
                    }
                    confirmRestore = nil
                }
                Button("取消", role: .cancel) { confirmRestore = nil }
            } message: {
                Text("历史内容、本机记录与云端最新记录会合并并上传。同一条记录使用本机值，恢复后的完整结果会同步到云端。")
            }
        }
    }

    // MARK: - 未登录

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("登录同步账号").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("服务器").font(.caption).foregroundStyle(Theme.mutedInk)
                TextField("https://…", text: $sync.serverText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12).background(Theme.softYellow, in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("syncServer")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("用户名").font(.caption).foregroundStyle(Theme.mutedInk)
                TextField("3–32 位小写字母、数字或 _ . - ", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12).background(Theme.softYellow, in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("syncUsername")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("密码").font(.caption).foregroundStyle(Theme.mutedInk)
                SecureField("至少 8 位", text: $password)
                    .padding(12).background(Theme.softYellow, in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("syncPassword")
            }
            HStack(spacing: 10) {
                Button("登录") {
                    Task { await sync.login(username: username, password: password, register: false) }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.ink)
                .disabled(!canSubmit)

                Button("创建账号") {
                    Task { await sync.login(username: username, password: password, register: true) }
                }
                .buttonStyle(.bordered)
                .disabled(!canSubmit)
            }
            if let label = sync.phase.label {
                HStack(spacing: 8) { ProgressView(); Text(label).font(.caption) }
                    .foregroundStyle(Theme.mutedInk)
            }
            Text("第一次用请点「创建账号」，之后在任何设备登录同一账号即可。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }.contentCard()
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 8 && sync.phase == .idle
    }

    // MARK: - 已登录

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(sync.accountName, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Spacer()
                Button("退出") { Task { await sync.logout() } }
                    .font(.subheadline).foregroundStyle(Theme.olive)
                    .disabled(sync.phase != .idle)
            }
            LabeledContent("服务器", value: sync.serverText)
                .font(.caption)
            LabeledContent("云端版本", value: "第 \(sync.lastKnownVersion) 版")
                .font(.caption)
            if let date = sync.lastSyncedAt {
                LabeledContent("上次同步", value: date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
            }
            Button {
                Task { await sync.syncNow(diary: diary) }
            } label: {
                HStack(spacing: 8) {
                    if sync.phase != .idle { ProgressView().controlSize(.small) }
                    Text(sync.phase.label ?? "立即同步")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.ink)
            .disabled(sync.phase != .idle)
            .accessibilityIdentifier("syncNow")
            Text("云端有更新版本时先合并两边记录，再上传。同一条记录使用本机值，独有条目全部保留。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }.contentCard()
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("版本历史").font(.headline)
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { Task { await sync.refreshVersions() } }
                    .labelStyle(.iconOnly).font(.subheadline).disabled(sync.phase != .idle)
            }
            if sync.versions.isEmpty {
                Text("还没有版本记录，点「立即同步」上传第一版。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            } else {
                ForEach(sync.versions) { version in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("第 \(version.version) 版").font(.subheadline.bold())
                            Text("\(version.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(version.deviceName) · \(version.sizeBytes / 1024) KB")
                                .font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                        Spacer()
                        Button("恢复") { confirmRestore = version.version }
                            .font(.caption.bold()).buttonStyle(.bordered).tint(Theme.olive)
                            .disabled(sync.phase != .idle)
                    }
                    .padding(.vertical, 6)
                    if version.id != sync.versions.last?.id { Divider() }
                }
            }
        }.contentCard()
    }
}
