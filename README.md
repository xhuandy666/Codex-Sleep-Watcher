# Codex Sleep Watcher

一个原生 macOS 菜单栏工具：从多个 Codex 会话中选择一个观测目标，在目标运行、等待授权或等待输入期间防止 Mac 空闲休眠；只有目标收到 `Stop` 事件后，才会按设定启动自动休眠倒计时。

## 运行要求与兼容范围

- macOS 13 或更高版本（Apple Silicon 与 Intel 均支持）。
- 已安装 ChatGPT 桌面端（含本地 Codex 功能）或 Codex Desktop App，建议放在 `/Applications`。
- 观测对象必须是使用本机 Codex 运行时、能够执行本地 Hooks 的任务。支持本地 Codex 任务及本地运行的 Work 任务；普通 ChatGPT 对话、Work Cloud、远程或云端执行任务不在支持范围内，即使云端任务启用了本地电脑访问，也不能依赖本工具的本地命令 Hooks。

0.1.3 的适配环境为 **ChatGPT 26.928.21956（build 12404） / Codex CLI 0.159.2**，于 2026-10-01 在本机验证。Watcher 优先查找 `/Applications` 和 `~/Applications` 中桌面端自带的 CLI，再使用 `PATH` 或常见独立 CLI 安装路径，因此正常安装桌面端后无需额外安装 Codex CLI，也不依赖 Finder 启动时的终端环境。

当前桌面端的内置路径包括 `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`；同时保留对 `codex-cli/bin/codex` 和旧版 `Contents/Resources/codex` 的支持。App Server 与 Hooks 会随桌面端更新，以上版本是本次验证记录，不代表所有未来版本都已验证。

## 安装 App

从 [GitHub Releases](https://github.com/xhuandy666/Codex-Sleep-Watcher/releases) 选择对应版本的 `Codex-Sleep-Watcher-<版本>.zip`。如果所需版本尚未提供安装包，可按下文从源码构建。

解压后先把 App 复制到 `/Applications`，再启动并安装 Hooks，避免之后移动 App 导致 Hook 路径失效。预编译 App 不需要 Xcode 或 Swift。

首次启动如果被 Gatekeeper 阻止，请在 Finder 中右键 App，选择“打开”。本项目当前使用本机临时签名，没有 Apple 公证。

## 从源码安装

源码构建额外需要 Swift 6 或更新版本的 Xcode Command Line Tools（可通过 `xcode-select --install` 安装）。可先运行 `swift --version` 确认编译器版本。

```zsh
git clone https://github.com/xhuandy666/Codex-Sleep-Watcher.git
cd Codex-Sleep-Watcher
./Scripts/package_app.sh
```

生成的安装包位于 `dist/Codex-Sleep-Watcher-<版本>.zip`，包含 arm64 / x86_64 通用可执行文件和闭环月亮应用图标。

## 开发验证

```zsh
swift run codex-sleep-tests
swift build
```

检查本机桌面端的 App Server 初始化与会话列表读取：

```zsh
swift run codex-sleep-tests --live-app-server
```

此诊断会输出实际使用的 CLI 路径，执行两次 `thread/list` 并解码结果，最后关闭由测试启动的 App Server；不会新建任务或触发休眠。

## 首次使用

1. 首次打开 App 会出现欢迎窗口；以后可从菜单栏月亮图标的“使用说明…”再次查看。
2. 点击“安装 / 更新 Codex Hooks”。
3. 在桌面端的 Hooks 管理界面审阅并信任标为 `Codex Sleep Watcher` 的六个 Hook：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PermissionRequest` 和 `Stop`。CLI 用户也可使用 `/hooks`。如果列表没有刷新，重启桌面端。
4. 点击菜单栏月亮图标，在可滚动列表中从最近 20 个 Codex 会话选择观测目标。App Server 负责发现会话，Hooks 负责实时更新状态。
5. 需要停止时点击“取消观测”，防休眠断言会立即释放。

App 启动后会立即监听 Hooks，无需先打开月亮面板。新版 Hook 还会在本机保存每个会话的最新状态，因此先运行 Codex、后打开 Watcher 时也能恢复已有任务，不必新建会话。状态含义如下：

- `运行中`：会话已经开始、收到新的用户任务或正在调用工具。
- `等待授权` / `等待输入`：Codex 正等待用户操作，Watcher 会继续保持 Mac 唤醒，不会启动休眠倒计时。
- `状态待确认`：最后一次 Hook 显示会话仍活动，但已超过 24 小时没有新事件；Watcher 会继续将其视为活动，避免误休眠。
- `本轮已完成`：当前回合结束，会话本身仍可继续使用和观测。
- `尚未收到事件`：App Server 已发现会话，但尚未收到该会话的 Hooks 事件。

从旧版本升级或移动 App 后，需要在 App 的最终位置再次点击“安装 / 更新 Codex Hooks”，并在 Codex 中重新审阅和信任。Hook 使用 App 内帮助程序的绝对路径，新增或路径发生变化的 Hook 在重新信任前可能不会运行。

## 桌面端更新后排查

0.1.3 更新了桌面端 CLI 自动发现，优先使用与桌面端匹配的内置运行时，避免旧的独立 CLI 干扰；Hook 帮助程序返回中性 JSON `{}`，兼容当前 Hook 输出格式，不批准工具、不阻止任务或要求任务继续。

- **找不到 Codex CLI**：确认 ChatGPT 或 Codex App 已完整安装在 `/Applications` 或 `~/Applications`，然后点击“刷新会话”。
- **App Server 已退出**：错误信息会附带退出码和可用的启动诊断。检查提示中的配置或安装问题，处理后刷新；Watcher 会重新启动连接，不需要新建任务。
- **响应超时**：单次响应等待最多 10 秒，失败后会清理旧的 App Server，下一次刷新重试。
- **会话出现但尚未收到事件**：确认任务在本机运行，更新并信任 Hooks，然后在已有任务中提交或继续工作。安装 Hooks 之前没有记录的事件无法恢复；已安装新版 Hooks 的任务可以先运行 Codex、后打开 Watcher。

列表同步失败时，Watcher 仍会继续监听本地 Hooks，并保留已恢复的 Hook 会话。状态不明确时不会据此触发自动休眠。协议和信任规则参见官方 [Codex App Server](https://learn.chatgpt.com/docs/app-server) 与 [Hooks](https://learn.chatgpt.com/docs/hooks) 文档。

## 安全与隐私

Hook 只转发并在本机保存事件名称、`session_id`、`turn_id`、工作目录和时间。工具不会转发或保存 prompt、助手回复和 transcript 内容；不连接外部网络。身份或事件状态不明确时采用安全失败，不触发休眠。

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
