import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Palette

extension Color {
    static let vaultAccent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.31, green: 0.49, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.35, blue: 0.83, alpha: 1)
    })

    static let vaultGreen = Color(nsColor: .systemGreen)
    static let vaultOrange = Color(nsColor: .systemOrange)
    static let vaultRed = Color(nsColor: .systemRed)
    static let vaultTeal = Color(nsColor: .systemTeal)
}

// Allow leading-dot color names in `.foregroundStyle(.vaultAccent)`.
extension ShapeStyle where Self == Color {
    static var vaultAccent: Color { .vaultAccent }
    static var vaultGreen: Color { .vaultGreen }
    static var vaultOrange: Color { .vaultOrange }
    static var vaultRed: Color { .vaultRed }
    static var vaultTeal: Color { .vaultTeal }
}

// MARK: - Backgrounds & cards

struct WindowBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [.vaultAccent.opacity(0.06), .clear, .vaultAccent.opacity(0.015)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.065), lineWidth: 1)
                    )
            )
    }
}

// MARK: - App mark

struct AppMark: View {
    var size: CGFloat = 64
    var shadow: Bool = true

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(
                color: shadow ? .black.opacity(0.18) : .clear,
                radius: size * 0.07,
                y: size * 0.04
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Small building blocks

struct IconBubble: View {
    let symbol: String
    var tint: Color = .vaultAccent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

enum StatusTone {
    case green, orange, red, gray, blue

    var color: Color {
        switch self {
        case .green: return .vaultGreen
        case .orange: return .vaultOrange
        case .red: return .vaultRed
        case .gray: return .secondary
        case .blue: return .vaultAccent
        }
    }
}

struct StatusChip: View {
    let text: String
    var tone: StatusTone = .green

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(tone.color.opacity(0.13)))
    }
}

struct StatusDot: View {
    var tone: StatusTone = .green
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
            .shadow(color: tone.color.opacity(0.55), radius: size * 0.7)
            .accessibilityHidden(true)
    }
}

struct StorageBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.vaultAccent, .vaultAccent.opacity(0.68)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fraction <= 0 ? 0 : max(4, geometry.size.width * min(1, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Vault storage used")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

struct ErrorNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.vaultOrange)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.vaultOrange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.vaultOrange.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

struct WorkingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.10).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 240)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        }
        .transition(.opacity)
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func itemSize(_ item: VaultItem) -> String {
        item.isDirectory ? "—" : bytes(item.size)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func relativeDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    static func countdown(_ remaining: TimeInterval?) -> String {
        guard let remaining else { return "Auto-lock off" }
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func autoLockDescription(_ minutes: Int) -> String {
        minutes <= 0 ? "Auto-lock off" : "Locks after \(minutes) min"
    }

    static func screenLock(_ seconds: Int?) -> String {
        guard let seconds else { return "Unknown" }
        if seconds == 0 { return "Immediately" }
        if seconds < 60 { return "After \(seconds) seconds" }
        if seconds % 60 == 0 && seconds < 3600 { return "After \(seconds / 60) minutes" }
        return "After \(seconds / 60) minutes"
    }

    static func itemCount(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

// MARK: - Clipboard

enum Clipboard {
    /// Copies a secret and clears it again after a minute, unless something
    /// else has replaced the pasteboard contents in the meantime.
    static func copySensitive(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }
}

// MARK: - File icons

@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func image(for item: VaultItem) -> NSImage {
        let key: String
        let type: UTType
        if item.isDirectory {
            key = "folder"
            type = .folder
        } else {
            let ext = (item.name as NSString).pathExtension.lowercased()
            key = ext.isEmpty ? "data" : ext
            type = UTType(filenameExtension: ext) ?? .data
        }
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}

// MARK: - Window access

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("mainWindow")
            window.tabbingMode = .disallowed
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Alerts

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String

    static func error(_ title: String, _ message: String) -> AppAlert {
        AppAlert(title: title, message: message)
    }
}
