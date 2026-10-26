import AppKit
import Foundation
import UniformTypeIdentifiers

public enum VaultError: LocalizedError {
    case imageExists
    case imageMissing
    case notMounted
    case wrongKey
    case mountFailed(String)
    case verificationFailed
    case detachFailed(String)
    case commandFailed(operation: String, status: Int32, message: String)
    case unsafeLocation(String)
    case invalidName
    case cancelled
    case vaultNotEmpty

    public var errorDescription: String? {
        switch self {
        case .imageExists:
            return "A vault already exists at this location."
        case .imageMissing:
            return "The encrypted vault file is missing."
        case .notMounted:
            return "The vault is locked."
        case .wrongKey:
            return "That key doesn't open this vault."
        case .mountFailed(let detail):
            return "Couldn't open the vault. \(detail)"
        case .verificationFailed:
            return "The vault opened, but its identity couldn't be verified. It was closed immediately."
        case .detachFailed(let detail):
            return "Couldn't lock the vault. \(detail)"
        case .commandFailed(let operation, let status, let message):
            let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(operation) failed (\(status)). \(cleaned.isEmpty ? "Unknown error." : cleaned)"
        case .unsafeLocation(let name):
            return "“\(name)” can't be moved into the vault because it's a protected system or app location."
        case .invalidName:
            return "That file name isn't valid."
        case .cancelled:
            return "The operation was cancelled."
        case .vaultNotEmpty:
            return "Close the files in use before deleting the vault."
        }
    }
}

public struct VaultItem: Identifiable, Hashable, Sendable {
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modified: Date?
    public let kind: String

    public var id: String { name }

    public init(name: String, isDirectory: Bool, size: Int64?, modified: Date?, kind: String) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.kind = kind
    }
}

public struct VaultUsage: Sendable, Equatable {
    public let usedBytes: Int64
    public let totalBytes: Int64

