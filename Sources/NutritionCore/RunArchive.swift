import Foundation

/// 精确轨迹留在本机独立目录，可同步摘要通过相同 ID 的 WorkoutRecord 保存。
public struct RunArchive: Sendable {
    public struct Snapshot: Sendable {
        public let records: [RunRecord]
        public let unreadableFiles: [String]
    }
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func saveDraft(_ session: RunSession) throws {
        try session.validate()
        try write(session, to: directory.appending(path: "draft.json"))
    }

    public func loadDraft() throws -> RunSession? {
        let url = directory.appending(path: "draft.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(RunSession.self, from: Data(contentsOf: url))
        try session.validate()
        return session
    }

    public func clearDraft() throws {
        let url = directory.appending(path: "draft.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    @discardableResult
    public func save(_ record: RunRecord, preservingDetails: Bool = true) throws -> RunRecord {
        var record = record
        if preservingDetails, FileManager.default.fileExists(atPath: recordURL(record.id).path) {
            let previous = try JSONDecoder().decode(RunRecord.self, from: Data(contentsOf: recordURL(record.id)))
            if record.heartRates.isEmpty { record.heartRates = previous.heartRates }
            if record.linkedHealthWorkoutID == nil { record.linkedHealthWorkoutID = previous.linkedHealthWorkoutID }
        }
        try record.session.validate()
        guard record.session.state == .finished, record.heartRates.count <= 100_000 else {
            throw DiaryError.invalidInput("跑步记录尚未结束或样本过多。")
        }
        try write(record, to: recordURL(record.id))
        return record
    }

    public func records() throws -> [RunRecord] {
        try loadRecords().records
    }

    public func loadRecords() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: directory.path) else { return Snapshot(records: [], unreadableFiles: []) }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        var records: [RunRecord] = []
        var unreadable: [String] = []
        for url in urls {
            do {
                let record = try JSONDecoder().decode(RunRecord.self, from: Data(contentsOf: url))
                try record.session.validate()
                guard record.id.uuidString == url.deletingPathExtension().lastPathComponent else {
                    throw DiaryError.unreadableDiary
                }
                records.append(record)
            } catch {
                unreadable.append(url.lastPathComponent)
            }
        }
        return Snapshot(records: records.sorted { $0.session.startedAt > $1.session.startedAt }, unreadableFiles: unreadable)
    }

    public func preserveUnreadableDraft() throws -> URL? {
        let original = directory.appending(path: "draft.json")
        guard FileManager.default.fileExists(atPath: original.path) else { return nil }
        let copy = directory.appending(path: "recovery-\(UUID()).json")
        try FileManager.default.moveItem(at: original, to: copy)
        return copy
    }

    public func pendingDeletions() throws -> [UUID] {
        let url = directory.appending(path: "pending-deletions.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([UUID].self, from: Data(contentsOf: url))
    }

    public func markForDeletion(id: UUID) throws {
        var pending = try pendingDeletions()
        if !pending.contains(id) { pending.append(id) }
        try write(pending, to: directory.appending(path: "pending-deletions.json"))
    }

    public func finishDeletion(id: UUID) throws {
        try remove(id: id)
        let remaining = try pendingDeletions().filter { $0 != id }
        try write(remaining, to: directory.appending(path: "pending-deletions.json"))
    }

    public func remove(id: UUID) throws {
        let url = recordURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func recordURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: directory.path)
        #endif
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: url.path)
        #endif
    }
}
