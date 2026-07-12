# Permission-Safe Sleep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent authorization requests from triggering sleep and restore accurate running state after authorization.

**Architecture:** Extend the Hook event model to cover the tool lifecycle, classify target events as activity/wait/stop in the core module, and make the app start countdowns only for `Stop`. Keep waiting sessions live so the multi-session delay policy remains fail-safe.

**Tech Stack:** Swift 6, SwiftUI, Foundation, Swift Package Manager, Codex Hooks.

---

### Task 1: Close the Hook status loop

**Files:**
- Modify: `Sources/CodexSleepWatcherCore/Hooks/HookEvent.swift`
- Modify: `Sources/CodexSleepWatcherCore/Hooks/HookInstaller.swift`
- Modify: `Sources/CodexSleepWatcherCore/Sessions/SessionRegistry.swift`
- Modify: `Sources/CodexSleepWatcherTests/main.swift`

- [ ] **Step 1: Write failing tests**

Add assertions that `PreToolUse` and `PostToolUse` decode into `HookEventKind`, both map a waiting session back to `.running`, and two consecutive installs create exactly six owned Hooks while preserving unrelated entries.

- [ ] **Step 2: Verify RED**

Run: `swift run codex-sleep-tests`

Expected: compilation fails because `preToolUse` and `postToolUse` do not exist, or the installer count remains four.

- [ ] **Step 3: Implement the event loop**

Add:

```swift
case preToolUse = "PreToolUse"
case postToolUse = "PostToolUse"
```

Register both names in `HookInstaller.events`. In `SessionRegistry.apply`, map `sessionStart`, `userPromptSubmit`, `preToolUse`, and `postToolUse` to `.running`, `permissionRequest` to `.waitingOnApproval`, and `stop` to `.idle`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift run codex-sleep-tests`

Expected: all tests pass.

Commit: `fix: close hook activity status loop`

### Task 2: Make sleep decisions permission-safe

**Files:**
- Create: `Sources/CodexSleepWatcherCore/Domain/TargetEventDecision.swift`
- Modify: `Sources/CodexSleepWatcherCore/Domain/WatchStateMachine.swift`
- Modify: `Sources/CodexSleepWatcherApp/AppController.swift`
- Modify: `Sources/CodexSleepWatcherTests/main.swift`

- [ ] **Step 1: Write failing policy tests**

Assert these exact mappings:

```swift
permissionRequest -> .waitingForAuthorization
stop              -> .stopped
sessionStart      -> .activity
userPromptSubmit  -> .activity
preToolUse        -> .activity
postToolUse       -> .activity
```

Also assert `WatchStateMachine` remains `.monitoring(target)` for `.waitingOnApproval`, returns from countdown to monitoring on activity, and considers a waiting other session active when `waitForOtherSessions` is enabled.

- [ ] **Step 2: Verify RED**

Run: `swift run codex-sleep-tests`

Expected: policy type is missing and waiting approval incorrectly starts countdown.

- [ ] **Step 3: Implement the core policy**

Create `TargetEventDecision` with `activity`, `waitingForAuthorization`, and `stopped`, plus `HookEventKind.targetDecision`. Change `WatchStateMachine` to use `SessionStatus.isLive` for the active set and keep monitoring for running/waiting states.

- [ ] **Step 4: Apply the policy in AppController**

For the selected target:

```swift
switch event.kind.targetDecision {
case .activity:
    cancel the countdown and waiting-after-stop state
case .waitingForAuthorization:
    keep the power assertion and show a waiting message
case .stopped:
    run the existing other-session check and countdown
}
```

Only `.stopped` may call `beginCountdown()`. Change `SessionRegistry.runningSessions()` to return all `status.isLive` sessions.

- [ ] **Step 5: Verify GREEN and commit**

Run: `swift run codex-sleep-tests && swift build`

Expected: all tests and Debug build pass.

Commit: `fix: prevent sleep while awaiting permission`

### Task 3: Document, verify, package, and publish

**Files:**
- Modify: `README.md`

- [ ] Update README to state that authorization keeps the Mac awake and only `Stop` triggers automatic sleep.
- [ ] Run `swift run codex-sleep-tests`, `swift build -c release`, and `git diff --check`.
- [ ] Build a Debug App with real sleep disabled and replay `PermissionRequest → PreToolUse → Stop`; verify only `Stop` produces a sleep request.
- [ ] Reinstall the six Hooks in the local test configuration and verify unrelated Hooks remain present.
- [ ] Run `./Scripts/package_app.sh`, strict codesign verification, and ZIP integrity verification.
- [ ] Commit documentation, push `main`, and confirm local/remote HEAD equality.
