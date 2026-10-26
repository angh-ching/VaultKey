import SwiftUI

struct RecoveryUnlockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                IconBubble(symbol: "key.fill", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Recovery Key")
                        .font(.headline)
                    Text("Enter the key you saved when you created this vault.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($focused)
                .disabled(isWorking)
                .onSubmit(submit)

            if let errorMessage {
                ErrorNote(message: errorMessage)
            }

            Text("The key is checked locally against the encrypted vault. It never leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button(action: submit) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock Vault")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
        }
        .padding(24)
        .frame(width: 470)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !isWorking else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task {
            let result = await model.unlockWithRecoveryKey(trimmed)
            isWorking = false
            if let result {
                errorMessage = result
            } else {
                dismiss()
            }
        }
    }
}

struct RecoveryKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let key: String
    let requiresConfirmation: Bool

    @State private var acknowledged = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                IconBubble(symbol: "key.fill", tint: .vaultOrange, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(requiresConfirmation ? "Save your recovery key" : "Your recovery key")
                        .font(.headline)
                    Text("This key opens your vault if Touch ID isn't available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(key)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button {
                    Clipboard.copySensitive(key)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy Key", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Text("Clears from the clipboard after a minute.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Write it down or store it in a password manager.", systemImage: "pencil.line")
                Label("Don't keep it on this Mac.", systemImage: "externaldrive.badge.xmark")
                Label("In Disk Utility, enter the 32 characters without the dashes.", systemImage: "externaldrive")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if requiresConfirmation {
                Toggle("I've saved my recovery key somewhere safe.", isOn: $acknowledged)
                    .toggleStyle(.checkbox)
                    .font(.callout)

                Text("If you lose this key and Touch ID becomes unavailable, VaultKey can't recover your files.")
                    .font(.caption)
                    .foregroundStyle(.vaultOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(requiresConfirmation ? "Continue" : "Done") {
                    if requiresConfirmation {
                        model.confirmRecoveryKeySaved()
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(requiresConfirmation && !acknowledged)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .interactiveDismissDisabled(requiresConfirmation)
    }
}
