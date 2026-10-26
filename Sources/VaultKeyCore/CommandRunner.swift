import Foundation
import Darwin

public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CommandError: LocalizedError {
    case launchFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let tool, let message):
            return "Couldn't run \(tool). \(message)"
        }
    }
}

/// Runs a command without a shell. Secrets are written to stdin, never argv.
public enum CommandRunner {
    private final class Buffers: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()

        func setOut(_ data: Data) { lock.lock(); out = data; lock.unlock() }
        func setErr(_ data: Data) { lock.lock(); err = data; lock.unlock() }
        func snapshot() -> (Data, Data) { lock.lock(); defer { lock.unlock() }; return (out, err) }
    }

    public static func run(
        _ executable: String,
        _ arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let input = Pipe()
                let output = Pipe()
                let errors = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = errors

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.launchFailed(executable, error.localizedDescription))
                    return
                }

                if let stdin {
                    // hdiutil may exit before reading (for example when the
                    // image already exists); a broken pipe must not crash us.
                    try? input.fileHandleForWriting.write(contentsOf: stdin)
                }
                try? input.fileHandleForWriting.closeFile()

                let buffers = Buffers()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    buffers.setOut(output.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    buffers.setErr(errors.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning {
                    process.terminate()
                    Thread.sleep(forTimeInterval: 0.2)
                    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                }
                process.waitUntilExit()
                _ = group.wait(timeout: .now() + 5)

                let (outData, errData) = buffers.snapshot()
                let result = CommandResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                )
                continuation.resume(returning: result)
            }
        }
    }
}
