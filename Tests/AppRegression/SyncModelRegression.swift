import Foundation
import NutritionCore

@MainActor final class UIDevice {
    static let current = UIDevice()
    let name = "Sync regression"
}
@MainActor enum SyncCredentialStore {
    static var clearCount = 0
    static func load() -> CloudSyncSession? {
        CloudSyncSession(token: "fixture", expiresAt: .distantFuture, username: "fixture", version: 2)
    }
    static func save(_ session: CloudSyncSession) throws {}
    static func clear() { clearCount += 1 }
}
@MainActor final class DiaryModel {
    var document: DiaryDocument
    let photosDirectory = FileManager.default.temporaryDirectory.appending(path: "unused-sync-fixture")
    init(_ document: DiaryDocument) { self.document = document }
    func replaceDocument(_ document: DiaryDocument) throws { try document.validate(); self.document = document }
}
final class SyncFixture: @unchecked Sendable {
    let lock = NSLock()
    let original: DiaryDocument
    var current: DiaryDocument
    var version = 2
    var uploads = 0
    var forceConflict = true
    var failDeletion = true
    var deletionRequests = 0
    init(original: DiaryDocument, current: DiaryDocument) { self.original = original; self.current = current }
    func handle(_ request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let path = request.url!.path
            var status = 200
            var object: Any = [:]
            if path == "/v1/account" {
                guard request.httpMethod == "DELETE",
                      request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" else {
                    throw URLError(.badServerResponse)
                }
                deletionRequests += 1
                return failDeletion ? (503, Data(#"{"detail":"稍后重试"}"#.utf8)) : (204, Data())
            }
            if path == "/v1/sync/state" { object = ["version": version] }
            else if path == "/v1/sync/versions" { object = [] as [String] }
            else if path.hasPrefix("/v1/sync/restore/") {
                current = original
                version += 1
                status = 201
            } else if path == "/v1/sync/snapshot" && request.httpMethod == "PUT" {
                var body = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var bytes = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&bytes, maxLength: bytes.count)
                        if count <= 0 { break }
                        body.append(contentsOf: bytes.prefix(count))
                    }
                }
                if forceConflict {
                    forceConflict = false
                    version += 1
                    status = 409
                    object = ["version": version]
                } else {
                    let data = try JSONSerialization.jsonObject(with: body) as! [String: Any]
                    guard data["baseVersion"] as? Int == version else { throw URLError(.badServerResponse) }
                    current = try decoder.decode(DiaryDocument.self, from: JSONSerialization.data(withJSONObject: data["payload"]!))
                    uploads += 1
                    version += 1
                    status = 201
                    object = ["version": version, "checksum": "fixture", "unchanged": false]
                }
            } else if path == "/v1/sync/snapshot" {
                let historical = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.queryItems?.contains { $0.name == "version" && $0.value == "1" } == true
                let value = historical ? original : current
                object = ["version": historical ? 1 : version, "checksum": "fixture",
                          "payload": try JSONSerialization.jsonObject(with: encoder.encode(value))]
            } else { throw URLError(.unsupportedURL) }
            return (status, try JSONSerialization.data(withJSONObject: object))
        }
    }
}
final class SyncFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: SyncFixture!
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "sync.fixture" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.fixture.handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@main struct SyncModelRegression {
    @MainActor static func main() async throws {
        let first = MealRecord(foods: [.manual(name: "历史", nutrition: Nutrition(calories: 100))])
        let second = MealRecord(foods: [.manual(name: "本机新增", nutrition: Nutrition(calories: 200))])
        let third = MealRecord(foods: [.manual(name: "云端新增", nutrition: Nutrition(calories: 300))])
        let original = DiaryDocument(records: [first])
        let local = DiaryDocument(records: [first, second])
        let cloud = DiaryDocument(records: [first, third])
        let fixture = SyncFixture(original: original, current: cloud)
        SyncFixtureProtocol.fixture = fixture
        URLProtocol.registerClass(SyncFixtureProtocol.self)
        let defaults = UserDefaults.standard
        defer {
            ["sync.server", "sync.knownVersion", "sync.lastSyncedAt", "sync.baselineOwner"].forEach(defaults.removeObject)
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        defaults.set("https://sync.fixture", forKey: "sync.server")
        defaults.set(2, forKey: "sync.knownVersion")
        defaults.set(Date.now, forKey: "sync.lastSyncedAt")
        let legacyOwner = CommandLine.arguments.contains("-legacy-owner")
        defaults.removeObject(forKey: "sync.baselineOwner")
        if legacyOwner { fixture.forceConflict = false }
        let diary = DiaryModel(local)
        let sync = SyncModel()
        if legacyOwner { await sync.syncNow(diary: diary) }
        else { await sync.restore(version: 1, diary: diary) }
        guard sync.errorText == nil else { fatalError(sync.errorText!) }
        guard Set(fixture.current.records.map(\.id)) == Set(diary.document.records.map(\.id)),
              fixture.current.records.count == 3, fixture.uploads == 1,
              sync.lastKnownVersion == fixture.version, !fixture.forceConflict else {
            fatalError("Restore marked synchronized before publishing the complete local/cloud union")
        }
        guard defaults.string(forKey: "sync.baselineOwner") == "https://sync.fixture\nfixture" else {
            fatalError("Successful baseline did not retain its server/account owner")
        }
        let priorVersion = sync.lastKnownVersion
        let priorSyncedAt = sync.lastSyncedAt
        await sync.deleteAccount()
        guard sync.errorText != nil, sync.isLoggedIn,
              sync.lastKnownVersion == priorVersion, sync.lastSyncedAt == priorSyncedAt,
              SyncCredentialStore.clearCount == 0 else {
            fatalError("Failed account deletion cleared the session or synchronization baseline")
        }
        fixture.failDeletion = false
        await sync.deleteAccount()
        guard sync.errorText == nil, !sync.isLoggedIn, sync.phase == .idle,
              sync.lastKnownVersion == 0, sync.lastSyncedAt == nil, sync.versions.isEmpty,
              defaults.object(forKey: "sync.baselineOwner") == nil,
              defaults.object(forKey: "sync.knownVersion") == nil,
              SyncCredentialStore.clearCount == 1, fixture.deletionRequests == 2,
              diary.document.records.count == 3 else {
            fatalError("Successful account deletion did not clear credentials and baseline while retaining local entries")
        }
        print("PASS — account deletion preserves state on failure and clears credentials/baseline only after success")
        print(legacyOwner ? "PASS — legacy unowned baseline forced a first pull and preserved remote records" : "PASS — actual SyncModel restored history, preserved local/cloud records and retried a conflict before marking synchronized")
    }
}
