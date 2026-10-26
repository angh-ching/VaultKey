import SwiftUI

struct SecurityDesignView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            IconBubble(symbol: "lock.shield.fill", size: 44)
                            Text("How VaultKey protects your files")
                                .font(.system(size: 22, weight: .semibold))
                        }
                        Text("A short, honest description of the security model.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    section(
                        "Encryption",
                        text: "Your vault is an Apple encrypted disk image (sparse bundle) using AES-256. The 160-bit vault key is generated on this Mac with the system random number generator. Files are copied into the encrypted volume, verified, and only then removed from their original location."
                    )

                    section(
                        "Touch ID",
                        text: "VaultKey asks macOS to authenticate you with Touch ID before it reads the vault key from your login Keychain. Each unlock uses a fresh authentication context, so an earlier success can't be reused. Strict mode removes the Mac password fallback."
                    )

                    section(
                        "Local by design",
                        text: "There is no account, no cloud sync, no analytics, and no networking code in VaultKey. The vault, its configuration, and its audit log live in ~/Library/Application Support/VaultKey. The vault key lives in your login Keychain."
                    )

                    section(
                        "Recovery",
                        text: "The recovery key is the passphrase of the encrypted disk image. That means you can always open the vault with Disk Utility and the key, even if VaultKey is gone. In Disk Utility, enter the 32 characters without the dashes. If both Touch ID and the recovery key are lost, the files cannot be recovered."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What VaultKey can't protect")
                            .font(.headline)
                        Bullet("While the vault is unlocked it is a normal mounted volume. Other apps running as your user can read it. Lock the vault when you step away.")
                        Bullet("Auto-lock, screen-lock locking, and sleep locking close the volume, but files that are still open can prevent it from closing. VaultKey warns you instead of forcing a detach.")
                        Bullet("If VaultKey is force quit or crashes while unlocked, the volume may stay mounted until VaultKey next opens and closes it.")
                        Bullet("Deleted originals are removed, not overwritten. FileVault protects the freed blocks on disk. Keep FileVault on.")
                        Bullet("VaultKey is signed locally without a provisioning entitlement, so Touch ID is enforced by the app before it reads the Keychain item. It is not a hardware-bound Keychain access control.")
                    }

                    Text("Keep macOS up to date, use FileVault, and lock your Mac when you leave it. No app can make an unlocked computer completely safe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 600, height: 640)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func Bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.callout.weight(.bold))
                .foregroundStyle(.vaultAccent)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
