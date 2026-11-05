import Foundation

/// 抽烟的累计数字：都来自事件流，可以一条条对回去。
public struct SmokingTotals: Sendable, Equatable {
    public var smoked: Int = 0
    public var shared: Int = 0
    public var packsOpened: Int = 0
    public var costs: [SmokingCurrency: Double] = [:]
    public var firstEventDate: Date?
    public var lastSmokedDate: Date?

    public init() {}

    public var hasData: Bool { smoked > 0 || shared > 0 || packsOpened > 0 }

    public func costText() -> String {
        let entries = costs.sorted { $0.value > $1.value }
        guard !entries.isEmpty else { return "未填价格" }
        return entries.map { currency, value in
            switch currency {
            case .cny: String(format: "¥%.0f", value)
            case .vnd: String(format: "₫%.0f", value)
            case .usd: String(format: "$%.2f", value)
            case .hkd: String(format: "HK$%.0f", value)
            }
        }.joined(separator: " + ")
    }
}

public enum SmokingStats {
    public static func totals(for document: DiaryDocument) -> SmokingTotals {
        var totals = SmokingTotals()
        let packs = Dictionary(uniqueKeysWithValues: document.smoking.packs.map { ($0.id, $0) })
        totals.packsOpened = document.smoking.packs.count
        for event in document.smoking.events {
            if totals.firstEventDate == nil || event.date < totals.firstEventDate! { totals.firstEventDate = event.date }
            switch event.kind {
            case .smoked:
                totals.smoked += event.count
                if totals.lastSmokedDate == nil || event.date > totals.lastSmokedDate! { totals.lastSmokedDate = event.date }
                if let pack = packs[event.packID], let price = pack.product.pricePerPack {
                    // 价格始终是「一整包」的价，按每包 20 支折算，与本机日汇总和 README 的口径一致。
                    let unit = price / Double(CigarettePack.capacity)
                    totals.costs[pack.product.currency, default: 0] += unit * Double(event.count)
                }
            case .shared:
                totals.shared += event.count
            case .stockCheck:
                break
            }
        }
        return totals
    }
}
