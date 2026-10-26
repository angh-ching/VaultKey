import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var draftName = ""
    @State private var autoLockMinutes = 15
    @State private var lockOnSleep = true
    @State private var lockOnScreenLock = true
    @State private var allowPasswordFallback = false
    @State private var showDeleteVault = false
    @State private var showRecovery = false
    @State private var showSecurityInfo = false
    @State private var revealedKey: String?
    @State private var copiedRecovery = false

    var body: some View {
        Group {
            if model.config != nil {
                settingsForm
            } else {
                noVault
            }
        }
        .frame(width: 540, height: 640)
        .onAppear { syncFromModel() }
        .onChange(of: model.config) { _, _ in syncFromModel() }
        .sheet(isPresented: $showDeleteVault) {
            DeleteVaultSheet(vaultName: model.vaultName) {
                showDeleteVault = false
            }
            .environment(model)
        }
        .sheet(isPresented: $showSecurityInfo) {
            SecurityDesignView()
        }
        .sheet(isPresented: $showRecovery) {
            if let revealedKey {
                RecoveryKeySheet(key: revealedKey, requiresConfirmation: false)
                    .environment(model)
            }
        }
        .onChange(of: showRecovery) { _, isShowing in
            if !isShowing { revealedKey = nil }
        }
    }

    // MARK: - Form

    private var settingsForm: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    HStack(spacing: 8) {
                        TextField("Vault name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            .frame(width: 230)
                            .onSubmit(rename)
                        Button("Rename", action: rename)
                            .disabled(!canRename)
                    }
                }

                LabeledContent("Location") {
                    HStack(spacing: 8) {
                        Text(model.paths.supportDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([model.paths.supportDirectory])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Show the vault folder in Finder")
                    }
                }

                LabeledContent("Created") {
                    Text(model.config?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Vault")
            }

            Section {
                Picker("Auto-lock", selection: $autoLockMinutes) {
                    Text("After 1 minute").tag(1)
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("After 30 minutes").tag(30)
                    Text("After 1 hour").tag(60)
                    Text("Never").tag(0)
                }
                .onChange(of: autoLockMinutes) { _, minutes in
                    model.setAutoLock(minutes: minutes)
                }

                Toggle("Lock when the Mac goes to sleep", isOn: $lockOnSleep)
                    .onChange(of: lockOnSleep) { _, enabled in
                        model.setLockOnSleep(enabled)
                    }

                Toggle("Lock when the screen locks", isOn: $lockOnScreenLock)
                    .onChange(of: lockOnScreenLock) { _, enabled in
                        model.setLockOnScreenLock(enabled)
                    }
            } header: {
                Text("Locking")
            } footer: {
                Text("Auto-lock counts from your last interaction with VaultKey. Opening the vault again always requires \(model.biometricKind).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow Mac password fallback", isOn: $allowPasswordFallback)
                    .onChange(of: allowPasswordFallback) { _, enabled in
                        model.setAllowPasswordFallback(enabled)
                    }

                LabeledContent("\(model.biometricKind)") {
                    HStack(spacing: 6) {
                        StatusDot(tone: model.security.biometricsAvailable ? .green : .orange, size: 6)
                        Text(model.security.biometricsAvailable ? "Ready" : "Unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Unlock")
            } footer: {
                Text(allowPasswordFallback
                     ? "Your Mac password can unlock the vault when \(model.biometricKind) is unavailable. Strict mode is safer."
                     : "Strict mode. Only \(model.biometricKind) can unlock the vault.")
                    .font(.caption)
                    .foregroundStyle(allowPasswordFallback ? Color.vaultOrange : Color.secondary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery key")
                        Text(model.recoveryKeyConfirmed ? "Saved and confirmed" : "Not confirmed yet")
                            .font(.caption)
                            .foregroundStyle(model.recoveryKeyConfirmed ? Color.secondary : Color.vaultOrange)
                    }
                    Spacer()
                    Button("Show Key…") {
                        Task {
                            if let key = await model.revealRecoveryKey() {
                                revealedKey = key
                                showRecovery = true
                            }
                        }
                    }
                    .disabled(model.phase != .unlocked)
                }

                Button("How VaultKey Protects Your Files…") {
                    showSecurityInfo = true
                }
            } header: {
                Text("Recovery & Security")
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete this vault")
                            .font(.callout.weight(.semibold))
                        Text("Permanently deletes the encrypted vault, every file inside it, its Keychain entry, and its activity log. This can't be undone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Delete Vault…") {
                        showDeleteVault = true
                    }
                    .tint(.vaultRed)
                }
            } header: {
                Text("Danger Zone")
            }

            Section {
                LabeledContent("Version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Privacy") {
                    Text("No network access · No accounts · No telemetry")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            } footer: {
                Text("VaultKey stores your vault in ~/Library/Application Support/VaultKey. The key lives in your login Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Empty state

    private var noVault: some View {
        VStack(spacing: 14) {
            AppMark(size: 58)
            Text("No vault yet")
                .font(.title3.weight(.semibold))
            Text("Create a vault in the main VaultKey window to change these settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var canRename: Bool {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != model.vaultName
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private func rename() {
        guard canRename else { return }
        model.renameVault(draftName)
        draftName = model.vaultName
    }

    private func syncFromModel() {
        guard let config = model.config else { return }
        draftName = config.name
        autoLockMinutes = config.autoLockMinutes
        lockOnSleep = config.lockOnSleep
        lockOnScreenLock = config.lockOnScreenLock
        allowPasswordFallback = config.allowPasswordFallback
    }
}

// MARK: - Delete confirmation

struct DeleteVaultSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let vaultName: String
    let onDeleted: () -> Void

    @State private var confirmation = ""
    @State private var isDeleting = false

    private var canDelete: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
            && !isDeleting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                IconBubble(symbol: "trash.fill", tint: .vaultRed, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete “\(vaultName)”?")
                        .font(.headline)
                    Text("Every file in the vault will be destroyed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("The encrypted vault file is deleted, not moved to the Trash.", systemImage: "xmark.circle")
                Label("The Keychain entry and activity log are removed.", systemImage: "key.slash")
                Label("Files can't be recovered, even with a recovery key.", systemImage: "exclamationmark.triangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Type DELETE to confirm.")
                    .font(.callout.weight(.medium))
                TextField("DELETE", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isDeleting)
                    .onSubmit { if canDelete { deleteVault() } }
            }

            if isDeleting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Deleting the vault…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isDeleting)
                Button("Delete Vault", role: .destructive, action: deleteVault)
                    .buttonStyle(.borderedProminent)
                    .tint(.vaultRed)
                    .disabled(!canDelete)
            }
        }
        .padding(24)
        .frame(width: 470)
        .interactiveDismissDisabled(isDeleting)
    }

    private func deleteVault() {
        guard canDelete else { return }
        isDeleting = true
        Task {
            let deleted = await model.deleteVault()
            isDeleting = false
            if deleted {
                dismiss()
                onDeleted()
            }
        }
    }
}
