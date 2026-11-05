import Foundation
import Testing
@testable import NutritionCore

struct PackagedSizesTests {
    @Test func instantNoodlesOfferWholeCupSizes() {
        let sizes = PackagedSizes.suggestions(for: "香辣牛肉面")
        #expect(sizes.contains { $0.amount == 140 && $0.unit == .grams })
        #expect(sizes.contains { $0.amount == 120 })
        #expect(PackagedSizes.isSoupy("香辣牛肉面"))
        #expect(PackagedSizes.withoutSoupRatio == 0.9)
    }

    @Test func drinksUseMillilitresAndUnknownFoodsHaveNoSuggestion() {
        let drink = PackagedSizes.suggestions(for: "可乐")
        #expect(drink.allSatisfy { $0.unit == .milliliters })
        #expect(PackagedSizes.suggestions(for: "苹果").isEmpty)
        #expect(!PackagedSizes.isSoupy("苹果"))
    }
}
