import Foundation
import Testing
@testable import NutritionCore

@Suite("成果与里程碑")
struct MilestoneTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!
    }

    private func document(days: [Int], foodsPerMeal: Int = 1) -> DiaryDocument {
        DiaryDocument(records: days.map { offset in
            MealRecord(date: day(offset).addingTimeInterval(12 * 3600), kind: .lunch,
                       foods: (0..<foodsPerMeal).map { index in
                           .manual(name: "食物\(index)", nutrition: Nutrition(calories: 300, protein: 10,
                                                                            carbohydrates: 30, fat: 10))
                       }, source: .manual)
        })
    }

    @Test("连续记录与最长记录")
    func streaks() {
        let stats = Milestones.stats(for: document(days: [-5, -4, -3, -2, -1, 0]), now: today, calendar: calendar)
        #expect(stats.currentStreak == 6)
        #expect(stats.longestStreak == 6)
        #expect(stats.recordedDays == 6)
        #expect(stats.totalMeals == 6)
    }

    @Test("断一天就不算连续")
    func streakBroken() {
        let stats = Milestones.stats(for: document(days: [-6, -5, -2, -1, 0]), now: today, calendar: calendar)
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 3)
    }

    @Test("昨天有记录仍算连记，前天就断了")
    func streakGrace() {
        #expect(Milestones.stats(for: document(days: [-1]), now: today, calendar: calendar).currentStreak == 1)
        #expect(Milestones.stats(for: document(days: [-2]), now: today, calendar: calendar).currentStreak == 0)
    }

    @Test("里程碑按阈值解锁")
    func achievementsUnlock() {
        let items = Milestones.achievements(for: document(days: Array(-6...0), foodsPerMeal: 5),
                                            now: today, calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["first-meal"]?.isAchieved == true)
        #expect(byID["streak-3"]?.isAchieved == true)
        #expect(byID["streak-7"]?.isAchieved == true)
        #expect(byID["streak-30"]?.isAchieved == false)
        #expect(byID["meals-30"]?.isAchieved == true)
        #expect(byID["meals-100"]?.isAchieved == false)
        #expect(byID["template"]?.isAchieved == false)
    }

    @Test("戒烟天数从最后一根算起")
    func smokeFree() {
        var document = document(days: [0])
        try? document.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试烟"), openedAt: day(-10)))
        try? document.smoking.record(.smoked, count: 1, date: day(-10))
        #expect(Milestones.smokeFreeDays(document: document, now: today, calendar: calendar) == 10)
        let items = Milestones.achievements(for: document, now: today, calendar: calendar)
        #expect(items.first { $0.id == "smoke-free-7" }?.isAchieved == true)
        #expect(items.first { $0.id == "smoke-free-30" }?.isAchieved == false)
    }

    @Test("空洞不做假功")
    func emptyDocument() {
        let stats = Milestones.stats(for: DiaryDocument(), now: today, calendar: calendar)
        #expect(stats.totalMeals == 0)
        #expect(stats.currentStreak == 0)
        #expect(stats.smokeFreeDays == nil)
        #expect(Milestones.achievements(for: DiaryDocument(), now: today, calendar: calendar).allSatisfy { !$0.isAchieved })
    }
}
