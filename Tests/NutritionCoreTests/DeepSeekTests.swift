import Foundation
import Testing
@testable import NutritionCore

struct DeepSeekTests {
    private let validResult = #"{"summary":"米饭一小碗","assumptions":["米饭按熟重估算"],"foods":[{"name":"米饭","grams":150,"per100g":{"calories":116,"protein":2.6,"carbohydrates":25.9,"fat":0.3},"notes":"熟重"}]}"#

    private func envelope(_ content: String, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": "test-completion", "model": "deepseek-flash",
            "choices": [["index": 0, "finish_reason": finish,
                         "message": ["role": "assistant", "content": content]]],
            "usage": ["prompt_tokens": 42, "completion_tokens": 12, "total_tokens": 54]
        ])
    }

    @Test func requestUsesOfficialVisionAndJSONContract() throws {
        let request = try DeepSeekClient.makeRequest(text: "午餐，吃了一半", imageJPEG: Data([1, 2, 3]), apiKey: " test-key ")
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.httpMethod == "POST")
        let bodyData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["model"] as? String == "deepseek-flash")
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(parts[0]["text"] as? String == "午餐，吃了一半")
        #expect((parts[1]["image_url"] as? [String: String])?["url"] == "data:image/jpeg;base64,AQID")
    }

    @Test func emptyCredentialsAndEmptyInputAreRejected() {
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.makeRequest(text: "米饭", imageJPEG: nil, apiKey: " \n")
        }
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.makeRequest(text: "  ", imageJPEG: nil, apiKey: "test-key")
        }
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.makeRequest(text: String(repeating: "a", count: 10_001), imageJPEG: nil, apiKey: "test-key")
        }
    }

    @Test func structuredEstimateBecomesEditableFood() throws {
        let result = try DeepSeekClient.parseResponse(data: envelope(validResult), statusCode: 200)
        #expect(result.foods.count == 1)
        #expect(result.foods[0].name == "米饭")
        #expect(result.foods[0].nutrition.calories == 174)
        #expect(result.foods[0].notes == "熟重")
        #expect(result.assumptions == ["米饭按熟重估算"])
        #expect(result.summary == "米饭一小碗")
    }

    @Test func blankTruncatedAndMalformedOutputAreRejected() throws {
        for content in ["   ", "not json", #"{"summary":"没有食物","assumptions":[],"foods":[]}"#] {
            #expect(throws: DiaryError.self) {
                try DeepSeekClient.parseResponse(data: envelope(content), statusCode: 200)
            }
        }
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.parseResponse(data: envelope(validResult, finish: "length"), statusCode: 200)
        }
        let negative = validResult.replacingOccurrences(of: #""grams":150"#, with: #""grams":-1"#)
        #expect(throws: DiaryError.self) {
            try DeepSeekClient.parseResponse(data: envelope(negative), statusCode: 200)
        }
    }

    @Test func providerFailuresAreReadableWithoutEchoingSecrets() {
        let secretBody = Data(#"{"error":{"message":"secret-user-input test-key"}}"#.utf8)
        for status in [400, 401, 402, 429, 500, 503] {
            do {
                _ = try DeepSeekClient.parseResponse(data: secretBody, statusCode: status)
                Issue.record("HTTP \(status) should fail")
            } catch {
                #expect(!error.localizedDescription.contains("test-key"))
                #expect(!error.localizedDescription.contains("secret-user-input"))
                #expect(!error.localizedDescription.isEmpty)
            }
        }
    }
}
