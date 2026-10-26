import AppKit
import SwiftUI

@main
struct VaultKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("VaultKey", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 620)
                .tint(.vaultAccent)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Vault") {
                Button(model.isUnlocked ? "Lock Vault" : "Unlock Vault") {
                    if model.isUnlocked {
                        Task { await model.lock() }
                    } else {
                        Task { await model.unlock() }
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!(model.phase == .unlocked || model.phase == .locked))

                Divider()

                Button("Add Files…") {
                    model.chooseFilesToAdd()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!model.isUnlocked)

                Button("Add Folder…") {
                    model.chooseFoldersToAdd()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!model.isUnlocked)

                Divider()

                Button("Open Vault in Finder") {
                    model.openVaultInFinder()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!model.isUnlocked)

                Button("Show Recovery Key…") {
                    Task {
                        if let key = await model.revealRecoveryKey() {
                            model.alert = AppAlert(title: "Recovery key", message: key)
                        }
                    }
                }
                .disabled(!model.isUnlocked)
            }

            CommandGroup(replacing: .help) {
                Button("VaultKey Security…") {
                    model.showSecurityInfo = true
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .tint(.vaultAccent)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Give AppKit a beat to remove the window, then lock if the main
            // window is gone. Settings windows don't keep the vault open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let mainVisible = NSApp.windows.contains { window in
                    window.identifier?.rawValue == "mainWindow" && window.isVisible
                }
                guard !mainVisible else { return }
                Task { @MainActor in
                    guard AppModel.shared.isUnlocked else { return }
                    await AppModel.shared.lock(reason: .windowClosed)
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            AppModel.shared.applicationBecameActive()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            let canQuit = await AppModel.shared.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.identifier?.rawValue == "mainWindow" {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
