import Foundation

public struct VaultConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var volumeName: String
    public var createdAt: Date
    public var quotaGB: Int
    public var autoLockMinutes: Int
    public var lockOnSleep: Bool
    public var lockOnScreenLock: Bool
    public var allowPasswordFallback: Bool
    public var recoveryKeyConfirmed: Bool

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        name: String,
        volumeName: String,
        createdAt: Date = Date(),
        quotaGB: Int = 32,
        autoLockMinutes: Int = 15,
        lockOnSleep: Bool = true,
        lockOnScreenLock: Bool = true,
        allowPasswordFallback: Bool = false,
        recoveryKeyConfirmed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.volumeName = volumeName
        self.createdAt = createdAt
        self.quotaGB = quotaGB
        self.autoLockMinutes = autoLockMinutes
        self.lockOnSleep = lockOnSleep
        self.lockOnScreenLock = lockOnScreenLock
        self.allowPasswordFallback = allowPasswordFallback
        self.recoveryKeyConfirmed = recoveryKeyConfirmed
    }

    public static func make(
        name: String,
        quotaGB: Int,
        autoLockMinutes: Int,
        allowPasswordFallback: Bool
    ) -> VaultConfig {
        // Whole seconds round-trip exactly through JSON dates; sub-second
        // precision does not, which would make a saved config compare unequal.
        let created = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return VaultConfig(
            id: UUID(),
            name: name,
            volumeName: Self.volumeName(from: name),
            createdAt: created,
            quotaGB: quotaGB,
            autoLockMinutes: autoLockMinutes,
            allowPasswordFallback: allowPasswordFallback
        )
    }

    /// Disk image volume names cannot contain a slash or colon and look best short.
    public static func volumeName(from name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.prefix(27))
        return trimmed.isEmpty ? "VaultKey" : trimmed
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case .corrupt(let details):
            return "The VaultKey configuration couldn't be read. \(details)"
        }
    }
}

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> VaultConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(VaultConfig.self, from: data)
        } catch {
            throw ConfigError.corrupt(error.localizedDescription)
        }
    }

    public func save(_ config: VaultConfig) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
