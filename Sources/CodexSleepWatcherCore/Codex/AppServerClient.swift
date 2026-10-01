import Foundation
import Darwin

public actor AppServerClient {
    private let executableURL: URL?
    private let responseTimeout: TimeInterval
    private let processLaunchHandler: (@Sendable (Int32) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var errorOutputEnded = false
    private var errorBuffer = Data()
    private var nextID = 0
    private var responseBuffer = JSONLineBuffer()

    public init(
        executableURL: URL? = nil,
        responseTimeout: TimeInterval = 10,
        processLaunchHandler: (@Sendable (Int32) -> Void)? = nil
    ) {
        self.executableURL = executableURL
        self.responseTimeout = responseTimeout
        self.processLaunchHandler = processLaunchHandler
    }

    public func start() throws {
        if process?.isRunning == true, input != nil, output != nil { return }
        guard let executableURL = executableURL ?? CodexExecutableLocator.locate() else {
            throw AppServerClientError.codexExecutableNotFound
        }
        stop()

        let launchedProcess = Process()
        launchedProcess.executableURL = executableURL
        // Stdio is the default transport in both legacy and current app-server versions.
        launchedProcess.arguments = ["app-server"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        launchedProcess.standardInput = stdin; launchedProcess.standardOutput = stdout
        launchedProcess.standardError = stderr

        do {
            try launchedProcess.run()
            processLaunchHandler?(launchedProcess.processIdentifier)
            process = launchedProcess
            input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading
            errorOutput = stderr.fileHandleForReading
            try send(["method":"initialize", "id":0, "params":["clientInfo":["name":"codex_sleep_watcher", "title":"Codex Sleep Watcher", "version":"0.1.3"]]])
            _ = try readResponse(id: 0)
            try send(["method":"initialized", "params":[:]])
            nextID = 1
        } catch {
            let failure = diagnosticError(for: error)
            stop()
            throw failure
        }
    }

    public func listThreads() throws -> ThreadListResponse {
        do {
            try start()
            let id = nextID; nextID += 1
            try send(["method":"thread/list", "id":id, "params":["archived":false, "limit":100, "sortKey":"updated_at", "sortDirection":"desc", "useStateDbOnly":true]])
            let result = try readResponse(id: id)
            return try JSONDecoder().decode(ThreadListResponse.self, from: JSONSerialization.data(withJSONObject: result))
        } catch {
            let failure = diagnosticError(for: error)
            stop()
            throw failure
        }
    }

    public func stop() {
        try? input?.close()
        try? output?.close()
        try? errorOutput?.close()
        if let process, process.isRunning {
            process.terminate()
            waitForExit(process, timeout: 0.25)
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                waitForExit(process, timeout: 0.25)
            }
        }
        process = nil
        input = nil
        output = nil
        errorOutput = nil
        errorOutputEnded = false
        errorBuffer = Data()
        nextID = 0
        responseBuffer = JSONLineBuffer()
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw AppServerClientError.serverClosed }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func readResponse(id: Int) throws -> Any {
        let deadline = Date().addingTimeInterval(responseTimeout)
        while true {
            while let line = responseBuffer.nextLine() {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["id"] as? Int == id, let result = object["result"] { return result }
                if object["id"] as? Int == id, let error = object["error"] as? [String: Any] {
                    throw AppServerClientError.serverError(error["message"] as? String ?? "unknown error")
                }
            }
            responseBuffer.append(try readAvailableData(until: deadline))
        }
    }

    private func readAvailableData(until deadline: Date) throws -> Data {
        guard let output else { throw AppServerClientError.serverClosed }
        while true {
            try Task.checkCancellation()
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw AppServerClientError.timedOut }
            let milliseconds = Int32(max(1, ceil(min(remaining, 0.1) * 1_000)))
            var descriptors = [pollfd(fd: output.fileDescriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)]
            if let errorOutput, !errorOutputEnded {
                descriptors.append(pollfd(fd: errorOutput.fileDescriptor, events: Int16(POLLIN), revents: 0))
            }
            let result = Darwin.poll(&descriptors, nfds_t(descriptors.count), milliseconds)
            if result > 0 {
                if descriptors.count > 1, descriptors[1].revents & Int16(POLLIN) != 0 {
                    let data = errorOutput?.availableData ?? Data()
                    appendDiagnostic(data)
                    if data.isEmpty { errorOutputEnded = true }
                }
                if descriptors.count > 1, descriptors[1].revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                    errorOutputEnded = true
                }
                if descriptors[0].revents != 0 {
                    let data = output.availableData
                    guard !data.isEmpty else { throw AppServerClientError.serverClosed }
                    return data
                }
                continue
            }
            if result == 0 { continue }
            if errno != EINTR { throw AppServerClientError.serverClosed }
        }
    }

    private func appendDiagnostic(_ data: Data) {
        errorBuffer.append(data)
        if errorBuffer.count > 8_192 { errorBuffer = Data(errorBuffer.suffix(8_192)) }
    }

    private func diagnosticError(for error: any Error) -> any Error {
        guard error as? AppServerClientError == .serverClosed else { return error }
        if let errorOutput {
            var descriptor = pollfd(fd: errorOutput.fileDescriptor, events: Int16(POLLIN), revents: 0)
            if Darwin.poll(&descriptor, 1, 0) > 0, descriptor.revents & Int16(POLLIN) != 0 {
                appendDiagnostic(errorOutput.availableData)
            }
        }
        let diagnostic = String(decoding: errorBuffer.suffix(2_048), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCode = process.flatMap { $0.isRunning ? nil : $0.terminationStatus }
        return AppServerClientError.serverExited(exitCode: exitCode, diagnostic: diagnostic)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { usleep(10_000) }
    }
}

public enum AppServerClientError: LocalizedError, Equatable {
    case codexExecutableNotFound
    case serverClosed
    case serverExited(exitCode: Int32?, diagnostic: String)
    case timedOut
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            "找不到 Codex CLI。请将 ChatGPT 或 Codex 桌面端安装到 /Applications，然后点击刷新重试。"
        case .serverClosed:
            "Codex App Server 连接已关闭。"
        case .serverExited(let exitCode, let diagnostic):
            "Codex App Server 已退出" + (exitCode.map { "（退出码 \($0)）" } ?? "")
                + (diagnostic.isEmpty ? "，请检查桌面端安装并点击刷新重试。" : "：\(diagnostic)")
        case .timedOut:
            "Codex App Server 响应超时，请点击刷新重试。"
        case .serverError(let message):
            "Codex App Server 错误：\(message)"
        }
    }
}
