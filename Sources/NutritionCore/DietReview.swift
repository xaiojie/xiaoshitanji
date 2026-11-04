import Foundation

public struct DietReview: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var recordCount: Int
    public var summary: String
    public var score: Int?
    public var highlights: [String]
    public var suggestions: [String]
    public var model: String
    public var generatedAt: Date
    public var calorieGoal: Double?

    public init(id: UUID = UUID(), date: Date, recordCount: Int, summary: String, score: Int?,
                highlights: [String], suggestions: [String], model: String, generatedAt: Date = .now,
                calorieGoal: Double? = nil) {
        self.id = id
        self.date = date
        self.recordCount = recordCount
        self.summary = summary
        self.score = score
        self.highlights = highlights
        self.suggestions = suggestions
        self.model = model
        self.generatedAt = generatedAt
        self.calorieGoal = calorieGoal
    }

    public func validate() throws {
        guard date.timeIntervalSinceReferenceDate.isFinite, generatedAt.timeIntervalSinceReferenceDate.isFinite,
              recordCount > 0, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              score.map({ (0...100).contains($0) }) ?? true,
              calorieGoal.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw DiaryError.invalidResponse("饮食分析结果不完整，请重新分析。")
        }
    }
}
