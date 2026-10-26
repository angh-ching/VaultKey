import SwiftUI

struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var showRecovery = false

    private var isAuthenticating: Bool { model.phase == .authenticating }
    private var isUnlocking: Bool { model.phase == .unlocking }
    private var isBusy: Bool { isAuthenticating || isUnlocking }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 26) {
                AppMark(size: 76)

                VStack(spacing: 7) {
                    Text(model.vaultName)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(statusText)
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }

                Button(action: unlock) {
                    HStack(spacing: 9) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "touchid")
                                .font(.system(size: 15, weight: .medium))
                        }
                        Text(buttonTitle)
                            .fontWeight(.medium)
                    }
                    .frame(minWidth: 250)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 10) {
                    if model.config?.allowPasswordFallback == true {
                        Button("Use Mac Password", action: unlock)
                            .buttonStyle(.link)
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }
                    Button("Use Recovery Key…") {
                        showRecovery = true
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)

                if let message = model.authMessage, !message.isEmpty {
                    ErrorNote(message: message)
                        .frame(maxWidth: 390)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 40)

            Spacer(minLength: 24)

            HStack(spacing: 7) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10, weight: .semibold))
                Text("AES-256 encryption · Stays on this Mac")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showRecovery) {
            RecoveryUnlockSheet()
                .environment(model)
        }
    }

    private var statusText: String {
        switch model.phase {
        case .authenticating: return "Waiting for \(model.biometricKind)…"
        case .unlocking: return "Opening your vault…"
        default: return "Locked"
        }
    }

    private var buttonTitle: String {
        if isAuthenticating { return "Waiting for \(model.biometricKind)…" }
        if isUnlocking { return "Opening…" }
        return "Unlock with \(model.biometricKind)"
    }

    private func unlock() {
        guard !isBusy else { return }
        Task { await model.unlock() }
    }
}
