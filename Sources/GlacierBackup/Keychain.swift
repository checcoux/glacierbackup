import Foundation
import Security

/// Conserva le credenziali AWS nel Portachiavi di macOS.
enum Keychain {
    struct Failure: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "errore \(status)"
            return "Impossibile salvare nel Portachiavi: \(detail)"
        }
    }

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.suertestudio.glacierbackup",
        kSecAttrAccount as String: "aws-credentials",
    ]

    static func load() -> AWSCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(AWSCredentials.self, from: data)
    }

    static func save(_ credentials: AWSCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
