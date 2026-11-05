import Foundation
import Testing
@testable import NutritionCore

private final class PhotoProtocolState: @unchecked Sendable {
    let lock = NSLock()
    var server: PhotoTestServer?
    func set(_ server: PhotoTestServer?) { lock.withLock { self.server = server } }
    func current() -> PhotoTestServer? { lock.withLock { server } }
}

private final class PhotoTestProtocol: URLProtocol, @unchecked Sendable {
    static let state = PhotoProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let server = try #require(Self.state.current())
            let (status, data) = try server.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class PhotoTestServer: @unchecked Sendable {
    let lock = NSLock()
    var photos: [String: Data] = [:]
    var uploaded: DiaryDocument?
    var operations: [String] = []
    var corruptDownload = false
    var failUpload = false
    var invalidMissingList = false

    private func body(of request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    func respond(_ request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            let path = request.url!.path
            let body = try body(of: request)
            operations.append("\(request.httpMethod!) \(path)")
            if path == "/v1/sync/photos/missing" {
                let object = try JSONSerialization.jsonObject(with: body) as! [String: [String]]
                let names = object["names"]!
                let missing = invalidMissingList ? ["photo-" + String(repeating: "a", count: 64) + ".jpg"] : names.filter { photos[$0] == nil }
                return (200, try JSONSerialization.data(withJSONObject: ["missing": missing]))
            }
            if path.hasPrefix("/v1/sync/photos/") {
                let name = request.url!.lastPathComponent
                if request.httpMethod == "PUT" {
                    if failUpload { return (503, Data(#"{"detail":"retry"}"#.utf8)) }
                    let data = body
                    photos[name] = data
                    let digest = String(name.dropFirst(6).dropLast(4))
                    return (201, try JSONSerialization.data(withJSONObject: ["name": name, "checksum": digest]))
                }
                if corruptDownload { return (200, Data([99])) }
                return (200, photos[name] ?? Data())
            }
            if request.httpMethod == "PUT" {
                let object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
                uploaded = try CloudSyncClient.decoder.decode(DiaryDocument.self,
                    from: JSONSerialization.data(withJSONObject: object["payload"]!))
                return (201, Data(#"{"version":1,"checksum":"fixture","unchanged":false}"#.utf8))
            }
            let payload = try CloudSyncClient.encoder.encode(uploaded ?? DiaryDocument())
            return (200, Data("{\"version\":1,\"checksum\":\"fixture\",\"payload\":\(String(decoding: payload, as: UTF8.self))}".utf8))
        }
    }
}

@Suite(.serialized)
struct CloudPhotoSyncTests {
    private func client(_ server: PhotoTestServer) -> CloudSyncClient {
        PhotoTestProtocol.state.set(server)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoTestProtocol.self]
        return CloudSyncClient(baseURL: URL(string: "https://fixture.test")!, session: URLSession(configuration: config))
    }

    private func source() -> DiaryDocument {
        DiaryDocument(records: [MealRecord(foods: [.manual(name: "饭", nutrition: Nutrition(calories: 100))], photoJPEG: Data([1, 2, 3]))])
    }

    @Test func uploadPublishesPhotosBeforeMetadataAndRetrySkipsExistingAssets() async throws {
        let server = PhotoTestServer()
        let api = client(server)
        _ = try await api.upload(token: "fixture", baseVersion: 0, document: source(), deviceName: "test")
        #expect(server.photos.count == 1)
        #expect(server.uploaded?.records[0].photoJPEG == nil)
        #expect(server.uploaded?.records[0].photoFileName == PhotoArchive.transferName(for: Data([1, 2, 3])))
        let firstCount = server.operations.filter { $0.hasPrefix("PUT /v1/sync/photos/") }.count
        _ = try await api.upload(token: "fixture", baseVersion: 1, document: source(), deviceName: "test")
        #expect(server.operations.filter { $0.hasPrefix("PUT /v1/sync/photos/") }.count == firstCount)
        let photoIndex = try #require(server.operations.firstIndex { $0.hasPrefix("PUT /v1/sync/photos/") })
        let snapshotIndex = try #require(server.operations.firstIndex(of: "PUT /v1/sync/snapshot"))
        #expect(photoIndex < snapshotIndex)
    }

    @Test func failedPhotoUploadDoesNotPublishTheSnapshot() async throws {
        let server = PhotoTestServer()
        server.failUpload = true
        let api = client(server)
        await #expect(throws: (any Error).self) {
            try await api.upload(token: "fixture", baseVersion: 0, document: source(), deviceName: "test")
        }
        #expect(server.uploaded == nil)
    }

    @Test func downloaderVerifiesImageBytesBeforeWritingAndCanRetry() async throws {
        let server = PhotoTestServer()
        let api = client(server)
        _ = try await api.upload(token: "fixture", baseVersion: 0, document: source(), deviceName: "test")
        let directory = FileManager.default.temporaryDirectory.appending(path: "sync-download-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        server.corruptDownload = true
        await #expect(throws: (any Error).self) {
            try await api.download(token: "fixture", photosDirectory: directory)
        }
        let name = try #require(server.uploaded?.records[0].photoFileName)
        #expect(PhotoArchive.load(name: name, in: directory) == nil)
        server.corruptDownload = false
        let restored = try await api.download(token: "fixture", photosDirectory: directory)
        #expect(restored.document.records.count == 1)
        #expect(PhotoArchive.load(name: name, in: directory) == Data([1, 2, 3]))
    }

    @Test func missingListCannotRequestUnrelatedLocalImages() async throws {
        let server = PhotoTestServer()
        server.invalidMissingList = true
        let api = client(server)
        await #expect(throws: (any Error).self) {
            try await api.upload(token: "fixture", baseVersion: 0, document: source(), deviceName: "test")
        }
        #expect(server.uploaded == nil)
        #expect(server.photos.isEmpty)
    }

    @Test func originalDeviceCanPullAndUpgradeLegacyPhotoReferences() async throws {
        let server = PhotoTestServer()
        let api = client(server)
        let directory = FileManager.default.temporaryDirectory.appending(path: "legacy-sync-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var legacy = source()
        legacy.records[0].photoJPEG = nil
        legacy.records[0].photoFileName = "record-old.jpg"
        try legacy.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试"), photoFileName: "pack-old.jpg"))
        server.uploaded = legacy
        try PhotoArchive.save(Data([1, 2, 3]), name: "record-old.jpg", in: directory)
        try PhotoArchive.save(Data([4, 5, 6]), name: "pack-old.jpg", in: directory)
        let pulled = try await api.download(token: "fixture", photosDirectory: directory)
        _ = try await api.upload(token: "fixture", baseVersion: pulled.version, document: pulled.document,
                                 deviceName: "test", photosDirectory: directory)
        #expect(server.photos.count == 2)
        #expect(server.uploaded?.referencedPhotoNames.allSatisfy(PhotoArchive.isTransferName) == true)
        #expect(!server.operations.contains { $0.hasPrefix("GET /v1/sync/photos/") })
    }

    @Test func legacyPhotoWithoutOriginalBytesFailsSafely() async throws {
        let server = PhotoTestServer()
        let api = client(server)
        var legacy = source()
        legacy.records[0].photoJPEG = nil
        legacy.records[0].photoFileName = "record-missing.jpg"
        server.uploaded = legacy
        let directory = FileManager.default.temporaryDirectory.appending(path: "missing-legacy-sync-\(UUID())")
        await #expect(throws: (any Error).self) {
            try await api.download(token: "fixture", photosDirectory: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(server.photos.isEmpty)
    }
}
