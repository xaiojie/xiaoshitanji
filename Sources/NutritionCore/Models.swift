import Foundation

public enum DiaryError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case unreadableDiary
    case unsupportedVersion
    case storage(String)
    case missingAPIKey
    case invalidResponse(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .invalidResponse(let message): message
        case .unreadableDiary: "饮食记录文件无法读取。原文件已保留，请先导出备份后检查。"
        case .unsupportedVersion: "记录来自更新版本的应用，请升级应用后再打开。"
        case .storage(let message): "记录未能保存，草稿已保留。\(message)"
        case .missingAPIKey: "请先在「我的」中配置 DeepSeek API Key，再开始 AI 记餐。"
        case .http(401): "DeepSeek API Key 无效，请到「我的」中检查。"
        case .http(402): "DeepSeek 账户余额不足，请充值后重试。"
        case .http(429): "DeepSeek 请求较多，请稍后重试。"
        case .http(400), .http(422): "DeepSeek 无法处理这次输入，请检查模型设置或更换照片后重试。"
        case .http(let status) where status >= 500: "DeepSeek 服务暂时不可用，请稍后重试。"
        case .http(let status): "DeepSeek 请求失败（HTTP \(status)），请稍后重试。"
        }
    }
}

public struct Nutrition: Codable, Equatable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double

    public init(calories: Double = 0, protein: Double = 0, carbohydrates: Double = 0, fat: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }

    public static let zero = Nutrition()

    public func scaled(by factor: Double) -> Nutrition {
        Nutrition(calories: calories * factor, protein: protein * factor,
                  carbohydrates: carbohydrates * factor, fat: fat * factor)
    }

    public static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                  carbohydrates: lhs.carbohydrates + rhs.carbohydrates, fat: lhs.fat + rhs.fat)
    }

    public func validate() throws {
        guard [calories, protein, carbohydrates, fat].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw DiaryError.invalidInput("热量或营养估算无效，请重新分析。")
        }
    }
}

public struct FoodItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var grams: Double
    public var per100g: Nutrition
    public var notes: String
    public var portionDescription: String?

    public init(id: UUID = UUID(), name: String = "", grams: Double = 100,
                per100g: Nutrition = .zero, notes: String = "", portionDescription: String? = nil) {
        self.id = id
        self.name = name
        self.grams = grams
        self.per100g = per100g
        self.notes = notes
        self.portionDescription = portionDescription
    }

    public var nutrition: Nutrition { per100g.scaled(by: grams / 100) }
    public var portionLabel: String {
        let label = portionDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? "一份" : label
    }

    public func scaledPortion(by multiplier: Double, description: String) throws -> FoodItem {
        guard multiplier.isFinite && multiplier > 0 else {
            throw DiaryError.invalidInput("请选择有效的食用份量。")
        }
        var food = self
        food.grams *= multiplier
        food.portionDescription = description
        try food.validate()
        return food
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiaryError.invalidInput("没有识别到食物名称，请补充描述后重试。")
        }
        guard grams.isFinite && grams > 0 else {
            throw DiaryError.invalidInput("「\(name)」的份量估算无效，请重新分析。")
        }
        try per100g.validate()
        try nutrition.validate()
    }
}

public enum MealKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: "sun.horizon"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    public static func suggested(for date: Date = .now, calendar: Calendar = .current) -> MealKind {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

public enum RecordSource: String, Codable, Sendable {
    case text, photo, manual

    public var title: String {
        switch self {
        case .text: "文字估算"
        case .photo: "图片估算"
        case .manual: "手动记录"
        }
    }
}

public struct MealRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: MealKind
    public var foods: [FoodItem]
    public var originalText: String
    public var photoJPEG: Data?
    public var source: RecordSource
    public var model: String?
    public var summary: String
    public var assumptions: [String]
    public var adjustments: [String]?

