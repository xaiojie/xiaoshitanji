import Foundation
import Testing
@testable import NutritionCore

@Suite("云端同步")
struct CloudSyncTests {
    @Test func historicalSnapshotUsesAQueryParameter() throws {
        let request = CloudSyncClient().makeSnapshotRequest(token: "fixture", version: 7)
        let url = try #require(request.url)
        #expect(url.path == "/v1/sync/snapshot")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems == [URLQueryItem(name: "version", value: "7")])
    }
    private func server() -> URL { URL(string: "https://sync.example.com")! }

    private func sessionJSON(token: String = "abc", expires: String = "2026-12-01T08:30:00.123456Z") -> Data {
        Data("""
        {"token":"\(token)","expiresAt":"\(expires)","username":"frog","version":3}
        """.utf8)
    }

    @Test("地址规范化")
    func normalizesServerURL() throws {
        #expect(try CloudSyncClient.normalizedBaseURL(" https://xiaoshitanji.papaclaoud.top/ ")
                == URL(string: "https://xiaoshitanji.papaclaoud.top")!)
        #expect(try CloudSyncClient.normalizedBaseURL("http://127.0.0.1:8787")
                == URL(string: "http://127.0.0.1:8787")!)
        #expect(throws: CloudSyncError.invalidServerURL) {
            _ = try CloudSyncClient.normalizedBaseURL("http://sync.example.com")
        }
        #expect(throws: CloudSyncError.invalidServerURL) {
            _ = try CloudSyncClient.normalizedBaseURL("https://sync.example.com/?a=1")
        }
        #expect(throws: CloudSyncError.invalidServerURL) {
            _ = try CloudSyncClient.normalizedBaseURL("not a url")
        }
    }

    @Test("账号密码本地校验")
    func validatesCredentials() throws {
        #expect(throws: CloudSyncError.invalidInput("用户名需 3–32 位，只能用小写字母、数字、下划线、点和短横线。")) {
            _ = try CloudSyncClient.validateCredentials(username: "ab", password: "12345678")
        }
        #expect(throws: CloudSyncError.invalidInput("用户名需 3–32 位，只能用小写字母、数字、下划线、点和短横线。")) {
            _ = try CloudSyncClient.validateCredentials(username: "Frog Li", password: "12345678")
        }
        #expect(throws: CloudSyncError.invalidInput("密码长度需在 8–128 位之间。")) {
            _ = try CloudSyncClient.validateCredentials(username: "frog", password: "short")
        }
        #expect(throws: Never.self) {
            _ = try CloudSyncClient.validateCredentials(username: "milk.frog", password: "12345678")
        }
    }

    @Test("注册请求")
    func buildsRegisterRequest() throws {
        let request = try CloudSyncClient.makeRegisterRequest(server: server(), username: " frog ",
                                                              password: "12345678", deviceName: "iPhone")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/auth/register")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["username"] as? String == "frog")
        #expect(json["password"] as? String == "12345678")
        #expect(json["deviceName"] as? String == "iPhone")
    }

    @Test("登录响应解析含小数秒")
    func parsesSession() throws {
        let session = try CloudSyncClient.parseSession(data: sessionJSON(), statusCode: 200)
        #expect(session.token == "abc")
        #expect(session.username == "frog")
        #expect(session.version == 3)
        let formatter = ISO8601DateFormatter()
        #expect(formatter.string(from: session.expiresAt) == "2026-12-01T08:30:00Z")
    }

    @Test("登录响应解析不含小数秒")
    func parsesSessionWithoutFraction() throws {
        let data = Data(#"{"token":"t","expiresAt":"2026-12-01T08:30:00Z","username":"frog","version":1}"#.utf8)
        let session = try CloudSyncClient.parseSession(data: data, statusCode: 200)
        #expect(session.token == "t")
    }

    @Test("鉴权失败与字段错误")
    func mapsErrors() {
        #expect(throws: CloudSyncError.unauthorized) {
            _ = try CloudSyncClient.parseSession(data: Data(), statusCode: 401)
        }
        let detail = Data(#"{"detail":"用户名或密码不正确"}"#.utf8)
        #expect(throws: CloudSyncError.server("用户名或密码不正确")) {
            _ = try CloudSyncClient.parseVersions(data: detail, statusCode: 500)
        }
        let fields = Data(#"{"detail":[{"loc":["body","username"],"msg":"String should have at least 3 characters"}]}"#.utf8)
        #expect(throws: CloudSyncError.server("body.username: String should have at least 3 characters")) {
            _ = try CloudSyncClient.parseSession(data: fields, statusCode: 422)
        }
        #expect(throws: CloudSyncError.payloadTooLarge(CloudSyncClient.maximumPayloadBytes)) {
            _ = try CloudSyncClient.parseSession(data: Data(), statusCode: 413)
        }
    }

    @Test("状态与快照解析")
    func parsesStateAndSnapshot() throws {
        let state = try CloudSyncClient.parseState(
            data: Data(#"{"version":7,"updatedAt":"2026-11-04T22:00:00Z","checksum":"abc"}"#.utf8),
            statusCode: 200)
        #expect(state.version == 7)
        #expect(state.checksum == "abc")

        let document = DiaryDocument(records: [
            MealRecord(date: Date(timeIntervalSince1970: 1_700_000_000), kind: .lunch,
                       foods: [.manual(name: "米饭", nutrition: Nutrition(calories: 232, protein: 4, carbohydrates: 52, fat: 0.6))])
        ])
        let payload = try CloudSyncClient.encoder.encode(document)
        let payloadJSON = String(decoding: payload, as: UTF8.self)
        let snapshotJSON = Data("""
        {"version":7,"updatedAt":"2026-11-04T22:00:00.000Z","checksum":"abc","payload":\(payloadJSON)}
        """.utf8)
        let snapshot = try CloudSyncClient.parseSnapshot(data: snapshotJSON, statusCode: 200)
        #expect(snapshot.version == 7)
        #expect(snapshot.checksum == "abc")
        #expect(snapshot.document.records.count == 1)
        #expect(snapshot.document.records[0].foods[0].name == "米饭")
    }

    @Test("上传结果三种分支")
    func parsesUpload() throws {
        let created = try CloudSyncClient.parseUpload(
            data: Data(#"{"version":8,"updatedAt":"2026-11-04T22:00:00Z","checksum":"c","unchanged":false}"#.utf8),
            statusCode: 201)
        guard case .created(let version, _, let checksum) = created else {
            Issue.record("应当返回 created")
            return
        }
        #expect(version == 8)
        #expect(checksum == "c")

        let unchanged = try CloudSyncClient.parseUpload(
            data: Data(#"{"version":8,"updatedAt":"2026-11-04T22:00:00Z","checksum":"c","unchanged":true}"#.utf8),
            statusCode: 200)
        #expect(unchanged == .unchanged(version: 8))

        let conflict = try CloudSyncClient.parseUpload(
            data: Data(#"{"detail":"cloud","version":9,"updatedAt":"2026-11-04T22:00:00Z"}"#.utf8),
            statusCode: 409)
        guard case .conflict(let serverVersion, _) = conflict else {
            Issue.record("应当返回 conflict")
            return
        }
        #expect(serverVersion == 9)
    }

    @Test("版本列表解析")
    func parsesVersions() throws {
        let data = Data("""
        [{"version":3,"createdAt":"2026-11-04T10:00:00Z","checksum":"a","sizeBytes":1024,"deviceName":"iPhone"},
         {"version":2,"createdAt":"2026-11-03T10:00:00Z","checksum":"b","sizeBytes":900,"deviceName":"iPad"}]
        """.utf8)
        let versions = try CloudSyncClient.parseVersions(data: data, statusCode: 200)
        #expect(versions.map(\.version) == [3, 2])
        #expect(versions[0].id == 3)
        #expect(versions[1].sizeBytes == 900)
    }

    @Test("上传请求带基线版本正文")
    func buildsUploadRequest() throws {
        let document = DiaryDocument()
        let request = try CloudSyncClient().makeUploadRequest(token: "t", baseVersion: 4,
                                                              document: document, deviceName: "iPhone")
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "/v1/sync/snapshot")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["baseVersion"] as? Int == 4)
        #expect(json["deviceName"] as? String == "iPhone")
        let payload = try #require(json["payload"] as? [String: Any])
        #expect(payload["schemaVersion"] as? Int == DiaryDocument.currentSchemaVersion)
    }

    @Test("超过 8 MB 拒绝上传")
    func rejectsOversizedPayload() throws {
        var document = DiaryDocument()
        document.records = [MealRecord(foods: [.manual(name: "大文件",
                                                       nutrition: Nutrition(calories: 1, protein: 0, carbohydrates: 0, fat: 0))])]
        document.records[0].originalText = String(repeating: "a", count: 9 * 1024 * 1024)
        #expect(throws: (any Error).self) {
            _ = try CloudSyncClient().makeUploadRequest(token: "t", baseVersion: 0,
                                                         document: document, deviceName: "iPhone")
        }
    }

    @Test("冲突合并取并集，本机优先")
    func mergesDocuments() throws {
        let shared = UUID()
        var local = DiaryDocument(records: [
            MealRecord(id: shared, date: Date(timeIntervalSince1970: 1_700_000_000), kind: .lunch,
                       foods: [.manual(name: "本机", nutrition: Nutrition(calories: 100))]),
            MealRecord(date: Date(timeIntervalSince1970: 1_700_003_600), kind: .dinner,
                       foods: [.manual(name: "只在本地", nutrition: Nutrition(calories: 200))])
        ], templates: [MealTemplate(name: "本机组合", foods: [.manual(name: "饭", nutrition: Nutrition(calories: 100))])])
        let remote = DiaryDocument(records: [
            MealRecord(id: shared, date: Date(timeIntervalSince1970: 1_700_000_000), kind: .lunch,
                       foods: [.manual(name: "云端", nutrition: Nutrition(calories: 999))]),
            MealRecord(date: Date(timeIntervalSince1970: 1_700_007_200), kind: .breakfast,
                       foods: [.manual(name: "只在云端", nutrition: Nutrition(calories: 300))])
        ], weights: [WeightRecord(date: Date(timeIntervalSince1970: 1_700_007_200), kilograms: 70)],
        templates: [MealTemplate(name: "云端组合", foods: [.manual(name: "面", nutrition: Nutrition(calories: 200))])],
        energy: EnergySettings(sex: .male, birthYear: 1995, activity: .moderate,
                               goalMode: .lose, weeklyRate: 0.5))

        let merged = try local.merged(with: remote)
        #expect(merged.records.count == 3)
        #expect(merged.records.first { $0.id == shared }?.foods.first?.name == "本机")
        #expect(merged.records.contains { $0.foods.first?.name == "只在云端" })
        #expect(merged.weights.count == 1)
        #expect(merged.templates.count == 2)
        #expect(merged.schemaVersion == DiaryDocument.currentSchemaVersion)
        #expect(merged.energy?.goalMode == .lose)

        // 再合并一次应当完全幂等。
        let again = try merged.merged(with: remote)
        #expect(again.records.count == merged.records.count)
        #expect(again.templates.count == merged.templates.count)
    }

    @Test("同一天两份复盘合并后只留较新的一条")
    func mergesReviewsByDay() throws {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        func review(_ summary: String, at offset: TimeInterval, generated: TimeInterval) -> DietReview {
            DietReview(date: day.addingTimeInterval(offset), recordCount: 2, summary: summary, score: 70,
                       highlights: [], suggestions: [], model: "deepseek-flash",
                       generatedAt: day.addingTimeInterval(generated))
        }
        var local = DiaryDocument()
        local.reviews = [review("旧的", at: 3600, generated: 100)]
        var remote = DiaryDocument()
        remote.reviews = [review("新的", at: 7200, generated: 900)]

        let merged = try local.merged(with: remote)
        #expect(merged.reviews.count == 1)
        #expect(merged.reviews.first?.summary == "新的")
    }

    @Test("同一周期两份汇总分析合并后只留较新的一份")
    func mergesWellnessReviewsByPeriod() throws {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var local = DiaryDocument(records: [
            MealRecord(date: day, kind: .lunch, foods: [.manual(name: "饭", nutrition: Nutrition(calories: 300))])
        ])
        var remote = local
        func report(_ text: String, generated: TimeInterval) throws -> WellnessReview {
            let snapshot = try WellnessSummary.make(document: local, period: .week, endDate: day)
            return WellnessReview(id: UUID(), snapshot: snapshot, summary: text,
                                  observations: WellnessArea.allCases.map { WellnessObservation(area: $0, text: "看到一些变化") },
                                  actions: [WellnessAction(title: "继续记录", detail: "按实际情况记录")],
                                  limitations: [], model: "deepseek-flash",
                                  generatedAt: day.addingTimeInterval(generated))
        }
        local.wellnessReviews = [try report("旧的", generated: 100)]
        remote.wellnessReviews = [try report("新的", generated: 900)]

        let merged = try local.merged(with: remote)
        #expect(merged.wellnessReviews.count == 1)
        #expect(merged.wellnessReviews.first?.summary == "新的")
    }

    @Test("重复 id 的复盘会被校验拦下")
    func duplicateReviewIdentifiersAreRejected() throws {
        var document = DiaryDocument(records: [
            MealRecord(date: Date(timeIntervalSince1970: 1_700_000_000), foods: [
                .manual(name: "饭", nutrition: Nutrition(calories: 300))
            ])
        ])
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let review = DietReview(date: day, recordCount: 1, summary: "一份复盘", score: 70,
                                highlights: [], suggestions: [], model: "deepseek-flash", generatedAt: day)
        document.reviews = [review, review]
        #expect(throws: DiaryError.self) { try document.validate() }

        document.reviews = []
        let snapshot = try WellnessSummary.make(document: document, period: .week, endDate: day)
        let report = WellnessReview(id: UUID(), snapshot: snapshot, summary: "一份汇总",
                                    observations: WellnessArea.allCases.map { WellnessObservation(area: $0, text: "看到一些变化") },
                                    actions: [WellnessAction(title: "继续记录", detail: "按实际情况记录")],
                                    limitations: [], model: "deepseek-flash", generatedAt: day)
        document.wellnessReviews = [report, report]
        #expect(throws: DiaryError.self) { try document.validate() }
    }

    @Test("合并两侧吸烟记录")
    func mergesSmoking() throws {
        var local = DiaryDocument()
        try local.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "本机烟"),
                                                openedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try local.smoking.record(.smoked, count: 2, date: Date(timeIntervalSince1970: 1_700_000_100))
        var remote = DiaryDocument()
        try remote.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试烟"),
                                                 openedAt: Date(timeIntervalSince1970: 1_700_080_000)))
        try remote.smoking.record(.smoked, count: 3, date: Date(timeIntervalSince1970: 1_700_086_400))

        let merged = try local.merged(with: remote)
        #expect(merged.smoking.events.count == 2)
        #expect(merged.smoking.events.map(\.count).reduce(0, +) == 5)
    }

    @Test("版本列表请求与恢复请求")
    func buildsVersionRequests() {
        let client = CloudSyncClient()
        let versions = client.makeVersionsRequest(token: "t")
        #expect(versions.url?.path() == "/v1/sync/versions")
        let restore = client.makeRestoreRequest(token: "t", version: 5)
        #expect(restore.httpMethod == "POST")
        #expect(restore.url?.path() == "/v1/sync/restore/5")
        let logout = client.makeLogoutRequest(token: "t")
        #expect(logout.httpMethod == "POST")
        #expect(logout.url?.path() == "/v1/auth/logout")
    }
}
