import Foundation

public struct CloudSyncSession: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAt: Date
    public let username: String
    public let version: Int

    public init(token: String, expiresAt: Date, username: String, version: Int) {
        self.token = token
        self.expiresAt = expiresAt
        self.username = username
        self.version = version
    }
}

public struct CloudSyncState: Codable, Sendable, Equatable {
    public let version: Int
    public let updatedAt: Date?
    public let checksum: String?

    public init(version: Int, updatedAt: Date?, checksum: String?) {
        self.version = version
        self.updatedAt = updatedAt
        self.checksum = checksum
    }

    public func needsDownload(knownVersion: Int?, hasSynced: Bool) -> Bool {
        version > 0 && (!hasSynced || knownVersion != version)
    }
}

public struct CloudSyncSnapshot: Sendable {
    public let version: Int
    public let updatedAt: Date?
    public let checksum: String
    public let document: DiaryDocument

    public init(version: Int, updatedAt: Date?, checksum: String, document: DiaryDocument) {
        self.version = version
        self.updatedAt = updatedAt
        self.checksum = checksum
        self.document = document
    }
}

public struct CloudSyncVersion: Codable, Sendable, Identifiable, Equatable {
    public let version: Int
    public let createdAt: Date
    public let checksum: String
    public let sizeBytes: Int
    public let deviceName: String

    public var id: Int { version }
}

public enum CloudSyncUploadResult: Sendable, Equatable {
    case created(version: Int, updatedAt: Date?, checksum: String)
    case unchanged(version: Int)
    case conflict(serverVersion: Int, updatedAt: Date?)
}

public enum CloudSyncError: LocalizedError, Equatable {
    case invalidServerURL
    case invalidInput(String)
    case notLoggedIn
    case unauthorized
    case payloadTooLarge(Int)
    case conflict
    case server(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "服务器地址需要是 https:// 开头的完整域名。"
        case .invalidInput(let message): message
        case .notLoggedIn: "请先登录同步账号。"
        case .unauthorized: "登录已失效，请重新登录。"
        case .payloadTooLarge(let bytes): "本机数据已有 \(bytes / 1024 / 1024) MB，超过单次同步上限，请先清理内嵌照片。"
        case .conflict: "云端有更新的数据。"
        case .server(let message): message
        case .invalidResponse(let message): message
        }
    }
}

/// 自建同步服务客户端。网络调用与解析分开，解析可以单独测。
public struct CloudSyncClient: Sendable {
    public static let defaultServerURL = URL(string: "https://xiaoshitanji.papaclaoud.top")!
    public static let maximumPayloadBytes = 8 * 1024 * 1024

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = CloudSyncClient.defaultServerURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - 服务器地址

