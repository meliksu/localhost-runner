import Foundation

public struct PortPidEntry: Sendable {
    public let port: Int
    public let pid: Int
    public let processType: String
}

public actor PortScanner {
    private let executor: ShellExecutor
    private let portRange: ClosedRange<Int>

    public init(executor: ShellExecutor = ShellExecutor(), portRange: ClosedRange<Int> = 3000...9000) {
        self.executor = executor
        self.portRange = portRange
    }

    /// Parse lsof output into port-PID entries using regex for robustness.
    public static func parseLsofOutput(_ output: String, portRange: ClosedRange<Int>) -> [PortPidEntry] {
        var seen = Set<Int>()
        var results: [PortPidEntry] = []

        for line in output.components(separatedBy: "\n") {
            guard line.contains("(LISTEN)") else { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 9 else { continue }

            let command = String(columns[0])
            guard let pid = Int(columns[1]) else { continue }

            let fullLine = String(line)
            guard let portMatch = fullLine.range(of: #":(\d+)\s+\(LISTEN\)"#, options: .regularExpression) else { continue }
            let matchedText = fullLine[portMatch]
            guard let colonRange = matchedText.range(of: #":(\d+)"#, options: .regularExpression) else { continue }

            let portString = matchedText[colonRange].dropFirst()
            guard let port = Int(portString) else { continue }

            guard portRange.contains(port) else { continue }
            guard !seen.contains(port) else { continue }

            seen.insert(port)
            results.append(PortPidEntry(port: port, pid: pid, processType: command.lowercased()))
        }

        return results
    }

    /// Parse cwd from `lsof -p PID -d cwd -Fn` output.
    public static func parseCwdFromLsofOutput(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    /// Check if a path is a system path (should be filtered out).
    public static func isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/usr/") || path.hasPrefix("/System/")
    }

    /// Scan result including possible error state.
    public enum ScanResult: Sendable {
        case success([LocalProject])
        case error(String)
    }

    /// Full scan: discover all projects listening on ports in range.
    public func scan() async -> ScanResult {
        let lsofPath = "/usr/sbin/lsof"

        let output: String
        do {
            output = try await executor.run(
                lsofPath,
                arguments: ["-iTCP:\(portRange.lowerBound)-\(portRange.upperBound)", "-sTCP:LISTEN", "-n", "-P"]
            )
        } catch let error as ShellError {
            switch error {
            case .notFound:
                return .error("lsof not found")
            case .timeout:
                return .error("Scan timed out")
            case .executionFailed(let msg):
                return .error("Scan failed: \(msg)")
            }
        } catch {
            return .error("Scan failed: \(error.localizedDescription)")
        }

        let entries = Self.parseLsofOutput(output, portRange: portRange)
        var projects: [LocalProject] = []

        for entry in entries {
            let cwdOutput = try? await executor.run(
                lsofPath,
                arguments: ["-p", "\(entry.pid)", "-d", "cwd", "-Fn"]
            )

            let cwd = cwdOutput.flatMap { Self.parseCwdFromLsofOutput($0) } ?? "/unknown"

            guard !Self.isSystemPath(cwd) else { continue }

            projects.append(LocalProject(
                port: entry.port,
                pid: entry.pid,
                processType: entry.processType,
                cwd: cwd
            ))
        }

        return .success(projects)
    }
}
