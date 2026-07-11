# Session Refresh and Welcome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep recent Codex sessions visible across refreshes and add a first-launch welcome window with a reusable help entry.

**Architecture:** Treat App Server thread records as discoverable candidates, not authoritative Desktop runtime state. Merge candidate metadata into `SessionRegistry`, preserve newer Hook-derived status, and drive the menu from the merged snapshot. Add a small SwiftUI window whose one-time presentation is controlled by `SettingsStore`.

**Tech Stack:** Swift 6, SwiftUI, Foundation, Swift Package Manager, custom executable test runner.

## Global Constraints

- Support macOS 13 and newer.
- Display at most the 20 most recently updated unarchived sessions.
- Preserve the selected target across refreshes, including when outside the newest 20.
- Hooks remain the authoritative source for live status.
- The test build uses the real system-sleep implementation.
- Do not add third-party dependencies.

---

### Task 1: Discover recent sessions without losing Hook status

**Files:**
- Modify: `Sources/CodexSleepWatcherCore/Codex/SessionDiscoveryService.swift`
- Modify: `Sources/CodexSleepWatcherCore/Sessions/SessionRegistry.swift`
- Modify: `Sources/CodexSleepWatcherCore/Domain/Models.swift`
- Modify: `Sources/CodexSleepWatcherTests/main.swift`

**Interfaces:**
- Produces: `SessionDiscoveryService.mapRecentThreads(_:limit:) -> [SessionSummary]`
- Produces: `SessionRegistry.refresh(from:preserving:)`
- Produces: `SessionRegistry.sessions() -> [SessionSummary]`

- [ ] **Step 1: Write failing tests**

Add test cases that decode active, idle, and notLoaded records, assert all three are returned in updated-time order with a limit of 20, and assert a newer Hook `Stop` remains `.idle` after metadata refresh. Add a selected session outside the newest 20 and assert `refresh(from:preserving:)` retains it.

- [ ] **Step 2: Run the test runner and verify RED**

Run: `swift run codex-sleep-tests`

Expected: compilation fails because `mapRecentThreads`, `refresh(from:preserving:)`, and `sessions()` do not exist.

- [ ] **Step 3: Implement minimal session mapping and merge**

Replace active-only mapping with:

```swift
public static func mapRecentThreads(_ threads: [ThreadRecord], limit: Int = 20) -> [SessionSummary] {
    threads.map { thread in
        let status: SessionStatus
        switch thread.status {
        case .active(let flags):
            status = flags.contains("waitingOnApproval") ? .waitingOnApproval
                : flags.contains("waitingOnUserInput") ? .waitingOnUserInput
                : .running(turnID: nil)
        case .idle, .notLoaded, .systemError:
            status = .unknown
        }
        return SessionSummary(id: SessionID(thread.sessionId), threadID: thread.id,
            name: thread.name ?? URL(fileURLWithPath: thread.cwd).lastPathComponent,
            cwd: thread.cwd, updatedAt: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt)), status: status)
    }.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(0, limit)).map { $0 }
}
```

Add `.unknown` to `SessionStatus`. In `SessionRegistry.refresh`, update metadata while retaining status whenever an entry has a later Hook event; retain the optional selected ID even if it is absent from incoming candidates. Return sorted merged entries from `sessions()`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift run codex-sleep-tests`

Expected: all core tests pass, including the new recent-session and preservation cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexSleepWatcherCore Sources/CodexSleepWatcherTests/main.swift
git commit -m "fix: preserve recent sessions across refreshes"
```

### Task 2: Drive the menu from merged candidates

**Files:**
- Modify: `Sources/CodexSleepWatcherApp/AppController.swift`
- Modify: `Sources/CodexSleepWatcherApp/MenuBarView.swift`
- Modify: `Sources/CodexSleepWatcherTests/main.swift`

**Interfaces:**
- Consumes: `SessionDiscoveryService.mapRecentThreads(_:limit:)`
- Consumes: `SessionRegistry.refresh(from:preserving:)`
- Produces: `SessionStatus.displayName`

- [ ] **Step 1: Write failing status-label tests**

