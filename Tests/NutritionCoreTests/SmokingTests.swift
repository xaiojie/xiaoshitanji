import Foundation
import Testing
@testable import NutritionCore

struct SmokingTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func pack(remaining: Int = 20, nicotine: Double? = 0.8, price: Double? = 30) -> CigarettePack {
        CigarettePack(product: CigaretteProduct(name: "测试香烟", nicotineMG: nicotine, pricePerPack: price),
                      openedAt: date, openingCount: remaining)
    }

    @Test func sharingOnlyReducesStockAndSmokingCountsPersonalLabelYield() throws {
        var diary = SmokingDiary()
        let pack = pack(remaining: 8)
        try diary.openPack(pack)
        try diary.record(.smoked, count: 1, date: date)
        try diary.record(.shared, count: 3, date: date)
        #expect(diary.remaining(in: pack.id) == 4)
        let day = diary.summary(on: date)
        #expect(day.smoked == 1)
        #expect(day.shared == 3)
        #expect(day.knownNicotineMG == 0.8)
        #expect(day.unknownNicotineCount == 0)
        #expect(day.costs[.cny] == 1.5)
    }

    @Test func stockCheckAndUndoKeepInventoryConsistent() throws {
        var diary = SmokingDiary()
        let pack = pack(remaining: 5)
        try diary.openPack(pack)
        try diary.record(.smoked, count: 1, date: date)
        try diary.record(.stockCheck, count: 2, date: date)
        #expect(diary.remaining(in: pack.id) == 2)
        #expect(diary.summary(on: date).smoked == 1)
        let last = try #require(diary.events.last)
        try diary.removeEvent(id: last.id)
        #expect(diary.remaining(in: pack.id) == 4)
        try diary.removeEvent(id: #require(diary.events.last).id)
        #expect(diary.remaining(in: pack.id) == 5)
    }

    @Test func emptyAndInvalidOperationsCannotPartiallyChangeTheJournal() throws {
        var diary = SmokingDiary()
        let pack = pack(remaining: 1)
        try diary.openPack(pack)
        #expect(throws: DiaryError.self) { try diary.record(.shared, count: 2, date: date) }
        #expect(diary.events.isEmpty)
        try diary.record(.smoked, count: 1, date: date)
        #expect(throws: DiaryError.self) { try diary.record(.smoked, count: 1, date: date) }
        #expect(throws: DiaryError.self) { try diary.record(.stockCheck, count: 21, date: date) }
        #expect(diary.events.count == 1)
        #expect(diary.remaining(in: pack.id) == 0)
    }

    @Test func unknownNicotineAndPricesStayUnknownAndPacksKeepTheirSnapshots() throws {
        var diary = SmokingDiary()
        let first = pack(nicotine: nil, price: nil)
        try diary.openPack(first)
        try diary.record(.smoked, count: 2, date: date)
        let second = pack(nicotine: 0.5, price: 20)
        try diary.openPack(second)
        try diary.record(.smoked, count: 1, date: date)
        let summary = diary.summary(on: date)
        #expect(summary.smoked == 3)
        #expect(summary.knownNicotineMG == 0.5)
        #expect(summary.unknownNicotineCount == 2)
        #expect(summary.unpricedCount == 2)
        #expect(summary.costs[.cny] == 1)
        #expect(diary.remaining(in: first.id) == 18)
        #expect(diary.remaining(in: second.id) == 19)
        try diary.activatePack(id: first.id)
        #expect(diary.activePack?.id == first.id)
    }

    @Test func smokingRoundTripAndLegacyCompatibilityKeepDailyCounts() throws {
        var document = DiaryDocument()
        try document.smoking.openPack(pack())
        try document.smoking.record(.smoked, count: 1, date: date)
        let reopened = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(document))
        try reopened.validate()
        #expect(reopened.smoking.summary(on: date).smoked == 1)
        #expect(reopened.smoking.summary(on: date.addingTimeInterval(86_400)).smoked == 0)
        let old = try JSONDecoder().decode(DiaryDocument.self, from: Data(#"{"schemaVersion":1,"records":[]}"#.utf8))
        #expect(old.smoking.events.isEmpty)
    }

    @Test func cigaretteRecognitionRequiresReadableEvidenceAndNeverInventsUnknownValues() throws {
        let content = #"{"name":"测试烟","nicotineMG":0.8,"nicotineEvidence":"烟气烟碱量0.8mg","pricePerPack":30,"priceEvidence":null,"currency":"CNY","notes":"价格未看见"}"#
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]])
        let recognized = try DeepSeekClient.parseCigaretteResponse(data: response, statusCode: 200)
        #expect(recognized.product.nicotineMG == 0.8)
        #expect(recognized.product.pricePerPack == nil)
        let request = try DeepSeekClient.makeCigaretteRequest(text: "这一包", imageJPEG: Data([1, 2]), apiKey: "test-key")
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self).contains("不得猜测"))
        #expect(throws: DiaryError.self) { try DeepSeekClient.parseCigaretteResponse(data: response, statusCode: 401) }
    }

    @Test func editingPackMetadataUpdatesItsHistoryAndInvalidStockEditsAreAtomic() throws {
        var journal = SmokingDiary()
        var pack = pack(nicotine: nil, price: nil)
        try journal.openPack(pack)
        try journal.record(.smoked, count: 1, date: date)
        pack.product.nicotineMG = 0.5
        pack.product.pricePerPack = 40
        try journal.updatePack(pack)
        #expect(journal.summary(on: date).knownNicotineMG == 0.5)
        #expect(journal.summary(on: date).costs[.cny] == 2)
        pack.openingCount = 0
        #expect(throws: DiaryError.self) { try journal.updatePack(pack) }
        #expect(journal.remaining(in: pack.id) == 19)
        #expect(journal.packs[0].openingCount == 20)
    }

    @Test func mixedCurrenciesStaySeparateAndRecordedZeroNicotineIsKnown() throws {
        var journal = SmokingDiary()
        let first = pack(nicotine: 0, price: 0)
        try journal.openPack(first)
        try journal.record(.smoked, count: 1, date: date)
        let second = CigarettePack(product: CigaretteProduct(name: "第二包", nicotineMG: nil, pricePerPack: 40_000, currency: .vnd), openedAt: date)
        try journal.openPack(second)
        try journal.record(.smoked, count: 1, date: date)
        let summary = journal.summary(on: date)
        #expect(summary.unknownNicotineCount == 1)
        #expect(summary.costs[.cny] == 0)
        #expect(summary.costs[.vnd] == 2_000)
    }

    @Test func sidePhotoCanFillNicotineWhileKeepingEnteredBrandAndPrice() throws {
        let content = #"{"name":"","nicotineMG":0.8,"nicotineEvidence":"烟气烟碱量0.8mg","pricePerPack":null,"priceEvidence":null,"currency":null,"notes":"侧面只有烟碱标注"}"#
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]])
        let result = try DeepSeekClient.parseCigaretteResponse(data: response, statusCode: 200)
        #expect(result.product.nicotineMG == 0.8)
        var draft = CigaretteProductDraft(product: CigaretteProduct(name: "已确认品牌", pricePerPack: 30))
        draft.fillMissing(from: result)
        let product = try draft.makeProduct()
        #expect(product.name == "已确认品牌")
        #expect(product.pricePerPack == 30)
        #expect(product.nicotineMG == 0.8)
    }

    @Test func recognizedUnknownPricePreservesTheManuallyConfirmedAmount() throws {
        let content = #"{"name":"新识别名称","nicotineMG":null,"pricePerPack":null}"#
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]])
        let result = try DeepSeekClient.parseCigaretteResponse(data: response, statusCode: 200)
        var draft = CigaretteProductDraft(product: CigaretteProduct(name: "已确认名称", nicotineMG: 0.5, pricePerPack: 30))
        draft.fillMissing(from: result)
        let product = try draft.makeProduct()
        #expect(product.name == "已确认名称")
        #expect(product.pricePerPack == 30)
        #expect(product.nicotineMG == 0.5)
    }
}
