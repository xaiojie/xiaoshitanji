import NutritionCore
import Foundation
import Security

/// 同步登录态放钥匙串：token 不进 UserDefaults，也不进日记文件。
enum SyncCredentialStore {
    private static let service = "com.jay.fooddiary.sync"
    private static let account = "session"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> CloudSyncSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSyncSession.self, from: data)
    }

    static func save(_ session: CloudSyncSession) throws {
        let data = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SyncCredentialError(status: addStatus) }
        } else if status != errSecSuccess {
            throw SyncCredentialError(status: status)
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

struct SyncCredentialError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "无法保存登录状态（钥匙串错误 \(status)）。"
    }
}
