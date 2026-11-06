import Foundation

/// AI 只接收可核对的摘要，轨迹与原始心率样本由 RunArchive 保留。
public struct RunAnalysisContext: Codable, Sendable {
    public let date: String
    public let distanceMeters: Double
    public let activeSeconds: Double
    public let averagePaceSecondsPerKM: Double?
    public let targetMeters: Double?
    public let goalReached: Bool
    public let trackSegments: Int
    public let averageHeartRate: Double?
    public let maximumHeartRate: Double?
    public let heartRateSampleCount: Int?
    public let weightKG: Double?
    public let weightMeasuredAt: String?
    public let estimatedActiveCalories: Double?
    public let recordedMeals: Int?
    public let recordedNutrition: Nutrition?

    public init(record: RunRecord, document: DiaryDocument, includesHeartRate: Bool, includesDietAndBody: Bool) {
        let session = record.session
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        date = formatter.string(from: session.startedAt)
        distanceMeters = session.distanceMeters
        activeSeconds = session.activeSeconds(at: session.lastCheckpoint)
        averagePaceSecondsPerKM = session.averagePace
        targetMeters = session.targetMeters
        goalReached = session.goalReached
        trackSegments = Set(session.points.map(\.segment)).count
        let heart = includesHeartRate ? record.heartRate : nil
        averageHeartRate = heart?.average
        maximumHeartRate = heart?.maximum
        heartRateSampleCount = heart?.points.count
        let weight = includesDietAndBody
            ? document.weights.filter { $0.date <= session.startedAt }.max { $0.date < $1.date } : nil
        weightKG = weight?.kilograms
        weightMeasuredAt = weight.map { formatter.string(from: $0.date) }
        estimatedActiveCalories = session.estimatedCalories(weightKG: weight?.kilograms)
        let meals = document.records(on: session.startedAt)
        recordedMeals = includesDietAndBody ? meals.count : nil
        recordedNutrition = includesDietAndBody && !meals.isEmpty ? document.total(on: session.startedAt) : nil
    }
}

public struct RunAdvice: Codable, Equatable, Sendable {
    public let summary: String
    public let suggestions: [String]
    public let limitations: [String]

    func validate() throws {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, summary.count <= 2000,
              (1...3).contains(suggestions.count),
              suggestions.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1000 }),
              limitations.count <= 5, limitations.allSatisfy({ !$0.isEmpty && $0.count <= 1000 }) else {
            throw DiaryError.invalidResponse("跑步建议不完整，请重试。")
        }
    }
}

public extension DeepSeekClient {
    static func makeRunAnalysisRequest(_ context: RunAnalysisContext) throws -> URLRequest {
        guard context.distanceMeters.isFinite, (0...1_000_000).contains(context.distanceMeters),
              context.activeSeconds.isFinite, context.activeSeconds > 0 else {
            throw DiaryError.invalidInput("请先完成并保存一次跑步。")
        }
        let data = try JSONEncoder().encode(context)
        return try buildRequest(parts: [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
                                prompt: runAnalysisPrompt)
    }

    func analyzeRun(_ context: RunAnalysisContext) async throws -> RunAdvice {
        let (data, status) = try await complete(Self.makeRunAnalysisRequest(context))
        guard (200..<300).contains(status) else { throw DiaryError.http(status) }
        do {
            let completion = try JSONDecoder().decode(Completion.self, from: data)
            guard let choice = completion.choices.first, choice.finish_reason == "stop",
                  let content = choice.message.content else {
                throw DiaryError.invalidResponse("跑步建议尚未生成完成，请重试。")
            }
            let result = try JSONDecoder().decode(RunAdvice.self, from: Data(content.utf8))
            try result.validate()
            return result
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.invalidResponse("跑步建议格式异常，请重试。") }
    }

    private static var runAnalysisPrompt: String {
        """
        你是小食痰记的奶蛙跑步记录助手。使用简体中文，亲切而具体。
        输入是本次跑步的统计与用户明确选择的已记录饮食、身体和心率统计。
        先引用实际距离、有效时长和配速，再给 1 至 3 条容易执行的训练、补餐或休息建议。
        营养只代表已经记录的餐食，不能假定全天都已记录。体重须结合测量日期看待。
        心率平均值和最高值仅代表返回样本，样本少时说明覆盖不足。
        未提供年龄、性别、个人最大心率、静息心率、训练史或症状时保持未知。
        不猜测心率区间，不判断心脏是否健康，不据单次心率建议加大强度，不诊断疾病。
        缺失字段保持未知，GPS 中断与分段会影响配速解读。估算消耗明确说估算。
        目标达成仅依据 goalReached，用户允许继续超过目标，禁止把估算当作精确实测。
        返回 JSON 对象，字段为 summary 字符串、suggestions 字符串数组、limitations 字符串数组。
        """
    }
}
