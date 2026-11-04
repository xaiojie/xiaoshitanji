import Foundation
import Testing
@testable import NutritionCore

@Suite("抽烟累计")
struct SmokingStatsTests {
    @Test("按根数累计，分烟不算自己抽")
    func totalsSmokedAndShared() throws {
        var document = DiaryDocument()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let pack = CigarettePack(product: CigaretteProduct(name: "测试烟", pricePerPack: 20, currency: .cny),
                                 openedAt: start, openingCount: 20)
        try document.smoking.openPack(pack)
        try document.smoking.record(.smoked, count: 3, date: start.addingTimeInterval(60))
        try document.smoking.record(.shared, count: 2, date: start.addingTimeInterval(500))

        let totals = SmokingStats.totals(for: document)
        #expect(totals.smoked == 3)
        #expect(totals.shared == 2)
        #expect(totals.packsOpened == 1)
        #expect(abs((totals.costs[.cny] ?? 0) - 3.0) < 0.001)
        #expect(totals.costText().hasPrefix("¥"))
        #expect(totals.lastSmokedDate != nil)
    }

    @Test("没有价格时显示未填，多币种分开算")
    func noPriceAndCurrencies() throws {
        var document = DiaryDocument()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cheap = CigarettePack(product: CigaretteProduct(name: "便宜的", pricePerPack: 10, currency: .cny),
                                  openedAt: start, openingCount: 20)
        let usd = CigarettePack(product: CigaretteProduct(name: "美元烟", pricePerPack: 8, currency: .usd),
                                openedAt: start.addingTimeInterval(100), openingCount: 20)
        try document.smoking.openPack(cheap)
        try document.smoking.record(.smoked, count: 2, date: start.addingTimeInterval(10))
        try document.smoking.openPack(usd)
        try document.smoking.record(.smoked, count: 1, date: start.addingTimeInterval(110))

        let totals = SmokingStats.totals(for: document)
        #expect(abs((totals.costs[.cny] ?? 0) - 1.0) < 0.001)
        #expect(abs((totals.costs[.usd] ?? 0) - 0.4) < 0.001)
        #expect(totals.costText().contains("¥1") && totals.costText().contains("$0.40"))

        let empty = SmokingStats.totals(for: DiaryDocument())
        #expect(!empty.hasData)
        #expect(empty.costText() == "未填价格")
    }
}
