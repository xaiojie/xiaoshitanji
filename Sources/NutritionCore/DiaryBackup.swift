import Foundation

/// 每天一份本机备份：即使重装 App 或同步失败，也能从最近的快照找回。
public enum DiaryBackup {
    public static let defaultKeeping = 14

    public static func directory(in root: URL) -> URL {
        root.appending(path: "FoodDiary/Backups", directoryHint: .isDirectory)
    }

    public static func filename(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "diary-\(formatter.string(from: date)).json"
    }

    /// 同一天只写一份；写成功后按保留数量裁掉最旧的备份。
    @discardableResult
    public static func make(_ document: DiaryDocument, in directory: URL, now: Date = .now,
                            calendar: Calendar = .current, keeping: Int = defaultKeeping) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: filename(for: now, calendar: calendar))
        if FileManager.default.fileExists(atPath: url.path()) { return url }

        var snapshot = document
        snapshot.schemaVersion = DiaryDocument.currentSchemaVersion
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try prune(in: directory, keeping: keeping)
        return url
    }

    public static func backups(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("diary-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public static func latest(in directory: URL) -> URL? {
        backups(in: directory).first
    }

    public static func restore(from url: URL) throws -> DiaryDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(DiaryDocument.self, from: data)
        try document.validate()
        return document
    }

    static func prune(in directory: URL, keeping: Int) throws {
        guard keeping > 0 else { return }
        let urls = backups(in: directory)
        for url in urls.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
