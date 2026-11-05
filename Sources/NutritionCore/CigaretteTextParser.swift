import Foundation

/// 从一句自然语言里读出的烟包信息：价格、余量或已抽根数。
public struct CigaretteTextHints: Equatable, Sendable {
    public var price: Double?
    public var currency: SmokingCurrency?
    /// 现在这包还剩几根（用户直接说“还剩 17 根”）。
    public var remaining: Int?
    /// 用户说“抽了 2 根”，需要从满包容量里减掉。
    public var smoked: Int?
    /// 原样摘录的匹配片段，用于在界面上说明读到了什么。
    public var evidence: [String] = []

    public var isEmpty: Bool { price == nil && remaining == nil && smoked == nil }

    public init(price: Double? = nil, currency: SmokingCurrency? = nil,
                remaining: Int? = nil, smoked: Int? = nil, evidence: [String] = []) {
        self.price = price
        self.currency = currency
        self.remaining = remaining
        self.smoked = smoked
        self.evidence = evidence
    }

    /// 结合满包容量换算出的开包余量，优先采用用户直接说的余量。
    public func openingCount(capacity: Int = CigarettePack.capacity) -> Int? {
        if let remaining { return min(max(remaining, 0), capacity) }
        if let smoked { return min(max(capacity - smoked, 0), capacity) }
        return nil
    }
}

/// 本地解析“这包烟二十，我抽了两根”“还剩 17 根”这类一句话。
/// 数值属于事实，先由本地确定性地读出来；AI 只在需要理解图片时参与。
public enum CigaretteTextParser {
    public static func parse(_ text: String) -> CigaretteTextHints {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return CigaretteTextHints() }
        var hints = CigaretteTextHints()

        let priceMatch = firstMatch(pricePattern, in: normalized)
            ?? firstMatch(symbolPricePattern, in: normalized)
            ?? firstMatch(barePricePattern, in: normalized)
        if let priceMatch, let value = decimal(from: priceMatch.number), value >= 0, value <= 100_000 {
            hints.price = value
            hints.evidence.append(priceMatch.text)
            hints.currency = currency(in: normalized)
        }

        if let match = firstMatch(remainingPattern, in: normalized), let value = number(from: match.number) {
            hints.remaining = value
            hints.evidence.append(match.text)
        } else if let match = firstMatch(smokedPattern, in: normalized), let value = number(from: match.number) {
            hints.smoked = value
            hints.evidence.append(match.text)
        }

        hints.evidence = hints.evidence.filter { !$0.isEmpty }
        return hints
    }

    // MARK: - 规则

    /// “这包烟二十”“买了 30 元”“价格改成 25 块”“一包 28”。
    private static let pricePattern = try! NSRegularExpression(
        pattern: "(?:(?:价格|售价|定价|买(?:成|了)?|花了?|这包(?:烟)?|一包|每包)[^0-9零一二两三四五六七八九十百点]{0,6})?([0-9]+(?:\\.[0-9]+)?|[零一二两三四五六七八九十百点]+)\\s*(?:元|块钱|块|rmb|RMB|¥|￥|人民币)",
        options: [])

    /// “¥ 19.5”这种货币符号在前面的写法。
    private static let symbolPricePattern = try! NSRegularExpression(
        pattern: "(?:¥|￥|\\$)\\s*([0-9]+(?:\\.[0-9]+)?)",
        options: [])

    /// “这包烟二十”这种没有货币单位的说法，只在“这包/一包/买”后紧跟数字时采用。
    private static let barePricePattern = try! NSRegularExpression(
        pattern: "(?:(?:这包(?:烟)?|一包|每包|价格|售价|买(?:成|了)?|花了?)[^0-9零一二两三四五六七八九十百点]{0,4})([0-9]+(?:\\.[0-9]+)?|[零一二两三四五六七八九十百]+)",
        options: [])

    /// “还剩 17 根”“剩下 5 支”“还有三根”。
    private static let remainingPattern = try! NSRegularExpression(
        pattern: "(?:还剩|还剩(?:下)?|剩下|剩余|还有|余下|余|剩)[^0-9零一二两三四五六七八九十百]{0,4}([0-9]+|[零一二两三四五六七八九十百]+)\\s*(?:根|支)?",
        options: [])

    /// “抽了 2 根”“已经抽了两支”“抽掉 3 根”。
    private static let smokedPattern = try! NSRegularExpression(
        pattern: "(?:已经抽了?|已抽|抽掉|抽了?)[^0-9零一二两三四五六七八九十百]{0,3}([0-9]+|[零一二两三四五六七八九十百]+)\\s*(?:根|支)?",
        options: [])

    // MARK: - 匹配与数字

    private struct Match { let number: String; let text: String }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> Match? {
        let range = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: range),
              result.numberOfRanges > 1,
              let numberRange = Range(result.range(at: 1), in: text) else { return nil }
        let whole = Range(result.range(at: 0), in: text).map { String(text[$0]) } ?? ""
        return Match(number: String(text[numberRange]), text: whole)
    }

    private static func number(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed) { return value }
        return chineseNumber(trimmed)
    }

    private static func decimal(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed) { return value }
        return chineseNumber(trimmed).map(Double.init)
    }

    private static func currency(in text: String) -> SmokingCurrency? {
        if text.contains("越南盾") || text.contains("盾") { return .vnd }
        if text.contains("港币") || text.contains("港元") { return .hkd }
        if text.contains("美元") || text.contains("美金") || text.contains("$") { return .usd }
        if text.contains("元") || text.contains("块") || text.contains("¥") || text.contains("￥") || text.contains("人民币") {
            return .cny
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        let fullWidthDigits = ["０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
                               "５": "5", "６": "6", "７": "7", "８": "8", "９": "9", "．": "."]
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if let replacement = fullWidthDigits[String(character)] { result += replacement }
            else { result.append(character) }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 只处理 0–999 的常见说法：十、二十、二十三、一百零五、两百。
    private static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        guard text.contains(where: { $0 == "十" || $0 == "百" || digits[$0] != nil }) else { return nil }
        var total = 0
        var current = 0
        var seen = false
        for character in text {
            if character == "百" {
                total += max(current, 1) * 100
                current = 0
                seen = true
            } else if character == "十" {
                total += max(current, 1) * 10
                current = 0
                seen = true
            } else if let digit = digits[character] {
                current = digit
                seen = true
            } else {
                return nil
            }
        }
        guard seen else { return nil }
        return total + current
    }
}
