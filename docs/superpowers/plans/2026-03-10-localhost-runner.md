# Localhost Runner Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that scans localhost ports 3000–9000 for running dev servers and lets you open them in the browser with one click.

**Architecture:** SwiftUI app with `MenuBarExtra` (`.window` style) for the menu bar dropdown. Port/process scanning via `lsof` in a Swift actor. Settings persisted in `UserDefaults`. Built as an Xcode project to produce a proper `.app` bundle (required for `LSUIElement`, `SMAppService`, and `MenuBarExtra`).

**Tech Stack:** Swift, SwiftUI, Foundation `Process`, Swift concurrency (async/await, actors), `SMAppService`, `MenuBarExtra`

**Spec:** `docs/superpowers/specs/2026-03-10-localhost-runner-design.md`

---

## File Structure

The project uses an Xcode project (not SPM) because a proper `.app` bundle is required for `LSUIElement`, `SMAppService`, and `MenuBarExtra` to work correctly. To keep tests working with `@testable import`, the core logic lives in a separate framework target (`LocalhostRunnerCore`) while the app target is a thin shell with just `@main`.

```
LocalhostRunner/
├── LocalhostRunner.xcodeproj/
├── Sources/
│   ├── App/
│   │   └── LocalhostRunnerApp.swift          # @main, thin shell
│   └── Core/
│       ├── Models/
│       │   └── LocalProject.swift            # Data model
│       ├── Services/
│       │   ├── PortScanner.swift             # Actor: lsof scanning
│       │   └── ShellExecutor.swift           # Process() wrapper with timeout
│       ├── Views/
│       │   ├── ProjectListView.swift         # Main dropdown content
│       │   ├── ProjectRowView.swift          # Single project row
│       │   ├── EmptyStateView.swift          # Empty/error state
│       │   └── SettingsView.swift            # Settings window
│       └── ViewModels/
│           └── ProjectListViewModel.swift    # @MainActor ObservableObject
├── Tests/
│   ├── LocalProjectTests.swift
│   ├── ShellExecutorTests.swift
│   └── PortScannerTests.swift
└── Info.plist                                # LSUIElement = true
```

---

## Chunk 1: Project Setup & Core Model

### Task 1: Create Xcode Project

**Files:**
- Create: entire project structure + Xcode project via `xcodebuild`

- [ ] **Step 1: Create directory structure**

```bash
cd /Users/meliksu/Github/localhost-runner
mkdir -p Sources/App
mkdir -p Sources/Core/Models
mkdir -p Sources/Core/Services
mkdir -p Sources/Core/Views
mkdir -p Sources/Core/ViewModels
mkdir -p Tests
```

- [ ] **Step 2: Create Package.swift with library + executable split**

This uses SPM with a library target for testable core logic and an executable for the app shell. We'll create a build script to bundle it as a `.app` later.

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalhostRunner",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LocalhostRunnerCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "LocalhostRunner",
            dependencies: ["LocalhostRunnerCore"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "LocalhostRunnerTests",
            dependencies: ["LocalhostRunnerCore"],
            path: "Tests"
        ),
    ]
)
```

- [ ] **Step 3: Create Info.plist**

Create `Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.localhostrunner.app</string>
    <key>CFBundleName</key>
    <string>Localhost Runner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Create build script for .app bundle**

Create `scripts/build-app.sh`:

```bash
#!/bin/bash
set -e

APP_NAME="Localhost Runner"
BUNDLE_DIR=".build/release/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

# Build release binary
swift build -c release

# Create .app bundle structure
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"

# Copy binary and Info.plist
cp .build/release/LocalhostRunner "${MACOS_DIR}/LocalhostRunner"
cp Info.plist "${CONTENTS_DIR}/Info.plist"

echo "Built: ${BUNDLE_DIR}"
```

```bash
chmod +x scripts/build-app.sh
```

- [ ] **Step 5: Commit**

```bash
git add Package.swift Info.plist Sources/ Tests/ scripts/
git commit -m "chore: scaffold project with library/executable split and build script"
```

---

### Task 2: LocalProject Model

**Files:**
- Create: `Sources/Core/Models/LocalProject.swift`
- Test: `Tests/LocalProjectTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LocalProjectTests.swift`:

