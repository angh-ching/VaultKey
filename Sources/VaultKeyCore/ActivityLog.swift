import Foundation

public struct ActivityEvent: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case created
        case unlocked
        case locked
        case automaticLock
        case failedUnlock
        case lockBlocked
        case added
        case restored
        case deleted
        case recoveryKeyViewed
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let detail: String

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, detail: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.detail = detail
    }
}

/// A small, local audit trail. File names are never written here.
public struct ActivityLog: Sendable {
    public let url: URL
    private let limit: Int

    public init(url: URL, limit: Int = 300) {
        self.url = url
        self.limit = limit
    }

    public func append(kind: ActivityEvent.Kind, detail: String, date: Date = Date()) {
        let event = ActivityEvent(date: date, kind: kind, detail: detail)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)

        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try? manager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
        trimIfNeeded()
    }

    public func recent(limit count: Int = 30) -> [ActivityEvent] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A)
        var events: [ActivityEvent] = []
        for line in lines.suffix(count) {
            if let event = try? decoder.decode(ActivityEvent.self, from: Data(line)) {
                events.append(event)
            }
        }
        return events.reversed()
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    private func trimIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > 128_000 else { return }
        let events = recent(limit: limit)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for event in events.reversed() {
            if let line = try? encoder.encode(event) {
                data.append(line)
                data.append(0x0A)
            }
        }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
