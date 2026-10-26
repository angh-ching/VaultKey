import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WindowBackground()
            content
                .transition(.opacity)
            if model.isWorking {
                WorkingOverlay(message: model.workMessage)
                    .zIndex(20)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isWorking)
        .task {
            await model.start()
            await model.autoPromptIfNeeded()
        }
        .sheet(isPresented: securityInfoBinding) {
            SecurityDesignView()
        }
        .sheet(isPresented: recoveryKeyBinding) {
            if let key = model.recoveryKey {
                RecoveryKeySheet(key: key, requiresConfirmation: true)
                    .environment(model)
            }
        }
        .alert(
            model.alert?.title ?? "VaultKey",
            isPresented: alertBinding
        ) {
            Button("OK", role: .cancel) { model.alert = nil }
        } message: {
            Text(model.alert?.message ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case .setup:
            OnboardingView()
        case .locked, .authenticating, .unlocking:
            LockView()
        case .unlocked, .locking:
            MainWindowView()
        case .unavailable(let message):
            UnavailableView(message: message)
        }
    }

    private var securityInfoBinding: Binding<Bool> {
        Binding(
            get: { model.showSecurityInfo },
            set: { model.showSecurityInfo = $0 }
        )
    }

    private var recoveryKeyBinding: Binding<Bool> {
        Binding(
            get: { model.recoveryKey != nil },
            set: { newValue in
                // The recovery key sheet is only dismissed after the key has
                // been acknowledged; never by clicking away.
                if !newValue && model.recoveryKey == nil { return }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        )
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 60)
            ProgressView()
                .controlSize(.small)
            Text("Opening VaultKey…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 22) {
            AppMark(size: 64)
            VStack(spacing: 8) {
                Text("VaultKey can't open")
                    .font(.system(size: 24, weight: .semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480)
            }
            HStack(spacing: 12) {
                Button("Reveal Vault Folder") {
                    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("VaultKey")
                    NSWorkspace.shared.activateFileViewerSelecting([support])
                }
                Button("Quit VaultKey") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
