import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ActivityFilter = .all

    private var events: [ActivityEvent] {
        switch filter {
        case .all:
            return model.activity
        case .access:
            return model.activity.filter { [.unlocked, .locked, .automaticLock, .failedUnlock, .lockBlocked].contains($0.kind) }
        case .files:
            return model.activity.filter { [.added, .restored, .deleted].contains($0.kind) }
        case .recovery:
            return model.activity.filter { [.created, .recoveryKeyViewed].contains($0.kind) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()

            if events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events) { event in
                            ActivityRow(event: event, showsDate: true)
                            if event.id != events.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Divider()

            HStack {
                Label("Stored only on this Mac", systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconBubble(symbol: "clock.arrow.circlepath", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity")
                    .font(.headline)
                Text("A local record of locks, unlocks, and file changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var filterBar: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ActivityFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "clock")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(filter == .all ? "No activity yet" : "Nothing in this category")
                .font(.callout.weight(.medium))
            Text("VaultKey records events here as you use your vault.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filters

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case access
    case files
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .access: return "Locks"
        case .files: return "Files"
        case .recovery: return "Recovery"
        }
    }
}

// MARK: - Row

struct ActivityRow: View {
    let event: ActivityEvent
    var showsDate: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(event.kind.tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(event.kind.tint.opacity(0.11))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(event.kind.title)
                    .font(.callout.weight(.medium))
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.relativeDate(event.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsDate {
                    Text(Format.date(event.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.kind.title). \(event.detail). \(Format.relativeDate(event.date)).")
    }
}

// MARK: - Event presentation

extension ActivityEvent.Kind {
    var title: String {
        switch self {
        case .created: return "Vault created"
        case .unlocked: return "Vault unlocked"
        case .locked: return "Vault locked"
        case .automaticLock: return "Auto-locked"
        case .failedUnlock: return "Unlock failed"
        case .lockBlocked: return "Lock blocked"
        case .added: return "Items added"
        case .restored: return "Items restored"
        case .deleted: return "Items deleted"
        case .recoveryKeyViewed: return "Recovery key viewed"
        }
    }

    var symbol: String {
        switch self {
        case .created: return "sparkles"
        case .unlocked: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .automaticLock: return "timer"
        case .failedUnlock: return "xmark.shield.fill"
        case .lockBlocked: return "exclamationmark.triangle.fill"
        case .added: return "plus.circle.fill"
        case .restored: return "arrow.up.doc.fill"
        case .deleted: return "trash.fill"
        case .recoveryKeyViewed: return "key.fill"
        }
    }

    var tint: Color {
        switch self {
        case .created, .unlocked, .added: return .vaultGreen
        case .locked, .automaticLock: return .secondary
        case .failedUnlock, .deleted: return .vaultRed
        case .lockBlocked, .recoveryKeyViewed: return .vaultOrange
        case .restored: return .vaultAccent
        }
    }
}
