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

    /// Extract `<title>` from HTML string.
    public static func parseTitleFromHTML(_ html: String) -> String? {
        guard let startRange = html.range(of: "<title>", options: .caseInsensitive),
              let endRange = html.range(of: "</title>", options: .caseInsensitive),
              startRange.upperBound < endRange.lowerBound else {
            return nil
        }
        let title = String(html[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Fetch the HTML title from a localhost URL with a short timeout.
    private func fetchTitle(port: Int) async -> String? {
        guard let url = URL(string: "http://localhost:\(port)") else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            return Self.parseTitleFromHTML(html)
        } catch {
            return nil
        }
    }

    /// Full scan: discover all projects listening on ports in range.
    /// Uses HTML title as project name, falls back to process cwd folder name.
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
            // Try HTML title first
            let title = await fetchTitle(port: entry.port)

            // Fall back to cwd folder name
            let cwdOutput = try? await executor.run(
                lsofPath,
                arguments: ["-p", "\(entry.pid)", "-d", "cwd", "-Fn"]
            )
            let cwd = cwdOutput.flatMap { Self.parseCwdFromLsofOutput($0) } ?? "/unknown"

            guard !Self.isSystemPath(cwd) else { continue }

            projects.append(LocalProject(
                name: title,
                port: entry.port,
                pid: entry.pid,
                processType: entry.processType,
                cwd: cwd
            ))
        }

        return .success(projects)
    }
}
