# Codex Sleep Watcher 设计

日期：2026-07-11

## 目标

构建一个原生 macOS 菜单栏 App。App 列出当前运行中的多个 Codex 桌面会话，让用户选择一个会话作为唯一观测目标。观测期间阻止系统因空闲进入睡眠；只有目标会话停止执行后，才在可取消的倒计时结束后让 Mac 休眠。

目标会话停止包括：成功、失败、取消、进入等待授权状态、Codex 退出或崩溃。其他非目标会话的状态变化不得误触发休眠。

## 非目标

- 不读取 Codex 任务正文、助手回复或不稳定的 transcript 内容。
- 不读取或修改 Codex 的内部数据库格式。
- 不自动选择目标；每次休眠任务由用户明确选择一个会话。
- 不绕过合盖、低电量、系统管理策略或用户主动触发的休眠。
- 不在第一版提供 App Store 发布、云同步或远程控制。

## 方案选择

采用原生 Swift/SwiftUI 菜单栏 App，组合使用两个 Codex 官方扩展接口：

1. Codex App Server 的 `thread/list` 提供已保存会话、用户可见元数据和 runtime status，用于构建会话列表。
2. Codex 生命周期 Hooks 为每个事件提供稳定的 `session_id`、`turn_id` 和 `cwd`，用于确认目标会话的开始、停止和等待授权事件。

App Server 负责“发现和展示会话”，Hooks 负责“权威事件通知”。休眠判定始终以目标 `session_id` 为边界，不依赖窗口标题、侧边栏位置或当前前台窗口。

放弃纯辅助功能检测作为核心路径，因为 UI 结构和标题会变化，且难以在并行会话间建立稳定身份。放弃纯标记文件方案，因为任务被取消、Codex 崩溃或等待授权时，任务本身无法可靠写入标记。

## 用户体验

App 以菜单栏图标运行，不显示 Dock 图标。菜单包含：

- “选择观测目标”
- 运行中会话列表
- 当前目标名称、项目路径和状态
- 取消观测
- 立即休眠
- 休眠延迟：0、15、30、60 秒，默认 30 秒
- “保持屏幕常亮”开关，默认关闭
- “其他会话仍运行时延后休眠”开关，默认关闭
- “登录时启动”开关，默认关闭

运行中会话列表中的每行显示：

- 运行状态图标
- 会话名称
- 工作目录或项目名称
- 本轮开始时间
- 短会话 ID，用于同名会话消歧

用户可以选择一个已经运行的会话，也可以等待列表刷新后选择刚开始的会话。选择后，App 立即为目标建立防休眠断言；其他会话继续显示状态，但不会影响目标判定。

目标停止后进入倒计时，菜单栏图标和系统通知显示剩余时间。用户可以取消休眠。若目标会话在倒计时期间开始新一轮任务，App 自动取消倒计时并恢复观测。

当“其他会话仍运行时延后休眠”关闭时，目标停止即触发倒计时，即使其他会话仍运行。当该选项开启时，目标停止后进入“等待其他会话”状态，直到其他已知运行会话全部停止，再启动倒计时。

## 首次安装与 Hook 信任

App 首次运行时安装一个随 App 交付的轻量 Hook 转发器，并以可合并、可识别的方式注册全局 Codex hooks。安装过程保留用户已有 hook 配置，只添加带本工具所有者标识的条目；卸载时只删除本工具自己的条目。

App 注册以下事件：

- `UserPromptSubmit`：记录 `session_id` 和 `turn_id`，将该会话标记为运行中。
- `Stop`：将对应会话标记为已停止；包含成功、失败和取消后的停止路径。
- `PermissionRequest`：将对应目标标记为等待授权，并按“目标停止”处理。
- `SessionStart`：登记会话元数据，辅助首次发现和恢复。

Hook 只转发事件名称、`session_id`、`turn_id`、`cwd`、时间戳和必要的状态字段，不转发 prompt、`last_assistant_message` 或 transcript 路径。

非托管 Hook 必须由用户在 Codex 中审阅并信任。未完成信任前，App 显示设置未完成状态，不允许启动观测。Hook 功能被管理员策略关闭时，App 明确报告不兼容，不降级为不可靠的自动休眠。

## 会话发现与身份

