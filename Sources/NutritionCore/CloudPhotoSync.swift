import Foundation

extension CloudSyncClient {
    private struct MissingPhotos: Codable { let names: [String] }
    private struct MissingResponse: Decodable { let missing: [String] }
    private struct PhotoReceipt: Decodable {
        let name: String
        let checksum: String
    }

    func uploadPhotos(_ photos: [PhotoAttachment], token: String) async throws {
        let byName = Dictionary(uniqueKeysWithValues: photos.map { ($0.name, $0) })
        let names = photos.map(\.name)
        for offset in stride(from: 0, to: names.count, by: 250) {
            try Task.checkCancellation()
            let batch = Array(names[offset..<min(offset + 250, names.count)])
            let lookup = try jsonRequest("/v1/sync/photos/missing", method: "POST", token: token, body: MissingPhotos(names: batch))
            let (data, status) = try await send(lookup)
            try Self.check(status, data)
            guard let response = try? Self.decoder.decode(MissingResponse.self, from: data),
                  Set(response.missing).isSubset(of: Set(batch)), Set(response.missing).count == response.missing.count else {
                throw CloudSyncError.invalidResponse("服务器返回的照片列表无效，请重试。")
            }
            for name in response.missing {
                guard let photo = byName[name] else { throw CloudSyncError.invalidResponse("照片清单与本机不一致。") }
                var upload = request("/v1/sync/photos/\(name)", method: "PUT", token: token)
                upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                upload.httpBody = photo.data
                let (receiptData, receiptStatus) = try await send(upload)
                try Self.check(receiptStatus, receiptData)
                guard let receipt = try? Self.decoder.decode(PhotoReceipt.self, from: receiptData),
                      receipt.name == name, "photo-\(receipt.checksum).jpg" == name else {
                    throw CloudSyncError.invalidResponse("照片上传校验未通过，请重新同步。")
                }
            }
        }
    }

    func downloadPhotos(for document: DiaryDocument, token: String, into directory: URL) async throws {
        for name in document.referencedPhotoNames {
            try Task.checkCancellation()
            if !PhotoArchive.isTransferName(name) {
                guard let original = PhotoArchive.load(name: name, in: directory) else {
                    throw CloudSyncError.invalidResponse("云端旧照片缺少原图，请在保留 Photos 目录的原设备同步，或补回原图后重试。")
                }
                _ = try PhotoAttachment(data: original)
                continue
            }
            if PhotoArchive.verifiedPhoto(name: name, in: directory) { continue }
            var download = request("/v1/sync/photos/\(name)", method: "GET", token: token)
            download.setValue("image/jpeg", forHTTPHeaderField: "Accept")
            let (data, status) = try await send(download)
            try Self.check(status, data)
            guard !data.isEmpty, data.count <= PhotoArchive.maximumPhotoBytes,
                  PhotoArchive.transferName(for: data) == name else {
                throw CloudSyncError.invalidResponse("下载的照片校验失败，本机记录已保留，请重试。")
            }
            _ = try PhotoArchive.save(data, name: name, in: directory)
        }
    }
}
