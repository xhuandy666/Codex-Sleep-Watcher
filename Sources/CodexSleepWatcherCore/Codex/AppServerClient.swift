import Foundation

public actor AppServerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextID = 0

    public init() {}

    public func start() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--stdio"]
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
        while let data = try output?.read(upToCount: 1_048_576), !data.isEmpty {
            for line in data.split(separator: 0x0A) {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["id"] as? Int == id, let result = object["result"] { return result }
            }
        }
        throw CocoaError(.fileReadUnknown)
    }
}