```swift
import Testing
@testable import LocalhostRunnerCore

@Suite("LocalProject Model")
struct LocalProjectTests {
    @Test("creates project with correct properties")
    func createProject() {
        let project = LocalProject(
            name: "lumaria-web",
            port: 3000,
            pid: 12345,
            processType: "node",
            cwd: "/Users/me/Github/lumaria-web"
        )

        #expect(project.name == "lumaria-web")
        #expect(project.port == 3000)
        #expect(project.pid == 12345)
        #expect(project.processType == "node")
        #expect(project.url.absoluteString == "http://localhost:3000")
    }

    @Test("derives name from cwd folder when name not provided")
    func deriveNameFromCwd() {
        let project = LocalProject(
            port: 3000,
            pid: 12345,
            processType: "node",
            cwd: "/Users/me/Github/my-project"
        )

        #expect(project.name == "my-project")
    }

    @Test("is identifiable by port")
    func identifiableByPort() {
        let project = LocalProject(
            port: 8080,
            pid: 99,
            processType: "python",
            cwd: "/tmp/test"
        )

        #expect(project.id == 8080)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LocalProjectTests 2>&1`
Expected: FAIL — `LocalProject` not defined

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Core/Models/LocalProject.swift`:

```swift
import Foundation

public struct LocalProject: Identifiable, Equatable, Hashable {
    public let name: String
    public let port: Int
    public let pid: Int
    public let processType: String
    public let cwd: String

    public var id: Int { port }

    public var url: URL {
        URL(string: "http://localhost:\(port)")!
    }

