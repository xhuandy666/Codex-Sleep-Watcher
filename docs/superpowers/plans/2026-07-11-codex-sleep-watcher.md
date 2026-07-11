# Codex Sleep Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local macOS menu-bar app that lists concurrent Codex sessions, lets the user select one stable `session_id`, keeps the Mac awake while that target runs, and sleeps only when that target reaches a configured stop condition.

**Architecture:** A SwiftPM library owns the state machine, Codex App Server JSON-RPC client, hook event transport, session registry, countdown, and power abstractions. Two thin executables depend on it: a SwiftUI `MenuBarExtra` app and a no-output hook forwarder. Codex `thread/list` supplies session metadata and runtime status; global Codex Hooks supply authoritative events keyed by `session_id`.

**Tech Stack:** Swift 6.0 package mode, macOS 13+, SwiftUI, Foundation, Darwin Unix datagram sockets, IOKit, UserNotifications, ServiceManagement, XCTest, shell packaging with `swift build` and `codesign`.

## Global Constraints

- Project path: `/Users/xhuandy/Documents/Codex/projects/codex-sleep-watcher`.
- Minimum deployment target: macOS 13.0.
- Build and test with Swift Package Manager; full Xcode is not installed on the development machine.
- Do not add third-party runtime dependencies.
- Do not read or persist prompts, assistant messages, transcript contents, or unstable transcript paths.
- Use `session_id` as the sleep-target identity; names, paths, titles, and list positions are display-only.
- Automated tests must never invoke a real system sleep or leave a real power assertion active.
- Hook installation must preserve unrelated user hooks and remove only entries owned by `Codex Sleep Watcher`.
- Any ambiguity in hook delivery, target identity, App Server status, or power assertion creation must fail safe by cancelling monitoring without sleeping.
- Package a local ad-hoc-signed `.app`; App Store distribution is out of scope.

---

## Planned File Structure

```text
Package.swift
README.md
Resources/Info.plist
Scripts/package_app.sh
Sources/
  CodexSleepWatcherCore/
    Domain/Models.swift
    Domain/WatchStateMachine.swift
    Codex/AppServerClient.swift
    Codex/AppServerModels.swift
    Codex/SessionDiscoveryService.swift
    Hooks/HookEvent.swift
    Hooks/HookEventReceiver.swift
    Hooks/HookInstaller.swift
    Hooks/UnixDatagramSocket.swift
    Sessions/SessionRegistry.swift
    Services/SleepCountdownController.swift
    Services/SettingsStore.swift
    Power/PowerAssertionController.swift
    Power/SystemSleeper.swift
  CodexSleepWatcherApp/
    CodexSleepWatcherApp.swift
    AppController.swift
    MenuBarView.swift
    NotificationController.swift
  CodexSleepHook/
    main.swift
Tests/
  CodexSleepWatcherCoreTests/
    WatchStateMachineTests.swift
    AppServerClientTests.swift
    HookTransportTests.swift
    HookInstallerTests.swift
    SessionRegistryTests.swift
    PowerControllerTests.swift
```

`CodexSleepWatcherCore` contains no SwiftUI views. The app executable owns presentation and notification authorization. The hook executable imports only event encoding and Unix-socket sending from the core library and must produce no stdout or stderr during successful operation.

---

### Task 1: SwiftPM Scaffold and Target-Aware State Machine

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexSleepWatcherCore/Domain/Models.swift`
- Create: `Sources/CodexSleepWatcherCore/Domain/WatchStateMachine.swift`
- Create: `Sources/CodexSleepWatcherApp/CodexSleepWatcherApp.swift`
- Create: `Sources/CodexSleepHook/main.swift`
- Create: `Tests/CodexSleepWatcherCoreTests/WatchStateMachineTests.swift`

**Interfaces:**
- Produces: `SessionID`, `TurnID`, `SessionStatus`, `SessionSummary`, `WatchPhase`, `WatchEvent`, and `WatchStateMachine.reduce(_:)`.
- Later tasks must express all target changes through `WatchEvent`; UI and Codex integrations may not mutate `WatchPhase` directly.

- [ ] **Step 1: Create the package manifest and minimal executable entries**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSleepWatcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexSleepWatcherCore", targets: ["CodexSleepWatcherCore"]),
        .executable(name: "CodexSleepWatcherApp", targets: ["CodexSleepWatcherApp"]),
        .executable(name: "codex-sleep-hook", targets: ["CodexSleepHook"]),
    ],
    targets: [
        .target(name: "CodexSleepWatcherCore"),
        .executableTarget(name: "CodexSleepWatcherApp", dependencies: ["CodexSleepWatcherCore"]),
        .executableTarget(name: "CodexSleepHook", dependencies: ["CodexSleepWatcherCore"]),
        .testTarget(name: "CodexSleepWatcherCoreTests", dependencies: ["CodexSleepWatcherCore"]),
    ]
)
```

