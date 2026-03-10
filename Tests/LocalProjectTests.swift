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
