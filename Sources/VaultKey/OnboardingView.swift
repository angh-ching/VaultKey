import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = "My Vault"
    @State private var quotaGB = 32
    @State private var autoLockMinutes = 15
    @State private var allowPasswordFallback = false
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (model.security.biometricsAvailable || allowPasswordFallback)
            && !model.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    AppMark(size: 72)
                    VStack(spacing: 8) {
                        Text("A private place for your files.")
                            .font(.system(size: 30, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("VaultKey encrypts folders and files in a vault that only Touch ID opens. Nothing leaves this Mac.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 500)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(
                        symbol: "touchid",
                        title: "Touch ID only",
                        detail: "Every unlock requires your fingerprint. The key is never read before you authenticate."
                    )
                    FeatureRow(
                        symbol: "lock.shield.fill",
                        title: "Encrypted at rest",
                        detail: "Apple's AES-256 encrypted disk image, with a 160-bit key generated on this Mac."
                    )
                    FeatureRow(
                        symbol: "wifi.slash",
                        title: "Completely offline",
                        detail: "No account, no cloud, no telemetry, and no network access of any kind."
                    )
                }
                .frame(maxWidth: 520)

                Card(padding: 16) {
                    VStack(spacing: 0) {
                        OnboardingRow(title: "Vault name") {
                            TextField("My Vault", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .frame(width: 240)
                                .focused($nameFocused)
                                .onSubmit(create)
                        }
                        Divider().padding(.vertical, 8)
                        OnboardingRow(title: "Maximum size") {
                            Picker("", selection: $quotaGB) {
                                ForEach([16, 32, 64, 128, 256], id: \.self) { size in
                                    Text("\(size) GB").tag(size)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                        Divider().padding(.vertical, 8)
                        OnboardingRow(title: "Auto-lock") {
                            Picker("", selection: $autoLockMinutes) {
                                Text("After 1 minute").tag(1)
                                Text("After 5 minutes").tag(5)
                                Text("After 15 minutes").tag(15)
                                Text("After 30 minutes").tag(30)
                                Text("After 1 hour").tag(60)
                                Text("Never").tag(0)
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        Divider().padding(.vertical, 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Allow Mac password fallback", isOn: $allowPasswordFallback)
                                .toggleStyle(.checkbox)
                            Text("If Touch ID is unavailable, you can use your Mac password instead. Strict Touch ID is safer.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: 520)

                if !model.security.biometricsAvailable && !allowPasswordFallback {
                    ErrorNote(
                        message: "\(model.security.biometricDetail ?? "Touch ID isn't available on this Mac.") Turn on Mac password fallback to create a vault."
                    )
                    .frame(maxWidth: 520)
                }

                if let setupError = model.setupError {
                    ErrorNote(message: setupError)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 10) {
                    Button(action: create) {
                        Text("Create Vault")
                            .fontWeight(.medium)
                            .frame(width: 230)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)

                    Text("You'll get a recovery key next. It's the only way in if Touch ID fails.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            nameFocused = true
        }
    }

    private func create() {
        guard canCreate else { return }
        Task {
            _ = await model.createVault(
                name: name,
                quotaGB: quotaGB,
                autoLockMinutes: autoLockMinutes,
                allowPasswordFallback: allowPasswordFallback
            )
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBubble(symbol: symbol, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
    }
}