The initial app entry is:

```swift
import SwiftUI

@main
struct CodexSleepWatcherApp: App {
    var body: some Scene {
        MenuBarExtra("Codex Sleep Watcher", systemImage: "moon.zzz") {
            Text("Initializing")
        }
    }
}
```

The initial hook entry imports `Foundation` and exits without output:

```swift
import Foundation
import CodexSleepWatcherCore
```

- [ ] **Step 2: Write failing state-machine tests**

```swift
import XCTest
@testable import CodexSleepWatcherCore

final class WatchStateMachineTests: XCTestCase {
    let target = SessionID("019f-target")
    let other = SessionID("019f-other")

    func testOnlyTargetStopStartsCountdown() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: other, status: .idle))
        XCTAssertEqual(machine.phase, .monitoring(target))

        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        XCTAssertEqual(machine.phase, .countdown(target, secondsRemaining: 30))
    }

    func testTargetRestartCancelsCountdown() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try machine.reduce(.sessionEvent(sessionID: target, status: .running(turnID: TurnID("turn-2"))))
        XCTAssertEqual(machine.phase, .monitoring(target))
    }

    func testWaitForOthersDefersCountdown() throws {
        var machine = WatchStateMachine(settings: .init(delaySeconds: 30, waitForOtherSessions: true))
        try machine.reduce(.knownRunningSessions([target, other]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        XCTAssertEqual(machine.phase, .waitingForOtherSessions(target))

        try machine.reduce(.sessionEvent(sessionID: other, status: .idle))
        XCTAssertEqual(machine.phase, .countdown(target, secondsRemaining: 30))
    }

    func testAmbiguousTargetFailsSafe() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.fatalObservationError("event stream disconnected"))
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.lastError, "event stream disconnected")
    }
}
```

- [ ] **Step 3: Run tests and confirm the missing-domain failure**

Run: `swift test --filter WatchStateMachineTests`

Expected: compilation fails because `SessionID`, `WatchStateMachine`, and related types are undefined.

- [ ] **Step 4: Implement the domain types and pure reducer**

`Models.swift` defines value types and statuses:

```swift
import Foundation

public struct SessionID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    public var short: String { String(rawValue.prefix(8)) }
}

public struct TurnID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum SessionStatus: Equatable, Sendable {
    case running(turnID: TurnID?)
    case waitingOnApproval
    case waitingOnUserInput
    case idle
    case unavailable
}

public struct SessionSummary: Identifiable, Equatable, Sendable {
    public var id: SessionID
    public var threadID: String
    public var name: String
    public var cwd: String
    public var updatedAt: Date
    public var status: SessionStatus
}

public struct WatchSettings: Equatable, Sendable {
    public var delaySeconds: Int = 30
    public var waitForOtherSessions: Bool = false
    public init(delaySeconds: Int = 30, waitForOtherSessions: Bool = false) {
        self.delaySeconds = delaySeconds
        self.waitForOtherSessions = waitForOtherSessions
    }
}

public enum WatchPhase: Equatable, Sendable {
    case setupRequired(String)
    case idle
    case monitoring(SessionID)
    case waitingForOtherSessions(SessionID)
    case countdown(SessionID, secondsRemaining: Int)
    case sleeping(SessionID)
}

public enum WatchEvent: Equatable, Sendable {
    case setupFailed(String)
    case setupReady
    case knownRunningSessions(Set<SessionID>)
    case selectTarget(SessionID)
    case sessionEvent(sessionID: SessionID, status: SessionStatus)
    case countdownTick
    case cancel
    case fatalObservationError(String)
}
```

`WatchStateMachine.swift` implements a synchronous value reducer. Maintain `runningSessions`, clear the target on cancel/error/sleep, ignore non-target stop events unless waiting for all sessions, and change `countdown` back to `monitoring` when the same target runs again.

- [ ] **Step 5: Run the focused and full tests**

Run: `swift test --filter WatchStateMachineTests`

Expected: 4 tests pass.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 6: Commit the scaffold and state machine**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add target-aware watch state machine"
```

---

### Task 2: Codex App Server Client and Session Discovery

**Files:**
- Create: `Sources/CodexSleepWatcherCore/Codex/AppServerModels.swift`
- Create: `Sources/CodexSleepWatcherCore/Codex/AppServerClient.swift`
- Create: `Sources/CodexSleepWatcherCore/Codex/SessionDiscoveryService.swift`
- Create: `Tests/CodexSleepWatcherCoreTests/AppServerClientTests.swift`

**Interfaces:**
- Produces: `AppServerTransport`, `AppServerClient.start()`, `AppServerClient.listThreads()`, and `SessionDiscoveryService.runningSessions()`.
- Consumes: `SessionID`, `SessionStatus`, and `SessionSummary` from Task 1.

- [ ] **Step 1: Write decoding and JSON-RPC framing tests**

Use a fake line transport so tests never start a real Codex process:

```swift
actor FakeAppServerTransport: AppServerTransport {
    var sent: [Data] = []
    var incoming: [Data]
    init(lines: [String]) { incoming = lines.map { Data(($0 + "\n").utf8) } }
    func start() async throws {}
    func send(_ data: Data) async throws { sent.append(data) }
    func nextLine() async throws -> Data? { incoming.isEmpty ? nil : incoming.removeFirst() }
    func stop() async {}
}

