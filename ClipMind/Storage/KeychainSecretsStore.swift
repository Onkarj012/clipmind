import Foundation
import Security

enum SecretsStoreKey: String, Sendable {
    case groqAPIKey = "io.clipmind.groq-api-key"
}

protocol SecretsStore: Sendable {
    func read(key: SecretsStoreKey) throws -> String?
    func write(key: SecretsStoreKey, value: String) throws
    func delete(key: SecretsStoreKey) throws
}

enum KeychainSecretsError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct KeychainSecretsStore: SecretsStore, Sendable {
    let service: String

    init(service: String = "io.clipmind.ClipMind") {
        self.service = service
    }

    func read(key: SecretsStoreKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretsError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            throw KeychainSecretsError.invalidData
        }
        return string
    }

    func write(key: SecretsStoreKey, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainSecretsError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainSecretsError.unexpectedStatus(updateStatus)
    }

    func delete(key: SecretsStoreKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretsError.unexpectedStatus(status)
        }
    }
}

#if DEBUG
final class InMemorySecretsStore: SecretsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecretsStoreKey: String] = [:]

    func read(key: SecretsStoreKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func write(key: SecretsStoreKey, value: String) throws {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    func delete(key: SecretsStoreKey) throws {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }
}
#endif
