import Foundation

/// 照片挪出 diary.json：文件按名字存在 `Photos/`，文档里只留文件名。
public enum PhotoArchive {
    public static let directoryName = "Photos"

    public static func recordName(_ id: UUID) -> String { "record-\(id.uuidString).jpg" }
    public static func packName(_ id: UUID) -> String { "pack-\(id.uuidString).jpg" }

    public static func ensureDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    public static func save(_ data: Data, name: String, in directory: URL) throws -> String {
        try ensureDirectory(directory)
        try data.write(to: directory.appending(path: name), options: .atomic)
        return name
    }

    public static func load(name: String, in directory: URL) -> Data? {
        try? Data(contentsOf: directory.appending(path: name))
    }

    public static func remove(name: String, in directory: URL) {
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }

    public static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 120 && !name.contains("/") && !name.contains("..")
    }
}

public extension DiaryDocument {
    /// 把内嵌的 base64 照片写成文件，返回是否有改动（旧文件一次性迁移用）。
    mutating func externalizePhotos(in directory: URL) throws -> Bool {
        var changed = false
        for index in records.indices where records[index].photoJPEG != nil {
            guard let data = records[index].photoJPEG else { continue }
            let name = try PhotoArchive.save(data, name: PhotoArchive.recordName(records[index].id), in: directory)
            records[index].photoFileName = name
            records[index].photoJPEG = nil
            changed = true
        }
        if try smoking.externalizePhotos(in: directory) { changed = true }
        return changed
    }
}
