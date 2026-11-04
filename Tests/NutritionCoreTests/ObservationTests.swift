import Foundation
import Testing
@testable import NutritionCore

struct ObservationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func record(_ day: Int, calories: Double, protein: Double, hour: Int = 12) -> MealRecord {
        MealRecord(date: date(day, hour), kind: .lunch, foods: [
            FoodItem(name: "米饭", grams: 100,
                     per100g: Nutrition(calories: calories, protein: protein, carbohydrates: 0, fat: 0))
        ], source: .manual)
    }

    private func budget(goal: GoalMode = .lose) throws -> EnergyBudget {
        try EnergyCalculator.budget(
            settings: EnergySettings(sex: .male, birthYear: 1995, activity: .moderate, goalMode: goal),
            weightKG: 70, heightCM: 175, now: date(4), calendar: calendar)
    }

    private func context(document: DiaryDocument, period: WellnessPeriod = .week,
                         endDate: Date? = nil, budget: EnergyBudget? = nil) throws -> ObservationContext {
        try ObservationFacts.make(document: document, period: period,
                                   endDate: endDate ?? date(10, 23), budget: budget, calendar: calendar)
    }

    // MARK: 上下文

    @Test func factsDivideByRecordedDaysNotWholeRange() throws {
        let document = DiaryDocument(records: [
            record(9, calories: 600, protein: 20),
            record(10, calories: 800, protein: 30)
        ])
        let facts = try context(document: document).facts
        #expect(facts.meals == 2)
        #expect(facts.recordedDays == 2)
        #expect(facts.averageCalories == 700)
        #expect(facts.averageProtein == 25)
    }

    @Test func factsReportMissingDataAsGaps() throws {
        let facts = try context(document: DiaryDocument()).facts
        #expect(facts.gaps.contains { $0.contains("没有饮食记录") })
        #expect(facts.gaps.contains { $0.contains("没有体重记录") })
        #expect(facts.gaps.contains { $0.contains("没有身高") })
        #expect(facts.gaps.contains { $0.contains("Apple 健康") })
    }

    @Test func evidenceMentionsRangeMealsAndSmoking() throws {
        var document = DiaryDocument(records: [record(10, calories: 700, protein: 30)])
        try document.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试烟"), openedAt: date(1)))
        try document.smoking.record(.smoked, count: 3, date: date(9, 21))
        let context = try context(document: document)
        #expect(context.evidence.contains("11/04–11/10"))
        #expect(context.evidence.contains("1 餐"))
        #expect(context.evidence.contains("3 根烟"))
    }

    @Test func promptJSONContainsNumbersButNoFoodNames() throws {
        let document = DiaryDocument(records: [record(10, calories: 700, protein: 30)])
        let json = try context(document: document).promptJSON()
        #expect(json.contains("averageCalories"))
        #expect(!json.contains("米饭"))
    }

    @Test func fingerprintChangesWhenRecordsChange() throws {
        let first = try context(document: DiaryDocument(records: [record(10, calories: 700, protein: 30)]))
        let same = try context(document: DiaryDocument(records: [record(10, calories: 700, protein: 30)]))
        let changed = try context(document: DiaryDocument(records: [record(10, calories: 900, protein: 30)]))
        #expect(first.fingerprint == same.fingerprint)
        #expect(first.fingerprint != changed.fingerprint)
    }

    // MARK: 回答

    @Test func answerRejectsBlankQuestionAndTooLongText() {
        let blank = AnalysisAnswer(question: "  ", answer: "好", evidence: "依据", period: .week,
                                   fingerprint: "a", contextJSON: "{}", model: "m")
        #expect(throws: DiaryError.self) { try blank.validate() }
        let long = AnalysisAnswer(question: "怎么吃", answer: String(repeating: "好", count: 4001),
                                  evidence: "依据", period: .week, fingerprint: "a",
                                  contextJSON: "{}", model: "m")
        #expect(throws: DiaryError.self) { try long.validate() }
        let valid = AnalysisAnswer(question: "怎么吃", answer: "多吃蛋白。", evidence: "依据",
                                   period: .week, fingerprint: "a", contextJSON: "{}", model: "m")
        #expect(throws: Never.self) { try valid.validate() }
    }

    @Test func documentKeepsLatestThirtyAnswers() throws {
        var document = DiaryDocument()
        for index in 0..<31 {
            let answer = AnalysisAnswer(
                question: "问题 \(index)", answer: "回答 \(index)", evidence: "依据",
                period: index.isMultiple(of: 2) ? .week : .month, fingerprint: "f\(index)",
                contextJSON: "{}", createdAt: date(4).addingTimeInterval(Double(index) * 60),
                model: "deepseek-flash")
            try document.saveObservation(answer)
        }
        #expect(document.observations.count == 30)
        #expect(!document.observations.contains { $0.question == "问题 0" })
        #expect(document.observations(for: .month).allSatisfy { $0.period == .month })
        #expect(document.observations(for: .week).count == 15)
    }

    // MARK: 模式识别

    @Test func lowProteinPatternTriggersBelowWeightFloor() throws {
        var document = DiaryDocument(records: [
            record(8, calories: 700, protein: 20),
            record(9, calories: 700, protein: 25),
            record(10, calories: 700, protein: 30)
        ])
        document.weights = [WeightRecord(date: date(4), kilograms: 70)]
        let patterns = HealthPatternDetector.detect(document: document, context: try context(document: document),
                                                    now: date(10, 23), calendar: calendar)
        let protein = patterns.first { $0.id == "protein-low" }
        #expect(protein != nil)
        #expect(protein?.severity == .attention)
        #expect(protein?.evidence.contains("日均蛋白质 25 克") == true)
    }

    @Test func proteinPatternSkipsWhenEnough() throws {
        var document = DiaryDocument(records: [
            record(8, calories: 900, protein: 120),
            record(9, calories: 900, protein: 120),
            record(10, calories: 900, protein: 120)
        ])
        document.weights = [WeightRecord(date: date(4), kilograms: 70)]
        let patterns = HealthPatternDetector.detect(document: document, context: try context(document: document),
                                                    now: date(10, 23), calendar: calendar)
        #expect(!patterns.contains { $0.id == "protein-low" })
    }

    @Test func smokingWindowDetectsConcentratedHours() throws {
        var document = DiaryDocument()
        try document.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试烟"), openedAt: date(1)))
        for hour in 21...22 { try document.smoking.record(.smoked, count: 3, date: date(8, hour)) }
        try document.smoking.record(.smoked, count: 2, date: date(9, 9))
        let patterns = HealthPatternDetector.detect(document: document, context: try context(document: document),
                                                    now: date(10, 23), calendar: calendar)
        let window = patterns.first { $0.id == "smoking-window" }
        #expect(window != nil)
        #expect(window?.evidence.contains("8 根烟中 6 根") == true)
        #expect(window?.evidence.contains("8 根烟中 6 根（75%）") == true)
    }

    @Test func recordGapFindsLongestHole() throws {
        let document = DiaryDocument(records: [
            record(4, calories: 700, protein: 30),
            record(9, calories: 700, protein: 30)
        ])
        let patterns = HealthPatternDetector.detect(document: document, context: try context(document: document),
                                                    now: date(10, 23), calendar: calendar)
        let gap = patterns.first { $0.id == "record-gap" }
        #expect(gap != nil)
        #expect(gap?.title.contains("4 天") == true)
    }

    @Test func continuousRecordsHaveNoGap() throws {
        let records = (4...9).map { record($0, calories: 700, protein: 30) }
        let document = DiaryDocument(records: records)
        let patterns = HealthPatternDetector.detect(document: document, context: try context(document: document),
                                                    now: date(10, 23), calendar: calendar)
        #expect(!patterns.contains { $0.id == "record-gap" })
    }

    @Test func weightStallNeedsFortnightSpan() throws {
        var document = DiaryDocument()
        document.weights = [
            WeightRecord(date: date(4), kilograms: 70),
            WeightRecord(date: date(20), kilograms: 70.1)
        ]
        let monthContext = try context(document: document, period: .month, endDate: date(24, 23))
        let patterns = HealthPatternDetector.detect(document: document, context: monthContext,
                                                    now: date(24, 23), calendar: calendar)
        #expect(patterns.contains { $0.id == "weight-stall" })

        var young = DiaryDocument()
        young.weights = [WeightRecord(date: date(4), kilograms: 70), WeightRecord(date: date(10), kilograms: 70.1)]
        let youngContext = try context(document: young)
        #expect(!HealthPatternDetector.detect(document: young, context: youngContext,
                                             now: date(10, 23), calendar: calendar).contains { $0.id == "weight-stall" })
    }

    @Test func calorieOvershootComparesToEnergyTarget() throws {
        let target = try budget().targetCalories
        let document = DiaryDocument(records: [
            record(8, calories: target * 1.25, protein: 100),
            record(9, calories: target * 1.25, protein: 100),
            record(10, calories: target * 1.25, protein: 100)
        ])
        let context = try context(document: document, budget: try budget())
        let patterns = HealthPatternDetector.detect(document: document, context: context,
                                                    now: date(10, 23), calendar: calendar)
        #expect(patterns.contains { $0.id == "calorie-over" })
    }

    // MARK: 请求

    @Test func askRequestRejectsLongQuestion() throws {
        let context = try context(document: DiaryDocument())
        #expect(throws: DiaryError.self) {
            _ = try DeepSeekClient.makeAskRequest(context: context, question: String(repeating: "问", count: 201), apiKey: "k")
        }
    }

    @Test func askRequestCarriesContextAndRules() throws {
        let document = DiaryDocument(records: [record(10, calories: 700, protein: 30)])
        let context = try context(document: document)
        let request = try DeepSeekClient.makeAskRequest(context: context, question: "晚饭怎么改？", apiKey: "k")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("averageCalories"))
        #expect(body.contains("晚饭怎么改"))
        #expect(body.contains("不得编造"))
        #expect(!body.contains("米饭"))
    }

    @Test func parseAskResponseBuildsBoundAnswer() throws {
        let context = try context(document: DiaryDocument(records: [record(10, calories: 700, protein: 30)]))
        let envelope = """
        {"model":"deepseek-flash","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"近 7 天只记录了 1 餐，还看不出习惯。"}}]}
        """
        let answer = try DeepSeekClient.parseAskResponse(data: Data(envelope.utf8), statusCode: 200,
                                                         question: "我吃得怎么样？", context: context)
        #expect(answer.answer.contains("1 餐"))
        #expect(answer.fingerprint == context.fingerprint)
        #expect(answer.evidence == context.evidence)
        #expect(answer.period == .week)
    }
}