final class AppServerClientTests: XCTestCase {
    func testListsOnlyActiveThreadsAndUsesSessionID() async throws {
        let initialize = #"{"id":0,"result":{"userAgent":"codex","platformFamily":"unix","platformOs":"macos"}}"#
        let list = #"{"id":1,"result":{"data":[{"id":"thread-a","sessionId":"session-a","name":"Build app","preview":"ignored","cwd":"/repo/a","createdAt":1,"updatedAt":2,"status":{"type":"active","activeFlags":[]},"source":"appServer","modelProvider":"openai","cliVersion":"1","ephemeral":false,"turns":[]},{"id":"thread-b","sessionId":"session-b","name":"Idle","preview":"ignored","cwd":"/repo/b","createdAt":1,"updatedAt":2,"status":{"type":"idle"},"source":"appServer","modelProvider":"openai","cliVersion":"1","ephemeral":false,"turns":[]}],"nextCursor":null,"backwardsCursor":null}}"#
        let transport = FakeAppServerTransport(lines: [initialize, list])
        let client = AppServerClient(transport: transport)

        try await client.start()
        let sessions = try await SessionDiscoveryService(client: client).runningSessions()

        XCTAssertEqual(sessions.map(\.id), [SessionID("session-a")])
        XCTAssertEqual(sessions.first?.threadID, "thread-a")
        XCTAssertEqual(sessions.first?.name, "Build app")
    }
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `swift test --filter AppServerClientTests`

Expected: compilation fails because the App Server interfaces do not exist.

- [ ] **Step 3: Implement exact App Server wire models**

Define `ThreadListResponse`, `ThreadRecord`, and a custom `ThreadRuntimeStatus` decoder for these stable shapes:

```swift
enum ThreadRuntimeStatus: Equatable, Decodable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active(flags: [String])

    private enum CodingKeys: String, CodingKey { case type, activeFlags }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "notLoaded": self = .notLoaded
        case "idle": self = .idle
        case "systemError": self = .systemError
        case "active": self = .active(flags: try values.decode([String].self, forKey: .activeFlags))
        default: self = .systemError
        }
    }
}
```

Never decode or store `preview`. Give it no property in `ThreadRecord`; `Decodable` ignores the field.

- [ ] **Step 4: Implement JSONL process transport and request routing**

`ProcessAppServerTransport` launches `/usr/bin/env codex app-server --stdio`, reads newline-delimited JSON, and terminates the child on `stop()`.

`AppServerClient.start()` sends exactly:

```json
{"method":"initialize","id":0,"params":{"clientInfo":{"name":"codex_sleep_watcher","title":"Codex Sleep Watcher","version":"0.1.0"}}}
{"method":"initialized","params":{}}
```

`listThreads()` sends:

```json
{"method":"thread/list","id":1,"params":{"archived":false,"limit":100,"sortKey":"updated_at","sortDirection":"desc","useStateDbOnly":true}}
```

Use an actor to serialize request IDs and response continuations. Ignore unrelated notifications. If the process exits, malformed JSON arrives, or an RPC error is returned, throw a typed `AppServerError` and let the caller fail safe.

- [ ] **Step 5: Implement discovery mapping and active flags**

Map `active` threads to `SessionSummary`; map `waitingOnApproval` and `waitingOnUserInput` flags to the corresponding `SessionStatus`, otherwise map active to `.running(turnID: nil)`. Exclude `idle`, `notLoaded`, and `systemError` records from the selectable list.

- [ ] **Step 6: Run tests**

Run: `swift test --filter AppServerClientTests`

Expected: App Server tests pass.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 7: Commit App Server discovery**

```bash
git add Sources/CodexSleepWatcherCore/Codex Tests/CodexSleepWatcherCoreTests/AppServerClientTests.swift
git commit -m "feat: discover active Codex sessions"
```

---

### Task 3: Hook Event Protocol and Unix Socket Transport

**Files:**
- Create: `Sources/CodexSleepWatcherCore/Hooks/HookEvent.swift`
- Create: `Sources/CodexSleepWatcherCore/Hooks/UnixDatagramSocket.swift`
- Create: `Sources/CodexSleepWatcherCore/Hooks/HookEventReceiver.swift`
- Modify: `Sources/CodexSleepHook/main.swift`
- Create: `Tests/CodexSleepWatcherCoreTests/HookTransportTests.swift`

**Interfaces:**
- Produces: `HookEvent`, `HookEventReceiver.events`, and a `codex-sleep-hook` executable that forwards stdin without output.
- Socket path: `~/Library/Application Support/CodexSleepWatcher/events.sock`.

- [ ] **Step 1: Write event privacy, deduplication, and transport tests**

```swift
final class HookTransportTests: XCTestCase {
    func testHookInputDropsSensitiveFields() throws {
        let input = Data(#"{"session_id":"s1","turn_id":"t1","cwd":"/repo","hook_event_name":"Stop","prompt":"secret","last_assistant_message":"secret","transcript_path":"/secret"}"#.utf8)
        let event = try HookEvent.fromHookInput(input, receivedAt: Date(timeIntervalSince1970: 10))
        let encoded = try JSONEncoder().encode(event)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertEqual(event.sessionID, SessionID("s1"))
        XCTAssertEqual(event.turnID, TurnID("t1"))
        XCTAssertEqual(event.kind, .stop)
    }

    func testDuplicateEventIsDeliveredOnce() async throws {
        let path = NSTemporaryDirectory() + "/codex-sleep-watcher-\(UUID().uuidString).sock"
        let receiver = HookEventReceiver(socketPath: path)
        try await receiver.start()
        defer { Task { await receiver.stop() } }

        let event = HookEvent(kind: .stop, sessionID: SessionID("s1"), turnID: TurnID("t1"), cwd: "/repo", receivedAt: .now)
        try UnixDatagramSocket.send(try JSONEncoder().encode(event), to: path)
        try UnixDatagramSocket.send(try JSONEncoder().encode(event), to: path)

        let received = try await receiver.collect(count: 1, timeout: .seconds(1))
        XCTAssertEqual(received, [event])
    }
}
```

- [ ] **Step 2: Run tests and verify missing-type failure**

Run: `swift test --filter HookTransportTests`

Expected: compilation fails because hook transport types do not exist.

- [ ] **Step 3: Implement the minimal privacy-preserving event model**

```swift
public enum HookEventKind: String, Codable, Sendable { case sessionStart, userPromptSubmit, permissionRequest, stop }

public struct HookEvent: Codable, Equatable, Sendable {
    public var kind: HookEventKind
    public var sessionID: SessionID
    public var turnID: TurnID?
    public var cwd: String
    public var receivedAt: Date

    public var deduplicationKey: String {
        "\(sessionID.rawValue)|\(turnID?.rawValue ?? "-")|\(kind.rawValue)"
    }
}
```

Decode hook stdin through a private `RawHookInput` that contains only `session_id`, `turn_id`, `cwd`, and `hook_event_name`; JSONDecoder ignores all other fields.

- [ ] **Step 4: Implement a user-only Unix datagram socket**

Use Darwin `socket(AF_UNIX, SOCK_DGRAM, 0)`, `bind`, `recv`, and `sendto`. Reject socket paths whose UTF-8 length does not fit `sockaddr_un.sun_path`. After bind, call `chmod(path, S_IRUSR | S_IWUSR)`. `HookEventReceiver` owns the socket file, unlinks it only on start/stop, and publishes decoded events through `AsyncStream<HookEvent>`.

Keep the socket implementation in one file so unsafe pointer handling is reviewable in isolation.

- [ ] **Step 5: Implement the hook executable**

`main.swift` reads stdin to EOF, decodes only allowed fields, encodes `HookEvent`, and calls `UnixDatagramSocket.send`. If the app is not running or forwarding fails, exit `0` without stdout/stderr so Codex is never blocked.

```swift
import Foundation
import CodexSleepWatcherCore

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = try? HookEvent.fromHookInput(input, receivedAt: .now) else { exit(0) }
let socketPath = HookEventReceiver.defaultSocketPath
if let payload = try? JSONEncoder().encode(event) {
    try? UnixDatagramSocket.send(payload, to: socketPath)
}
exit(0)
```

- [ ] **Step 6: Run transport tests and verify hook silence**

Run: `swift test --filter HookTransportTests`

Expected: hook tests pass.

Run:

```bash
printf '%s' '{"session_id":"s1","turn_id":"t1","cwd":"/repo","hook_event_name":"Stop"}' | swift run codex-sleep-hook >/tmp/codex-sleep-hook.stdout 2>/tmp/codex-sleep-hook.stderr
test ! -s /tmp/codex-sleep-hook.stdout
test ! -s /tmp/codex-sleep-hook.stderr
```

Expected: both `test` commands exit `0`.

- [ ] **Step 7: Commit the hook transport**

```bash
git add Sources/CodexSleepWatcherCore/Hooks Sources/CodexSleepHook Tests/CodexSleepWatcherCoreTests/HookTransportTests.swift
git commit -m "feat: forward Codex lifecycle events"
```

---

### Task 4: Safe Global Hook Installation

**Files:**
- Create: `Sources/CodexSleepWatcherCore/Hooks/HookInstaller.swift`
- Create: `Tests/CodexSleepWatcherCoreTests/HookInstallerTests.swift`

**Interfaces:**
- Produces: `HookInstaller.inspect()`, `install(helperPath:)`, and `uninstall(helperPath:)`.
- Consumes: the packaged helper path `Contents/Helpers/codex-sleep-hook`.

- [ ] **Step 1: Write merge and uninstall tests using temporary homes**

```swift
final class HookInstallerTests: XCTestCase {
    func testInstallPreservesExistingHooksAndIsIdempotent() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let codex = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let file = codex.appendingPathComponent("hooks.json")
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/existing","statusMessage":"Existing"}]}]}}"#.utf8).write(to: file)
        let installer = HookInstaller(hooksFile: file)

        try installer.install(helperPath: "/Applications/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook")
        try installer.install(helperPath: "/Applications/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook")

        let document = try installer.readDocument()
        XCTAssertEqual(document.handlers(event: "Stop", owner: HookInstaller.owner).count, 1)
        XCTAssertEqual(document.handlers(event: "Stop", command: "/existing").count, 1)
    }

    func testUninstallRemovesOnlyOwnedHandlers() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let codex = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let file = codex.appendingPathComponent("hooks.json")
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/existing","statusMessage":"Existing"}]}]}}"#.utf8).write(to: file)
        let installer = HookInstaller(hooksFile: file)
        let helper = "/Applications/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook"

        try installer.install(helperPath: helper)
        try installer.uninstall(helperPath: helper)

        let document = try installer.readDocument()
        XCTAssertTrue(document.handlers(event: "Stop", owner: HookInstaller.owner).isEmpty)
        XCTAssertEqual(document.handlers(event: "Stop", command: "/existing").count, 1)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter HookInstallerTests`

Expected: compilation fails because `HookInstaller` is undefined.

- [ ] **Step 3: Implement a JSON-preserving owned-entry merger**

Represent the document as `[String: Any]` using `JSONSerialization` so unknown user fields survive round trips. The owner marker is exactly `Codex Sleep Watcher` in `statusMessage`. Register one matcher group for each of `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, and `Stop` with this handler:

```json
{
  "type": "command",
  "command": "'/absolute/path/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook'",
  "timeout": 5,
  "statusMessage": "Codex Sleep Watcher"
}
```

Quote apostrophes in the absolute path with POSIX single-quote escaping. Write to a sibling temporary file, set mode `0600`, then atomically replace `hooks.json`. Before first modification, create `hooks.json.codex-sleep-watcher.backup` only if no backup exists.

`inspect()` returns `.missing`, `.installedAndCurrent`, `.installedAtDifferentHelperPath`, or `.invalidJSON`. Invalid JSON is never overwritten.

- [ ] **Step 4: Complete the uninstall test and run all installer tests**

Run: `swift test --filter HookInstallerTests`

Expected: merge, idempotency, invalid JSON, and owned-only uninstall tests pass.

- [ ] **Step 5: Commit the installer**

```bash
git add Sources/CodexSleepWatcherCore/Hooks/HookInstaller.swift Tests/CodexSleepWatcherCoreTests/HookInstallerTests.swift
git commit -m "feat: install lifecycle hooks safely"
```

---

### Task 5: Session Registry, Event Reconciliation, and Countdown

**Files:**
- Create: `Sources/CodexSleepWatcherCore/Sessions/SessionRegistry.swift`
- Create: `Sources/CodexSleepWatcherCore/Services/SleepCountdownController.swift`
- Create: `Tests/CodexSleepWatcherCoreTests/SessionRegistryTests.swift`

**Interfaces:**
- Produces: `SessionRegistry.refresh(from:)`, `apply(_:)`, `selectableSessions`, and `SleepCountdownController.ticks(seconds:)`.
- Consumes: App Server summaries, Hook events, and Task 1 state-machine events.

- [ ] **Step 1: Write reconciliation tests**

```swift
final class SessionRegistryTests: XCTestCase {
    func testNewerHookEventOverridesAppServerSnapshot() async throws {
        let registry = SessionRegistry()
        let summary = SessionSummary(id: SessionID("s1"), threadID: "thread-1", name: "Task", cwd: "/repo", updatedAt: Date(timeIntervalSince1970: 10), status: .running(turnID: nil))
        await registry.refresh(from: [summary])
        await registry.apply(HookEvent(kind: .stop, sessionID: SessionID("s1"), turnID: TurnID("t1"), cwd: "/repo", receivedAt: Date(timeIntervalSince1970: 20)))
        XCTAssertEqual(await registry.session(id: SessionID("s1"))?.status, .idle)
    }

