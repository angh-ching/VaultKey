import Foundation
import LocalAuthentication

public struct SecurityReport: Sendable, Equatable {
    public var fileVaultEnabled: Bool?
    public var screenLockSeconds: Int?
    public var freeDiskBytes: Int64?
    public var biometricsAvailable: Bool
    public var biometricKind: String
    public var biometricDetail: String?

    public init(
        fileVaultEnabled: Bool? = nil,
        screenLockSeconds: Int? = nil,
        freeDiskBytes: Int64? = nil,
        biometricsAvailable: Bool = false,
        biometricKind: String = "Touch ID",
        biometricDetail: String? = nil
    ) {
        self.fileVaultEnabled = fileVaultEnabled
        self.screenLockSeconds = screenLockSeconds
        self.freeDiskBytes = freeDiskBytes
        self.biometricsAvailable = biometricsAvailable
        self.biometricKind = biometricKind
        self.biometricDetail = biometricDetail
    }
}

public enum SecurityInspector {
    public static func inspect(allowPasswordFallback: Bool = true) async -> SecurityReport {
        async let vault = fileVaultEnabled()
        async let screen = screenLockDelay()
        let biometrics = BiometricGate.availability(allowPasswordFallback: allowPasswordFallback)
        let free = freeDiskSpace()

        return SecurityReport(
            fileVaultEnabled: await vault,
            screenLockSeconds: await screen,
            freeDiskBytes: free,
            biometricsAvailable: biometrics.isAvailable,
            biometricKind: biometrics.kind,
            biometricDetail: biometrics.detail
        )
    }

    public static func fileVaultEnabled() async -> Bool? {
        guard let result = try? await CommandRunner.run("/usr/bin/fdesetup", ["status"]),
              result.succeeded else { return nil }
        let text = result.stdout.lowercased()
        if text.contains("filevault is on") { return true }
        if text.contains("filevault is off") { return false }
        return nil
    }

    /// Reads the system screen-lock delay. `sysadminctl` writes its answer to
    /// stderr on some macOS versions.
    public static func screenLockDelay() async -> Int? {
        guard let result = try? await CommandRunner.run("/usr/sbin/sysadminctl", ["-screenLock", "status"]) else {
            return nil
        }
        let text = (result.stdout + " " + result.stderr).lowercased()
        if text.contains("off") { return 0 }
        let pattern = #"delay is (\d+) seconds"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let seconds = Int(text[range]) {
            return seconds
        }
        return nil
    }

    public static func freeDiskSpace() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return capacity
    }
}
