# Codex Sleep Watcher

一个原生 macOS 菜单栏工具：从多个正在运行的 Codex 会话中选择一个目标，在目标运行期间防止 Mac 空闲休眠，并在目标完成、取消或等待授权后按设定休眠。

## 构建

```zsh
./Scripts/package_app.sh
```

生成的 App 位于 `dist/Codex Sleep Watcher.app`。可直接双击，或复制到 `/Applications`。

## 首次使用

1. 打开 App，点击“安装 / 更新 Codex Hooks”。
2. 在 Codex 的 Hooks 管理界面审阅并信任标为 `Codex Sleep Watcher` 的四个 Hook；如果列表没有刷新，重启 Codex。
3. 启动一个或多个 Codex 任务，在菜单栏中点击刷新并选择观测目标。
4. 需要停止时点击“取消观测”，防休眠断言会立即释放。

移动 App 后需要再次点击“安装 / 更新 Codex Hooks”，因为 Hook 使用 App 内帮助程序的绝对路径。

## 安全与隐私

Hook 只转发事件名称、`session_id`、`turn_id`、工作目录和时间。工具不会转发或保存 prompt、助手回复和 transcript 内容；不连接外部网络。身份或事件状态不明确时采用安全失败，不触发休眠。

开发调试时可使用：

```zsh
open "dist/Codex Sleep Watcher.app" --args --disable-real-sleep
```

该模式只记录休眠请求，不会真的使 Mac 休眠。

## 卸载

取消观测，在菜单中点击“卸载 Codex Hooks”，退出并删除 App。
