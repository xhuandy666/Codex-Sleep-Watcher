# Codex Sleep Watcher

一个原生 macOS 菜单栏工具：从多个 Codex 会话中选择一个观测目标，在目标运行、等待授权或等待输入期间防止 Mac 空闲休眠；只有目标收到 `Stop` 事件后，才会按设定启动自动休眠倒计时。

## 系统要求

- macOS 13 或更高版本（Apple Silicon 与 Intel 均支持）。
- Codex Desktop App，并且终端可以运行 `codex app-server`。
- Xcode Command Line Tools（可通过 `xcode-select --install` 安装）。

## 从源码安装

```zsh
git clone https://github.com/xhuandy666/Codex-Sleep-Watcher.git
cd Codex-Sleep-Watcher
./Scripts/package_app.sh
```

生成的安装包位于 `dist/Codex-Sleep-Watcher-<版本>.zip`。解压后先把 App 复制到 `/Applications`，再启动并安装 Hooks，避免之后移动 App 导致 Hook 路径失效。

首次启动如果被 Gatekeeper 阻止，请在 Finder 中右键 App，选择“打开”。本项目当前使用本机临时签名，没有 Apple 公证。

## 开发验证

```zsh
swift run codex-sleep-tests
swift build
```

## 首次使用

1. 首次打开 App 会出现欢迎窗口；以后可从菜单栏月亮图标的“使用说明…”再次查看。
2. 点击“安装 / 更新 Codex Hooks”。
3. 在 Codex 的 Hooks 管理界面审阅并信任标为 `Codex Sleep Watcher` 的六个 Hook：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PermissionRequest` 和 `Stop`。如果列表没有刷新，重启 Codex。
4. 点击菜单栏月亮图标，在可滚动列表中从最近 20 个 Codex 会话选择观测目标。App Server 负责发现会话，Hooks 负责实时更新状态。
5. 需要停止时点击“取消观测”，防休眠断言会立即释放。

App 启动后会立即监听 Hooks，无需先打开月亮面板。状态含义如下：

- `运行中`：会话已经开始、收到新的用户任务或正在调用工具。
- `等待授权` / `等待输入`：Codex 正等待用户操作，Watcher 会继续保持 Mac 唤醒，不会启动休眠倒计时。
- `本轮已完成`：当前回合结束，会话本身仍可继续使用和观测。
- `尚未收到事件`：App Server 已发现会话，但尚未收到该会话的 Hooks 事件。

从旧版本升级或移动 App 后，需要在 App 的最终位置再次点击“安装 / 更新 Codex Hooks”，并在 Codex 中重新审阅和信任。Hook 使用 App 内帮助程序的绝对路径，新增或路径发生变化的 Hook 在重新信任前可能不会运行。

## 安全与隐私

Hook 只转发事件名称、`session_id`、`turn_id`、工作目录和时间。工具不会转发或保存 prompt、助手回复和 transcript 内容；不连接外部网络。身份或事件状态不明确时采用安全失败，不触发休眠。

开发调试时可使用：

```zsh
swift run CodexSleepWatcherApp
```

该命令默认使用真实休眠。仅当需要避免休眠时才使用调试参数：

```zsh
swift run CodexSleepWatcherApp --disable-real-sleep
```

该模式只记录休眠请求，不会真的使 Mac 休眠。

## 卸载

取消观测，在菜单中点击“卸载 Codex Hooks”，退出并删除 App。
