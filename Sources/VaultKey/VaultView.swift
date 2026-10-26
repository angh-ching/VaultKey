import SwiftUI

struct VaultView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var isDropTargeted = false
    @State private var showDelete = false
    @State private var pendingDelete: Set<String> = []
    @State private var showForceLock = false
    @State private var showRecoveryReveal = false
    @State private var revealedKey: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let issue = model.lockIssue {
                lockIssueBanner(issue)
            }
            if !model.recoveryKeyConfirmed {
                recoveryBanner
            }

            Divider()

            if model.items.isEmpty {
                EmptyVaultView()
            } else {
                Table(model.items, selection: $selection) {
                    TableColumn("Name") { item in
                        HStack(spacing: 8) {
                            Image(nsImage: FileIcons.image(for: item))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 1)
                    }
                    .width(min: 220, ideal: 380)

                    TableColumn("Kind") { item in
                        Text(item.kind)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 90, ideal: 120)

                    TableColumn("Size") { item in
                        Text(Format.itemSize(item))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)

                    TableColumn("Modified") { item in
                        Text(Format.date(item.modified))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 150)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .contextMenu(forSelectionType: String.self) { names in
                    if !names.isEmpty {
                        Button("Open") { model.openItems(names) }
                        Button("Show in Finder") { model.revealItems(names) }
                        Divider()
                        Button("Restore to…") { model.beginRestore(names: names) }
                        Divider()
                        Button("Delete Permanently…", role: .destructive) {
                            confirmDelete(names)
                        }
                    }
                } primaryAction: { names in
                    model.openItems(names)
                }
                .onDeleteCommand {
                    if !selection.isEmpty { confirmDelete(selection) }
                }
            }

            if !selection.isEmpty {
                selectionBar
            }

            Divider()
            footer
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addItems(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .onChange(of: model.items) { _, newItems in
            selection = selection.intersection(Set(newItems.map(\.name)))
        }
        .sheet(isPresented: $showDelete) {
            DeleteItemsSheet(names: pendingDelete) {
                let names = pendingDelete
                showDelete = false
                Task { await model.deleteItems(names) }
            } onCancel: {
                showDelete = false
            }
        }
        .sheet(isPresented: $showRecoveryReveal) {
            if let revealedKey {
                RecoveryKeySheet(key: revealedKey, requiresConfirmation: false)
                    .environment(model)
            }
        }
        .onChange(of: showRecoveryReveal) { _, isShowing in
            if !isShowing { revealedKey = nil }
        }
        .alert("Force lock the vault?", isPresented: $showForceLock) {
            Button("Force Lock", role: .destructive) {
                Task { await model.forceLock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Force locking while files are open can cause unsaved changes to be lost. Quit the apps using the vault first if you can.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.vaultName)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        StatusDot()
                        Text("Unlocked")
                        Text("·").foregroundStyle(.tertiary)
                        Text(model.autoLockText)
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Vault unlocked. \(model.autoLockText).")
                }

                Spacer()

                Menu {
                    Button("Add Files…") { model.chooseFilesToAdd() }
                    Button("Add Folder…") { model.chooseFoldersToAdd() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.button)
                .help("Add files or folders to the vault")

                Button {
                    model.openVaultInFinder()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 18)
                }
                .buttonStyle(.bordered)
                .help("Open the vault in Finder")
            }

            HStack(spacing: 10) {
                StorageBar(fraction: model.usage?.fraction ?? 0)
                    .frame(width: 190)
                Text("\(Format.bytes(model.usage?.usedBytes)) of \(Format.bytes(model.usage?.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(Format.itemCount(model.items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private func lockIssueBanner(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.vaultOrange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("VaultKey couldn't close the vault")
                    .font(.callout.weight(.semibold))
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Try Again") {
                Task { await model.lock() }
            }
            Button("Force Lock…") {
                showForceLock = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.vaultOrange.opacity(0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.vaultOrange.opacity(0.20)).frame(height: 1)
        }
    }

    private var recoveryBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.vaultAccent)
            Text("Your recovery key hasn't been saved yet.")
                .font(.callout)
            Spacer()
            Button("Show Key…") {
                Task {
                    if let key = await model.revealRecoveryKey() {
                        revealedKey = key
                        showRecoveryReveal = true
                    }
                }
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color.vaultAccent.opacity(0.07))
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selection.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Restore…") {
                model.beginRestore(names: selection)
            }
            Button("Delete…") {
                confirmDelete(selection)
            }
            .tint(.vaultRed)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("AES-256 · Key stored in your login Keychain")
            Spacer()
            if let lastLock = model.lastLockDate {
                Text("Last locked \(Format.relativeDate(lastLock))")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.vaultAccent.opacity(0.06))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.vaultAccent,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.vaultAccent)
                Text("Add to \(model.vaultName)")
                    .font(.title3.weight(.semibold))
                Text("Files are encrypted and removed from their original location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func confirmDelete(_ names: Set<String>) {
        guard !names.isEmpty else { return }
        pendingDelete = names
        showDelete = true
    }
}

// MARK: - Empty state

struct EmptyVaultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.vaultAccent.opacity(0.09))
                    .frame(width: 100, height: 100)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.vaultAccent)
            }

            VStack(spacing: 7) {
                Text("Your vault is empty")
                    .font(.title3.weight(.semibold))
                Text("Drag files or folders here, or choose them from your Mac.\nThey're encrypted and removed from their original location.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Add Files…") { model.chooseFilesToAdd() }
                    .buttonStyle(.borderedProminent)
                Button("Add Folder…") { model.chooseFoldersToAdd() }
            }
            .controlSize(.large)

            Text("Originals are deleted after a verified copy.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(36)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 7])
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

// MARK: - Delete confirmation

struct DeleteItemsSheet: View {
    let names: Set<String>
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBubble(symbol: "trash.fill", tint: .vaultRed, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete permanently?")
                        .font(.headline)
                    Text("This can't be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !names.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(names.sorted().prefix(6)), id: \.self) { name in
                        Text(name)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if names.count > 6 {
                        Text("and \(names.count - 6) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
            }

            Text("These items won't go to the Trash. Restore them to your Mac instead if you want to keep them.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete Permanently", action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .tint(.vaultRed)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    private var description: String {
        names.count == 1
            ? "This item will be removed from the vault."
            : "These \(names.count) items will be removed from the vault."
    }
}
