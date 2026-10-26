import AppKit
import Foundation
import Observation
import SwiftUI

enum AppPhase: Equatable {
    case loading
    case setup
    case locked
    case authenticating
    case unlocking
    case unlocked
    case locking
    case unavailable(String)

    var showsLockScreen: Bool {
        switch self {
        case .locked, .authenticating, .unlocking: return true
        default: return false
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case vault
    case security

    var id: String { rawValue }
    var title: String {
        switch self {
        case .vault: return "Vault"
        case .security: return "Security"
        }
    }

    var symbol: String {
        switch self {
        case .vault: return "lock.fill"
        case .security: return "checkmark.shield.fill"
        }
    }
}

enum LockReason: String {
    case manual
    case automatic
    case screenLock
    case sleep
    case windowClosed
    case external
    case quit

    var activityDetail: String {
        switch self {
        case .manual: return "Locked manually"
        case .automatic: return "Auto-lock"
        case .screenLock: return "Screen locked"
        case .sleep: return "Mac went to sleep"
        case .windowClosed: return "Window closed"
        case .external: return "Vault volume disappeared"
        case .quit: return "VaultKey quit"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Public state

    private(set) var phase: AppPhase = .loading
    private(set) var config: VaultConfig?
    private(set) var items: [VaultItem] = []
    private(set) var usage: VaultUsage?
    private(set) var security = SecurityReport()
    private(set) var activity: [ActivityEvent] = []
    private(set) var lockIssue: String?
    private(set) var autoLockRemaining: TimeInterval?
    private(set) var isWorking = false
    private(set) var workMessage = ""
    private(set) var authMessage: String?
    private(set) var setupError: String?
    private(set) var recoveryKey: String?
    private(set) var lastLockDate: Date?

    var alert: AppAlert?
    var showSecurityInfo = false
    var sidebarSection: SidebarSection = .vault

    // MARK: Dependencies

    let paths: VaultPaths
    @ObservationIgnored private let engine: VaultEngine
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private let activityLog: ActivityLog

    // MARK: Private state

    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var didAutoPrompt = false
    @ObservationIgnored private var lastInteraction: Date?
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var eventMonitor: Any?

    private init(paths: VaultPaths = VaultPaths()) {
        let paths = paths
        self.paths = paths
        self.engine = VaultEngine(paths: paths)
        self.configStore = ConfigStore(url: paths.configURL)
        self.activityLog = ActivityLog(url: paths.activityURL)
        self.security = SecurityReport(
            biometricsAvailable: BiometricGate.availability().isAvailable,
            biometricKind: BiometricGate.availability().kind
        )
    }

    // MARK: Derived values

    var vaultName: String { config?.name ?? "VaultKey" }
    var isUnlocked: Bool { phase == .unlocked || phase == .locking }
    var isLocked: Bool { phase == .locked || phase == .authenticating || phase == .unlocking }
    var autoLockMinutes: Int { config?.autoLockMinutes ?? 15 }
    var autoLockText: String {
        autoLockMinutes <= 0 ? "Auto-lock off" : Format.countdown(autoLockRemaining)
    }

    var recoveryKeyConfirmed: Bool { config?.recoveryKeyConfirmed ?? false }

    var biometricKind: String {
        security.biometricKind.isEmpty ? "Touch ID" : security.biometricKind
    }

    var requiresInitialUnlock: Bool {
        if case .locked = phase { return true }
        return false
    }

    // MARK: - Lifecycle

    func start() async {
        guard !didStart else { return }
        didStart = true
        installObservers()
        await bootstrap()
    }

    private func bootstrap() async {
        do {
            guard let loaded = try configStore.load() else {
                phase = .setup
                await refreshSecurity()
                return
            }
            config = loaded

            guard FileManager.default.fileExists(atPath: paths.imageURL.path) else {
                phase = .unavailable(
                    "The encrypted vault file is missing.\n\nVaultKey expected it at:\n\(paths.imageURL.path)\n\nPut the file back, or move the matching config back with it."
                )
                return
            }

            _ = await engine.imageSize() // warm the file system cache
            if let warning = await engine.cleanupStaleMount() {
                lockIssue = warning
            }
            await refreshSecurity()
            activity = activityLog.recent(limit: 40)
            phase = .locked
        } catch {
            phase = .unavailable(error.localizedDescription)
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.systemLocked(.sleep) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.systemLocked(.sleep) }
        })

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.systemLocked(.screenLock) }
        })
        observers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.sessionDidResignActive"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.systemLocked(.screenLock) }
        })

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel, .flagsChanged, .gesture]
        ) { [weak self] event in
            Task { @MainActor in self?.noteInteraction() }
            return event
        }
    }

    private func systemLocked(_ reason: LockReason) async {
        guard let config, phase == .unlocked else { return }
        if reason == .sleep && !config.lockOnSleep { return }
        if reason == .screenLock && !config.lockOnScreenLock { return }
        await lock(reason: reason)
    }

    // MARK: - Setup

    func createVault(
        name: String,
        quotaGB: Int,
        autoLockMinutes: Int,
        allowPasswordFallback: Bool
    ) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setupError = "Give your vault a name."
            return false
        }
        guard !isWorking else { return false }

        setupError = nil
        isWorking = true
        workMessage = "Creating your vault…"
        defer { isWorking = false }

        let config = VaultConfig.make(
            name: trimmed,
            quotaGB: quotaGB,
            autoLockMinutes: autoLockMinutes,
            allowPasswordFallback: allowPasswordFallback
        )
        let recovery = RecoveryKey.generate()
        let key = Secret(string: recovery)
        defer { key.wipe() }

        do {
            let availability = BiometricGate.availability(allowPasswordFallback: allowPasswordFallback)
            let reason = availability.isAvailable
                ? "Set up \(availability.kind) for “\(trimmed)”"
                : "Set up your vault"
            try await BiometricGate.authenticate(reason: reason, allowPasswordFallback: allowPasswordFallback)
        } catch {
            setupError = error.localizedDescription
            return false
        }

        var imageCreated = false
        var keySaved = false
        do {
            workMessage = "Encrypting the vault…"
            try await engine.create(id: config.id, name: config.name, quotaGB: quotaGB, key: key)
            imageCreated = true

            workMessage = "Sealing the key…"
            try keychain.saveKey(key, vaultID: config.id, vaultName: config.name)
            keySaved = true

            try configStore.save(config)
            self.config = config
            self.recoveryKey = RecoveryKey.formatted(recovery)
            self.lastInteraction = Date()
            self.activityLog.append(kind: .created, detail: "Encrypted vault created")
            self.activity = self.activityLog.recent(limit: 40)
            self.phase = .unlocked
            self.startAutoLockTimer()
            await refreshContents()
            await refreshSecurity()
            return true
        } catch {
            if keySaved { try? keychain.deleteKey(vaultID: config.id) }
            if imageCreated {
                try? await engine.detach(force: true)
                try? await engine.removeVaultImage()
            }
            setupError = error.localizedDescription
            return false
        }
    }

    func confirmRecoveryKeySaved() {
        guard var config else { return }
        config.recoveryKeyConfirmed = true
        self.config = config
        try? configStore.save(config)
        recoveryKey = nil
    }

    // MARK: - Lock & unlock

    func unlock() async {
        guard phase == .locked, let config else { return }
        authMessage = nil
        phase = .authenticating
        do {
            try await BiometricGate.authenticate(
                reason: "Unlock “\(config.name)”",
                allowPasswordFallback: config.allowPasswordFallback
            )
            phase = .unlocking
            let key = try keychain.loadKey(vaultID: config.id)
            defer { key.wipe() }
            _ = try await engine.attach(key: key, expectedID: config.id)
            await didUnlock(detail: config.allowPasswordFallback ? "Authentication" : biometricKind)
        } catch is CancellationError {
            phase = .locked
        } catch {
            phase = .locked
            authMessage = friendlyUnlockError(error)
            if let biometric = error as? BiometricError, case .cancelled = biometric {
                // No audit entry for a deliberate cancel.
            } else {
                activityLog.append(kind: .failedUnlock, detail: "Unlock failed")
                activity = activityLog.recent(limit: 40)
            }
        }
    }

    private func didUnlock(detail: String) async {
        authMessage = nil
        lockIssue = nil
        lastInteraction = Date()
        autoLockRemaining = nil
        activityLog.append(kind: .unlocked, detail: "Unlocked with \(detail)")
        activity = activityLog.recent(limit: 40)
        phase = .unlocked
        startAutoLockTimer()
        await refreshContents()
        await refreshSecurity()
    }

    func unlockWithRecoveryKey(_ raw: String) async -> String? {
        guard let config else { return "The vault configuration is missing." }
        guard let normalized = RecoveryKey.normalize(raw) else {
            return "That recovery key isn't valid. It has 32 characters, usually shown in groups of four."
        }
        guard phase == .locked || phase == .authenticating else { return nil }

        phase = .unlocking
        let key = Secret(string: normalized)
        do {
            _ = try await engine.attach(key: key, expectedID: config.id)
            // Repair the Keychain entry if it was missing or stale.
            try? keychain.saveKey(key, vaultID: config.id, vaultName: config.name)
            key.wipe()
            await didUnlock(detail: "Recovery key")
            return nil
        } catch {
            key.wipe()
            phase = .locked
            return friendlyUnlockError(error)
        }
    }

    private func friendlyUnlockError(_ error: Error) -> String {
        if let keychainError = error as? KeychainError {
            switch keychainError {
            case .notFound, .corrupt, .keychainLocked:
                return "\(keychainError.localizedDescription) Open it with your recovery key."
            default:
                return keychainError.localizedDescription
            }
        }
        if let biometric = error as? BiometricError {
            switch biometric {
            case .cancelled:
                return ""
            default:
                return biometric.localizedDescription
            }
        }
        return error.localizedDescription
    }

    func lock(reason: LockReason = .manual) async {
        guard phase == .unlocked else { return }
        phase = .locking
        authMessage = nil
        do {
            try await engine.detach()
            completeLock(reason: reason)
        } catch {
            phase = .unlocked
            lockIssue = error.localizedDescription
            activityLog.append(kind: .lockBlocked, detail: "Couldn't lock: \(reason.activityDetail)")
            activity = activityLog.recent(limit: 40)
        }
    }

    func forceLock() async {
        guard phase == .unlocked || phase == .locking else { return }
        isWorking = true
        workMessage = "Closing the vault…"
        defer { isWorking = false }
        do {
            try await engine.detach(force: true)
            completeLock(reason: .manual)
        } catch {
            lockIssue = error.localizedDescription
        }
    }

    private func completeLock(reason: LockReason) {
        autoLockTask?.cancel()
        autoLockTask = nil
        autoLockRemaining = nil
        lastInteraction = nil
        items = []
        usage = nil
        lockIssue = nil
        authMessage = nil
        lastLockDate = Date()
        phase = .locked
        let kind: ActivityEvent.Kind = reason == .automatic ? .automaticLock : .locked
        activityLog.append(kind: kind, detail: reason.activityDetail)
        activity = activityLog.recent(limit: 40)
        engine.cleanupAfterLock()
    }

    func prepareForTermination() async -> Bool {
        guard phase == .unlocked else { return true }
        do {
            try await engine.detach()
            completeLock(reason: .quit)
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "VaultKey couldn't lock your vault."
            alert.informativeText = """
            \(error.localizedDescription)

            If you quit now, the vault volume stays mounted until VaultKey opens again. Close the files in use and try again, or quit anyway.
            """
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Anyway")
            let response = alert.runModal()
            return response == .alertSecondButtonReturn
        }
    }

    // MARK: - Contents

    func refreshContents() async {
        guard isUnlocked else { return }
        do {
            let newItems = try await engine.listItems()
            let newUsage = try await engine.usage()
            items = newItems
            usage = newUsage
        } catch let error as VaultError {
            if case .notMounted = error {
                items = []
                usage = nil
                completeLock(reason: .external)
            } else {
                alert = .error("Couldn't read the vault", error.localizedDescription)
            }
        } catch {
            alert = .error("Couldn't read the vault", error.localizedDescription)
        }
    }

    func refreshSecurity() async {
        security = await SecurityInspector.inspect(allowPasswordFallback: config?.allowPasswordFallback ?? false)
    }

    func addItems(_ urls: [URL]) {
        guard isUnlocked, !isWorking else { return }
        let accepted = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !accepted.isEmpty else { return }

        isWorking = true
        workMessage = accepted.count == 1 ? "Protecting 1 item…" : "Protecting \(accepted.count) items…"
        Task {
            do {
                let summary = try await engine.addItems(accepted) { [weak self] name in
                    Task { @MainActor in self?.workMessage = "Protecting “\(name)”…" }
                }
                workMessage = "Updating your vault…"
                await refreshContents()
                isWorking = false

                if !summary.added.isEmpty {
                    activityLog.append(
                        kind: .added,
                        detail: summary.added.count == 1 ? "1 item added" : "\(summary.added.count) items added"
                    )
                    activity = activityLog.recent(limit: 40)
                }

                if !summary.failed.isEmpty {
                    alert = .error("Some items couldn't be added", failureMessage(summary.failed))
                } else if summary.added.isEmpty {
                    alert = .error("Nothing was added", "VaultKey couldn't move those items into the vault.")
                }

                if !summary.originalsNotRemoved.isEmpty {
                    let names = summary.originalsNotRemoved.prefix(4).joined(separator: "\n")
                    alert = .error(
                        "Copies left outside the vault",
                        "These items were copied into the vault but couldn't be removed from their original location:\n\n\(names)"
                    )
                }
            } catch {
                isWorking = false
                alert = .error("Couldn't add items", error.localizedDescription)
            }
        }
    }

    func chooseFilesToAdd() {
        guard isUnlocked else { return }
        let panel = NSOpenPanel()
        panel.title = "Add to \(vaultName)"
        panel.message = "Choose files to encrypt in your vault. They'll be removed from their original location."
        panel.prompt = "Add to Vault"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        if panel.runModal() == .OK {
            addItems(panel.urls)
        }
    }

    func chooseFoldersToAdd() {
        guard isUnlocked else { return }
        let panel = NSOpenPanel()
        panel.title = "Add to \(vaultName)"
        panel.message = "Choose folders to encrypt in your vault. They'll be removed from their original location."
        panel.prompt = "Add to Vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            addItems(panel.urls)
        }
    }

    func beginRestore(names: Set<String>) {
        guard isUnlocked, !names.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Restore from \(vaultName)"
        panel.message = "Choose where to put the decrypted copies."
        panel.prompt = "Restore Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await restore(names: Array(names), to: destination) }
    }

    private func restore(names: [String], to destination: URL) async {
        isWorking = true
        workMessage = "Restoring…"
        do {
            let summary = try await engine.restoreItems(names: names, to: destination)
            await refreshContents()
            isWorking = false
            if !summary.restored.isEmpty {
                activityLog.append(
                    kind: .restored,
                    detail: summary.restored.count == 1 ? "1 item restored" : "\(summary.restored.count) items restored"
                )
                activity = activityLog.recent(limit: 40)
                NSWorkspace.shared.activateFileViewerSelecting(summary.restored)
            }
            if !summary.failed.isEmpty {
                alert = .error("Some items need attention", failureMessage(summary.failed))
            }
        } catch {
            isWorking = false
            alert = .error("Couldn't restore items", error.localizedDescription)
        }
    }

    func deleteItems(_ names: Set<String>) async {
        guard isUnlocked, !names.isEmpty, !isWorking else { return }
        isWorking = true
        workMessage = names.count == 1 ? "Deleting 1 item…" : "Deleting \(names.count) items…"
        defer { isWorking = false }
        do {
            let deleted = try await engine.deleteItems(names: Array(names))
            await refreshContents()
            activityLog.append(kind: .deleted, detail: deleted == 1 ? "1 item deleted" : "\(deleted) items deleted")
            activity = activityLog.recent(limit: 40)
        } catch {
            alert = .error("Couldn't delete items", error.localizedDescription)
        }
    }

    func openItems(_ names: Set<String>) {
        for name in names where !name.contains("/") && name != ".." {
            NSWorkspace.shared.open(paths.mountPoint.appendingPathComponent(name))
        }
    }

    func revealItems(_ names: Set<String>) {
        let urls = names
            .filter { !$0.contains("/") && $0 != ".." }
            .map { paths.mountPoint.appendingPathComponent($0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openVaultInFinder() {
        guard isUnlocked else { return }
        NSWorkspace.shared.open(paths.mountPoint)
    }

    func revealVaultFile() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.imageURL])
    }

    // MARK: - Recovery key

    func revealRecoveryKey() async -> String? {
        guard let config else { return nil }
        do {
            try await BiometricGate.authenticate(
                reason: "Show the recovery key for “\(config.name)”",
                allowPasswordFallback: config.allowPasswordFallback
            )
            let key = try keychain.loadKey(vaultID: config.id)
            let formatted = RecoveryKey.formatted(key.string)
            key.wipe()
            activityLog.append(kind: .recoveryKeyViewed, detail: "Recovery key viewed")
            activity = activityLog.recent(limit: 40)
            return formatted
        } catch {
            if let biometric = error as? BiometricError, case .cancelled = biometric {
                return nil
            }
            alert = .error("Couldn't show the recovery key", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Settings

    func setAutoLock(minutes: Int) {
        guard var config else { return }
        config.autoLockMinutes = minutes
        self.config = config
        try? configStore.save(config)
        lastInteraction = Date()
        startAutoLockTimer()
    }

    func setLockOnSleep(_ enabled: Bool) {
        updateConfig { $0.lockOnSleep = enabled }
    }

    func setLockOnScreenLock(_ enabled: Bool) {
        updateConfig { $0.lockOnScreenLock = enabled }
    }

    func setAllowPasswordFallback(_ enabled: Bool) {
        updateConfig { $0.allowPasswordFallback = enabled }
        Task { await refreshSecurity() }
    }

    func renameVault(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = .error("The name can't be empty", "Choose a name for your vault.")
            return
        }
        updateConfig { $0.name = trimmed }
    }

    private func updateConfig(_ mutate: (inout VaultConfig) -> Void) {
        guard var config else { return }
        mutate(&config)
        self.config = config
        try? configStore.save(config)
    }

    // MARK: - Deletion

    func deleteVault() async -> Bool {
        guard let config else { return false }
        isWorking = true
        workMessage = "Deleting the vault…"
        defer { isWorking = false }
        do {
            try await BiometricGate.authenticate(
                reason: "Permanently delete “\(config.name)”",
                allowPasswordFallback: config.allowPasswordFallback
            )
            if await engine.isMounted() {
                try await engine.detach(force: true)
            }
            try await engine.removeVaultImage()
            try configStore.delete()
            try? keychain.deleteKey(vaultID: config.id)
            activityLog.clear()
            self.config = nil
            self.recoveryKey = nil
            self.items = []
            self.usage = nil
            self.activity = []
            self.lastInteraction = nil
            autoLockTask?.cancel()
            autoLockTask = nil
            self.phase = .setup
            return true
        } catch {
            alert = .error("Couldn't delete the vault", error.localizedDescription)
            return false
        }
    }

    // MARK: - Auto-lock

    func noteInteraction() {
        guard phase == .unlocked else { return }
        lastInteraction = Date()
    }

    func applicationBecameActive() {
        guard phase == .unlocked else { return }
        enforceAutoLockDeadline()
        noteInteraction()
    }

    private func enforceAutoLockDeadline() {
        guard let config, config.autoLockMinutes > 0, let lastInteraction else { return }
        if Date().timeIntervalSince(lastInteraction) >= Double(config.autoLockMinutes * 60) {
            Task { await lock(reason: .automatic) }
        }
    }

    private func startAutoLockTimer() {
        autoLockTask?.cancel()
        autoLockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                self?.tickAutoLock()
            }
        }
    }

    private func tickAutoLock() {
        guard phase == .unlocked else {
            autoLockRemaining = nil
            return
        }
        guard let config, config.autoLockMinutes > 0, let lastInteraction else {
            autoLockRemaining = nil
            return
        }
        let deadline = lastInteraction.addingTimeInterval(Double(config.autoLockMinutes) * 60)
        let remaining = deadline.timeIntervalSinceNow
        autoLockRemaining = max(0, remaining)
        if remaining <= 0 {
            autoLockTask?.cancel()
            Task { await lock(reason: .automatic) }
        }
    }

    func autoPromptIfNeeded() async {
        guard !didAutoPrompt, phase == .locked, config != nil else { return }
        didAutoPrompt = true
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard phase == .locked, NSApp.isActive, !isWorking else { return }
        await unlock()
    }

    // MARK: - Helpers

    private func failureMessage(_ failures: [AddFailure]) -> String {
        failures.prefix(6).map { "“\($0.name)”: \($0.message)" }.joined(separator: "\n\n")
    }
}