    public static func normalizedBaseURL(_ raw: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: text), let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false, url.query == nil, url.fragment == nil else {
            throw CloudSyncError.invalidServerURL
        }
        let local = url.host == "localhost" || url.host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local) else { throw CloudSyncError.invalidServerURL }
        url.standardize()
        if url.path() == "/" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.path = ""
            if let trimmed = components?.url { return trimmed }
        }
        return url
    }

    // MARK: - 请求构造

    func request(_ path: String, method: String, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func jsonRequest<T: Encodable>(_ path: String, method: String, token: String? = nil,
                                           body: T) throws -> URLRequest {
        var request = request(path, method: method, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CloudSyncClient.encoder.encode(body)
        return request
    }

    struct CredentialBody: Encodable {
        let username: String
        let password: String
        let deviceName: String
    }

    struct UploadBody: Encodable {
        let baseVersion: Int
        let payload: DiaryDocument
        let deviceName: String
    }

    public static func makeRegisterRequest(server: URL, username: String, password: String,
                                           deviceName: String) throws -> URLRequest {
        try validateCredentials(username: username, password: password)
        var request = URLRequest(url: server.appending(path: "/v1/auth/register"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(CredentialBody(username: username.trimmingCharacters(in: .whitespaces),
                                                            password: password, deviceName: deviceName))
        return request
    }

    public static func makeLoginRequest(server: URL, username: String, password: String,
                                        deviceName: String) throws -> URLRequest {
        try validateCredentials(username: username, password: password)
        var request = URLRequest(url: server.appending(path: "/v1/auth/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(CredentialBody(username: username.trimmingCharacters(in: .whitespaces),
                                                            password: password, deviceName: deviceName))
        return request
    }

    public static func validateCredentials(username: String, password: String) throws {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.-")
        guard (3...32).contains(name.count), name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw CloudSyncError.invalidInput("用户名需 3–32 位，只能用小写字母、数字、下划线、点和短横线。")
        }
        guard (8...128).contains(password.count) else {
            throw CloudSyncError.invalidInput("密码长度需在 8–128 位之间。")
        }
    }

    public func makeLogoutRequest(token: String) -> URLRequest {
        request("/v1/auth/logout", method: "POST", token: token)
    }

    public func makeStateRequest(token: String) -> URLRequest {
        request("/v1/sync/state", method: "GET", token: token)
    }

    public func makeSnapshotRequest(token: String, version: Int? = nil) -> URLRequest {
        var request = request("/v1/sync/snapshot", method: "GET", token: token)
        if let version, let url = request.url,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            components.queryItems = [URLQueryItem(name: "version", value: String(version))]
            request.url = components.url
        }
        return request
    }

    public func makeVersionsRequest(token: String) -> URLRequest {
        request("/v1/sync/versions", method: "GET", token: token)
    }

    public func makeRestoreRequest(token: String, version: Int) -> URLRequest {
        request("/v1/sync/restore/\(version)", method: "POST", token: token)
    }

    public func makeUploadRequest(token: String, baseVersion: Int, document: DiaryDocument,
                                  deviceName: String) throws -> URLRequest {
        let body = UploadBody(baseVersion: baseVersion, payload: document, deviceName: deviceName)
        var request = request("/v1/sync/snapshot", method: "PUT", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try CloudSyncClient.encoder.encode(body)
        guard data.count <= CloudSyncClient.maximumPayloadBytes else {
            throw CloudSyncError.payloadTooLarge(data.count)
        }
        request.httpBody = data
        return request
    }

    // MARK: - 解析

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: text) ?? plainFormatter.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析时间：\(text)")
        }
        return decoder
    }()

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter = ISO8601DateFormatter()

    struct ErrorBody: Decodable {
        let detail: Detail
        enum Detail: Decodable {
            case text(String)
            case fields([String])
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else if let items = try? container.decode([Field].self) {
                    self = .fields(items.map { "\($0.loc.joined(separator: ".")): \($0.msg)" })
                } else {
                    self = .text("服务器拒绝了这次请求。")
                }
            }
            var message: String {
                switch self {
                case .text(let text): text
                case .fields(let messages): messages.joined(separator: "；")
                }
            }
        }
        struct Field: Decodable {
            let loc: [String]
            let msg: String
        }
    }

    static func serverMessage(_ data: Data) -> String {
        (try? decoder.decode(ErrorBody.self, from: data))?.detail.message ?? "同步服务返回了错误。"
    }

    static func check(_ statusCode: Int, _ data: Data) throws {
        if statusCode == 401 { throw CloudSyncError.unauthorized }
        if statusCode == 413 { throw CloudSyncError.payloadTooLarge(maximumPayloadBytes) }
        guard (200..<300).contains(statusCode) else {
            throw CloudSyncError.server(serverMessage(data))
        }
    }

    public static func parseSession(data: Data, statusCode: Int) throws -> CloudSyncSession {
        try check(statusCode, data)
        do {
            return try decoder.decode(CloudSyncSession.self, from: data)
        } catch {
            throw CloudSyncError.invalidResponse("登录响应无法解析。")
        }
    }

    public static func parseState(data: Data, statusCode: Int) throws -> CloudSyncState {
        try check(statusCode, data)
        do {
            return try decoder.decode(CloudSyncState.self, from: data)
        } catch {
            throw CloudSyncError.invalidResponse("同步状态无法解析。")
        }
    }

    struct SnapshotEnvelope: Decodable {
        let version: Int
        let updatedAt: Date?
        let checksum: String
        let payload: DiaryDocument
    }

    public static func parseSnapshot(data: Data, statusCode: Int) throws -> CloudSyncSnapshot {
        try check(statusCode, data)
        do {
            let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
            try envelope.payload.validate()
            return CloudSyncSnapshot(version: envelope.version, updatedAt: envelope.updatedAt,
                                     checksum: envelope.checksum, document: envelope.payload)
        } catch {
            throw CloudSyncError.invalidResponse("云端快照无法解析，可能来自更新版本的 App。")
        }
    }

    struct UploadResponse: Decodable {
        let version: Int
        let updatedAt: Date?
        let checksum: String
        let unchanged: Bool?
    }

    struct ConflictResponse: Decodable {
        let version: Int
        let updatedAt: Date?
    }

    public static func parseUpload(data: Data, statusCode: Int) throws -> CloudSyncUploadResult {
        if statusCode == 409 {
            let conflict = try? decoder.decode(ConflictResponse.self, from: data)
            return .conflict(serverVersion: conflict?.version ?? 0, updatedAt: conflict?.updatedAt)
        }
        try check(statusCode, data)
        guard let response = try? decoder.decode(UploadResponse.self, from: data) else {
            throw CloudSyncError.invalidResponse("上传结果无法解析。")
        }
        if response.unchanged == true {
            return .unchanged(version: response.version)
        }
        return .created(version: response.version, updatedAt: response.updatedAt, checksum: response.checksum)
    }

    public static func parseVersions(data: Data, statusCode: Int) throws -> [CloudSyncVersion] {
        try check(statusCode, data)
        guard let versions = try? decoder.decode([CloudSyncVersion].self, from: data) else {
            throw CloudSyncError.invalidResponse("版本列表无法解析。")
        }
        return versions
    }

    public static func parseEmpty(data: Data, statusCode: Int) throws {
        try check(statusCode, data)
    }

    // MARK: - 网络调用

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch let error as CloudSyncError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CloudSyncError.server("连不上同步服务器：\(error.localizedDescription)")
        }
    }

    public func register(username: String, password: String, deviceName: String) async throws -> CloudSyncSession {
        let request = try Self.makeRegisterRequest(server: baseURL, username: username,
                                                   password: password, deviceName: deviceName)
        let (data, status) = try await send(request)
        return try Self.parseSession(data: data, statusCode: status)
    }

    public func login(username: String, password: String, deviceName: String) async throws -> CloudSyncSession {
        let request = try Self.makeLoginRequest(server: baseURL, username: username,
                                                password: password, deviceName: deviceName)
        let (data, status) = try await send(request)
        return try Self.parseSession(data: data, statusCode: status)
    }

    public func logout(token: String) async throws {
        let (data, status) = try await send(makeLogoutRequest(token: token))
        try Self.parseEmpty(data: data, statusCode: status)
    }

    public func state(token: String) async throws -> CloudSyncState {
        let (data, status) = try await send(makeStateRequest(token: token))
        return try Self.parseState(data: data, statusCode: status)
    }

    public func download(token: String, version: Int? = nil, photosDirectory: URL? = nil) async throws -> CloudSyncSnapshot {
        let (data, status) = try await send(makeSnapshotRequest(token: token, version: version))
        let snapshot = try Self.parseSnapshot(data: data, statusCode: status)
        if let photosDirectory {
            try await downloadPhotos(for: snapshot.document, token: token, into: photosDirectory)
        }
        return snapshot
    }

    public func upload(token: String, baseVersion: Int, document: DiaryDocument,
                       deviceName: String, photosDirectory: URL? = nil) async throws -> CloudSyncUploadResult {
        let transfer = try await Task.detached { try document.photoTransfer(from: photosDirectory) }.value
        try Task.checkCancellation()
        try await uploadPhotos(transfer.photos, token: token)
        let request = try makeUploadRequest(token: token, baseVersion: baseVersion,
                                            document: transfer.document, deviceName: deviceName)
        let (data, status) = try await send(request)
        return try Self.parseUpload(data: data, statusCode: status)
    }

    public func versions(token: String) async throws -> [CloudSyncVersion] {
        let (data, status) = try await send(makeVersionsRequest(token: token))
        return try Self.parseVersions(data: data, statusCode: status)
    }

    public func restore(token: String, version: Int) async throws {
        let (data, status) = try await send(makeRestoreRequest(token: token, version: version))
        try Self.parseEmpty(data: data, statusCode: status)
    }
}

