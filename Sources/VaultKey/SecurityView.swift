import SwiftUI

struct SecurityView: View {
    @Environment(AppModel.self) private var model
    @State private var showActivity = false
    @State private var showRecovery = false
    @State private var revealedKey: String?

    private var report: SecurityReport { model.security }

    private var needsAttention: Bool {
        report.fileVaultEnabled == false
            || model.autoLockMinutes == 0
            || report.screenLockSeconds == nil
            || !report.biometricsAvailable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                statGrid
                protectionCard
                recoveryCard
                activityCard
                footer
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 30)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(WindowBackground())
        .navigationTitle("Security")
        .sheet(isPresented: $showActivity) {
            ActivityView()
                .environment(model)
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

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.vaultAccent.opacity(0.20), .vaultAccent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.vaultAccent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(needsAttention ? "Review recommended" : "Your vault is protected")
                        .font(.system(size: 25, weight: .bold))
                        .lineLimit(2)
                    StatusChip(
                        text: needsAttention ? "Check settings" : "All clear",
                        tone: needsAttention ? .orange : .green
                    )
                }
                Text(needsAttention
                     ? "A few Mac settings could leave your files exposed. VaultKey still encrypts everything in the vault."
                     : "Encrypted at rest, locked automatically, and opened only after \(model.biometricKind).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                Task { await model.refreshSecurity() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.bordered)
            .help("Check these settings again")
            .accessibilityLabel("Refresh security check")
        }
    }

    // MARK: - Stat cards

    private var statGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
            spacing: 14
        ) {
            SecurityStatCard(
                symbol: "lock.square.stack.fill",
                label: "Encryption",
                value: "AES-256",
                detail: "Apple encrypted disk image",
                tone: .blue
            )
            SecurityStatCard(
                symbol: "touchid",
                label: "Unlock",
                value: model.biometricKind,
                detail: model.config?.allowPasswordFallback == true ? "Mac password fallback on" : "Strict mode",
                tone: report.biometricsAvailable ? .green : .orange
            )
            SecurityStatCard(
                symbol: "timer",
                label: "Auto-lock",
                value: model.autoLockMinutes <= 0 ? "Off" : "\(model.autoLockMinutes) min",
                detail: model.autoLockMinutes <= 0 ? "Vault stays open" : "After last activity",
                tone: model.autoLockMinutes <= 0 ? .orange : .green
            )
            SecurityStatCard(
                symbol: "internaldrive.fill",
                label: "FileVault",
                value: fileVaultText,
                detail: "Full-disk encryption",
                tone: report.fileVaultEnabled == false ? .orange : .green
            )
        }
    }

    private var fileVaultText: String {
        switch report.fileVaultEnabled {
        case true: return "On"
        case false: return "Off"
        case nil: return "Unknown"
        }
    }

    // MARK: - Protection details

    private var protectionCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                cardHeader("Protection details", subtitle: "Settings that keep your Mac and vault safe")

                SecurityRow(
                    symbol: "touchid",
                    title: "\(model.biometricKind)",
                    detail: report.biometricDetail ?? "Required before the vault key is read.",
                    value: report.biometricsAvailable ? "Ready" : "Unavailable",
                    tone: report.biometricsAvailable ? .green : .orange
                )
                Divider().padding(.leading, 62)
                SecurityRow(
                    symbol: "internaldrive",
                    title: "FileVault",
                    detail: "Protects the whole disk if your Mac is lost or stolen.",
                    value: fileVaultText,
                    tone: report.fileVaultEnabled == false ? .orange : .green
                )
                Divider().padding(.leading, 62)
                SecurityRow(
                    symbol: "rectangle.inset.filled.and.person.filled",
                    title: "Screen lock",
                    detail: "VaultKey locks when macOS locks the screen.",
                    value: Format.screenLock(report.screenLockSeconds),
                    tone: report.screenLockSeconds == nil ? .orange : .green
                )
                Divider().padding(.leading, 62)
                SecurityRow(
                    symbol: "lock.rotation",
                    title: "Auto-lock",
                    detail: "Counts from your last interaction with VaultKey.",
                    value: Format.autoLockDescription(model.autoLockMinutes),
                    tone: model.autoLockMinutes == 0 ? .orange : .green
                )
                Divider().padding(.leading, 62)
                SecurityRow(
                    symbol: "key.horizontal.fill",
                    title: "Mac password fallback",
                    detail: model.config?.allowPasswordFallback == true
                        ? "Your Mac password can also unlock this vault."
                        : "Strict mode only accepts \(model.biometricKind).",
                    value: model.config?.allowPasswordFallback == true ? "Allowed" : "Off",
                    tone: model.config?.allowPasswordFallback == true ? .orange : .green
                )
            }
        }
    }

    // MARK: - Recovery

    private var recoveryCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                IconBubble(symbol: "key.fill", tint: .vaultOrange, size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Recovery key")
                            .font(.headline)
                        StatusChip(
                            text: model.recoveryKeyConfirmed ? "Saved" : "Not confirmed",
                            tone: model.recoveryKeyConfirmed ? .green : .orange
                        )
                    }
                    Text("This key is the passphrase of the encrypted disk image. It opens your vault even if VaultKey or Touch ID stops working.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

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
        }
    }

    // MARK: - Activity

    private var activityCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recent activity")
                            .font(.headline)
                        Text("VaultKey never records file names.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show All…") { showActivity = true }
                        .buttonStyle(.link)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Divider()

                if model.activity.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.tertiary)
                        Text("No activity yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.activity.prefix(5))) { event in
                            ActivityRow(event: event)
                            if event.id != model.activity.prefix(5).last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("How VaultKey Works…") {
                model.showSecurityInfo = true
            }
            Button("Activity Log…") {
                showActivity = true
            }
            Spacer()
            Text("AES-256 · 160-bit key · Local only")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func cardHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Building blocks

private struct SecurityStatCard: View {
    let symbol: String
    let label: String
    let value: String
    let detail: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBubble(symbol: symbol, tint: tone.color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SecurityRow: View {
    let symbol: String
    let title: String
    let detail: String
    let value: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(tone.color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}
