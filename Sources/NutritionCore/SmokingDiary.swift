import Foundation

public enum SmokingCurrency: String, Codable, CaseIterable, Sendable, Identifiable {
    case cny = "CNY", vnd = "VND", usd = "USD", hkd = "HKD"
    public var id: Self { self }
    public var title: String {
        switch self {
        case .cny: "人民币"
        case .vnd: "越南盾"
        case .usd: "美元"
        case .hkd: "港币"
        }
    }
}

public struct CigaretteProduct: Codable, Equatable, Sendable {
    public var name: String
    public var nicotineMG: Double?
    public var pricePerPack: Double?
    public var currency: SmokingCurrency
    public var notes: String

    public init(name: String, nicotineMG: Double? = nil, pricePerPack: Double? = nil,
                currency: SmokingCurrency = .cny, notes: String = "") {
        self.name = name
        self.nicotineMG = nicotineMG
        self.pricePerPack = pricePerPack
        self.currency = currency
        self.notes = notes
    }

    public func validate(requireName: Bool = true) throws {
        guard name.count <= 100, !requireName || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiaryError.invalidInput("请填写香烟名称，控制在100字以内。")
        }
        if let nicotineMG, !nicotineMG.isFinite || !(0...20).contains(nicotineMG) {
            throw DiaryError.invalidInput("请检查每根烟的尼古丁标注值，单位为毫克。")
        }
        if let pricePerPack, !pricePerPack.isFinite || !(0...100_000_000).contains(pricePerPack) {
            throw DiaryError.invalidInput("请填写有效的每包价格。")
        }
    }
}

public struct CigarettePack: Identifiable, Codable, Equatable, Sendable {
    public static let capacity = 20
    public var id: UUID
    public var product: CigaretteProduct
    public var openedAt: Date
    public var openingCount: Int
    /// 旧数据内嵌的照片；迁移后为 nil。
    public var photoJPEG: Data?
    /// 照片文件名（相对 `Photos/`）。
    public var photoFileName: String?

    public init(id: UUID = UUID(), product: CigaretteProduct, openedAt: Date = .now,
                openingCount: Int = 20, photoJPEG: Data? = nil, photoFileName: String? = nil) {
        self.id = id
        self.product = product
        self.openedAt = openedAt
        self.openingCount = openingCount
        self.photoJPEG = photoJPEG
        self.photoFileName = photoFileName
    }

    public func validate() throws {
        try product.validate()
        if let photoFileName, !PhotoArchive.validName(photoFileName) {
            throw DiaryError.invalidInput("烟包照片文件名无效。")
        }
        guard openedAt.timeIntervalSinceReferenceDate.isFinite, (0...Self.capacity).contains(openingCount),
              (photoJPEG?.count ?? 0) <= 5_000_000 else {
            throw DiaryError.invalidInput("烟包余量需在0至20根之间，请检查照片和开包时间。")
        }
    }
}

public enum SmokingEventKind: String, Codable, Sendable {
    case smoked, shared, stockCheck
    public var title: String {
        switch self {
        case .smoked: "自己抽了"
        case .shared: "分给别人"
        case .stockCheck: "余量校准为"
        }
    }
}

public struct SmokingEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var packID: UUID
    public var date: Date
    public var kind: SmokingEventKind
    public var count: Int
}

public struct SmokingDaySummary: Sendable {
    public var smoked = 0
    public var shared = 0
    public var knownNicotineMG = 0.0
    public var unknownNicotineCount = 0
    public var costs: [SmokingCurrency: Double] = [:]
    public var unpricedCount = 0
}

public struct SmokingDiary: Codable, Equatable, Sendable {
    public private(set) var packs: [CigarettePack] = []
    public private(set) var events: [SmokingEvent] = []
    public private(set) var activePackID: UUID?

    public init() {}

