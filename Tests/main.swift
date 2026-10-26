import Foundation
import AppKit

// A dependency-free self-test for the VaultKey engine. Run with ./selftest.sh.
// It creates a throwaway vault, exercises every file operation, and cleans up.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(message)")
    }
}

func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    checks += 1
    if lhs != rhs {
        failures += 1
        print("  ✗ \(message) (got \(lhs), expected \(rhs))")
    }
}

func test(_ name: String, _ body: () async throws -> Void) async {
    print("• \(name)")
    do {
        try await body()
    } catch {
        failures += 1
        print("  ✗ threw: \(error.localizedDescription)")
    }
}

func expectThrows(_ name: String, _ body: () async throws -> Void) async {
    checks += 1
    do {
        try await body()
        failures += 1
        print("  ✗ \(name): expected an error")
    } catch is VaultError {
        // Expected.
    } catch {
        failures += 1
        print("  ✗ \(name): wrong error \(error)")
    }
}

// MARK: - Recovery keys

await test("recovery key generation") {
    for _ in 0..<50 {
        let key = RecoveryKey.generate()
        checkEqual(key.count, 32, "key length")
        check(RecoveryKey.isValid(key), "generated key is valid")
        let pretty = RecoveryKey.formatted(key)
        check(pretty.contains("-"), "formatted key has separators")
        checkEqual(RecoveryKey.normalize(pretty), key, "formatted key normalizes back")
    }

    let key = RecoveryKey.generate()
    let messy = key.lowercased()
        .replacingOccurrences(of: "0", with: "o")
        .replacingOccurrences(of: "1", with: "l")
        .replacingOccurrences(of: "-", with: " ")
    checkEqual(RecoveryKey.normalize(messy), key, "lookalikes normalize")
    check(RecoveryKey.normalize("") == nil, "empty key rejected")
    check(RecoveryKey.normalize("ABCD") == nil, "short key rejected")
    check(RecoveryKey.normalize(String(repeating: "!", count: 32)) == nil, "invalid characters rejected")
}

// MARK: - Config

await test("configuration round trip") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VaultKeyConfig-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
    let config = VaultConfig.make(name: "My Vault", quotaGB: 32, autoLockMinutes: 15, allowPasswordFallback: false)
    try store.save(config)
    let loaded = try store.load()
    checkEqual(loaded, config, "config round trip")
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    checkEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, "config is owner-only")
    checkEqual(VaultConfig.volumeName(from: "My/Vault:One"), "My-Vault-One", "volume name sanitizing")
    checkEqual(VaultConfig.volumeName(from: "   "), "VaultKey", "empty volume name fallback")
}

// MARK: - Engine

