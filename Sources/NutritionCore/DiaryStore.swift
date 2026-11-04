import Foundation

public struct DiaryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> DiaryDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return DiaryDocument() }
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(DiaryDocument.self, from: data)
            try document.validate()
            return document
        } catch DiaryError.unsupportedVersion {
            throw DiaryError.unsupportedVersion
        } catch {
            throw DiaryError.unreadableDiary
        }
    }

    public func save(_ document: DiaryDocument) throws {
        try document.validate()
        // Read first so an unreadable or newer existing file can never be replaced by an empty diary.
        _ = try load()
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
        } catch {
            throw DiaryError.storage(error.localizedDescription)
        }
    }
}
