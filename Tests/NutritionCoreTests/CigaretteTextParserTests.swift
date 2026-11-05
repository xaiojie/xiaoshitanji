import Foundation
import Testing
@testable import NutritionCore

struct CigaretteTextParserTests {
    @Test func readsPriceAndSmokedCountFromOneSentence() {
        let hints = CigaretteTextParser.parse("这包烟二十，我抽了2一根")
        #expect(hints.price == 20)
        #expect(hints.smoked == 2)
        #expect(hints.remaining == nil)
        #expect(hints.openingCount() == 18)
        #expect(!hints.evidence.isEmpty)
    }

    @Test func readsRemainingCount() {
        let hints = CigaretteTextParser.parse("还剩17")
        #expect(hints.remaining == 17)
        #expect(hints.openingCount() == 17)
        #expect(hints.price == nil)
    }

    @Test func prefersStatedRemainingOverSmoked() {
        let hints = CigaretteTextParser.parse("抽了两根，还剩15根")
        #expect(hints.remaining == 15)
        #expect(hints.openingCount() == 15)
    }

    @Test func readsPriceWithCurrencyAndChineseNumbers() {
        #expect(CigaretteTextParser.parse("这包买了三十元").price == 30)
        #expect(CigaretteTextParser.parse("一包28块").price == 28)
        #expect(CigaretteTextParser.parse("价格改成二十五").price == 25)
        #expect(CigaretteTextParser.parse("花了一百零五块").price == 105)
        #expect(CigaretteTextParser.parse("¥ 19.5").price == 19.5)
    }

    @Test func recognizesOtherCurrencies() {
        #expect(CigaretteTextParser.parse("这包5美元").currency == .usd)
        #expect(CigaretteTextParser.parse("这包80000越南盾").currency == .vnd)
        #expect(CigaretteTextParser.parse("这包60港币").currency == .hkd)
    }

    @Test func normalizesFullWidthDigits() {
        let hints = CigaretteTextParser.parse("这包３０元，还剩１７根")
        #expect(hints.price == 30)
        #expect(hints.remaining == 17)
    }

    @Test func clampsCountsToPackCapacity() {
        #expect(CigaretteTextParser.parse("还剩99根").openingCount() == 20)
        #expect(CigaretteTextParser.parse("抽了25根").openingCount() == 0)
    }

    @Test func ignoresSentencesWithoutNumbers() {
        let hints = CigaretteTextParser.parse("今天抽得有点多")
        #expect(hints.isEmpty)
        #expect(hints.openingCount() == nil)
    }

    @Test func doesNotMistakeBrandForPrice() {
        #expect(CigaretteTextParser.parse("中华软盒").price == nil)
    }
}