await test("vault lifecycle") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultKeyEngine-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let sourceDir = root.appendingPathComponent("Source", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    let single = sourceDir.appendingPathComponent("notes.txt")
    try "hello vault".write(to: single, atomically: true, encoding: .utf8)

    let folder = sourceDir.appendingPathComponent("Photos", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "one".write(to: folder.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
    try "two".write(to: folder.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)

    let paths = VaultPaths(supportDirectory: root.appendingPathComponent("Support"))
    let engine = VaultEngine(paths: paths)
    let id = UUID()
    let key = Secret(string: "TESTRECOVERYKEY000000000000000A")

    try await engine.create(id: id, name: "Test Vault", quotaGB: 1, key: key)
    let imageExists = await engine.imageExists
    check(imageExists, "image created")

    let mount = try await engine.attach(key: key, expectedID: id)
    checkEqual(mount.path, paths.mountPoint.path, "private mount point")
    check(!mount.path.contains("/Volumes"), "not mounted under /Volumes")

    let summary = try await engine.addItems([single, folder])
    checkEqual(summary.added.count, 2, "two items added")
    check(summary.failed.isEmpty, "no add failures")
    check(summary.originalsNotRemoved.isEmpty, "originals removed")
    check(!FileManager.default.fileExists(atPath: single.path), "source file moved")
    check(!FileManager.default.fileExists(atPath: folder.path), "source folder moved")

    let items = try await engine.listItems()
    checkEqual(items.map(\.name).sorted(), ["Photos", "notes.txt"], "vault listing")
    check(items.first { $0.name == "Photos" }?.isDirectory == true, "folder detected")

    let inside = mount.appendingPathComponent("notes.txt")
    let contents = try String(contentsOf: inside, encoding: .utf8)
    checkEqual(contents, "hello vault", "file contents intact")

    let usage = try await engine.usage()
    check(usage.totalBytes > 0, "volume has capacity")
    check(usage.usedBytes > 0, "volume usage reported")

    try await engine.detach()
    var mounted = await engine.isMounted()
    check(!mounted, "detached")

    await expectThrows("wrong key is rejected") {
        _ = try await engine.attach(key: Secret(string: "WRONG"), expectedID: id)
    }
    mounted = await engine.isMounted()
    check(!mounted, "still unmounted after wrong key")

    await expectThrows("foreign marker is rejected") {
        _ = try await engine.attach(key: key, expectedID: UUID())
    }
    mounted = await engine.isMounted()
    check(!mounted, "detached after identity mismatch")

    let remount = try await engine.attach(key: key, expectedID: id)
    let contentsAgain = try String(contentsOf: remount.appendingPathComponent("notes.txt"), encoding: .utf8)
    checkEqual(contentsAgain, "hello vault", "file survives remount")

    let destination = root.appendingPathComponent("Restored", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let restored = try await engine.restoreItems(names: ["notes.txt", "Photos"], to: destination)
    checkEqual(restored.restored.count, 2, "two items restored")
    check(restored.failed.isEmpty, "no restore failures")
    check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("notes.txt").path), "restored file exists")
    check(
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("Photos/two.txt").path),
        "restored folder exists"
    )
    let remaining = try await engine.listItems()
    check(remaining.isEmpty, "vault empty after restore")

    try await engine.detach()
    try await engine.removeVaultImage()
    let imageStillExists = await engine.imageExists
    check(!imageStillExists, "image deleted")
}

await test("duplicate names and safety") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultKeyEngine-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = VaultPaths(supportDirectory: root.appendingPathComponent("Support"))
    let engine = VaultEngine(paths: paths)
    let id = UUID()
    let key = Secret(string: "TESTKEY")
    try await engine.create(id: id, name: "Duplicates", quotaGB: 1, key: key)
    _ = try await engine.attach(key: key, expectedID: id)

    let source = root.appendingPathComponent("Source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let a = source.appendingPathComponent("a.txt")
    try "one".write(to: a, atomically: true, encoding: .utf8)
    _ = try await engine.addItems([a])

    try "three".write(to: a, atomically: true, encoding: .utf8)
    let second = try await engine.addItems([a])
    print("    second add:", second.added, second.failed.map { "FAIL \($0.name): \($0.message)" })
    let names = try await engine.listItems().map(\.name)
    checkEqual(names, ["a 2.txt", "a.txt"], "duplicate name suffixed")

    // A reserved internal name must never replace the identity marker.
    let marker = root.appendingPathComponent(".vaultkey.json")
    try "evil".write(to: marker, atomically: true, encoding: .utf8)
    let reserved = try await engine.addItems([marker])
    checkEqual(reserved.added.count, 0, "reserved name refused")
    check(FileManager.default.fileExists(atPath: marker.path), "reserved source left alone")

    // Dragging the vault's own support folder in is refused.
    let support = root.appendingPathComponent("Support")
    let unsafe = try await engine.addItems([support])
    checkEqual(unsafe.added.count, 0, "support folder refused")

    try await engine.detach()
    try await engine.removeVaultImage()
}

await test("locked vault refuses access") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultKeyEngine-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = VaultEngine(paths: VaultPaths(supportDirectory: root.appendingPathComponent("Support")))
    await expectThrows("listing a locked vault fails") {
        _ = try await engine.listItems()
    }
}

// MARK: - Report

print("")
if failures == 0 {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures) of \(checks) checks failed")
    exit(1)
}