    public var activePack: CigarettePack? { packs.first { $0.id == activePackID } }
    public var latestSmoke: SmokingEvent? { events.filter { $0.kind == .smoked }.max { $0.date < $1.date } }
    public var savedCigarettes: [CigarettePack] {
        var names = Set<String>()
        return packs.reversed().filter { pack in
            names.insert(pack.product.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
        }
    }

    public mutating func openAnotherPack(like packID: UUID, date: Date = .now) throws {
        guard let saved = packs.first(where: { $0.id == packID }) else {
            throw DiaryError.invalidInput("找不到已保存的香烟，请重新选择。")
        }
        try openPack(CigarettePack(product: saved.product, openedAt: date, photoJPEG: saved.photoJPEG))
    }

    public func remaining(in packID: UUID) -> Int {
        guard let pack = packs.first(where: { $0.id == packID }) else { return 0 }
        return events.filter { $0.packID == packID }.reduce(pack.openingCount) { count, event in
            event.kind == .stockCheck ? event.count : count - event.count
        }
    }

    /// 把烟包照片写到文件，旧文件迁移与保存新包都用这一条。
    public mutating func externalizePhotos(in directory: URL) throws -> Bool {
        var changed = false
        for index in packs.indices where packs[index].photoJPEG != nil {
            guard let data = packs[index].photoJPEG else { continue }
            let name = try PhotoArchive.save(data, name: PhotoArchive.transferName(for: data), in: directory)
            packs[index].photoFileName = name
            packs[index].photoJPEG = nil
            changed = true
        }
        return changed
    }

    mutating func transformPhotos(_ transform: (Data?, String?) throws -> (Data?, String?)) throws {
        for index in packs.indices {
            let photo = try transform(packs[index].photoJPEG, packs[index].photoFileName)
            packs[index].photoJPEG = photo.0
            packs[index].photoFileName = photo.1
        }
    }

    public mutating func openPack(_ pack: CigarettePack) throws {
        try pack.validate()
        guard !packs.contains(where: { $0.id == pack.id }) else {
            throw DiaryError.invalidInput("这包香烟已保存，请直接切换到已有烟包。")
        }
        packs.append(pack)
        activePackID = pack.id
    }

    public mutating func activatePack(id: UUID) throws {
        guard packs.contains(where: { $0.id == id }) else { throw DiaryError.invalidInput("找不到这包香烟。") }
        activePackID = id
    }

    public mutating func updatePack(_ pack: CigarettePack) throws {
        guard let index = packs.firstIndex(where: { $0.id == pack.id }) else {
            throw DiaryError.invalidInput("找不到需要修改的烟包。")
        }
        var next = self
        next.packs[index] = pack
        try next.validate()
        self = next
    }

    public mutating func record(_ kind: SmokingEventKind, count: Int, date: Date = .now) throws {
        guard let pack = activePack else { throw DiaryError.invalidInput("先添加当前这一包香烟，再开始记录。") }
        let range = kind == .stockCheck ? 0...20 : 1...20
        guard range.contains(count), date.timeIntervalSinceReferenceDate.isFinite, date >= pack.openedAt else {
            throw DiaryError.invalidInput("请填写有效的根数和记录时间。")
        }
        guard kind == .stockCheck || count <= remaining(in: pack.id) else {
            throw DiaryError.invalidInput("当前烟包余量不足，请检查实际剩余数量，或换一包。")
        }
        events.append(SmokingEvent(id: UUID(), packID: pack.id, date: date, kind: kind, count: count))
    }

    /// 合并另一份记录（例如云端）：按 id 去重，本机已有的不动。
    public mutating func merge(_ other: SmokingDiary) {
        var seenPacks = Set(packs.map(\.id))
        for pack in other.packs where !seenPacks.contains(pack.id) {
            packs.append(pack)
            seenPacks.insert(pack.id)
        }
        var seenEvents = Set(events.map(\.id))
        for event in other.events where !seenEvents.contains(event.id) {
            events.append(event)
            seenEvents.insert(event.id)
        }
        events.sort { $0.date < $1.date }
        if activePackID == nil { activePackID = other.activePackID }
    }

    public mutating func removeEvent(id: UUID) throws {
        var next = self
        next.events.removeAll { $0.id == id }
        try next.validate()
        self = next
    }

    public func summary(on date: Date, calendar: Calendar = .current) -> SmokingDaySummary {
        summarize(events.filter { calendar.isDate($0.date, inSameDayAs: date) })
    }

    public func summary(from start: Date, until end: Date) -> SmokingDaySummary {
        summarize(events.filter { $0.date >= start && $0.date < end })
    }

    private func summarize(_ selected: [SmokingEvent]) -> SmokingDaySummary {
        let products = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0.product) })
        var result = SmokingDaySummary()
        for event in selected {
            if event.kind == .shared { result.shared += event.count }
            guard event.kind == .smoked, let product = products[event.packID] else { continue }
            result.smoked += event.count
            if let nicotine = product.nicotineMG { result.knownNicotineMG += nicotine * Double(event.count) }
            else { result.unknownNicotineCount += event.count }
            if let price = product.pricePerPack {
                result.costs[product.currency, default: 0] += price * Double(event.count) / 20
            } else { result.unpricedCount += event.count }
        }
        return result
    }

    public func validate() throws {
        guard Set(packs.map(\.id)).count == packs.count, Set(events.map(\.id)).count == events.count,
              activePackID == nil || packs.contains(where: { $0.id == activePackID }) else { throw DiaryError.unreadableDiary }
        for pack in packs { try pack.validate() }
        let packMap = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
        var stock = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0.openingCount) })
        for event in events {
            guard let pack = packMap[event.packID], let current = stock[event.packID],
                  event.date.timeIntervalSinceReferenceDate.isFinite, event.date >= pack.openedAt,
                  (event.kind == .stockCheck ? 0...20 : 1...20).contains(event.count) else { throw DiaryError.unreadableDiary }
            let remaining = event.kind == .stockCheck ? event.count : current - event.count
            guard (0...20).contains(remaining) else {
                throw DiaryError.invalidInput("更改记录后烟包余量不一致，请先检查后续分烟或余量校准记录。")
            }
            stock[event.packID] = remaining
        }
    }
}