    func testNonTargetSessionCannotCreateTargetEvent() async throws {
        let registry = SessionRegistry()
        await registry.setTarget(SessionID("target"))
        let effect = await registry.apply(HookEvent(kind: .stop, sessionID: SessionID("other"), turnID: TurnID("t1"), cwd: "/repo", receivedAt: .now))
        XCTAssertEqual(effect, .nonTargetUpdated)
    }
}
```

- [ ] **Step 2: Run the test and verify missing-type failure**

Run: `swift test --filter SessionRegistryTests`

Expected: compilation fails because registry types are undefined.

- [ ] **Step 3: Implement the actor registry**

Store entries keyed only by `SessionID`, track `lastEventAt` and `lastTurnID`, and map events as follows:

```swift
switch event.kind {
case .sessionStart:
    status = .idle
case .userPromptSubmit:
    status = .running(turnID: event.turnID)
case .permissionRequest:
    status = .waitingOnApproval
case .stop:
    status = .idle
}
```

Ignore events older than `lastEventAt`. Expose a `RegistryEffect` value so the app controller can distinguish target restarted, target stopped, target waiting, non-target updated, and invalid target.

- [ ] **Step 4: Implement a testable countdown clock**

Define a `ClockSleeping` protocol and production `ContinuousClock` adapter. `SleepCountdownController.ticks(seconds:)` returns an `AsyncStream<Int>` emitting the initial value down to zero once per second; cancellation ends the stream without zero.

Add these exact assertions with a fake clock whose `sleepOneSecond()` increments a counter and returns immediately:

```swift
func testCountdownEmitsEveryValueThroughZero() async throws {
    let clock = ImmediateClock()
    let controller = SleepCountdownController(clock: clock)
    var values: [Int] = []
    for await value in controller.ticks(seconds: 3) { values.append(value) }
    XCTAssertEqual(values, [3, 2, 1, 0])
    XCTAssertEqual(await clock.sleepCount, 3)
}

func testCancelledCountdownNeverEmitsZero() async throws {
    let clock = SuspendingClock()
    let controller = SleepCountdownController(clock: clock)
    let task = Task { () -> [Int] in
        var values: [Int] = []
        for await value in controller.ticks(seconds: 3) { values.append(value) }
        return values
    }
    await clock.waitUntilSleepWasRequested()
    task.cancel()
    XCTAssertFalse(await task.value.contains(0))
}
```

- [ ] **Step 5: Run registry and countdown tests**

Run: `swift test --filter SessionRegistryTests`

Expected: registry and clock tests pass.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 6: Commit reconciliation and countdown**

```bash
git add Sources/CodexSleepWatcherCore/Sessions Sources/CodexSleepWatcherCore/Services Tests/CodexSleepWatcherCoreTests/SessionRegistryTests.swift
git commit -m "feat: reconcile multi-session lifecycle events"
```

---

### Task 6: Power Assertions, Settings, and Safe Sleep Abstraction

**Files:**
- Create: `Sources/CodexSleepWatcherCore/Power/PowerAssertionController.swift`
- Create: `Sources/CodexSleepWatcherCore/Power/SystemSleeper.swift`
- Create: `Sources/CodexSleepWatcherCore/Services/SettingsStore.swift`
- Create: `Tests/CodexSleepWatcherCoreTests/PowerControllerTests.swift`

**Interfaces:**
- Produces: `PowerAssertionControlling`, `SystemSleeping`, `SettingsStore`.
- Later app code must receive these protocols by dependency injection; tests use fakes only.

- [ ] **Step 1: Write assertion ownership tests against a fake IOKit adapter**

```swift
final class PowerControllerTests: XCTestCase {
    func testStartAndStopOwnExactlyOneSystemAssertion() throws {
        let api = FakePowerAssertionAPI(createdIDs: [41])
        let controller = PowerAssertionController(api: api)
        try controller.start(keepDisplayAwake: false)
        controller.stop()
        XCTAssertEqual(api.createdTypes, ["PreventUserIdleSystemSleep"])
        XCTAssertEqual(api.releasedIDs, [41])
    }

