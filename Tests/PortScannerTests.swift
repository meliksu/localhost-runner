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

    @Test("filters out known system processes like ControlCenter and Antivirus")
    func filterSystemProcesses() {
        let output = """
        COMMAND     PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        ControlCe   637  user    8u  IPv4 0x1234   0t0  TCP *:7000 (LISTEN)
        Antivirus   848  user   10u  IPv4 0x5678   0t0  TCP 127.0.0.1:8890 (LISTEN)
        node      12345  user   20u  IPv6 0x9abc   0t0  TCP [::1]:5173 (LISTEN)
        node      67890  user   13u  IPv6 0xdef0   0t0  TCP *:3000 (LISTEN)
        """

        let results = PortScanner.parseLsofOutput(output, portRange: 3000...9000)
        #expect(results.count == 2)
        #expect(results[0].port == 5173)
        #expect(results[1].port == 3000)
    }

    @Test("isSystemProcess recognizes known processes")
    func systemProcessCheck() {
        #expect(PortScanner.isSystemProcess("ControlCe") == true)
        #expect(PortScanner.isSystemProcess("Antivirus") == true)
        #expect(PortScanner.isSystemProcess("rapportd") == true)
        #expect(PortScanner.isSystemProcess("node") == false)
        #expect(PortScanner.isSystemProcess("python") == false)
    }
}

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

@Suite("PortScanner HTML Title")
struct PortScannerTitleTests {
    @Test("extracts title from HTML")
    func extractTitle() {
        let html = "<html><head><title>My Cool App</title></head><body></body></html>"
        #expect(PortScanner.parseTitleFromHTML(html) == "My Cool App")
    }

    @Test("handles uppercase TITLE tag")
    func uppercaseTitle() {
        let html = "<html><head><TITLE>Dashboard</TITLE></head></html>"
        #expect(PortScanner.parseTitleFromHTML(html) == "Dashboard")
    }

    @Test("returns nil when no title tag")
    func noTitle() {
        let html = "<html><head></head><body>Hello</body></html>"
        #expect(PortScanner.parseTitleFromHTML(html) == nil)
    }

    @Test("returns nil for empty title")
    func emptyTitle() {
        let html = "<html><head><title></title></head></html>"
        #expect(PortScanner.parseTitleFromHTML(html) == nil)
    }

    @Test("trims whitespace from title")
    func trimWhitespace() {
        let html = "<title>  Lumaria Web  </title>"
        #expect(PortScanner.parseTitleFromHTML(html) == "Lumaria Web")
    }
}
