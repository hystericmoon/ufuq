import Foundation

enum ProcessRunnerError: Error {
    case timedOut
    case failed(Int32)
}

/// Runs a command off the main thread with a timeout and returns its stdout.
enum ProcessRunner {
    struct Output {
        var status: Int32
        var stdout: Data
    }

    private final class Box: @unchecked Sendable {
        let process = Process()
        var timedOut = false
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) async throws -> Output {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let box = Box()
                let pipe = Pipe()
                box.process.executableURL = URL(fileURLWithPath: executable)
                box.process.arguments = arguments
                box.process.standardOutput = pipe
                box.process.standardError = FileHandle.nullDevice
                box.process.standardInput = FileHandle.nullDevice
                do {
                    try box.process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let killer = DispatchWorkItem {
                    box.timedOut = true
                    if box.process.isRunning { box.process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                // Blocks until the process closes stdout (exits or is terminated).
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                box.process.waitUntilExit()
                killer.cancel()
                if box.timedOut {
                    continuation.resume(throwing: ProcessRunnerError.timedOut)
                } else {
                    continuation.resume(returning: Output(status: box.process.terminationStatus, stdout: data))
                }
            }
        }
    }
}
