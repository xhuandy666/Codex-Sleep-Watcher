import Foundation

public actor AppServerClient {
    private let executableURL: URL?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextID = 0
    private var responseBuffer = JSONLineBuffer()

    public init(executableURL: URL? = CodexExecutableLocator.locate()) {
        self.executableURL = executableURL
    }

    public func start() throws {
        guard let executableURL else { throw AppServerClientError.codexExecutableNotFound }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        try send(["method":"initialize", "id":0, "params":["clientInfo":["name":"codex_sleep_watcher", "title":"Codex Sleep Watcher", "version":"0.1.0"]]])
        _ = try readResponse(id: 0)
        try send(["method":"initialized", "params":[:]])
        nextID = 1
    }

    public func listThreads() throws -> ThreadListResponse {
        let id = nextID; nextID += 1
        try send(["method":"thread/list", "id":id, "params":["archived":false, "limit":100, "sortKey":"updated_at", "sortDirection":"desc", "useStateDbOnly":true]])
        let result = try readResponse(id: id)
        return try JSONDecoder().decode(ThreadListResponse.self, from: JSONSerialization.data(withJSONObject: result))
    }

    public func stop() { process?.terminate(); process = nil }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(0x0A); try input?.write(contentsOf: data)
    }

    private func readResponse(id: Int) throws -> Any {
        while true {
            while let line = responseBuffer.nextLine() {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["id"] as? Int == id, let result = object["result"] { return result }
                if object["id"] as? Int == id, let error = object["error"] as? [String: Any] {
                    throw AppServerClientError.serverError(error["message"] as? String ?? "unknown error")
                }
            }
            guard let data = try output?.read(upToCount: 65_536), !data.isEmpty else { break }
            responseBuffer.append(data)
        }
        throw AppServerClientError.serverClosed
    }
}

public enum AppServerClientError: LocalizedError, Equatable {
    case codexExecutableNotFound
    case serverClosed
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            "找不到 Codex。请安装或更新 Codex Desktop App，然后重新启动本工具。"
        case .serverClosed:
            "Codex App Server 在初始化完成前退出。"
        case .serverError(let message):
            "Codex App Server 错误：\(message)"
        }
    }
}