    public init(usedBytes: Int64, totalBytes: Int64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

public struct AddFailure: Sendable, Identifiable {
    public let name: String
    public let message: String
    public var id: String { name + message }
}

public struct AddSummary: Sendable {
    public var added: [String] = []
    public var failed: [AddFailure] = []
    public var originalsNotRemoved: [String] = []
}

public struct RestoreSummary: Sendable {
    public var restored: [URL] = []
    public var failed: [AddFailure] = []
}

private struct VaultMarker: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let format: Int
}

private struct FileSnapshot: Equatable {
    let fileCount: Int
    let totalSize: Int64
}

/// Owns the encrypted disk image: creating it, mounting it at a private path,
/// verifying its identity, and moving files in and out.
public actor VaultEngine {
    public let paths: VaultPaths
    private let fileManager = FileManager.default

    public static let markerName = ".vaultkey.json"
    public static let indexMarkerName = ".metadata_never_index"
    private static let incomingName = ".vaultkey-incoming"
    private static let internalNames: Set<String> = [
        markerName,
        indexMarkerName,
        incomingName,
        ".DS_Store",
        ".fseventsd",
        ".Spotlight-V100",
        ".Trashes",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
        ".vol",
        ".com.apple.timemachine.donotpresent",
        ".apdisk",
    ]

    public init(paths: VaultPaths) {
        self.paths = paths
    }

    public var imageExists: Bool {
        fileManager.fileExists(atPath: paths.imageURL.path)
    }

    // MARK: - Setup

    public func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.supportDirectory.path
        )
    }

    public func create(id: UUID, name: String, quotaGB: Int, key: Secret) async throws {
        try prepareDirectories()
        guard !imageExists else { throw VaultError.imageExists }

        var payload = key.data
        payload.append(0x0A)
        let arguments = [
            "create", "-quiet",
            "-type", "SPARSEBUNDLE",
            "-size", "\(max(1, quotaGB))g",
            "-fs", "APFS",
            "-encryption", "AES-256",
            "-stdinpass",
            "-volname", VaultConfig.volumeName(from: name),
            paths.imageURL.path,
        ]
        let result = try await CommandRunner.run("/usr/bin/hdiutil", arguments, stdin: payload, timeout: 300)
        payload.resetBytes(in: 0..<payload.count)

        guard result.succeeded else {
            try? fileManager.removeItem(at: paths.imageURL)
            throw VaultError.commandFailed(operation: "Creating the vault", status: result.status, message: result.stderr)
        }

        do {
            // Leave the new vault mounted: setup finishes with the vault open
            // while the recovery key is presented.
            _ = try await attach(key: key, expectedID: nil)
            try writeMarker(id: id, name: name)
            try ensureIndexMarker()
        } catch {
            try? await detach(force: true)
            try? fileManager.removeItem(at: paths.imageURL)
            throw error
        }
    }

    /// Mounts the image at a hidden, private path. Never uses /Volumes, so the
    /// vault never appears on the Desktop or in the Finder sidebar.
    public func attach(key: Secret, expectedID: UUID?) async throws -> URL {
        try prepareDirectories()
        guard imageExists else { throw VaultError.imageMissing }

        if Self.isMounted(paths.mountPoint) {
            if let expectedID, markerID() == expectedID {
                return paths.mountPoint
            }
            try await detach(force: true)
        }

        if fileManager.fileExists(atPath: paths.mountPoint.path) {
            try? fileManager.removeItem(at: paths.mountPoint)
        }
        try fileManager.createDirectory(
            at: paths.mountPoint,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var payload = key.data
        payload.append(0x0A)
        let arguments = [
            "attach",
            "-stdinpass",
            "-nobrowse",
            "-noautoopen",
            "-owners", "on",
            "-mountpoint", paths.mountPoint.path,
            paths.imageURL.path,
        ]
        let result = try await CommandRunner.run("/usr/bin/hdiutil", arguments, stdin: payload)
        payload.resetBytes(in: 0..<payload.count)

        guard result.succeeded else {
            cleanupEmptyMount()
            let text = result.stderr.lowercased()
            if text.contains("authentication") || text.contains("passphrase") {
                throw VaultError.wrongKey
            }
            throw VaultError.mountFailed(Self.friendlyDetail(result.stderr))
        }
        guard Self.isMounted(paths.mountPoint) else {
            throw VaultError.verificationFailed
        }
        if let expectedID {
            guard markerID() == expectedID else {
                try? await detach(force: true)
                throw VaultError.verificationFailed
            }
        }
        try ensureIndexMarker()
        return paths.mountPoint
    }

    public func detach(force: Bool = false) async throws {
        guard Self.isMounted(paths.mountPoint) else {
            cleanupEmptyMount()
            return
        }
        var arguments = ["detach"]
        if force { arguments.append("-force") }
        arguments.append(paths.mountPoint.path)
        let result = try await CommandRunner.run("/usr/bin/hdiutil", arguments, timeout: 60)
        guard result.succeeded else {
            throw VaultError.detachFailed(Self.friendlyDetail(result.stderr))
        }
        for _ in 0..<30 {
            if !Self.isMounted(paths.mountPoint) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Self.isMounted(paths.mountPoint) else {
            throw VaultError.detachFailed("The volume is still mounted.")
        }
        cleanupEmptyMount()
    }

    public func isMounted() -> Bool {
        Self.isMounted(paths.mountPoint)
    }

    public func mountedMarkerID() -> UUID? {
        markerID()
    }

    // MARK: - Contents

    public func listItems() throws -> [VaultItem] {
        guard Self.isMounted(paths.mountPoint) else { throw VaultError.notMounted }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .typeIdentifierKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: paths.mountPoint,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        var items: [VaultItem] = []
        for url in urls where !Self.internalNames.contains(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory ?? false
            let kind = Self.kindDescription(for: url, values: values)
            items.append(
                VaultItem(
                    name: url.lastPathComponent,
                    isDirectory: isDirectory,
                    size: isDirectory ? nil : Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate,
                    kind: kind
                )
            )
        }
        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public func usage() throws -> VaultUsage {
        guard Self.isMounted(paths.mountPoint) else { throw VaultError.notMounted }
        let values = try paths.mountPoint.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        ])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        return VaultUsage(usedBytes: max(0, total - free), totalBytes: total)
    }

    public func itemURL(named name: String) throws -> URL {
        try Self.validate(name: name)
        return paths.mountPoint.appendingPathComponent(name)
    }

    // MARK: - Adding

    public func addItems(
        _ urls: [URL],
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> AddSummary {
        guard Self.isMounted(paths.mountPoint) else { throw VaultError.notMounted }
        let incoming = paths.mountPoint.appendingPathComponent(Self.incomingName, isDirectory: true)
        try? fileManager.removeItem(at: incoming)
        try fileManager.createDirectory(at: incoming, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        var summary = AddSummary()
        var existingNames = Set((try? listItems())?.map(\.name) ?? [])

        defer { try? fileManager.removeItem(at: incoming) }

        for source in urls {
            if Task.isCancelled { throw VaultError.cancelled }
            let name = source.lastPathComponent
            guard !name.isEmpty, name != ".", name != ".." else {
                summary.failed.append(AddFailure(name: name, message: "Invalid file name."))
                continue
            }
            do {
                try validateSource(source)
            } catch {
                summary.failed.append(AddFailure(name: name, message: error.localizedDescription))
                continue
            }

            guard !Self.internalNames.contains(name) else {
                summary.failed.append(AddFailure(name: name, message: "That name is reserved by VaultKey."))
                continue
            }

            progress(name)
            let finalName = Self.uniqueName(name, existing: existingNames)
            let temporary = incoming.appendingPathComponent(UUID().uuidString, isDirectory: false)
            do {
                let before = try Self.snapshot(source)
                try fileManager.copyItem(at: source, to: temporary)
                let after = try Self.snapshot(temporary)
                guard before == after else {
                    throw VaultError.verificationFailed
                }
                let destination = paths.mountPoint.appendingPathComponent(finalName)
                try fileManager.moveItem(at: temporary, to: destination)
                existingNames.insert(finalName)
                summary.added.append(finalName)

                do {
                    try fileManager.removeItem(at: source)
                } catch {
                    summary.originalsNotRemoved.append(source.path)
                }
            } catch {
                try? fileManager.removeItem(at: temporary)
                summary.failed.append(AddFailure(name: name, message: error.localizedDescription))
            }
        }
        return summary
    }

    // MARK: - Restoring & deleting

    public func restoreItems(names: [String], to destination: URL) async throws -> RestoreSummary {
        guard Self.isMounted(paths.mountPoint) else { throw VaultError.notMounted }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw VaultError.invalidName
        }
        let destinationPath = destination.standardizedFileURL.path
        let mountPath = paths.mountPoint.standardizedFileURL.path
        let supportPath = paths.supportDirectory.standardizedFileURL.path
        guard destinationPath != mountPath,
              !destinationPath.hasPrefix(mountPath + "/"),
              destinationPath != supportPath,
              !destinationPath.hasPrefix(supportPath + "/") else {
            throw VaultError.unsafeLocation(destination.lastPathComponent)
        }

        var summary = RestoreSummary()
        var existing = Set((try? fileManager.contentsOfDirectory(atPath: destination.path)) ?? [])
        for name in names {
            let temporary = destination.appendingPathComponent(".vaultkey-restore-\(UUID().uuidString)")
            do {
                try Self.validate(name: name)
                let source = paths.mountPoint.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path) else {
                    throw VaultError.invalidName
                }
                let finalName = Self.uniqueName(name, existing: existing)
                let target = destination.appendingPathComponent(finalName)
                let before = try Self.snapshot(source)
                try fileManager.copyItem(at: source, to: temporary)
                let after = try Self.snapshot(temporary)
                guard before == after else {
                    try? fileManager.removeItem(at: temporary)
                    throw VaultError.verificationFailed
                }
                try fileManager.moveItem(at: temporary, to: target)
                existing.insert(finalName)
                summary.restored.append(target)
                do {
                    try fileManager.removeItem(at: source)
                } catch {
                    summary.failed.append(AddFailure(
                        name: name,
                        message: "The copy was restored, but the vault copy couldn't be removed."
                    ))
                }
            } catch {
                try? fileManager.removeItem(at: temporary)
                summary.failed.append(AddFailure(name: name, message: error.localizedDescription))
            }
        }
        return summary
    }

    public func deleteItems(names: [String]) throws -> Int {
        guard Self.isMounted(paths.mountPoint) else { throw VaultError.notMounted }
        var deleted = 0
        for name in names {
            try Self.validate(name: name)
            let url = paths.mountPoint.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
            deleted += 1
        }
        return deleted
    }

    // MARK: - Maintenance

    public func revealInFinder(_ name: String) {
        let url = paths.mountPoint.appendingPathComponent(name)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openVaultInFinder() {
        NSWorkspace.shared.open(paths.mountPoint)
    }

    public func imageSize() -> Int64? {
        guard let enumerator = fileManager.enumerator(
            at: paths.imageURL,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    public func removeVaultImage() throws {
        if Self.isMounted(paths.mountPoint) {
            throw VaultError.vaultNotEmpty
        }
        if imageExists {
            try fileManager.removeItem(at: paths.imageURL)
        }
        try? fileManager.removeItem(at: paths.mountPoint)
    }

    public nonisolated func cleanupAfterLock() {
        guard !Self.isMounted(paths.mountPoint) else { return }
        try? FileManager.default.removeItem(at: paths.mountPoint)
    }

    public func cleanupStaleMount() async -> String? {
        guard Self.isMounted(paths.mountPoint) else {
            cleanupEmptyMount()
            return nil
        }
        do {
            try await detach(force: false)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Helpers

    public nonisolated static func isMounted(_ url: URL) -> Bool {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return false }
        let mountedOn: String = withUnsafeBytes(of: info.f_mntonname) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
            return String(cString: base)
        }
        return URL(fileURLWithPath: mountedOn).standardizedFileURL.path == url.standardizedFileURL.path
    }

    private func writeMarker(id: UUID, name: String) throws {
        let marker = VaultMarker(id: id, name: name, createdAt: Date(), format: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(marker)
        let url = paths.mountPoint.appendingPathComponent(Self.markerName)
        try data.write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try ensureIndexMarker()
    }

    private func ensureIndexMarker() throws {
        let url = paths.mountPoint.appendingPathComponent(Self.indexMarkerName)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: Data())
        }
    }

    private func markerID() -> UUID? {
        let url = paths.mountPoint.appendingPathComponent(Self.markerName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(VaultMarker.self, from: data))?.id
    }

    private func cleanupEmptyMount() {
        guard !Self.isMounted(paths.mountPoint) else { return }
        if fileManager.fileExists(atPath: paths.mountPoint.path) {
            try? fileManager.removeItem(at: paths.mountPoint)
        }
    }

    private func validateSource(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        let support = paths.supportDirectory.standardizedFileURL.path
        let mount = paths.mountPoint.standardizedFileURL.path
        let forbidden: Set<String> = ["/", "/System", "/Library", "/Applications", "/Users", "/private", "/Volumes"]
        let home = NSHomeDirectory()

        if forbidden.contains(path) || path == home || path.hasPrefix(mount + "/") || path == mount {
            throw VaultError.unsafeLocation(url.lastPathComponent)
        }
        // Never move the folder that *contains* the encrypted vault into itself.
        if path.hasPrefix(support) || support.hasPrefix(path + "/") {
            throw VaultError.unsafeLocation(url.lastPathComponent)
        }
        if path == Bundle.main.bundlePath || path.hasPrefix(Bundle.main.bundlePath + "/") {
            throw VaultError.unsafeLocation(url.lastPathComponent)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw VaultError.invalidName
        }
        guard fileManager.isReadableFile(atPath: path) else {
            throw VaultError.unsafeLocation(url.lastPathComponent)
        }
    }

    private static func validate(name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw VaultError.invalidName
        }
        guard !internalNames.contains(name) else {
            throw VaultError.invalidName
        }
    }

    private static func snapshot(_ url: URL) throws -> FileSnapshot {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw VaultError.invalidName
        }
        if !isDirectory.boolValue {
            // attributesOfItem is uncached, unlike URL.resourceValues, which can
            // return stale sizes for a URL that was reused after the file changed.
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return FileSnapshot(fileCount: 1, totalSize: size)
        }

        var count = 0
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw VaultError.invalidName
        }
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values?.isRegularFile == true || values?.isSymbolicLink == true {
                count += 1
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return FileSnapshot(fileCount: count, totalSize: total)
    }

    private static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !existing.contains(candidate) { return candidate }
            index += 1
        }
    }

    private static func kindDescription(for url: URL, values: URLResourceValues?) -> String {
        if values?.isDirectory == true { return "Folder" }
        if values?.isSymbolicLink == true { return "Alias" }
        if let type = values?.typeIdentifier, let utType = UTType(type) {
            return utType.localizedDescription ?? type
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.localizedDescription ?? "File"
        }
        return "File"
    }

    private static func friendlyDetail(_ stderr: String) -> String {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Unknown error." }
        if text.lowercased().contains("resource busy") {
            return "Files in the vault are still open. Quit the apps using them, then try again."
        }
        return text
    }
}
