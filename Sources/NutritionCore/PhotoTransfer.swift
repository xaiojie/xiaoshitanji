import CryptoKit
import Foundation

public struct PhotoAttachment: Sendable, Equatable {
    public let name: String
    public let data: Data

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= PhotoArchive.maximumPhotoBytes else {
            throw DiaryError.invalidInput("照片为空或超过5 MB，请重新选择照片。")
        }
        self.name = PhotoArchive.transferName(for: data)
        self.data = data
    }
}

public struct DiaryPhotoTransfer: Sendable {
    public let document: DiaryDocument
    public let photos: [PhotoAttachment]
}

public extension PhotoArchive {
    static let maximumPhotoBytes = 5_000_000

    static func transferName(for data: Data) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "photo-\(digest).jpg"
    }

    static func isTransferName(_ name: String) -> Bool {
        name.utf8.count == 74 && name.range(of: #"^photo-[0-9a-f]{64}\.jpg$"#, options: .regularExpression) != nil
    }

    static func verifiedPhoto(name: String, in directory: URL) -> Bool {
        guard isTransferName(name), let data = load(name: name, in: directory) else { return false }
        return transferName(for: data) == name
    }

    static func resolve(inline: Data?, name: String?, in directory: URL?) throws -> Data? {
        if let inline {
            _ = try PhotoAttachment(data: inline)
            return inline
        }
        guard let name else { return nil }
        guard validName(name), let directory, let data = load(name: name, in: directory) else {
            throw DiaryError.invalidInput("找不到照片「\(name)」，请补全原 Photos 目录后重试。")
        }
        _ = try PhotoAttachment(data: data)
        if isTransferName(name), transferName(for: data) != name {
            throw DiaryError.invalidInput("照片「\(name)」的内容校验失败，请从原设备或备份补回原图后重试。")
        }
        return data
    }
}

public extension DiaryDocument {
    var referencedPhotoNames: [String] {
        let records = records.filter { $0.photoJPEG == nil }.compactMap(\.photoFileName)
        let packs = smoking.packs.filter { $0.photoJPEG == nil }.compactMap(\.photoFileName)
        return Set(records + packs).sorted()
    }

    func embeddingPhotos(from directory: URL? = nil) throws -> DiaryDocument {
        try validate()
        return try mappingPhotos { inline, name in
            (try PhotoArchive.resolve(inline: inline, name: name, in: directory), nil)
        }
    }

    func photoTransfer(from directory: URL? = nil) throws -> DiaryPhotoTransfer {
        try validate()
        var photos: [String: PhotoAttachment] = [:]
        let document = try mappingPhotos { inline, name in
            guard let data = try PhotoArchive.resolve(inline: inline, name: name, in: directory) else { return (nil, nil) }
            let photo = try PhotoAttachment(data: data)
            photos[photo.name] = photo
            return (nil, photo.name)
        }
        return DiaryPhotoTransfer(document: document, photos: photos.values.sorted { $0.name < $1.name })
    }

    private func mappingPhotos(_ transform: (Data?, String?) throws -> (Data?, String?)) throws -> DiaryDocument {
        var next = self
        for index in next.records.indices {
            let photo = try transform(next.records[index].photoJPEG, next.records[index].photoFileName)
            next.records[index].photoJPEG = photo.0
            next.records[index].photoFileName = photo.1
        }
        try next.smoking.transformPhotos(transform)
        return next
    }
}