`SessionDiscoveryService` 启动一个本地 Codex App Server 子进程，并通过 JSON-RPC 调用 `thread/list`。列表只保留 runtime status 表示正在执行的会话，同时合并 Hook 转发器已观察到的运行事件。

会话的唯一身份是 `session_id`。名称、工作目录、窗口位置和侧边栏顺序只用于展示，不能参与休眠判定。会话重命名不会改变目标。

App 启动时已经运行的会话由 `thread/list` 引导发现；App 启动后新运行的会话由 `UserPromptSubmit` 事件实时加入。若 App Server 元数据与 Hook 状态冲突，以较新的 Hook 事件为准。

若某个列表项缺少稳定 `session_id`、runtime status 不明确，或无法和事件流建立一致映射，App 将其标记为“状态不可确认”且禁止选择，避免误休眠。

## 事件传输

Hook 转发器通过仅限当前用户访问的 Unix domain socket 向菜单栏 App 发送单个 JSON 事件。Socket 位于 App 的 Application Support 目录，权限限制为当前用户。

App 未运行、Socket 不存在或发送失败时，转发器立即以成功状态退出，不阻塞 Codex，也不改变 Codex 的正常处理。Hook 不执行网络请求。

每个事件包含递增接收序号和事件时间。App 按 `(session_id, turn_id, event_name)` 去重，并忽略比当前会话状态更旧的事件。

## 状态机

全局状态流为：

`setupRequired -> idle -> targetSelected -> monitoring -> countdown -> sleeping -> idle`

可选分支：

`monitoring -> waitingForOtherSessions -> countdown`

- `setupRequired`：Hooks 未安装、未信任或被策略禁用。
- `idle`：未选择目标，不持有电源断言。
- `targetSelected`：已选择一个当前运行的 `session_id`。
- `monitoring`：目标正在执行，持有防空闲睡眠断言。
- `waitingForOtherSessions`：目标已停止，但设置要求等待其他会话；继续持有断言。
- `countdown`：休眠倒计时；继续持有断言，避免系统提前睡眠。
- `sleeping`：释放断言并请求系统休眠。

在 `targetSelected`、`monitoring`、`waitingForOtherSessions` 或 `countdown` 中执行“取消观测”，均回到 `idle` 并释放断言。

目标会话在 `countdown` 或 `waitingForOtherSessions` 期间收到新的 `UserPromptSubmit` 时，恢复到 `monitoring`。非目标会话的 `Stop`、`PermissionRequest` 或失败事件不会直接启动倒计时。

## 电源管理与休眠

`PowerAssertionController` 使用 IOKit 创建防空闲睡眠断言。默认允许显示器熄灭；启用“保持屏幕常亮”后额外创建显示器防休眠断言。所有断言在取消观测、回到 `idle`、App 正常退出时释放；App 崩溃后由 macOS 清理进程断言。

`SystemSleeper` 将系统休眠封装为可替换接口。生产实现调用 macOS 电源管理接口；若系统拒绝休眠请求，显示错误并回到 `idle`，不循环重试，也不修改永久电源设置。

## 组件边界

- `AppStateController`：状态机、目标选择和用户操作入口。
- `AppServerClient`：管理 Codex App Server 子进程和 JSON-RPC 通信。
- `SessionDiscoveryService`：调用 `thread/list`，合并会话元数据和事件状态。
- `HookInstaller`：合并安装、验证和卸载本工具的 Codex Hooks。
- `HookEventReceiver`：管理 Unix socket、校验和去重 Hook 事件。
- `SessionRegistry`：以 `session_id` 保存当前会话状态及展示信息。
- `PowerAssertionController`：创建和释放系统、显示器电源断言。
- `SleepCountdownController`：管理倒计时、取消和同目标恢复。
- `SystemSleeper`：请求系统休眠。
- `NotificationController`：权限、倒计时通知和错误通知。
- `SettingsStore`：保存延迟、屏幕常亮、其他会话策略和登录启动偏好。
- `MenuBarView`：展示会话列表、目标和操作，不包含事件或电源逻辑。

组件通过协议注入。状态机不直接依赖 App Server、Hook 进程、IOKit 或真实休眠调用，从而可以安全测试。

## 权限与隐私

