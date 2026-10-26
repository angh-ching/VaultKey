import Foundation
import Security

/// A small container for sensitive bytes. Best-effort zeroing on release.
///
/// Swift strings and copy-on-write buffers can leave copies behind in memory.
/// This type keeps the secret in a single `Data` for as long as possible,
/// hands it to processes over stdin (never argv), and zeroes the buffer when
/// the vault locks.
public final class Secret: @unchecked Sendable {
    private var storage: Data

    public init(data: Data) {
        storage = data
    }

    public init(string: String) {
        storage = Data(string.utf8)
    }

    public var data: Data { storage }
    public var string: String { String(decoding: storage, as: UTF8.self) }

    public func wipe() {
        guard !storage.isEmpty else { return }
        storage.resetBytes(in: 0..<storage.count)
        storage = Data()
    }

    deinit {
        wipe()
    }

    /// 256 bits from the system CSPRNG.
    public static func random(byteCount: Int = 32) -> Secret {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "System random number generator unavailable")
        return Secret(data: Data(bytes))
    }
}
