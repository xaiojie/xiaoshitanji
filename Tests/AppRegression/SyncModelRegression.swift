import CryptoKit
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
    let photosDirectory: URL
    init(_ document: DiaryDocument, photosDirectory: URL) {
        self.document = document
        self.photosDirectory = photosDirectory
    }
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
    /// 服务端已存照片：名字 → 字节。照片同步的两个方向都靠它验证。
    var storedPhotos: [String: Data] = [:]
    var photoMissingLookups = 0
    var photoUploads = 0
    var photoDownloads = 0
    init(original: DiaryDocument, current: DiaryDocument) { self.original = original; self.current = current }

    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        var body = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            body.append(contentsOf: bytes.prefix(count))
        }
        return body
    }

    func handle(_ request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let path = request.url!.path
            var status = 200
            var object: Any = [:]
            if path == "/v1/sync/photos/missing" {
                guard request.httpMethod == "POST",
                      request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" else {
                    throw URLError(.badServerResponse)
                }
                photoMissingLookups += 1
                let names = (try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])?["names"] as? [String] ?? []
                return (200, try JSONSerialization.data(withJSONObject: ["missing": names.filter { storedPhotos[$0] == nil }]))
            }
            if path.hasPrefix("/v1/sync/photos/") {
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" else {
                    throw URLError(.badServerResponse)
                }
                let name = String(path.dropFirst("/v1/sync/photos/".count))
                guard PhotoArchive.isTransferName(name) else {
                    return (422, Data(#"{"detail":"照片名无效"}"#.utf8))
                }
                switch request.httpMethod {
                case "PUT":
                    let data = requestBody(request)
                    guard !data.isEmpty, request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg",
                          PhotoArchive.transferName(for: data) == name else {
                        return (422, Data(#"{"detail":"照片校验失败"}"#.utf8))
                    }
                    storedPhotos[name] = data
                    photoUploads += 1
                    return (200, try JSONSerialization.data(withJSONObject: ["name": name, "checksum": Self.checksum(data)]))
                case "GET":
                    guard let data = storedPhotos[name] else {
                        return (404, Data(#"{"detail":"照片不存在"}"#.utf8))
                    }
                    photoDownloads += 1
                    return (200, data)
                default:
                    throw URLError(.unsupportedURL)
                }
            }
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
        // 照片同步是跨端闭环的唯一空白：本机有一张待上传的，云端有一张待下载的。
        let photosDirectory = FileManager.default.temporaryDirectory
            .appending(path: "sync-regression-photos-\(UUID().uuidString)")
        try PhotoArchive.ensureDirectory(photosDirectory)
        let localPhoto = Data("local-photo-payload".utf8)
        let localPhotoName = PhotoArchive.transferName(for: localPhoto)
        try PhotoArchive.save(localPhoto, name: localPhotoName, in: photosDirectory)
        let cloudPhoto = Data("cloud-photo-payload".utf8)
        let cloudPhotoName = PhotoArchive.transferName(for: cloudPhoto)
        let localPhotoRecord = MealRecord(foods: [.manual(name: "带照片", nutrition: Nutrition(calories: 150))],
                                          photoFileName: localPhotoName)
        let cloudPhotoRecord = MealRecord(foods: [.manual(name: "云端旧照片", nutrition: Nutrition(calories: 80))],
                                          photoFileName: cloudPhotoName)
        let original = DiaryDocument(records: [first, cloudPhotoRecord])
        let local = DiaryDocument(records: [first, second, localPhotoRecord])
        let cloud = DiaryDocument(records: [first, third, cloudPhotoRecord])
        let fixture = SyncFixture(original: original, current: cloud)
        fixture.storedPhotos[cloudPhotoName] = cloudPhoto
        SyncFixtureProtocol.fixture = fixture
        URLProtocol.registerClass(SyncFixtureProtocol.self)
        let defaults = UserDefaults.standard
        defer {
            ["sync.server", "sync.knownVersion", "sync.lastSyncedAt", "sync.baselineOwner"].forEach(defaults.removeObject)
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
            try? FileManager.default.removeItem(at: photosDirectory)
        }
        defaults.set("https://sync.fixture", forKey: "sync.server")
        defaults.set(2, forKey: "sync.knownVersion")
        defaults.set(Date.now, forKey: "sync.lastSyncedAt")
        let legacyOwner = CommandLine.arguments.contains("-legacy-owner")
        defaults.removeObject(forKey: "sync.baselineOwner")
        if legacyOwner { fixture.forceConflict = false }
        let diary = DiaryModel(local, photosDirectory: photosDirectory)
        let sync = SyncModel()
        if legacyOwner { await sync.syncNow(diary: diary) }
        else { await sync.restore(version: 1, diary: diary) }
        guard sync.errorText == nil else { fatalError(sync.errorText!) }
        guard Set(fixture.current.records.map(\.id)) == Set(diary.document.records.map(\.id)),
              fixture.current.records.count == 5, fixture.uploads == 1,
              sync.lastKnownVersion == fixture.version, !fixture.forceConflict else {
            fatalError("Restore marked synchronized before publishing the complete local/cloud union")
        }
        guard PhotoArchive.verifiedPhoto(name: cloudPhotoName, in: photosDirectory) else {
            fatalError("Cloud photo was never downloaded into the local Photos directory")
        }
        guard fixture.storedPhotos[localPhotoName] == localPhoto, fixture.photoUploads == 1 else {
            fatalError("Local photo was never uploaded to the cloud exactly once")
        }
        guard fixture.photoMissingLookups >= 1, fixture.photoDownloads == 1 else {
            fatalError("Photo transfer skipped the missing lookup or downloaded a photo twice")
        }
        guard diary.document.referencedPhotoNames.contains(cloudPhotoName),
              diary.document.referencedPhotoNames.contains(localPhotoName) else {
            fatalError("Merged document lost one of the photo references")
        }
        print("PASS — photos travelled both ways (1 uploaded, 1 downloaded) and stayed referenced")
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
              diary.document.records.count == 5 else {
            fatalError("Successful account deletion did not clear credentials and baseline while retaining local entries")
        }
        print("PASS — account deletion preserves state on failure and clears credentials/baseline only after success")
        print(legacyOwner ? "PASS — legacy unowned baseline forced a first pull and preserved remote records" : "PASS — actual SyncModel restored history, preserved local/cloud records and retried a conflict before marking synchronized")
    }
}
