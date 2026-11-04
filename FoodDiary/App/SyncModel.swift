import Foundation
import Observation
import NutritionCore
import UIKit

@MainActor
@Observable
final class SyncModel {
    enum Phase: Equatable {
        case idle
        case busy(String)

        var label: String? {
            if case .busy(let text) = self { return text }
            return nil
        }
    }

    private(set) var session: CloudSyncSession?
    private(set) var phase = Phase.idle
    private(set) var versions: [CloudSyncVersion] = []
    private(set) var lastSyncedAt: Date?
    private(set) var lastKnownVersion: Int
    var serverText: String
    var errorText: String?
    var noticeText: String?

    private let defaults = UserDefaults.standard

    private enum Key {
        static let server = "sync.server"
        static let version = "sync.knownVersion"
        static let lastSynced = "sync.lastSyncedAt"
    }

    private var deviceName: String {
        let name = UIDevice.current.name
        return name.isEmpty ? "iPhone" : name
    }

    private var isBusy: Bool { phase != .idle }

    init() {
        self.session = SyncCredentialStore.load()
        self.serverText = defaults.string(forKey: Key.server) ?? CloudSyncClient.defaultServerURL.absoluteString
        self.lastKnownVersion = defaults.integer(forKey: Key.version)
        self.lastSyncedAt = defaults.object(forKey: Key.lastSynced) as? Date
    }

    var isLoggedIn: Bool { session != nil }

    var accountName: String { session?.username ?? "" }

    private func client() throws -> CloudSyncClient {
        let url = try CloudSyncClient.normalizedBaseURL(serverText)
        return CloudSyncClient(baseURL: url)
    }

    private func persist(session: CloudSyncSession) {
        self.session = session
        try? SyncCredentialStore.save(session)
        defaults.set(serverText, forKey: Key.server)
        setKnownVersion(session.version)
    }

    private func setKnownVersion(_ version: Int) {
        lastKnownVersion = version
        defaults.set(version, forKey: Key.version)
    }

    private func markSynced() {
        lastSyncedAt = .now
        defaults.set(lastSyncedAt, forKey: Key.lastSynced)
    }

    private func run(_ label: String, _ work: () async throws -> Void) async {
        guard !isBusy else { return }
        phase = .busy(label)
        errorText = nil
        noticeText = nil
        do {
            try await work()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        phase = .idle
    }

    // MARK: - 账号

    func login(username: String, password: String, register: Bool) async {
        await run(register ? "正在注册…" : "正在登录…") {
            let client = try client()
            let session = register
                ? try await client.register(username: username, password: password, deviceName: deviceName)
                : try await client.login(username: username, password: password, deviceName: deviceName)
            persist(session: session)
            noticeText = register ? "账号已创建，可以开始同步了。" : "已登录 \(session.username)。"
        }
    }

    func logout() async {
        guard let token = session?.token else {
            SyncCredentialStore.clear()
            session = nil
            return
        }
        let client: CloudSyncClient? = try? client()
        await run("正在退出…") {
            try? await client?.logout(token: token)
            SyncCredentialStore.clear()
            session = nil
            versions = []
            noticeText = "已退出登录，本机数据不受影响。"
        }
    }

    // MARK: - 同步

    func syncNow(diary: DiaryModel) async {
        guard let token = session?.token else {
            errorText = CloudSyncError.notLoggedIn.errorDescription
            return
        }
        await run("正在同步…") {
            let client = try client()
            let state = try await client.state(token: token)
            var base = max(lastKnownVersion, 0)
            // 第一次同步：以云端当前版本为基线，避免老的本地基线直接 409。
            if defaults.object(forKey: Key.version) == nil { base = state.version }
            do {
                try await upload(client: client, token: token, baseVersion: base, document: diary.document)
            } catch SyncConflictError.conflict {
                let snapshot = try await client.download(token: token)
                let merged = try diary.document.merged(with: snapshot.document)
                try diary.replaceDocument(merged)
                try await upload(client: client, token: token, baseVersion: snapshot.version,
                                 document: merged)
                noticeText = "云端和本机都已合并，共 \(merged.records.count) 餐。"
            }
            do {
                versions = try await client.versions(token: token)
            } catch {
                versions = []
            }
            markSynced()
        }
    }

    private enum SyncConflictError: Error { case conflict }

    private func upload(client: CloudSyncClient, token: String, baseVersion: Int,
                        document: DiaryDocument) async throws {
        let result = try await client.upload(token: token, baseVersion: baseVersion,
                                             document: document, deviceName: deviceName)
        switch result {
        case .created(let version, _, _), .unchanged(let version):
            setKnownVersion(version)
            if case .unchanged = result {
                noticeText = "云端已是最新，没有需要上传的改动。"
            } else {
                noticeText = "已上传到云端第 \(version) 版。"
            }
        case .conflict(let serverVersion, _):
            // 把服务器版本带出去，交给 syncNow 合并后重试。
            throw SyncConflictError.conflict
        }
    }

    func refreshVersions() async {
        guard let token = session?.token else { return }
        await run("正在读取版本…") {
            versions = try await client().versions(token: token)
        }
    }

    func restore(version: Int, diary: DiaryModel) async {
        guard let token = session?.token else { return }
        await run("正在恢复第 \(version) 版…") {
            let client = try client()
            try await client.restore(token: token, version: version)
            let snapshot = try await client.download(token: token)
            try diary.replaceDocument(try diary.document.merged(with: snapshot.document))
            setKnownVersion(snapshot.version)
            versions = try await client.versions(token: token)
            markSynced()
            noticeText = "已恢复第 \(version) 版，并合并进本机。"
        }
    }

    func clearMessages() {
        errorText = nil
        noticeText = nil
    }
}