    func testCreationFailureReleasesPartialAssertions() throws {
        let api = FakePowerAssertionAPI(createdIDs: [41], failOnCreateNumber: 2)
        let controller = PowerAssertionController(api: api)
        XCTAssertThrowsError(try controller.start(keepDisplayAwake: true))
        XCTAssertEqual(api.releasedIDs, [41])
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter PowerControllerTests`

Expected: compilation fails because the power abstractions are undefined.

- [ ] **Step 3: Implement the IOKit adapter and idempotent controller**

Use `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep`; when requested, also create `kIOPMAssertionTypePreventUserIdleDisplaySleep`. Store non-zero assertion IDs, release each exactly once, and make `stop()` idempotent.

Define production sleep behind this protocol:

```swift
public protocol SystemSleeping: Sendable {
    func sleepNow() throws
}
```

`MacSystemSleeper.sleepNow()` obtains an `io_connect_t` with `IOPMFindPowerManagement(MACH_PORT_NULL)`, defers `IOServiceClose(connection)`, calls `IOPMSleepSystem(connection)`, and throws unless the return value is `kIOReturnSuccess`. No test instantiates `MacSystemSleeper`.

- [ ] **Step 4: Implement settings persistence**

`SettingsStore` uses an injected `UserDefaults` suite and exact keys:

```swift
enum SettingsKey {
    static let delaySeconds = "delaySeconds"
    static let waitForOtherSessions = "waitForOtherSessions"
    static let keepDisplayAwake = "keepDisplayAwake"
    static let launchAtLogin = "launchAtLogin"
}
```

Clamp delay to `0...300` and default to 30 seconds.

Add a test using `UserDefaults(suiteName: UUID().uuidString)!`: write `delaySeconds = 999`, reload the store, and assert `delaySeconds == 300`; then set all four properties, create a second store with the same suite, and assert every value round-trips.

- [ ] **Step 5: Run tests**

Run: `swift test --filter PowerControllerTests`

Expected: power and settings tests pass without creating a real assertion.

- [ ] **Step 6: Commit power and settings**

```bash
git add Sources/CodexSleepWatcherCore/Power Sources/CodexSleepWatcherCore/Services/SettingsStore.swift Tests/CodexSleepWatcherCoreTests/PowerControllerTests.swift
git commit -m "feat: manage wake assertions and sleep safely"
```

---

### Task 7: App Controller and Menu-Bar UI

**Files:**
- Create: `Sources/CodexSleepWatcherApp/AppController.swift`
- Create: `Sources/CodexSleepWatcherApp/MenuBarView.swift`
- Create: `Sources/CodexSleepWatcherApp/NotificationController.swift`
- Modify: `Sources/CodexSleepWatcherApp/CodexSleepWatcherApp.swift`

**Interfaces:**
- Consumes: all core services and protocols from Tasks 1–6.
- Produces: a usable `MenuBarExtra` app with setup, session selection, monitoring, countdown, settings, and cancellation.

- [ ] **Step 1: Implement the main-actor controller with injected dependencies**

```swift
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var phase: WatchPhase = .setupRequired("Checking Codex Hooks")
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var selectedSessionID: SessionID?
    @Published var settings: WatchSettings

    func start() async
    func refreshSessions() async
    func select(_ sessionID: SessionID) async
    func cancelMonitoring()
    func sleepImmediately()
    func installHooks() async
    func uninstallHooks() async
}
```

At startup: resolve the packaged helper path, inspect hooks, start the event receiver, start App Server, refresh sessions, then consume hook events. Any event-stream or identity error calls `.fatalObservationError`, stops the countdown, and releases power assertions.

Selecting a session starts the power assertion before updating the visible phase. If assertion creation fails, remain idle and show the error.

- [ ] **Step 2: Implement notification behavior**

`NotificationController` requests authorization only when the first countdown begins. Send category `SLEEP_COUNTDOWN` with action `CANCEL_SLEEP`. Clicking that action calls `cancelMonitoring()`. Notification body contains only the target display name and remaining seconds.

- [ ] **Step 3: Build the menu view**

Use a `Menu` titled “选择观测目标” listing only selectable sessions. Each label shows a colored status circle, `name`, abbreviated cwd, and `id.short`. Disable the selected target row.

Below the list render:

```swift
Text(controller.phase.description)
Button("取消观测") { controller.cancelMonitoring() }
Button("立即休眠") { controller.sleepImmediately() }
Picker("休眠延迟", selection: $delay) { Text("0 秒").tag(0); Text("15 秒").tag(15); Text("30 秒").tag(30); Text("60 秒").tag(60) }
Toggle("其他会话仍运行时延后休眠", isOn: $waitForOthers)
Toggle("保持屏幕常亮", isOn: $keepDisplayAwake)
Divider()
Button("退出") { NSApplication.shared.terminate(nil) }
```

When hooks need setup, replace the selection list with “安装 Codex Hooks” and concise trust instructions. Do not expose prompt previews.

- [ ] **Step 4: Wire the app entry and lifecycle cleanup**

Create the controller once with `@StateObject`, call `start()` from `.task`, and call `cancelMonitoring()` plus service shutdown from `applicationWillTerminate` through an `NSApplicationDelegateAdaptor`.

Use `SMAppService.mainApp.register()` and `.unregister()` for the launch-at-login toggle; report errors in the menu instead of silently changing the stored setting.

- [ ] **Step 5: Compile and run the test suite**

Run: `swift build`

Expected: both executable products compile.

Run: `swift test`

Expected: all core tests pass.

- [ ] **Step 6: Commit the menu-bar app**

```bash
git add Sources/CodexSleepWatcherApp
git commit -m "feat: add multi-session menu bar controls"
```

---

### Task 8: Package the `.app`, Document Setup, and Verify End to End

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/package_app.sh`
- Create: `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `dist/Codex Sleep Watcher.app` with the app binary and hook helper.
- Provides commands for install, Hook trust, use, update, and uninstall.

- [ ] **Step 1: Create the menu-only app plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CodexSleepWatcherApp</string>
  <key>CFBundleIdentifier</key><string>com.xhuandy.codex-sleep-watcher</string>
  <key>CFBundleName</key><string>Codex Sleep Watcher</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
```

- [ ] **Step 2: Create a strict packaging script**

`Scripts/package_app.sh` must use `set -euo pipefail`, run `swift build -c release --product CodexSleepWatcherApp` and `swift build -c release --product codex-sleep-hook`, create:

```text
dist/Codex Sleep Watcher.app/Contents/MacOS/CodexSleepWatcherApp
dist/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook
dist/Codex Sleep Watcher.app/Contents/Info.plist
```

Set both executables to mode `0755`, then run:

```bash
codesign --force --deep --sign - "dist/Codex Sleep Watcher.app"
codesign --verify --deep --strict "dist/Codex Sleep Watcher.app"
```

Add `.build/` and `dist/` to `.gitignore`; do not commit generated binaries.

- [ ] **Step 3: Write the README with exact setup flow**

Document:

1. Run `./Scripts/package_app.sh`.
2. Copy `dist/Codex Sleep Watcher.app` to `/Applications` or run it in place.
3. Click “安装 Codex Hooks”.
4. Restart Codex if the hook list does not refresh automatically.
5. Review and trust entries labeled `Codex Sleep Watcher` in Codex Hooks UI.
6. Start multiple Codex tasks, open the menu, and select exactly one target.
7. Use “取消观测” to release wake assertions without sleeping.
8. Before moving or replacing the `.app`, cancel monitoring; after moving, reopen it so `HookInstaller` updates the absolute helper path.
9. To uninstall, choose “卸载 Codex Hooks”, quit the app, then delete the `.app`.

Include a privacy section listing the exact forwarded fields and explicitly excluding prompts, messages, and transcripts.

- [ ] **Step 4: Run automated verification**

Run:

```bash
swift test
./Scripts/package_app.sh
plutil -lint "dist/Codex Sleep Watcher.app/Contents/Info.plist"
codesign --verify --deep --strict "dist/Codex Sleep Watcher.app"
test -x "dist/Codex Sleep Watcher.app/Contents/MacOS/CodexSleepWatcherApp"
test -x "dist/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook"
```

Expected: all commands exit `0`; tests pass; plist reports `OK`; code signature verifies.

- [ ] **Step 5: Perform a no-sleep manual smoke test**

Add a debug launch argument `--disable-real-sleep` that injects a sleeper writing `sleep requested for <session_id>` to unified logging. Launch:

```bash
open "dist/Codex Sleep Watcher.app" --args --disable-real-sleep
```

Verify with three concurrent Codex sessions:

1. All three appear with distinct short IDs.
2. Select session B.
3. Finish session A; no countdown starts.
4. Put session B into a permission request; countdown starts.
5. Send a new prompt to B during countdown; countdown cancels.
6. Cancel B; countdown starts again.
7. Confirm unified log records one sleep request and the Mac does not actually sleep.

- [ ] **Step 6: Perform the one-time real-sleep acceptance test**

Only after automated and debug smoke tests pass, launch without `--disable-real-sleep`, select a disposable short task, allow the countdown to finish, and confirm the Mac enters sleep. Perform this step interactively with the user present; never run it unattended during implementation.

- [ ] **Step 7: Commit packaging and documentation**

```bash
git add Resources Scripts README.md .gitignore
git commit -m "docs: package and explain Codex Sleep Watcher"
```

---

## Final Verification

- [ ] Run `swift test` and confirm all tests pass.
- [ ] Run `swift build -c release` and confirm both executables build.
- [ ] Run `./Scripts/package_app.sh` and confirm ad-hoc signature verification succeeds.
- [ ] Run `git diff --check` and confirm no whitespace errors.
- [ ] Run `git status --short` and confirm only intentional files remain.
- [ ] Compare the implementation against every acceptance criterion in `docs/superpowers/specs/2026-07-11-codex-sleep-watcher-design.md`.
- [ ] Keep the real-sleep acceptance test as the final interactive check.