    public init(name: String? = nil, port: Int, pid: Int, processType: String, cwd: String) {
        self.name = name ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.port = port
        self.pid = pid
        self.processType = processType
        self.cwd = cwd
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LocalProjectTests 2>&1`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/LocalProject.swift Tests/LocalProjectTests.swift
git commit -m "feat: add LocalProject model with URL generation"
```

---

### Task 3: ShellExecutor

**Files:**
- Create: `Sources/Core/Services/ShellExecutor.swift`
- Test: `Tests/ShellExecutorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ShellExecutorTests.swift`:

```swift
import Testing
@testable import LocalhostRunnerCore

@Suite("ShellExecutor")
struct ShellExecutorTests {
    let executor = ShellExecutor()

    @Test("executes simple command and returns output")
    func simpleCommand() async throws {
        let result = try await executor.run("/bin/echo", arguments: ["hello"])
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("throws on invalid command")
    func invalidCommand() async {
        do {
            _ = try await executor.run("/nonexistent/binary", arguments: [])
            Issue.record("Expected error for invalid command")
        } catch {
            #expect(error is ShellError)
        }
    }

    @Test("throws on timeout")
    func timeout() async {
        do {
            _ = try await executor.run("/bin/sleep", arguments: ["10"], timeout: 0.5)
            Issue.record("Expected timeout error")
        } catch let error as ShellError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected ShellError.timeout, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShellExecutorTests 2>&1`
Expected: FAIL — `ShellExecutor` not defined

- [ ] **Step 3: Write implementation using terminationHandler (non-blocking)**

Create `Sources/Core/Services/ShellExecutor.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ShellExecutorTests 2>&1`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Services/ShellExecutor.swift Tests/ShellExecutorTests.swift
git commit -m "feat: add ShellExecutor with non-blocking execution and timeout"
```

---

## Chunk 2: Port Scanner

### Task 4: PortScanner — lsof Output Parsing

**Files:**
- Create: `Sources/Core/Services/PortScanner.swift`
- Test: `Tests/PortScannerTests.swift`

- [ ] **Step 1: Write failing tests for lsof parsing**

Create `Tests/PortScannerTests.swift`:

```swift
import Testing
@testable import LocalhostRunnerCore

@Suite("PortScanner Parsing")
struct PortScannerParsingTests {
    @Test("parses standard lsof output into port-PID pairs")
    func parseLsofOutput() {
        let output = """
        COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345  user   22u  IPv4 0x1234   0t0  TCP *:3000 (LISTEN)
        python  67890  user   3u   IPv6 0x5678   0t0  TCP [::1]:8080 (LISTEN)
        """

        let results = PortScanner.parseLsofOutput(output, portRange: 3000...9000)

        #expect(results.count == 2)
        #expect(results[0].port == 3000)
        #expect(results[0].pid == 12345)
        #expect(results[0].processType == "node")
        #expect(results[1].port == 8080)
        #expect(results[1].pid == 67890)
        #expect(results[1].processType == "python")
    }

    @Test("deduplicates same port IPv4 and IPv6")
    func deduplicateSamePort() {
        let output = """
        COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345  user   22u  IPv4 0x1234   0t0  TCP *:3000 (LISTEN)
        node    12345  user   23u  IPv6 0x5678   0t0  TCP [::1]:3000 (LISTEN)
        """

        let results = PortScanner.parseLsofOutput(output, portRange: 3000...9000)
        #expect(results.count == 1)
        #expect(results[0].port == 3000)
    }

    @Test("filters ports outside range")
    func filterOutOfRange() {
        let output = """
        COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345  user   22u  IPv4 0x1234   0t0  TCP *:2999 (LISTEN)
        node    67890  user   23u  IPv4 0x5678   0t0  TCP *:3000 (LISTEN)
        node    11111  user   24u  IPv4 0x9abc   0t0  TCP *:9001 (LISTEN)
        """

        let results = PortScanner.parseLsofOutput(output, portRange: 3000...9000)
        #expect(results.count == 1)
        #expect(results[0].port == 3000)
    }

    @Test("skips malformed lines")
    func skipMalformed() {
        let output = """
        COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        this is garbage
        node    12345  user   22u  IPv4 0x1234   0t0  TCP *:3000 (LISTEN)
        """

        let results = PortScanner.parseLsofOutput(output, portRange: 3000...9000)
        #expect(results.count == 1)
    }

    @Test("handles multiple PIDs on same port — first PID wins")
    func multiplePidsSamePort() {
        let output = """
        COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    111  user   22u  IPv4 0x1234   0t0  TCP *:3000 (LISTEN)
        node    222  user   23u  IPv4 0x5678   0t0  TCP *:3000 (LISTEN)
        """

        let results = PortScanner.parseLsofOutput(output, portRange: 3000...9000)
        #expect(results.count == 1)
        #expect(results[0].pid == 111)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PortScannerParsingTests 2>&1`
Expected: FAIL — `PortScanner` not defined

- [ ] **Step 3: Write PortScanner with regex-based parsing**

Create `Sources/Core/Services/PortScanner.swift`:

```swift
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
            // Match lines containing (LISTEN)
            guard line.contains("(LISTEN)") else { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 9 else { continue }

            let command = String(columns[0])
            guard let pid = Int(columns[1]) else { continue }

            // Find the column containing ":PORT" before (LISTEN)
            // Patterns: *:3000, [::1]:3000, 127.0.0.1:3000
            let fullLine = String(line)
            guard let portMatch = fullLine.range(of: #":(\d+)\s+\(LISTEN\)"#, options: .regularExpression) else { continue }
            let matchedText = fullLine[portMatch]
            guard let colonRange = matchedText.range(of: #":(\d+)"#, options: .regularExpression) else { continue }

            let portString = matchedText[colonRange].dropFirst() // drop ":"
            guard let port = Int(portString) else { continue }

            guard portRange.contains(port) else { continue }
            guard !seen.contains(port) else { continue }

            seen.insert(port)
            results.append(PortPidEntry(port: port, pid: pid, processType: command.lowercased()))
        }

        return results
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PortScannerParsingTests 2>&1`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Services/PortScanner.swift Tests/PortScannerTests.swift
git commit -m "feat: add PortScanner with regex-based lsof output parsing"
```

---

### Task 5: PortScanner — CWD Resolution & Full Scan

**Files:**
- Modify: `Sources/Core/Services/PortScanner.swift`
- Modify: `Tests/PortScannerTests.swift`

- [ ] **Step 1: Write failing test for cwd parsing**

Add to `Tests/PortScannerTests.swift`:

```swift
@Suite("PortScanner CWD Resolution")
struct PortScannerCwdTests {
    @Test("parses cwd from lsof -d cwd output")
    func parseCwdOutput() {
        let output = """
        p12345
        fcwd
        n/Users/me/Github/lumaria-web
        """

        let cwd = PortScanner.parseCwdFromLsofOutput(output)
        #expect(cwd == "/Users/me/Github/lumaria-web")
    }

    @Test("returns nil for empty output")
    func emptyOutput() {
        let cwd = PortScanner.parseCwdFromLsofOutput("")
        #expect(cwd == nil)
    }

    @Test("filters system cwd paths")
    func filterSystemPaths() {
        #expect(PortScanner.isSystemPath("/usr/local/bin") == true)
        #expect(PortScanner.isSystemPath("/System/Library") == true)
        #expect(PortScanner.isSystemPath("/Users/me/Github/project") == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PortScannerCwdTests 2>&1`
Expected: FAIL — `parseCwdFromLsofOutput` not defined

- [ ] **Step 3: Add cwd parsing and full scan method**

Add to `PortScanner.swift` inside the actor:

```swift
    /// Parse cwd from `lsof -p PID -d cwd -Fn` output.
    /// The output has lines prefixed with field codes: p=PID, f=FD, n=name.
    public static func parseCwdFromLsofOutput(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            // Lines starting with "n/" contain the path (the "n" is the field code for "name")
            if line.hasPrefix("n/") {
                return String(line.dropFirst()) // drop the "n" prefix
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PortScannerCwdTests 2>&1`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Services/PortScanner.swift Tests/PortScannerTests.swift
git commit -m "feat: add cwd resolution, error handling, and full scan to PortScanner"
```

---

## Chunk 3: ViewModel & UI

### Task 6: ProjectListViewModel

**Files:**
- Create: `Sources/Core/ViewModels/ProjectListViewModel.swift`

- [ ] **Step 1: Create the ViewModel**

Create `Sources/Core/ViewModels/ProjectListViewModel.swift`:

```swift
import Foundation
import SwiftUI
import Combine

@MainActor
public class ProjectListViewModel: ObservableObject {
    @Published public var projects: [LocalProject] = []
    @Published public var isScanning = false
    @Published public var errorMessage: String?

    private var scanner: PortScanner
    private var timerCancellable: AnyCancellable?
    private var settingsObserver: NSObjectProtocol?

    public init(scanner: PortScanner = PortScanner()) {
        self.scanner = scanner
        setupSettingsObserver()
        updateTimer()
    }

    private func setupSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimer()
            }
        }
    }

    private func updateTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil

        let interval = UserDefaults.standard.double(forKey: "scanInterval")
        guard interval > 0 else { return }

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    public func refresh() async {
        isScanning = true
        errorMessage = nil

        // Read port range from settings, with validation
        var portMin = UserDefaults.standard.integer(forKey: "portRangeMin")
        var portMax = UserDefaults.standard.integer(forKey: "portRangeMax")
        if portMin == 0 { portMin = 3000 }
        if portMax == 0 { portMax = 9000 }
        portMin = Swift.max(1024, Swift.min(65535, portMin))
        portMax = Swift.max(1024, Swift.min(65535, portMax))
        if portMin > portMax { swap(&portMin, &portMax) }

        let range = portMin...portMax
        scanner = PortScanner(portRange: range)

        let result = await scanner.scan()
        switch result {
        case .success(let found):
            projects = found
            errorMessage = nil
        case .error(let message):
            projects = []
            errorMessage = message
        }

        isScanning = false
    }

    public func openInBrowser(_ project: LocalProject) {
        NSWorkspace.shared.open(project.url)
    }

    public var projectCount: Int { projects.count }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/ViewModels/ProjectListViewModel.swift
git commit -m "feat: add ProjectListViewModel with error handling and auto-refresh"
```

---

### Task 7: SwiftUI Views

**Files:**
- Create: `Sources/Core/Views/ProjectRowView.swift`
- Create: `Sources/Core/Views/EmptyStateView.swift`
- Create: `Sources/Core/Views/ProjectListView.swift`

- [ ] **Step 1: Create ProjectRowView**

Create `Sources/Core/Views/ProjectRowView.swift`:

```swift
import SwiftUI

public struct ProjectRowView: View {
    let project: LocalProject

    public init(project: LocalProject) {
        self.project = project
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
            Text("localhost:\(project.port) · \(project.processType)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Create EmptyStateView**

Create `Sources/Core/Views/EmptyStateView.swift`:

```swift
import SwiftUI

public struct EmptyStateView: View {
    let message: String

    public init(message: String = "No projects running") {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }
}
```

- [ ] **Step 3: Create ProjectListView**

Create `Sources/Core/Views/ProjectListView.swift`:

```swift
import SwiftUI

public struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectListViewModel

    public init(viewModel: ProjectListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Content area
            if let error = viewModel.errorMessage {
                EmptyStateView(message: error)
            } else if viewModel.projects.isEmpty && !viewModel.isScanning {
                EmptyStateView()
            } else if viewModel.isScanning && viewModel.projects.isEmpty {
                EmptyStateView(message: "Scanning...")
            } else {
                ForEach(viewModel.projects) { project in
                    ProjectRowView(project: project)
                        .onTapGesture {
                            viewModel.openInBrowser(project)
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }

                    if project.id != viewModel.projects.last?.id {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button(action: {
                    Task { await viewModel.refresh() }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning)

                Spacer()

                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }) {
                    Label("Settings", systemImage: "gear")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Views/
git commit -m "feat: add SwiftUI views with error state and settings button"
```

---

### Task 8: App Entry Point

**Files:**
- Create: `Sources/App/LocalhostRunnerApp.swift`

- [ ] **Step 1: Create the app entry point**

Create `Sources/App/LocalhostRunnerApp.swift`:

```swift
import SwiftUI
import ServiceManagement
import LocalhostRunnerCore

@main
struct LocalhostRunnerApp: App {
    @StateObject private var viewModel = ProjectListViewModel()

    init() {
        registerLoginItemIfFirstLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            ProjectListView(viewModel: viewModel)
        } label: {
            Text("\(viewModel.projectCount)")
                .foregroundColor(viewModel.projectCount > 0 ? .primary : .secondary)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private func registerLoginItemIfFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        guard !hasLaunched else { return }

        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        UserDefaults.standard.set(true, forKey: "autostart")

        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to register login item: \(error)")
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/App/LocalhostRunnerApp.swift
git commit -m "feat: add app entry point with MenuBarExtra and login item"
```

---

## Chunk 4: Settings & Final Integration

### Task 9: Settings View

**Files:**
- Create: `Sources/Core/Views/SettingsView.swift`

- [ ] **Step 1: Create SettingsView with validation**

Create `Sources/Core/Views/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    @AppStorage("scanInterval") private var scanInterval: Double = 0
    @AppStorage("portRangeMin") private var portRangeMin: Int = 3000
    @AppStorage("portRangeMax") private var portRangeMax: Int = 9000
    @AppStorage("autostart") private var autostart: Bool = true

    public init() {}

    public var body: some View {
        Form {
            Section("Scanning") {
                Picker("Scan Interval", selection: $scanInterval) {
                    Text("Manual").tag(0.0)
                    Text("5 seconds").tag(5.0)
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                }

                HStack {
                    Text("Port Range")
                    TextField("Min", value: $portRangeMin, format: .number)
                        .frame(width: 80)
                        .onChange(of: portRangeMin) { _, newValue in
                            portRangeMin = max(1024, min(65535, newValue))
                        }
                    Text("–")
                    TextField("Max", value: $portRangeMax, format: .number)
                        .frame(width: 80)
                        .onChange(of: portRangeMax) { _, newValue in
                            portRangeMax = max(1024, min(65535, newValue))
                        }
                }
            }

            Section("General") {
                Toggle("Start at Login", isOn: $autostart)
                    .onChange(of: autostart) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update login item: \(error)")
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 250)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Views/SettingsView.swift
git commit -m "feat: add settings view with port range validation and login item toggle"
```

---

### Task 10: Run All Tests & Build App Bundle

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1`
Expected: All tests PASS

- [ ] **Step 2: Build .app bundle**

Run: `./scripts/build-app.sh 2>&1`
Expected: "Built: .build/release/Localhost Runner.app"

- [ ] **Step 3: Manual smoke test**

```bash
open ".build/release/Localhost Runner.app" &
```

Verify:
1. Number appears in menu bar (greyed out "0" if no servers running)
2. Start a dev server: `python3 -m http.server 3000 &`
3. Click refresh → project appears in list with name, port, runtime
4. Click the project → opens `http://localhost:3000` in browser
5. Open Settings → change port range, scan interval
6. Quit from menu

Kill test server: `kill %1`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: verify full test suite and app bundle"
```
