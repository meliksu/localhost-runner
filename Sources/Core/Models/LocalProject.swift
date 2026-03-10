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
