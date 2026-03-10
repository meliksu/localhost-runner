import Foundation

public enum ShellError: Error, Equatable {
    case executionFailed(String)
    case timeout
    case notFound
}

public struct ShellExecutor: Sendable {
    public init() {}

    public func run(_ path: String, arguments: [String] = [], timeout: TimeInterval = 5.0) async throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ShellError.notFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            var outputData = Data()
            var hasResumed = false
            let lock = NSLock()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            // Read data as it arrives to avoid pipe buffer deadlock
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                lock.lock()
                outputData.append(chunk)
                lock.unlock()
            }

            // Timer for timeout
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                process.terminate()
            }
            timer.resume()

            // Use terminationHandler to avoid blocking a thread
            process.terminationHandler = { proc in
                timer.cancel()
                // Stop reading
                pipe.fileHandleForReading.readabilityHandler = nil
                // Read any remaining data
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()

                lock.lock()
                outputData.append(remaining)
                let finalData = outputData
                let alreadyResumed = hasResumed
                hasResumed = true
                lock.unlock()

                guard !alreadyResumed else { return }

                if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: ShellError.timeout)
                } else {
                    let output = String(data: finalData, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                lock.lock()
                let alreadyResumed = hasResumed
                hasResumed = true
                lock.unlock()
                guard !alreadyResumed else { return }
                continuation.resume(throwing: ShellError.executionFailed(error.localizedDescription))
            }
        }
    }
}