Add assertions that `.running`, `.waitingOnApproval`, `.waitingOnUserInput`, `.idle`, and `.unknown` produce the Chinese labels `运行中`, `等待授权`, `等待输入`, `已停止`, and `状态未知`.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift run codex-sleep-tests`

Expected: compilation fails because `SessionStatus.displayName` does not exist.

- [ ] **Step 3: Implement merged refresh and clear labels**

Change `AppController.refresh()` to map recent threads, merge them with `preserving: selected`, and assign `sessions = await registry.sessions()`. On failure, only set the error status and leave `sessions` unchanged. Update `handle(_:)` to apply the Hook event, then refresh without allowing App Server metadata to erase the event status.

Show each row as `session.name — session.status.displayName`. Change the empty copy to `没有找到最近的 Codex 会话，请先创建或运行一个任务。` and keep the existing refresh button.

- [ ] **Step 4: Run tests and build**

Run: `swift run codex-sleep-tests`

Expected: all tests pass.

Run: `swift build`

Expected: debug build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexSleepWatcherApp Sources/CodexSleepWatcherCore/Domain/Models.swift Sources/CodexSleepWatcherTests/main.swift
git commit -m "fix: keep selected sessions visible on refresh"
```

### Task 3: Add first-launch welcome and reusable help window

**Files:**
- Create: `Sources/CodexSleepWatcherApp/WelcomeView.swift`
- Modify: `Sources/CodexSleepWatcherApp/CodexSleepWatcherApp.swift`
- Modify: `Sources/CodexSleepWatcherApp/MenuBarView.swift`
- Modify: `Sources/CodexSleepWatcherApp/AppController.swift`
- Modify: `Sources/CodexSleepWatcherCore/Services/SettingsStore.swift`
- Modify: `Sources/CodexSleepWatcherTests/main.swift`

**Interfaces:**
- Produces: `SettingsStore.hasShownWelcome: Bool`
- Produces: `AppController.shouldPresentWelcome: Bool`
- Produces: `AppController.showWelcome()` and `dismissWelcome()`

- [ ] **Step 1: Write failing persistence test**

Create an isolated `UserDefaults` suite, assert `hasShownWelcome` initially returns false, set it to true, and assert the value persists through a second `SettingsStore` instance.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift run codex-sleep-tests`

Expected: compilation fails because `hasShownWelcome` does not exist.

- [ ] **Step 3: Implement the welcome flow**

Add the Boolean setting. Add a `Window("欢迎使用 Codex Sleep Watcher", id: "welcome")` scene sized approximately 520×420. `WelcomeView` contains the four approved steps and a primary `开始使用` button. On first start, open the window and set `hasShownWelcome` when the user dismisses it. Add `Button("使用说明…")` to the menu using SwiftUI's `openWindow(id: "welcome")` action so it can always be reopened.

Keep `MacSystemSleeper` as the default and do not add a debug-only replacement to the distributed test build.

- [ ] **Step 4: Verify tests and Debug build**

Run: `swift run codex-sleep-tests`

Expected: all tests pass.

Run: `swift build`

Expected: debug build succeeds.

- [ ] **Step 5: Launch the unpackaged Debug executable for user testing**

Run: `swift run CodexSleepWatcherApp`

Expected: a welcome window appears on first launch, the menu-bar moon remains visible, refreshing shows recent sessions, and selecting a target uses the real sleep path.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSleepWatcherApp Sources/CodexSleepWatcherCore/Services/SettingsStore.swift Sources/CodexSleepWatcherTests/main.swift
git commit -m "feat: add first-launch welcome guidance"
```

### Task 4: Full verification and test handoff

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: all preceding behavior.
- Produces: documented test instructions; no packaged `.app` yet.

- [ ] **Step 1: Update test instructions**

Document the welcome window, recent-session behavior, Hooks as the live-state source, and the fact that the user test build performs real sleep.

- [ ] **Step 2: Run full verification**

Run: `swift run codex-sleep-tests && swift build -c release && git diff --check`

Expected: tests pass, release compilation succeeds, and the diff check prints no errors.

- [ ] **Step 3: Commit and hand off**

```bash
git add README.md
git commit -m "docs: explain refreshed session and welcome flow"
```

Provide the user with the exact Debug launch command and wait for confirmation before running the packaging script or producing a final `.app` archive.