// MARK: - 冲突合并

extension DiaryDocument {
    /// 把云端文档并进本机文档：按 id 取并集，重复时保留本机那份。
    ///
    /// 本机已有偏好优先，初始空档案从云端继承，其余条目取并集后按时间排序。
    public func merged(with remote: DiaryDocument) throws -> DiaryDocument {
        try validate()
        try remote.validate()
        var result = self
        result.schemaVersion = DiaryDocument.currentSchemaVersion
        result.records = Self.union(records, remote.records).sorted { $0.date < $1.date }
        result.reviews = Self.union(reviews, remote.reviews)
        result.weights = Self.union(weights, remote.weights).sorted { $0.date < $1.date }
        result.workouts = Self.union(workouts, remote.workouts).sorted { $0.date < $1.date }
        result.plans = Self.union(plans, remote.plans).sorted { $0.lastUsedAt > $1.lastUsedAt }
        result.wellnessReviews = Self.union(wellnessReviews, remote.wellnessReviews)
        result.templates = Self.union(templates, remote.templates)
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        result.observations = Self.union(observations, remote.observations)
            .sorted { $0.createdAt < $1.createdAt }
        var smoking = self.smoking
        smoking.merge(remote.smoking)
        result.smoking = smoking
        if result.profile == HealthProfile() { result.profile = remote.profile }
        if result.energy == nil { result.energy = remote.energy }
        try result.validate()
        return result
    }

    private static func union<T: Identifiable>(_ local: [T], _ remote: [T]) -> [T] where T.ID: Equatable {
        var seen = Set(local.map(\.id))
        var result = local
        for item in remote where !seen.contains(item.id) {
            result.append(item)
            seen.insert(item.id)
        }
        return result
    }
}
