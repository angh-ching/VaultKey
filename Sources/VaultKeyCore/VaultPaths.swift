import Foundation

/// Every on-disk location the app uses. All of it lives inside one folder in
/// Application Support; nothing is written anywhere else.
public struct VaultPaths: Sendable, Equatable {
    public let supportDirectory: URL

    public init(supportDirectory: URL? = nil) {
        if let supportDirectory {
            self.supportDirectory = supportDirectory.standardizedFileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.supportDirectory = base
                .appendingPathComponent("VaultKey", isDirectory: true)
                .standardizedFileURL
        }
    }

    public var configURL: URL { supportDirectory.appendingPathComponent("config.json") }
    public var imageURL: URL { supportDirectory.appendingPathComponent("Vault.sparsebundle") }
    public var mountPoint: URL { supportDirectory.appendingPathComponent("Mount", isDirectory: true) }
    public var activityURL: URL { supportDirectory.appendingPathComponent("activity.jsonl") }
    public var keychainService: String { "com.local.vaultkey.vault" }
}
