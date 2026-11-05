import Foundation
import Testing
@testable import NutritionCore

private final class ManagedAIQuotaProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"detail":"今日免费分析额度已用完，请稍后重试。"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct ManagedAIServiceTests {
    @Test func quotaFailureShowsTheBackendMessageWithoutRequestingAKey() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManagedAIQuotaProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = DeepSeekClient(session: session)
        do {
            _ = try await client.analyze(text: "米饭", imageJPEG: nil)
            Issue.record("Quota exceeded unexpectedly succeeded")
        } catch let error as DiaryError {
            #expect(error.errorDescription == "今日免费分析额度已用完，请稍后重试。")
        }
    }
}
