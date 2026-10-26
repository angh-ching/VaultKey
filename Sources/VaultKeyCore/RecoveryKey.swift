import Foundation
import Security

/// A human-typable 160-bit key, encoded with Crockford's base32 alphabet.
/// It is both the recovery code and the passphrase of the encrypted disk image,
/// so a vault can always be opened with Disk Utility and this key, even if
/// VaultKey itself is gone.
public enum RecoveryKey {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let keyLength = 32 // 160 bits

    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 20)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "System random number generator unavailable")

        var bits = 0
        var accumulator = 0
        var output = ""
        output.reserveCapacity(keyLength)
        for byte in bytes {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(accumulator >> bits) & 0x1F])
            }
        }
        return output
    }

    /// Uppercases, strips separators, and corrects common lookalikes.
    /// Returns nil when the result is not a valid 160-bit key.
    public static func normalize(_ input: String) -> String? {
        var result = ""
        result.reserveCapacity(keyLength)
        for character in input.uppercased() {
            switch character {
            case "0", "O": result.append("0")
            case "1", "I", "L": result.append("1")
            case "U": result.append("V")
            case " ", "-", "_", "\t", "\n": continue
            default:
                if alphabet.contains(character) {
                    result.append(character)
                } else {
                    return nil
                }
            }
        }
        guard result.count == keyLength else { return nil }
        return result
    }

    public static func formatted(_ key: String) -> String {
        stride(from: 0, to: key.count, by: 4).map { offset in
            let start = key.index(key.startIndex, offsetBy: offset)
            let end = key.index(start, offsetBy: min(4, key.count - offset))
            return String(key[start..<end])
        }.joined(separator: "-")
    }

    public static func isValid(_ input: String) -> Bool {
        normalize(input) != nil
    }
}
