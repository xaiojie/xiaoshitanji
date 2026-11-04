import Foundation

/// 「蛙的观察」的一份上下文：只包含本地聚合后的确定性数字，不含照片与原始输入。
public struct ObservationContext: Codable, Equatable, Sendable {
    public let facts: ObservationFacts
    public let evidence: String

    public init(facts: ObservationFacts, evidence: String) {
        self.facts = facts
        self.evidence = evidence
    }

    /// 发给 DeepSeek 的聚合摘要：只含数字，不含照片、原始输入与食物名。
    public func promptJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(facts)
        guard data.count <= 100_000 else {
            throw DiaryError.invalidInput("区间数据过多，请先选近 7 天或近 30 天。")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 稳定的上下文指纹，用于判断回答是否基于同一份数据。
    public var fingerprint: String {
        let json = (try? promptJSON()) ?? ""
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in json.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

public struct ObservationFacts: Codable, Equatable, Sendable {
    public let period: String
    public let startDate: Date
    public let endDate: Date
    public let dayCount: Int
    public let timeZone: String

    public let meals: Int
    public let recordedDays: Int
    public let averageCalories: Double?
    public let averageProtein: Double?
    public let averageCarbs: Double?
    public let averageFat: Double?

    public let targetCalories: Double?
    public let proteinTarget: Double?
    public let carbTarget: Double?
    public let fatTarget: Double?

    public let latestWeightKG: Double?
    public let weightChangeKG: Double?
    public let targetWeightKG: Double?

    public let smoked: Int
    public let smokedEventDays: Int
    public let knownNicotineMG: Double
    public let unknownNicotineCount: Int

    public let averageSteps: Double?
    public let averageExerciseMinutes: Double?

    public let gaps: [String]

    public static func make(document: DiaryDocument, period: WellnessPeriod, endDate: Date = .now,
                            activityDays: [HealthActivityDay] = [], healthWeights: [WeightRecord] = [],
                            healthHeightCM: Double? = nil, healthHeightDate: Date? = nil,
                            budget: EnergyBudget? = nil, includesHealth: Bool = false,
                            calendar: Calendar = .current) throws -> ObservationContext {
        let summary = try WellnessSummary.make(document: document, period: period, endDate: endDate,
                                              activityDays: activityDays, healthWeights: healthWeights,
                                              healthHeightCM: healthHeightCM, healthHeightDate: healthHeightDate,
                                              calorieGoal: budget?.targetCalories,
                                              includesHealth: includesHealth, calendar: calendar)
        return make(summary: summary, budget: budget)
    }

    public static func make(summary: WellnessSummary, budget: EnergyBudget?) -> ObservationContext {
        let recordedDays = max(1, summary.diet.recordedDays)
        let diet = summary.diet.total
        var gaps: [String] = []
        if summary.diet.recordCount == 0 {
            gaps.append("这段区间没有饮食记录")
        } else if summary.diet.recordedDays < 3 {
            gaps.append("只有 \(summary.diet.recordedDays) 天饮食记录，尚不足以判断习惯")
        }
        if summary.body.latestWeight == nil { gaps.append("没有体重记录") }
        if summary.body.heightCM == nil { gaps.append("没有身高，无法计算 BMI 与蛋白目标") }
        if summary.body.latestWeight != nil, summary.body.weightChangeKG == nil {
            gaps.append("区间内只有一次体重，无法判断变化")
        }
        if !summary.activity.hasData { gaps.append("没有可读取的 Apple 健康活动数据") }
        if summary.smoking.eventDays == 0 { gaps.append("区间内没有吸烟记录") }
        if summary.smoking.unpricedCount > 0 { gaps.append("\(summary.smoking.unpricedCount) 根香烟缺少价格") }

        let facts = ObservationFacts(
            period: summary.period.rawValue,
            startDate: summary.startDate, endDate: summary.endDate,
            dayCount: summary.dayCount, timeZone: summary.timeZone,
            meals: summary.diet.recordCount, recordedDays: summary.diet.recordedDays,
            averageCalories: diet.map { $0.calories / Double(recordedDays) },
            averageProtein: diet.map { $0.protein / Double(recordedDays) },
            averageCarbs: diet.map { $0.carbohydrates / Double(recordedDays) },
            averageFat: diet.map { $0.fat / Double(recordedDays) },
            targetCalories: budget?.targetCalories,
            proteinTarget: budget?.proteinGrams,
            carbTarget: budget?.carbGrams,
            fatTarget: budget?.fatGrams,
            latestWeightKG: summary.body.latestWeight?.kilograms,
            weightChangeKG: summary.body.weightChangeKG,
            targetWeightKG: summary.body.targetWeightKG,
            smoked: summary.smoking.smoked, smokedEventDays: summary.smoking.eventDays,
            knownNicotineMG: summary.smoking.knownNicotineMG,
            unknownNicotineCount: summary.smoking.unknownNicotineCount,
            averageSteps: summary.activity.steps.average,
            averageExerciseMinutes: summary.activity.exerciseMinutes.average,
            gaps: gaps)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: summary.timeZone) ?? .current
        formatter.dateFormat = "MM/dd"
        var parts = ["依据：\(formatter.string(from: summary.startDate))–\(formatter.string(from: summary.endDate))"]
        if summary.diet.recordCount > 0 { parts.append("的 \(summary.diet.recordCount) 餐 / \(summary.diet.recordedDays) 个记录日") }
        if summary.body.latestWeight != nil { parts.append("、体重记录") }
        if summary.smoking.eventDays > 0 { parts.append("、\(summary.smoking.smoked) 根烟") }
        let evidence = parts.joined()
        return ObservationContext(facts: facts, evidence: evidence)
    }

}

/// 自由追问的回答。绑定当时的上下文指纹，数据变了会标记为「基于旧数据」。
public struct AnalysisAnswer: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let question: String
    public let answer: String
    public let evidence: String
    public let period: WellnessPeriod
    public let fingerprint: String
    public let contextJSON: String
    public let createdAt: Date
    public let model: String

    public init(id: UUID = UUID(), question: String, answer: String, evidence: String,
                period: WellnessPeriod, fingerprint: String, contextJSON: String,
                createdAt: Date = .now, model: String) {
        self.id = id
        self.question = question
        self.answer = answer
        self.evidence = evidence
        self.period = period
        self.fingerprint = fingerprint
        self.contextJSON = contextJSON
        self.createdAt = createdAt
        self.model = model
    }

    public func validate() throws {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, question.count <= 200,
              !trimmedAnswer.isEmpty, answer.count <= 4000,
              contextJSON.count <= 120_000,
              fingerprint.count <= 32,
              !evidence.isEmpty, evidence.count <= 500,
              !model.isEmpty, model.count <= 200,
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DiaryError.invalidResponse("追问回答不完整，请重新提问。")
        }
    }
}
