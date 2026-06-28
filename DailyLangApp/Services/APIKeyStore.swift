import Foundation
import Security

protocol APIKeyStoring {
    func loadAPIKey() throws -> String
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

enum APIKeyStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain error: \(status)"
        case .invalidData:
            "保存されたAPIキーを読み取れませんでした。"
        }
    }
}

enum APIKeyEnvironment {
    static let variableName = "OPENAI_API_KEY"

    static var currentValue: String {
        ProcessInfo.processInfo.environment[variableName]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private let service = "DailyLang.OpenAI"
    private let account = "OPENAI_API_KEY"

    func loadAPIKey() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return APIKeyEnvironment.currentValue
        }

        guard status == errSecSuccess else {
            throw APIKeyStoreError.unexpectedStatus(status)
        }

        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.invalidData
        }

        return key
    }

    @discardableResult
    func seedFromEnvironmentIfAvailable() throws -> Bool {
        let key = APIKeyEnvironment.currentValue
        guard !key.isEmpty else {
            return false
        }

        try saveAPIKey(key)
        return true
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            try deleteAPIKey()
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw APIKeyStoreError.unexpectedStatus(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
