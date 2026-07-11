# Scrollable Session Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reliably display sessions from multiple projects in a scrollable menu-bar panel and accurately describe per-turn Hook state.

**Architecture:** Keep App Server and Hook reconciliation unchanged, but render the result in a window-style `MenuBarExtra` instead of an `NSMenu`. Make Hook-to-status mapping and display labels explicit and unit tested. Verify with two concurrent CLI sessions from different working directories.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, Codex App Server, Codex Hooks.

## Global Constraints

- Support macOS 13 and newer.
- Keep the most recent 20 App Server sessions plus Hook-only live sessions.
- Preserve the selected target on refresh.
- Do not change the existing real-sleep trigger rules.
- Do not create the final release archive until the user confirms the test build.

---

### Task 1: Correct Hook status semantics

**Files:**
- Modify: `Sources/CodexSleepWatcherCore/Domain/Models.swift`
- Modify: `Sources/CodexSleepWatcherCore/Sessions/SessionRegistry.swift`
- Modify: `Sources/CodexSleepWatcherTests/main.swift`

**Interfaces:**
- Produces: `SessionStatus.displayName`
- Consumes: `SessionRegistry.apply(_:)`

- [ ] Add failing tests asserting `SessionStart` maps to `.running(turnID: nil)`, `Stop` maps to `.idle`, and labels are `运行中`, `等待授权`, `等待输入`, `本轮已完成`, `尚未收到事件`.
- [ ] Run `swift run codex-sleep-tests`; expect the SessionStart and label assertions to fail.
- [ ] Change `SessionRegistry.apply(_:)` so `.sessionStart` becomes running and `.stop` becomes idle; update display labels.
- [ ] Run `swift run codex-sleep-tests`; expect all tests to pass.
- [ ] Commit with `fix: clarify live session status semantics`.

### Task 2: Build the scrollable menu-bar panel

**Files:**
- Modify: `Sources/CodexSleepWatcherApp/CodexSleepWatcherApp.swift`
- Replace: `Sources/CodexSleepWatcherApp/MenuBarView.swift`
- Modify: `Sources/CodexSleepWatcherApp/AppController.swift`

**Interfaces:**
- Consumes: `AppController.sessions`, `selected`, `status`, and existing actions.
- Produces: a window-style `MenuBarExtra` with a `ScrollView` session region.

- [ ] Add `.menuBarExtraStyle(.window)` to the scene and set a stable panel frame.
- [ ] Replace menu-only controls with a `VStack`: header and refresh button, 320-point scrollable session cards, selected-state highlight, and bottom settings/actions.
- [ ] Update `select(_:)` to stop the previous power assertion before switching targets.
- [ ] Run `swift run codex-sleep-tests` and `swift build`; expect both to pass.
- [ ] Commit with `feat: add scrollable session picker panel`.

### Task 3: Two-session end-to-end verification

**Files:**
- No production files expected.

**Interfaces:**
- Exercises the built App, global Hooks, App Server, and two temporary Codex CLI sessions.

- [ ] Start the Debug App with captured output.
- [ ] Start session A in `/tmp/codex-sleep-watcher-e2e-a` and session B in `/tmp/codex-sleep-watcher-e2e-b`, each running a bounded wait command with Hook trust bypassed for the vetted local Hooks.
- [ ] Verify both session IDs and working directories appear in the event/data path and remain distinct in registry tests.
- [ ] Terminate both Codex CLI sessions and all wait child processes; verify no matching process remains.
- [ ] Run `swift run codex-sleep-tests`, `swift build -c release`, and `git diff --check`.
- [ ] Relaunch a clean Debug App for user confirmation; do not create the final release archive.
