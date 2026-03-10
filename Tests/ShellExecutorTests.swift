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
