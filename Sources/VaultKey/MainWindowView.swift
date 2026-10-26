import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var section: SidebarSection = .vault

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $section) {
                    Section {
                        Label("Vault", systemImage: "lock.fill")
                            .badge(model.items.count)
                            .tag(SidebarSection.vault)
                    }
                    Section("Security") {
                        Label("Overview", systemImage: "checkmark.shield.fill")
                            .tag(SidebarSection.security)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                SidebarFooter()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 218, max: 270)
        } detail: {
            Group {
                switch section {
                case .vault:
                    VaultView()
                case .security:
                    SecurityView()
                }
            }
            .navigationTitle(section.title)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            section = model.sidebarSection
        }
        .onChange(of: section) { _, newValue in
            model.sidebarSection = newValue
        }
        .onChange(of: model.sidebarSection) { _, newValue in
            section = newValue
        }
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    StatusDot(tone: model.lockIssue == nil ? .green : .orange, size: 6)
                    Text(model.lockIssue == nil ? "Unlocked" : "Lock blocked")
                        .font(.caption.weight(.medium))
                }
                Text(model.lockIssue == nil ? model.autoLockText : "Action needed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                Task { await model.lock() }
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Lock Vault (⌘L)")
            .disabled(model.phase != .unlocked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
