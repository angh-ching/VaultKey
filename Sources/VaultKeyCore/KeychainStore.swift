import Foundation
import Security

public enum KeychainError: LocalizedError {
    case notFound
    case corrupt
    case keychainLocked
    case status(OSStatus, String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "The vault key is missing from Keychain. Use your recovery key to open the vault."
        case .corrupt:
            return "The vault key in Keychain is damaged. Use your recovery key to open the vault."
        case .keychainLocked:
            return "Your login keychain is locked. Unlock it and try again."
        case .status(let status, let message):
            return "Keychain error \(status). \(message)"
        }
    }
}

/// The vault's 160-bit key lives in the login keychain, local to this Mac.
/// VaultKey reads it only after a successful Touch ID check.
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.local.vaultkey.vault") {
        self.service = service
    }

    private func baseQuery(vaultID: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: vaultID.uuidString,
            kSecAttrSynchronizable: false,
        ]
    }

    public func hasKey(vaultID: UUID) -> Bool {
        var query = baseQuery(vaultID: vaultID)
        query[kSecReturnAttributes] = true
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    public func saveKey(_ key: Secret, vaultID: UUID, vaultName: String) throws {
        let query = baseQuery(vaultID: vaultID)
        var attributes: [CFString: Any] = [
            kSecValueData: key.data,
            kSecAttrLabel: "VaultKey vault key",
            kSecAttrDescription: "Encryption key for “\(vaultName)”",
            kSecAttrComment: "Local only. Managed by VaultKey.",
        ]
        if let access = Self.makeAccess(prompt: "VaultKey needs your vault key") {
            attributes[kSecAttrAccess] = access
        }

        let status = SecItemAdd((query.merging(attributes) { _, new in new }) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [CFString: Any] = [
                kSecValueData: key.data,
                kSecAttrLabel: "VaultKey vault key",
                kSecAttrDescription: "Encryption key for “\(vaultName)”",
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw keychainError(updateStatus)
            }
        default:
            throw keychainError(status)
        }
    }

    public func loadKey(vaultID: UUID) throws -> Secret {
        var query = baseQuery(vaultID: vaultID)
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw keychainError(status, notFound: true)
        }
        guard let data = result as? Data, !data.isEmpty else {
            throw KeychainError.corrupt
        }
        return Secret(data: data)
    }

    public func deleteKey(vaultID: UUID) throws {
        let status = SecItemDelete(baseQuery(vaultID: vaultID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func keychainError(_ status: OSStatus, notFound: Bool = false) -> KeychainError {
        switch status {
        case errSecItemNotFound where notFound: return .notFound
        case errSecInteractionNotAllowed, errSecAuthFailed: return .keychainLocked
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return .status(status, message)
        }
    }

    /// Binds the item to VaultKey's code signature and gives other apps a clear
    /// prompt if they ever ask for it. Best effort: the legacy keychain does not
    /// support biometric access control without an Apple-issued entitlement.
    private static func makeAccess(prompt: String) -> SecAccess? {
        var trusted: SecTrustedApplication?
        let path = Bundle.main.bundlePath
        var status = SecTrustedApplicationCreateFromPath(path, &trusted)
        if status != errSecSuccess {
            status = SecTrustedApplicationCreateFromPath(nil, &trusted)
        }
        guard status == errSecSuccess, let trusted else { return nil }
        var access: SecAccess?
        status = SecAccessCreate(prompt as CFString, [trusted] as CFArray, &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
}
