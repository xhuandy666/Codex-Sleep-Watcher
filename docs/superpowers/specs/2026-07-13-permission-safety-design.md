# 授权等待期间防误休眠设计

## 背景与根因

当前实现将目标会话的 `PermissionRequest` 与 `Stop` 都视为任务结束并启动休眠倒计时。macOS 电源日志显示，`CodexSleepWatcherApp` 在误休眠发生时释放了 `PreventUserIdleSystemSleep` 断言，同一秒显示器关闭，证明黑屏由本工具主动触发。

同时，Hooks 只安装 `SessionStart`、`UserPromptSubmit`、`PermissionRequest` 和 `Stop`。授权通过后缺少 `PreToolUse` / `PostToolUse` 事件来恢复运行状态，因此会话会错误地长期显示“等待授权”。

## 方案比较

1. **事件闭环方案（采用）**：只有 `Stop` 触发休眠；增加 `PreToolUse` 和 `PostToolUse`，授权后恢复运行状态。优点是实时、准确且不依赖轮询。
2. **仅忽略授权休眠**：`PermissionRequest` 不再休眠，但不增加新 Hooks。可以阻止误休眠，但状态仍可能卡在“等待授权”。
3. **App Server 轮询**：定期查询任务状态。独立 App Server 无法可靠反映 Codex Desktop 的实时状态，且增加资源消耗，不采用。

## 已确认行为

- 目标收到 `PermissionRequest` 时继续持有防休眠断言，不启动倒计时。
- UI 显示“等待授权”，表示 Codex 此刻确实正在请求用户操作。
- 目标收到 `PreToolUse` 或 `PostToolUse` 时恢复“运行中”。
- 只有目标收到 `Stop` 时才根据延迟设置启动休眠倒计时。
- `SessionStart`、`UserPromptSubmit`、`PreToolUse` 或 `PostToolUse` 都属于活动事件，必须取消尚未结束的休眠倒计时和“等待其他会话”状态。
- 处于等待授权或等待输入的其他会话仍算活跃会话；开启“其他会话仍运行时延后休眠”后，不得因为它们等待用户而休眠。

## 组件修改

### Hook 事件

`HookEventKind` 增加 `PreToolUse` 和 `PostToolUse`。`HookInstaller` 安装六类事件，并继续以 `Codex Sleep Watcher` 标记所有自有 Hook，确保升级与卸载不会影响其他工具的 Hook。

### 会话状态

`SessionRegistry` 将 `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse` 映射为运行中，将 `PermissionRequest` 映射为等待授权，仅将 `Stop` 映射为本轮已完成。

### 休眠决策

把目标事件处理拆为三类：

- 活动事件：取消倒计时，恢复观测状态。
- 等待授权：保持唤醒，只更新提示。
- `Stop`：执行现有的其他会话检查和休眠倒计时。

## 测试与验收

- `PermissionRequest` 不会进入倒计时或调用系统休眠。
- `PermissionRequest → PreToolUse` 后状态恢复运行中。
- 活动事件能取消已有倒计时。
- 只有 `Stop` 能启动目标休眠倒计时。
- 等待授权/等待输入的其他会话会阻止“等待其他会话”模式进入倒计时。
- Hook 安装器安装并可卸载六类自有 Hook，不删除第三方 Hook。
- 自动化测试、Debug 构建、Release 构建和真实事件序列验证通过后再重新打包并推送 GitHub。