    public init(id: UUID = UUID(), date: Date = .now, kind: MealKind = .lunch,
                foods: [FoodItem] = [], originalText: String = "", photoJPEG: Data? = nil,
                source: RecordSource = .manual, model: String? = nil,
                summary: String = "", assumptions: [String] = [], adjustments: [String]? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.foods = foods
        self.originalText = originalText
        self.photoJPEG = photoJPEG
        self.source = source
        self.model = model
        self.summary = summary
        self.assumptions = assumptions
        self.adjustments = adjustments
    }

    public var nutrition: Nutrition { foods.reduce(.zero) { $0 + $1.nutrition } }
    public var foodNames: String { foods.map(\.name).joined(separator: " · ") }

    public static func draft(on day: Date, now: Date = .now, calendar: Calendar = .current) -> MealRecord {
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                 second: time.second ?? 0, of: day) ?? day
        return MealRecord(date: date, kind: .suggested(for: date, calendar: calendar))
    }

    public mutating func updateInput(text: String, photoJPEG: Data?) {
        guard text != originalText || photoJPEG != self.photoJPEG else { return }
        originalText = text
        self.photoJPEG = photoJPEG
        if source != .manual {
            foods = []
            source = .manual
            model = nil
            summary = ""
            assumptions = []
            adjustments = nil
        }
    }

    public func validate() throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw DiaryError.invalidInput("请选择有效的记录时间。")
        }
        guard !foods.isEmpty && foods.count <= 50 else {
            throw DiaryError.invalidInput("每餐需要包含 1 至 50 种食物。")
        }
        guard Set(foods.map(\.id)).count == foods.count else {
            throw DiaryError.invalidInput("食物记录重复，请重新添加。")
        }
        for food in foods { try food.validate() }
        try nutrition.validate()
    }
}

public struct DiaryDocument: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var records: [MealRecord]
    public var reviews: [DietReview]

    public init(records: [MealRecord] = [], reviews: [DietReview] = []) {
        self.records = records
        self.reviews = reviews
    }

    private enum CodingKeys: CodingKey { case schemaVersion, records, reviews }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        records = try container.decode([MealRecord].self, forKey: .records)
        reviews = try container.decodeIfPresent([DietReview].self, forKey: .reviews) ?? []
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw DiaryError.unsupportedVersion }
        guard Set(records.map(\.id)).count == records.count else {
            throw DiaryError.unreadableDiary
        }
        for record in records { try record.validate() }
        for review in reviews { try review.validate() }
    }

    public mutating func upsert(_ record: MealRecord) throws {
        try record.validate()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            if records[index] == record { return }
            invalidateReview(on: records[index].date)
            records[index] = record
        } else {
            records.append(record)
        }
        invalidateReview(on: record.date)
    }

    public mutating func remove(id: UUID) {
        if let record = records.first(where: { $0.id == id }) { invalidateReview(on: record.date) }
        records.removeAll { $0.id == id }
    }

    public func review(on date: Date, calendar: Calendar = .current) -> DietReview? {
        reviews.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public mutating func saveReview(_ review: DietReview, snapshot: [MealRecord], calendar: Calendar = .current) throws {
        try review.validate()
        guard !snapshot.isEmpty, review.recordCount == snapshot.count,
              records(on: review.date, calendar: calendar) == snapshot.sorted(by: { $0.date < $1.date }) else {
            throw DiaryError.invalidInput("饮食记录已更新，请重新分析这一天。")
        }
        reviews.removeAll { calendar.isDate($0.date, inSameDayAs: review.date) }
        reviews.append(review)
    }

    private mutating func invalidateReview(on date: Date) {
        reviews.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    public func records(on date: Date, calendar: Calendar = .current) -> [MealRecord] {
        records.filter { calendar.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }

    public func total(on date: Date, calendar: Calendar = .current) -> Nutrition {
        records(on: date, calendar: calendar).reduce(.zero) { $0 + $1.nutrition }
    }
}
