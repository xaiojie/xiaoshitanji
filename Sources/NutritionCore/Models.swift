import Foundation

public enum DiaryError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case unreadableDiary
    case unsupportedVersion
    case storage(String)
    case invalidResponse(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .invalidResponse(let message): message
        case .unreadableDiary: "饮食记录文件无法读取。原文件已保留，请先导出备份后检查。"
        case .unsupportedVersion: "记录来自更新版本的应用，请升级应用后再打开。"
        case .storage(let message): "记录未能保存，草稿已保留。\(message)"
        case .http(401): "AI 服务暂时不可用，请稍后重试。"
        case .http(402): "AI 服务暂时不可用，请稍后重试。"
        case .http(429): "分析次数较多，请稍后重试。"
        case .http(400), .http(422): "AI 无法处理这次输入，请简化描述或更换照片后重试。"
        case .http(let status) where status >= 500: "AI 服务暂时不可用，请稍后重试。"
        case .http(let status): "AI 请求失败（HTTP \(status)），请稍后重试。"
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
    public var nutritionLabel: NutritionLabel?
    /// 由用户手工填写或改写的食物，界面会标注「手动」而不是 AI 估算。
    public var isManual: Bool

    public init(id: UUID = UUID(), name: String = "", grams: Double = 100,
                per100g: Nutrition = .zero, notes: String = "", portionDescription: String? = nil,
                nutritionLabel: NutritionLabel? = nil, isManual: Bool = false) {
        self.id = id
        self.name = name
        self.grams = grams
        self.per100g = per100g
        self.notes = notes
        self.portionDescription = portionDescription
        self.nutritionLabel = nutritionLabel
        self.isManual = isManual
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, grams, per100g, notes, portionDescription, nutritionLabel, isManual
    }

    /// 旧版本文件没有 `isManual`，用显式解码保证兼容性，避免升级后读不出历史记录。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        grams = try container.decode(Double.self, forKey: .grams)
        per100g = try container.decode(Nutrition.self, forKey: .per100g)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        portionDescription = try container.decodeIfPresent(String.self, forKey: .portionDescription)
        nutritionLabel = try container.decodeIfPresent(NutritionLabel.self, forKey: .nutritionLabel)
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
    }

    /// 手填营养值：用户给的是这一份的总量，内部再折算成每 100 克，便于之后按份量缩放。
    public static func manual(name: String, nutrition: Nutrition, grams: Double? = nil,
                              portionDescription: String? = nil, notes: String = "") -> FoodItem {
        let weight = grams ?? 100
        let per100g = weight > 0 ? nutrition.scaled(by: 100 / weight) : .zero
        return FoodItem(name: name, grams: weight, per100g: per100g, notes: notes,
                        portionDescription: portionDescription, nutritionLabel: nil, isManual: true)
    }

    /// 直接改写营养值：保留食物身份，去掉旧标签依据，并标记为手动修改。
    public func withManualNutrition(_ nutrition: Nutrition, grams: Double? = nil,
                                    portionDescription: String? = nil) throws -> FoodItem {
        var food = self
        if let grams { food.grams = grams }
        food.per100g = food.grams > 0 ? nutrition.scaled(by: 100 / food.grams) : .zero
        food.nutritionLabel = nil
        food.isManual = true
        if let portionDescription { food.portionDescription = portionDescription }
        try food.validate()
        return food
    }

    public var nutrition: Nutrition { nutritionLabel?.nutrition ?? per100g.scaled(by: grams / 100) }
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
        food.nutritionLabel?.consumedAmount *= multiplier
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
        try nutritionLabel?.validate()
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
    /// 旧数据里内嵌的 base64 照片；迁移后为 nil。
    public var photoJPEG: Data?
    /// 照片文件名（相对 `Photos/`），新数据只存这个。
    public var photoFileName: String?
    public var source: RecordSource
    public var model: String?
    public var summary: String
    public var assumptions: [String]
    public var adjustments: [String]?
    public var analysisMode: FoodAnalysisMode?

    public init(id: UUID = UUID(), date: Date = .now, kind: MealKind = .lunch,
                foods: [FoodItem] = [], originalText: String = "", photoJPEG: Data? = nil,
                photoFileName: String? = nil,
                source: RecordSource = .manual, model: String? = nil,
                summary: String = "", assumptions: [String] = [], adjustments: [String]? = nil,
                analysisMode: FoodAnalysisMode? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.foods = foods
        self.originalText = originalText
        self.photoJPEG = photoJPEG
        self.photoFileName = photoFileName
        self.source = source
        self.model = model
        self.summary = summary
        self.assumptions = assumptions
        self.adjustments = adjustments
        self.analysisMode = analysisMode
    }

    public var nutrition: Nutrition { foods.reduce(.zero) { $0 + $1.nutrition } }
    public var foodNames: String { foods.map(\.name).joined(separator: " · ") }

    public static func draft(on day: Date, kind: MealKind? = nil, now: Date = .now,
                              calendar: Calendar = .current) -> MealRecord {
        var record = MealRecord(date: day, kind: kind ?? .suggested(for: now, calendar: calendar))
        record.usePresetTime(for: record.kind, now: now, calendar: calendar)
        return record
    }

    public mutating func usePresetTime(for kind: MealKind, now: Date = .now, calendar: Calendar = .current) {
        let time: (hour: Int, minute: Int, second: Int)
        switch kind {
        case .breakfast: time = (8, 45, 0)
        case .lunch: time = (12, 0, 0)
        case .dinner: time = (20, 0, 0)
        case .snack:
            time = (calendar.component(.hour, from: now), calendar.component(.minute, from: now),
                    calendar.component(.second, from: now))
        }
        self.kind = kind
        date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: time.second, of: date) ?? date
    }

    public mutating func updateInput(text: String, photoJPEG: Data?, analysisMode: FoodAnalysisMode? = nil) {
        let mode = analysisMode ?? self.analysisMode ?? .automatic
        guard text != originalText || photoJPEG != self.photoJPEG || mode != (self.analysisMode ?? .automatic) else { return }
        originalText = text
        self.photoJPEG = photoJPEG
        // 换了照片就让旧文件名失效，保存时会按记录 id 重新写文件。
        self.photoFileName = nil
        self.analysisMode = mode
        if source != .manual {
            foods = []
            source = .manual
            model = nil
            summary = ""
            assumptions = []
            adjustments = nil
        }
    }

    public mutating func addFood(_ food: FoodItem) throws {
        guard foods.count < 50 else { throw DiaryError.invalidInput("每餐最多记录 50 种食物。") }
        guard !foods.contains(where: { $0.id == food.id }) else {
            throw DiaryError.invalidInput("这种食物已经在这一餐里了。")
        }
        try food.validate()
        foods.append(food)
    }

    public mutating func replaceFood(_ food: FoodItem) throws {
        guard let index = foods.firstIndex(where: { $0.id == food.id }) else {
            throw DiaryError.invalidInput("这种食物已不在这一餐里，请重新打开记录。")
        }
        try food.validate()
        foods[index] = food
        adjustments = (adjustments ?? []) + ["「\(food.name)」的营养值改为手动填写"]
    }

    public func validate() throws {
        if let photoFileName, !PhotoArchive.validName(photoFileName) {
            throw DiaryError.invalidInput("照片文件名不合法。")
        }
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
    /// 2：新增「常吃组合」（templates）与手填食物标记（FoodItem.isManual）。
    /// 3：新增训练记录（workouts）。
    /// 4：照片外置（photoFileName），diary.json 不再内嵌 base64。
    /// 5：新增训练计划（plans）。
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int = DiaryDocument.currentSchemaVersion
    public var records: [MealRecord]
    public var reviews: [DietReview]
    public var profile: HealthProfile
    public var weights: [WeightRecord]
    public var smoking: SmokingDiary
    public var wellnessReviews: [WellnessReview]
    public var workouts: [WorkoutRecord]
    public var plans: [WorkoutPlan]
    public var templates: [MealTemplate]
    public var observations: [AnalysisAnswer]
    /// 为 nil 时还没有配置能量目标，App 退回旧的「参考热量」。
    public var energy: EnergySettings?

    public init(records: [MealRecord] = [], reviews: [DietReview] = [],
                profile: HealthProfile = HealthProfile(), weights: [WeightRecord] = [], smoking: SmokingDiary = SmokingDiary(),
                wellnessReviews: [WellnessReview] = [], workouts: [WorkoutRecord] = [],
                plans: [WorkoutPlan] = [], templates: [MealTemplate] = [],
                observations: [AnalysisAnswer] = [], energy: EnergySettings? = nil) {
        self.records = records
        self.reviews = reviews
        self.profile = profile
        self.weights = weights
        self.smoking = smoking
        self.wellnessReviews = wellnessReviews
        self.workouts = workouts
        self.plans = plans
        self.templates = templates
        self.observations = observations
        self.energy = energy
    }

    private enum CodingKeys: CodingKey { case schemaVersion, records, reviews, profile, weights, smoking, wellnessReviews, workouts, plans, templates, observations, energy }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        records = try container.decode([MealRecord].self, forKey: .records)
        reviews = try container.decodeIfPresent([DietReview].self, forKey: .reviews) ?? []
        profile = try container.decodeIfPresent(HealthProfile.self, forKey: .profile) ?? HealthProfile()
        weights = try container.decodeIfPresent([WeightRecord].self, forKey: .weights) ?? []
        smoking = try container.decodeIfPresent(SmokingDiary.self, forKey: .smoking) ?? SmokingDiary()
        wellnessReviews = try container.decodeIfPresent([WellnessReview].self, forKey: .wellnessReviews) ?? []
        workouts = try container.decodeIfPresent([WorkoutRecord].self, forKey: .workouts) ?? []
        plans = try container.decodeIfPresent([WorkoutPlan].self, forKey: .plans) ?? []
        templates = try container.decodeIfPresent([MealTemplate].self, forKey: .templates) ?? []
        observations = try container.decodeIfPresent([AnalysisAnswer].self, forKey: .observations) ?? []
        energy = try container.decodeIfPresent(EnergySettings.self, forKey: .energy)
    }

    public func validate() throws {
        guard (1...DiaryDocument.currentSchemaVersion).contains(schemaVersion) else {
            throw DiaryError.unsupportedVersion
        }
        guard Set(records.map(\.id)).count == records.count else {
            throw DiaryError.unreadableDiary
        }
        for record in records { try record.validate() }
        for review in reviews { try review.validate() }
        try profile.validate()
        guard Set(weights.map(\.id)).count == weights.count else { throw DiaryError.unreadableDiary }
        for weight in weights { try weight.validate() }
        try smoking.validate()
        for report in wellnessReviews { try report.validate() }
        guard Set(workouts.map(\.id)).count == workouts.count else { throw DiaryError.unreadableDiary }
        for workout in workouts { try workout.validate() }
        guard Set(plans.map(\.id)).count == plans.count else { throw DiaryError.unreadableDiary }
        for plan in plans { try plan.validate() }
        guard Set(templates.map(\.id)).count == templates.count else { throw DiaryError.unreadableDiary }
        for template in templates { try template.validate() }
        guard Set(observations.map(\.id)).count == observations.count else { throw DiaryError.unreadableDiary }
        for answer in observations { try answer.validate() }
        try energy?.validate()
    }

    /// 计划满 20 条时淘汰最久没用的。
    public mutating func savePlan(_ plan: WorkoutPlan) throws {
        try plan.validate()
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        if plans.count > 20 {
            plans.sort { $0.lastUsedAt > $1.lastUsedAt }
            plans.removeLast(plans.count - 20)
        }
    }

    public mutating func removePlan(id: UUID) {
        plans.removeAll { $0.id == id }
    }

    public func recentPlans(limit: Int = 10) -> [WorkoutPlan] {
        Array(plans.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(limit))
    }

    /// 从计划开练：生成训练记录并记一次使用；找不到计划时返回 nil。
    public mutating func startWorkout(fromPlan id: UUID, on date: Date = .now) throws -> WorkoutRecord? {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return nil }
        var plan = plans[index]
        plan.markUsed(now: date)
        plans[index] = plan
        let workout = plan.makeWorkout(on: date)
        try workout.validate()
        try saveWorkout(workout)
        return workout
    }

    public mutating func saveWorkout(_ workout: WorkoutRecord) throws {
        try workout.validate()
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = workout
        } else {
            workouts.append(workout)
        }
    }

    public mutating func removeWorkout(id: UUID) {
        workouts.removeAll { $0.id == id }
    }

    public func workouts(on day: Date, calendar: Calendar = .current) -> [WorkoutRecord] {
        workouts.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    public mutating func saveTemplate(_ template: MealTemplate) throws {
        try template.validate()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        if templates.count > 50 {
            templates.sort { $0.lastUsedAt > $1.lastUsedAt }
            templates.removeLast(templates.count - 50)
        }
    }

    public mutating func removeTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
    }

    public func recentTemplates(limit: Int = 10) -> [MealTemplate] {
        Array(templates.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(limit))
    }

    public mutating func saveWellnessReview(_ report: WellnessReview) throws {
        try report.validate()
        wellnessReviews.removeAll { $0.snapshot.period == report.snapshot.period }
        wellnessReviews.append(report)
    }

    public mutating func saveObservation(_ answer: AnalysisAnswer) throws {
        try answer.validate()
        observations.removeAll { $0.id == answer.id }
        observations.append(answer)
        if observations.count > 30 {
            observations.sort { $0.createdAt > $1.createdAt }
            observations.removeLast(observations.count - 30)
        }
    }

    public mutating func removeObservation(id: UUID) {
        observations.removeAll { $0.id == id }
    }

    public func observations(for period: WellnessPeriod) -> [AnalysisAnswer] {
        observations.filter { $0.period == period }.sorted { $0.createdAt > $1.createdAt }
    }

    public mutating func updateProfile(_ profile: HealthProfile, weightKG: Double? = nil, date: Date = .now) throws {
        try profile.validate()
        let weight = try weightKG.map { value in
            let entry = WeightRecord(date: date, kilograms: value)
            try entry.validate()
            return entry
        }
        self.profile = profile
        if let weight { weights.append(weight) }
    }

    public mutating func saveWeight(_ weight: WeightRecord) throws {
        try weight.validate()
        if let index = weights.firstIndex(where: { $0.id == weight.id }) { weights[index] = weight }
        else { weights.append(weight) }
    }

    public mutating func removeWeight(id: UUID) { weights.removeAll { $0.id == id } }

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

    /// 有记录的那些天各自的摄入热量，用于校准维持热量。
    public func dailyCalories(withinDays days: Int = 28, now: Date = .now, calendar: Calendar = .current) -> [Double] {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        let grouped = Dictionary(grouping: records.filter { $0.date >= start && $0.date <= now },
                                 by: { calendar.startOfDay(for: $0.date) })
        return grouped.values.map { $0.reduce(.zero) { $0 + $1.nutrition }.calories }
    }

    /// 最近吃过的餐食，新到旧；用于「复制上一餐 / 昨天」。
    public func recentRecords(limit: Int = 10, before date: Date = .distantFuture) -> [MealRecord] {
        Array(records.filter { $0.date < date }.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// 历史里吃过的食物，按名称去重、新到旧，可按关键词过滤。
    public func matchingFoods(query: String = "", limit: Int = 8) -> [FoodItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        var result: [FoodItem] = []
        for record in records.sorted(by: { $0.date > $1.date }) {
            for food in record.foods {
                let key = food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty, !seen.contains(key) else { continue }
                if !needle.isEmpty && !key.contains(needle) { continue }
                seen.insert(key)
                result.append(food)
                if result.count >= limit { return result }
            }
        }
        return result
    }
}
