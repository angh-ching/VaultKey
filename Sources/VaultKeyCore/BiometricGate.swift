import Foundation
import LocalAuthentication

public enum BiometricError: LocalizedError {
    case unavailable(String)
    case cancelled
    case lockout
    case notEnrolled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .cancelled:
            return "Authentication was cancelled."
        case .lockout:
            return "Touch ID is locked. Enter your Mac password to re-enable it, then try again."
        case .notEnrolled:
            return "Touch ID has no enrolled fingers. Set up Touch ID in System Settings."
        case .failed(let message):
            return "Authentication failed. \(message)"
        }
    }
}

public struct BiometricAvailability: Sendable, Equatable {
    public let isAvailable: Bool
    public let kind: String
    public let detail: String?

    public init(isAvailable: Bool, kind: String, detail: String? = nil) {
        self.isAvailable = isAvailable
        self.kind = kind
        self.detail = detail
    }
}

public enum BiometricGate {
    public static func availability(allowPasswordFallback: Bool = true) -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        let hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let kind = name(for: context.biometryType)

        if hasBiometrics {
            return BiometricAvailability(isAvailable: true, kind: kind)
        }

        // canEvaluatePolicy can fail before biometryType is populated.
        let reason = friendlyReason(error)
        let hasPassword = allowPasswordFallback && context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        if hasPassword {
            return BiometricAvailability(
                isAvailable: true,
                kind: kind,
                detail: "\(kind) is unavailable. Your Mac password will be used."
            )
        }
        return BiometricAvailability(
            isAvailable: false,
            kind: kind,
            detail: reason ?? "\(kind) is unavailable."
        )
    }

    /// Shows a fresh Touch ID prompt. A new LAContext is used every time, so an
    /// earlier success can never be replayed for a later unlock.
    public static func authenticate(
        reason: String,
        allowPasswordFallback: Bool
    ) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        if !allowPasswordFallback {
            context.localizedFallbackTitle = ""
        }

        var error: NSError?
        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else if allowPasswordFallback,
                  context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            policy = .deviceOwnerAuthentication
        } else {
            throw BiometricError.unavailable(friendlyReason(error) ?? "Touch ID is unavailable on this Mac.")
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                context.evaluatePolicy(policy, localizedReason: reason) { success, evaluationError in
                    if success {
                        continuation.resume()
                    } else if let evaluationError {
                        continuation.resume(throwing: Self.mapError(evaluationError as NSError))
                    } else {
                        continuation.resume(throwing: BiometricError.failed("Unknown error."))
                    }
                }
            }
        } catch let error as BiometricError {
            throw error
        } catch {
            throw Self.mapError(error as NSError)
        }
    }

    private static func mapError(_ error: NSError) -> BiometricError {
        guard error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code) else {
            return .failed(error.localizedDescription)
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .biometryLockout:
            return .lockout
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryNotAvailable:
            return .unavailable("Touch ID is not available on this Mac.")
        case .authenticationFailed:
            return .failed("Touch ID didn't recognize you.")
        case .userFallback:
            return .cancelled
        case .passcodeNotSet:
            return .unavailable("Set a password for your Mac before using VaultKey.")
        default:
            return .failed(error.localizedDescription)
        }
    }

    private static func friendlyReason(_ error: NSError?) -> String? {
        guard let error else { return nil }
        return mapError(error).errorDescription
    }

    public static func name(for type: LABiometryType) -> String {
        switch type {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        default: return "Touch ID"
        }
    }
}
