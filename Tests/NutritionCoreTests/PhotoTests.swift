import Foundation
import Testing
@testable import NutritionCore

@Suite("照片外置")
struct PhotoTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "photos-\(UUID().uuidString)")
    }

    private func legacyDocument(photo: Data) -> DiaryDocument {
        let record = MealRecord(date: Date(timeIntervalSince1970: 1_700_000_000), kind: .lunch,
                                foods: [.manual(name: "饭", nutrition: Nutrition(calories: 200, protein: 4,
                                                                                carbohydrates: 40, fat: 1))],
                                photoJPEG: photo, source: .photo, summary: "照片")
        var document = DiaryDocument(records: [record])
        document.schemaVersion = 3
        return document
    }

    @Test("文件写读删往返")
    func archiveRoundTrip() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try PhotoArchive.save(Data([1, 2, 3]), name: "record-x.jpg", in: dir)
        #expect(PhotoArchive.load(name: name, in: dir) == Data([1, 2, 3]))
        PhotoArchive.remove(name: name, in: dir)
        #expect(PhotoArchive.load(name: name, in: dir) == nil)
        #expect(!PhotoArchive.validName("../etc/passwd"))
        #expect(PhotoArchive.validName("record-ABC.jpg"))
    }

    @Test("旧文件的 base64 照片迁移成文件")
    func migratesEmbeddedPhoto() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = Data(repeating: 7, count: 128)
        var document = legacyDocument(photo: photo)

        #expect(try document.externalizePhotos(in: dir) == true)
        let record = document.records[0]
        #expect(record.photoJPEG == nil)
        #expect(record.photoFileName == PhotoArchive.transferName(for: photo))
        #expect(PhotoArchive.load(name: record.photoFileName!, in: dir) == photo)
        #expect(try document.externalizePhotos(in: dir) == false)
    }

    @Test("烟包照片也迁移")
    func migratesPackPhoto() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var document = DiaryDocument()
        let pack = CigarettePack(product: CigaretteProduct(name: "测试烟"),
                                 photoJPEG: Data(repeating: 9, count: 32))
        try document.smoking.openPack(pack)
        #expect(try document.externalizePhotos(in: dir) == true)
        let migrated = document.smoking.packs[0]
        #expect(migrated.photoJPEG == nil)
        #expect(migrated.photoFileName == PhotoArchive.transferName(for: Data(repeating: 9, count: 32)))
        #expect(PhotoArchive.load(name: migrated.photoFileName!, in: dir)?.count == 32)
    }

    @Test("迁移后编码不再带 base64，字段只留文件名")
    func encodingOmitsBase64() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var document = legacyDocument(photo: Data(repeating: 1, count: 64))
        _ = try document.externalizePhotos(in: dir)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = String(decoding: try encoder.encode(document), as: UTF8.self)
        #expect(!text.contains("photoJPEG"))
        #expect(text.contains("photoFileName"))
    }

    @Test("旧 JSON 仍可解码出内嵌照片")
    func legacyDecode() throws {
        let json = #"""
        {"schemaVersion":3,"records":[{"id":"11111111-1111-1111-1111-111111111111","date":"2023-11-14T12:00:00Z","kind":"lunch","foods":[],"originalText":"","photoJPEG":"AQID","source":"photo","summary":"","assumptions":[],"analysisMode":"automatic"}],"reviews":[],"weights":[],"smoking":{"packs":[],"events":[]},"wellnessReviews":[],"templates":[],"observations":[]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(DiaryDocument.self, from: Data(json.utf8))
        #expect(document.records[0].photoJPEG == Data([1, 2, 3]))
        #expect(document.records[0].photoFileName == nil)
    }
}
