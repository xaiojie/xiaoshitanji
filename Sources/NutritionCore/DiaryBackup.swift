import Foundation

/// 每天一份自包含备份，包含日记和关联照片，用户可另外导出保存。
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
                            calendar: Calendar = .current, keeping: Int = defaultKeeping,
                            photosDirectory: URL? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: filename(for: now, calendar: calendar))
        if FileManager.default.fileExists(atPath: url.path()) {
            let existing = try decode(Data(contentsOf: url))
            if !existing.referencedPhotoNames.isEmpty {
                try data(for: existing, photosDirectory: photosDirectory).write(to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return url
        }

        let data = try data(for: document, photosDirectory: photosDirectory)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try prune(in: directory, keeping: keeping, preserving: url)
        return url
    }

    public static func data(for document: DiaryDocument, photosDirectory: URL? = nil) throws -> Data {
        var snapshot = try document.embeddingPhotos(from: photosDirectory)
        snapshot.schemaVersion = DiaryDocument.currentSchemaVersion
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func makeRestorePoint(_ document: DiaryDocument, in directory: URL,
                                        photosDirectory: URL? = nil) throws -> URL {
        let data = try data(for: document, photosDirectory: photosDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        let url = directory.appending(path: "diary-\(formatter.string(from: .now))-before-restore-\(UUID()).json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try prune(in: directory, keeping: defaultKeeping, preserving: url)
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

    public static func restore(from url: URL, photosDirectory: URL? = nil) throws -> DiaryDocument {
        try decode(Data(contentsOf: url)).embeddingPhotos(from: photosDirectory)
    }

    private static func decode(_ data: Data) throws -> DiaryDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: DiaryDocument
        do { document = try decoder.decode(DiaryDocument.self, from: data) }
        catch is DecodingError { document = try JSONDecoder().decode(DiaryDocument.self, from: data) }
        try document.validate()
        return document
    }

    static func prune(in directory: URL, keeping: Int, preserving: URL? = nil) throws {
        guard keeping > 0 else { return }
        var urls = backups(in: directory)
        if let preserving, let index = urls.firstIndex(where: { $0.standardizedFileURL.path == preserving.standardizedFileURL.path }) {
            urls.insert(urls.remove(at: index), at: 0)
        }
        for url in urls.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