- Codex Hook 信任：必需；由用户审阅并确认本工具注册的 Hook。
- 通知权限：建议；拒绝后菜单栏倒计时仍可使用。
- 登录项权限：仅在用户启用“登录时启动”时请求。
- 不需要 macOS 辅助功能权限。
- App 和 Hook 不需要外部网络权限，不上传遥测，不保存 Codex 任务内容。

## 错误处理

- Codex 未安装或 App Server 无法启动：禁用会话选择并显示修复指引。
- Hooks 未信任、被禁用或被管理策略阻止：进入 `setupRequired`，不观测、不休眠。
- Hook socket 暂时中断：标记事件流不可用，释放电源断言并取消观测，不根据过期状态休眠。
- 无法建立防休眠断言：停止本次观测并通知用户。
- 目标会话身份丢失或状态冲突无法消解：取消休眠并通知用户，采用安全失败。
- 休眠请求失败：显示错误并回到 `idle`，不循环重试。
- App 被退出：断言随进程清理，不留下永久系统配置。

## 测试策略

自动化测试绝不调用真实系统休眠。

- App Server 解析测试：覆盖分页、runtime status、缺失字段和错误响应。
- Hook 事件测试：覆盖 `UserPromptSubmit`、`Stop`、`PermissionRequest`、乱序、重复和不同 session。
- 会话选择测试：同名会话通过 `session_id` 正确隔离。
- 状态机测试：覆盖目标完成、失败、取消、等待授权、Codex 退出和目标重新开始。
- 多会话测试：非目标结束不休眠；目标结束按设置立即倒计时或等待其他会话。
- 电源断言测试：只在观测、等待其他会话和倒计时期间持有，所有退出路径均释放。
- 倒计时测试：时间到只调用一次假的 `SystemSleeper`；取消或目标重启后不调用。
- Hook 安装测试：保留已有配置，只增删带本工具所有者标识的条目。
- 权限和错误测试：事件流、Hook 信任、App Server 或断言错误时均不休眠。
- 手动验收：在真实 Codex 桌面 App 中并行启动至少三个会话，分别选择其中一个，验证其他会话停止不会触发休眠。

## 验收标准

1. 菜单栏列出多个当前运行的 Codex 会话，并显示足以让用户区分的名称、项目和短 ID。
2. 用户可以选择恰好一个运行会话作为目标。
3. 观测和休眠判定以稳定 `session_id` 为准，不受重命名、窗口切换或列表排序影响。
4. 只有目标的停止、失败、取消或等待授权事件能进入休眠流程。
5. 非目标会话结束不会误触发休眠。
6. 用户可选择目标完成后立即倒计时，或等待其他会话全部停止。
7. 目标在倒计时期间重新开始时，自动取消休眠并恢复观测。
8. 观测期间 Mac 不因空闲睡眠；屏幕默认允许熄灭。
9. 用户取消观测或倒计时后不会休眠。
10. Hook、事件流、会话身份或电源断言异常时采用安全失败，不触发休眠。
11. 自动化测试不会让开发机器真实休眠。
12. 项目可生成一个可双击运行的本地 `.app`，并附带安装、Hook 信任和卸载说明。

## 项目与交付

项目位于 `/Users/xhuandy/Documents/Codex/projects/codex-sleep-watcher`。第一版使用系统自带 Swift、SwiftUI、AppKit、IOKit 和 Foundation，不引入第三方运行时依赖。

交付物包括：

- macOS 菜单栏 App 源代码
- Hook 转发器源代码
- 单元测试与集成测试
- 构建和打包脚本
- 可双击运行的本地 `.app`
- 中文安装、Hook 信任、使用和卸载说明

## 官方接口依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server#api-overview)：`thread/list` 可枚举线程并返回 runtime status；`turn/completed` 区分 completed、interrupted 和 failed。
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks#common-input-fields)：Hooks 在桌面 App、CLI 和 IDE 扩展中运行。公共输入字段包含 `session_id` 和 `cwd`，turn 范围事件包含 `turn_id`。
- [Codex Hooks 事件](https://learn.chatgpt.com/docs/hooks#hooks)：`UserPromptSubmit`、`PermissionRequest` 和 `Stop` 均为受支持的 turn 范围 Hook 事件；非托管 Hook 需要用户审阅并信任。
