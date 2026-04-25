# Vibe Pulse 技术架构文档

## 1. 架构总览

Vibe Pulse 是一款 macOS 原生桌面应用（Swift + SwiftUI），专注于 Claude Code 会话的**智能通知**。与 Vibe Notch 的"全量监控 + 聊天交互"定位不同，Vibe Pulse 的核心是**事件捕获 -> 智能分类 -> 分级通知**这条管线。

### 1.1 架构图

```
+------------------------------------------------------------------+
|                        macOS Notch UI Layer                       |
|  +------------------+  +------------------+  +-----------------+  |
|  | NotificationCard |  | StatusIndicator  |  | TimelineView    |  |
|  | (通知卡片)        |  | (状态小圆点)     |  | (历史时间线)    |  |
|  +--------+---------+  +--------+---------+  +--------+--------+  |
|           |                     |                     |           |
+-----------+---------------------+---------------------+-----------+
            |                     |                     |
    +-------v---------------------v---------------------v-------+
    |                    NotchViewModel                          |
    |              (UI 状态管理, 复用 Vibe Notch)                |
    +---------------------------+-------------------------------+
                                |
    +---------------------------v-------------------------------+
    |                   NotificationQueue                       |
    |           (通知队列 / 去重 / 节流 / 5s 合并)              |
    +---------------------------+-------------------------------+
                                |
    +---------------------------v-------------------------------+
    |                   EventClassifier                         |
    |         (事件分类 + 通知分级, Vibe Pulse 核心模块)        |
    +---------------------------+-------------------------------+
                                |
    +---------------------------v-------------------------------+
    |                    EventCapture                           |
    |          (事件捕获: Hook 事件 + Bash stdout 分析)         |
    +-------------+-------------------+-------------------------+
                  |                   |
    +-------------v------+  +---------v-----------+
    | HookSocketServer   |  | BashOutputAnalyzer  |
    | (Unix Socket, 复用)|  | (stdout/exit code)  |
    +-------------+------+  +---------+-----------+
                  |                   |
    +-------------v-------------------v-----------+
    |          claude-pulse-hook.py                |
    |     (Hook 脚本, 基于 claude-island-state.py  |
    |      扩展 Bash stdout/exit code 捕获)        |
    +---------------------------------------------+
                  |
    +-------------v-------------------------------+
    |          Claude Code Hook System             |
    |  (PreToolUse / PostToolUse / Stop / ...)     |
    +---------------------------------------------+
```

### 1.2 分层设计

| 层级 | 职责 | 复用/新建 |
|------|------|-----------|
| **Hook 脚本层** | 从 Claude Code 捕获原始事件并传递额外数据 | 改造（基于 claude-island-state.py） |
| **EventCapture 层** | 接收 Hook 事件，解析 Bash stdout | 部分复用 HookSocketServer |
| **EventClassifier 层** | 将原始事件分类为 7 种 PulseEvent，并分配通知级别 | **全新** |
| **NotificationQueue 层** | 通知队列管理、去重、节流、合并 | **全新** |
| **State 层** | 会话状态管理、通知历史持久化 | 复用 SessionStore actor 模式 |
| **UI 层** | NotchView 通知卡片、时间线、状态指示器 | 改造（精简 Vibe Notch UI） |

---

## 2. 模块设计

### 2.1 EventCapture 层

EventCapture 负责从两个来源捕获原始事件：

#### 来源 1: Claude Code Hook 事件（复用）

直接复用 Vibe Notch 的 `HookSocketServer`，通过 Unix Domain Socket (`/tmp/claude-pulse.sock`) 接收 Hook 脚本发送的 JSON 事件。

关键复用组件：
- `HookSocketServer` -- 仅修改 socket 路径
- `HookEvent` 数据结构 -- 扩展新增字段
- `HookInstaller` -- 修改脚本名和注册的事件类型

#### 来源 2: Bash stdout / exit code 分析（新建）

这是 Vibe Pulse 的核心差异化数据来源。Hook 脚本在 `PostToolUse` 和 `PostToolUseFailure` 阶段捕获 Bash 工具的 stdout 和 exit code，发送到 App 端进行语义分析。

```swift
/// 分析 Bash 工具的输出内容，提取结构化信号
actor BashOutputAnalyzer {
    /// 从 Bash stdout + exit code 中提取事件信号
    func analyze(stdout: String, exitCode: Int, toolName: String) -> BashSignal? {
        // 匹配测试框架输出模式
        // 匹配构建错误模式
        // 匹配反复失败模式（需要历史上下文）
    }
}

enum BashSignal {
    case testPassed(summary: String)       // "42 passed, 0 failed"
    case testFailed(summary: String)       // "3 failed" / assertion error
    case buildFailed(summary: String)      // 编译错误
    case repeatedFailure(count: Int)       // 同一命令连续失败 N 次
}
```

`BashOutputAnalyzer` 使用**正则模式匹配**而非 LLM 推理，保证延迟在 1ms 以内。匹配规则覆盖主流测试框架：

| 框架 | 通过模式 | 失败模式 |
|------|---------|---------|
| pytest | `X passed` | `X failed`, `FAILED`, `ERROR` |
| Jest | `Tests: X passed` | `Tests: X failed` |
| XCTest | `Test Suite.*passed` | `Test Suite.*failed` |
| Go test | `ok` + `PASS` | `FAIL` |
| cargo test | `test result: ok` | `test result: FAILED` |
| 通用构建 | -- | `error:`, `BUILD FAILED`, exit code != 0 |

#### EventCapture 聚合器

```swift
/// 聚合 Hook 事件和 Bash 分析结果
actor EventCaptureService {
    private let socketServer: HookSocketServer
    private let bashAnalyzer: BashOutputAnalyzer

    /// 输出统一的原始事件流
    let rawEventStream: AsyncStream<RawCapturedEvent>
}
```

### 2.2 EventClassifier 层（核心模块）

EventClassifier 是 Vibe Pulse 的核心差异化模块。它将原始事件分类为 7 种 `PulseEvent`，并分配通知级别。

```swift
/// 事件分类器 -- Vibe Pulse 的核心逻辑
actor EventClassifier {
    /// 最近事件历史（用于检测"反复失败"等时序模式）
    private var recentEvents: RingBuffer<ClassifiedEvent>

    /// 将原始事件分类为 PulseEvent
    func classify(_ raw: RawCapturedEvent, session: SessionState) -> PulseEvent?
}
```

#### 分类规则

| PulseEvent | 触发条件 | 通知级别 |
|-----------|---------|---------|
| `testPassed` | BashSignal.testPassed | `.silent` |
| `testFailed` | BashSignal.testFailed | `.alert` |
| `buildFailed` | BashSignal.buildFailed 或 exit code != 0 且 stdout 包含编译错误关键词 | `.alert` |
| `taskCompleted` | Hook event == "Stop" 且 phase 从 processing 转为 waitingForInput | `.remind` |
| `repeatedFailure` | 同一 session 中，同类失败事件在 60s 内出现 >= 3 次 | `.alert` |
| `claudeAsking` | Hook event == "Notification" 且 notification_type == "idle_prompt" | `.remind` |
| `permissionRequest` | Hook event == "PermissionRequest" | `.remind` |

#### 通知级别定义

```swift
enum NotificationLevel: Int, Comparable {
    case silent = 0   // 仅记录到时间线，无视觉/声音打扰
    case remind = 1   // 刘海弹出通知卡片 + 轻柔提示音
    case alert  = 2   // 刘海弹出 + 强提示音 + 持续显示直到用户确认

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

#### 级别对应的 UI 行为

| 级别 | 刘海弹出 | 声音 | 持续时间 | 状态圆点颜色 |
|------|---------|------|---------|------------|
| `silent` | 不弹出 | 无 | -- | 不变 |
| `remind` | 弹出卡片 | 轻柔提示音（系统 Tink） | 5s 后自动收起 | 蓝色闪烁一次 |
| `alert` | 弹出卡片 | 强提示音（系统 Sosumi） | 常驻直到点击 | 红色持续 |

### 2.3 NotificationQueue 层

NotificationQueue 管理通知的排队、去重和节流，防止通知风暴。

```swift
/// 通知队列管理器
actor NotificationQueue {
    /// 待展示的通知队列（优先级排序）
    private var queue: PriorityQueue<NotificationCard>

    /// 去重窗口内的事件指纹 -> 最后时间戳
    private var deduplicationWindow: [String: Date]

    /// 节流窗口（同类事件 5s 内合并）
    private let throttleInterval: TimeInterval = 5.0

    /// 入队一个新通知，返回是否实际入队（可能被去重/合并）
    func enqueue(_ event: PulseEvent, session: SessionState) -> NotificationCard?

    /// 取出下一个待展示的通知
    func dequeue() -> NotificationCard?

    /// 当前队列深度
    var pendingCount: Int
}
```

#### 去重策略

事件指纹 = `sessionId + eventType + truncatedContent(前 64 字符)`。5 秒窗口内指纹相同的事件合并为一个，计数累加：

```
"3 tests failed" (10:00:01)
"3 tests failed" (10:00:03)  -> 合并为 "3 tests failed (x2)"
"5 tests failed" (10:00:04)  -> 内容不同，独立通知
```

#### 优先级排序

队列按 `(NotificationLevel.rawValue DESC, timestamp ASC)` 排序。alert 级别优先，同级别先到先展示。

### 2.4 UI 层

#### 2.4.1 NotchView 改造方案

Vibe Pulse 的 NotchView 在 Vibe Notch 基础上进行**精简改造**：

- **移除**：ChatView、ClaudeInstancesView（完整聊天和实例列表）
- **保留**：NotchShape、刘海几何计算、动画系统、鼠标事件处理
- **新增**：NotificationCardView、TimelineView、StatusIndicatorView

```
NotchView (改造)
  |
  +-- headerRow (保留, 改造)
  |     +-- StatusIndicator (新增, 替代 ClaudeCrabIcon)
  |     +-- 当前通知摘要文字 (新增)
  |
  +-- contentView (改造)
        +-- NotificationCardView (新增, 替代 instances/chat)
        +-- TimelineView (新增, 展开后显示)
```

#### 2.4.2 通知卡片 UI (NotificationCardView)

通知卡片是 Vibe Pulse 的核心 UI 组件，在刘海区展示精简信息：

```
+------------------------------------------+
| [icon] Test Failed                 10:03 |
| 3 tests failed in AuthService      [>]  |
+------------------------------------------+
   ^icon    ^标题        ^时间    ^跳转按钮
```

- 宽度：刘海宽度 + 扩展宽度（约 320pt）
- 高度：单卡片 56pt，多卡片堆叠
- 点击 `[>]` 按钮执行一键跳回终端
- 卡片左侧 icon 颜色编码事件类型（绿色=通过，红色=失败，蓝色=提问，橙色=权限）

#### 2.4.3 一键跳回终端

复用 Vibe Notch 的 `TmuxController.switchToPane()` 和 `TerminalVisibilityDetector`：

```swift
/// 跳转到对应会话的终端
func jumpToTerminal(session: SessionState) async {
    // 1. 尝试 tmux 跳转（复用 TmuxController）
    if session.isInTmux, let pid = session.pid {
        if let target = await TmuxController.shared.findTmuxTarget(forClaudePid: pid) {
            await TmuxController.shared.switchToPane(target: target)
            // 激活终端应用
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            return
        }
    }
    // 2. 降级：通过 PID 查找终端窗口并聚焦
    TerminalFocusHelper.focusByPid(session.pid)
}
```

#### 2.4.4 通知历史时间线 (TimelineView)

展开刘海后，显示最近 50 条通知的时间线：

```
+------------------------------------------+
|  Timeline                          Clear |
|------------------------------------------|
|  10:15  Task Completed    project-a      |
|  10:12  Test Passed (x3)  project-a      |
|  10:08  Build Failed      project-b      |
|  10:03  Test Failed       project-a      |
|  09:55  Permission Req    project-b      |
|  ...                                     |
+------------------------------------------+
```

- 每条记录包含：时间、事件类型 icon、摘要文字、项目名
- 支持滚动
- `Clear` 按钮清空历史

#### 2.4.5 会话状态指示器 (StatusIndicator)

常驻在刘海区域的小圆点（替代 Vibe Notch 的 ClaudeCrabIcon），用颜色表示当前状态：

| 颜色 | 状态 |
|------|------|
| 灰色（静态） | 无活跃会话 |
| 蓝色（脉冲动画） | 有会话正在 processing |
| 绿色（静态） | 所有会话 idle/waitingForInput |
| 橙色（脉冲动画） | 有会话等待权限审批 |
| 红色（快速闪烁） | alert 级别通知未确认 |

### 2.5 State 层

复用 Vibe Notch 的 **actor 模式**，新增通知相关状态：

```swift
/// Vibe Pulse 的中央状态管理器
/// 基于 Vibe Notch 的 SessionStore actor 模式
actor PulseStore {
    static let shared = PulseStore()

    // 复用: 会话状态（从 SessionStore 精简而来）
    private var sessions: [String: SessionState]

    // 新增: 通知历史
    private var notificationHistory: [NotificationRecord]

    // 新增: 事件分类器
    private let classifier: EventClassifier

    // 新增: 通知队列
    private let notificationQueue: NotificationQueue

    // 复用: Combine publisher 模式
    private let stateSubject = CurrentValueSubject<PulseState, Never>(.empty)
    nonisolated var statePublisher: AnyPublisher<PulseState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// 统一事件处理入口（复用 SessionStore.process() 模式）
    func process(_ event: PulseStoreEvent) async { ... }
}
```

`PulseState` 是发布给 UI 的聚合状态快照：

```swift
struct PulseState {
    let sessions: [SessionState]        // 活跃会话
    let currentCard: NotificationCard?  // 当前展示的通知卡片
    let pendingCount: Int               // 待处理通知数
    let history: [NotificationRecord]   // 通知历史（最近 50 条）
    let aggregateStatus: AggregateStatus // 聚合状态（用于指示器颜色）

    static let empty = PulseState(sessions: [], currentCard: nil, pendingCount: 0, history: [], aggregateStatus: .inactive)
}
```

---

## 3. 核心数据模型

### 3.1 PulseEvent

```swift
/// Vibe Pulse 的 7 种事件类型
enum PulseEventType: String, Codable {
    case testPassed         // 测试通过
    case testFailed         // 测试失败
    case buildFailed        // 构建失败
    case taskCompleted      // 任务完成（Claude 停止并等待输入）
    case repeatedFailure    // 反复失败（同类失败 >=3 次/60s）
    case claudeAsking       // Claude 向用户提问
    case permissionRequest  // 权限请求
}

struct PulseEvent: Identifiable, Sendable {
    let id: UUID
    let type: PulseEventType
    let sessionId: String
    let projectName: String
    let summary: String              // 简短摘要，如 "3 tests failed"
    let detail: String?              // 详细信息（stdout 片段等）
    let level: NotificationLevel
    let timestamp: Date
    let mergeCount: Int              // 合并计数（去重后 > 1）
}
```

### 3.2 NotificationCard

```swift
/// 展示在刘海区的通知卡片
struct NotificationCard: Identifiable, Sendable {
    let id: UUID
    let event: PulseEvent
    let displayDuration: TimeInterval? // nil = 常驻直到确认
    let actions: [CardAction]

    /// 卡片的 icon 和颜色
    var icon: String {
        switch event.type {
        case .testPassed:        return "checkmark.circle.fill"
        case .testFailed:        return "xmark.circle.fill"
        case .buildFailed:       return "hammer.circle.fill"
        case .taskCompleted:     return "checkmark.seal.fill"
        case .repeatedFailure:   return "exclamationmark.triangle.fill"
        case .claudeAsking:      return "questionmark.bubble.fill"
        case .permissionRequest: return "lock.shield.fill"
        }
    }

    var iconColor: Color {
        switch event.level {
        case .silent: return .gray
        case .remind: return .blue
        case .alert:  return .red
        }
    }
}

enum CardAction: Sendable {
    case jumpToTerminal    // 跳转到终端
    case approve           // 批准权限
    case deny              // 拒绝权限
    case dismiss           // 关闭卡片
}
```

### 3.3 NotificationRecord

```swift
/// 通知历史记录（持久化到时间线）
struct NotificationRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let eventType: PulseEventType
    let sessionId: String
    let projectName: String
    let summary: String
    let level: NotificationLevel
    let timestamp: Date
    let acknowledged: Bool       // 用户是否已确认
}
```

### 3.4 SessionState（精简复用）

从 Vibe Notch 的 `SessionState` 精简而来，移除聊天相关字段：

```swift
struct SessionState: Equatable, Identifiable, Sendable {
    // 保留: 身份和基础元数据
    let sessionId: String
    let cwd: String
    let projectName: String
    var pid: Int?
    var tty: String?
    var isInTmux: Bool
    var phase: SessionPhase

    // 保留: 时间戳
    var lastActivity: Date
    var createdAt: Date

    // 移除: chatItems, toolTracker, subagentState, conversationInfo
    // 移除: needsClearReconciliation
    // 这些在 Vibe Pulse 中不需要，事件流由 EventClassifier 处理
}
```

### 3.5 RawCapturedEvent

```swift
/// 从 Hook 和 Bash 分析捕获的原始事件
struct RawCapturedEvent: Sendable {
    let hookEvent: HookEvent
    let bashSignal: BashSignal?  // 仅 Bash 工具有此信号
    let timestamp: Date
}
```

---

## 4. 与 Vibe Notch 的关系

### 4.1 复用清单

| 组件 | 路径 | 复用方式 |
|------|------|---------|
| `HookSocketServer` | Services/Hooks/ | **直接复用**，仅改 socket 路径常量 |
| `HookEvent` | Services/Hooks/ | **扩展复用**，新增 `stdout`, `exitCode`, `bashCommand` 字段 |
| `HookInstaller` | Services/Hooks/ | **改造复用**，修改脚本名、注册事件、版本检测逻辑 |
| `SessionPhase` | Models/ | **直接复用** |
| `NotchShape` | UI/Components/ | **直接复用** |
| `NotchGeometry` | UI/Components/ | **直接复用** |
| `NotchViewModel` | Core/ | **精简改造**，移除 chat/menu 相关逻辑 |
| `TmuxController` | Services/Tmux/ | **直接复用** |
| `TmuxTargetFinder` | Services/Tmux/ | **直接复用** |
| `ProcessTreeBuilder` | Services/ | **直接复用** |
| `TerminalVisibilityDetector` | Services/ | **直接复用** |
| `AppDelegate` + Window 管理 | App/ | **直接复用** |
| `EventMonitors` | Core/ | **直接复用** |
| `ScreenSelector` | Core/ | **直接复用** |

### 4.2 新建清单

| 组件 | 职责 |
|------|------|
| `EventClassifier` | 事件分类 + 通知分级（核心） |
| `BashOutputAnalyzer` | Bash stdout 正则匹配分析 |
| `NotificationQueue` | 通知队列 / 去重 / 节流 |
| `PulseStore` | 中央状态管理器（基于 actor 模式） |
| `EventCaptureService` | 事件捕获聚合 |
| `NotificationCardView` | 通知卡片 UI |
| `TimelineView` | 通知历史时间线 UI |
| `StatusIndicatorView` | 状态小圆点 UI |
| `claude-pulse-hook.py` | Hook 脚本（扩展版） |

### 4.3 移除清单（Vibe Notch 中有但 Vibe Pulse 不需要）

| 组件 | 原因 |
|------|------|
| `ChatView` / `ChatHistoryItem` | Vibe Pulse 不展示完整聊天 |
| `ConversationParser` | 不解析完整 JSONL 对话 |
| `ClaudeInstancesView` | 不展示实例列表 |
| `NotchMenuView` | 精简菜单，不需要完整设置面板 |
| `ToolTracker` / `SubagentState` | 工具追踪由 EventClassifier 替代 |
| `InterruptWatcherManager` | 中断检测归入 EventCapture 层 |

---

## 5. 目录结构

```
VibePulse/
├── App/
│   ├── VibePulseApp.swift              # @main 入口
│   ├── AppDelegate.swift               # 窗口管理 (复用)
│   └── AppSettings.swift               # 用户配置
│
├── Core/
│   ├── NotchViewModel.swift            # UI 状态管理 (精简改造)
│   ├── NotchGeometry.swift             # 刘海几何计算 (复用)
│   └── EventMonitors.swift             # 鼠标事件监听 (复用)
│
├── Models/
│   ├── PulseEvent.swift                # 7 种事件类型 + NotificationLevel
│   ├── NotificationCard.swift          # 通知卡片模型
│   ├── NotificationRecord.swift        # 通知历史记录
│   ├── SessionState.swift              # 会话状态 (精简版)
│   ├── SessionPhase.swift              # 会话阶段枚举 (复用)
│   ├── PulseState.swift                # UI 聚合状态快照
│   └── BashSignal.swift                # Bash 分析信号枚举
│
├── Services/
│   ├── Capture/
│   │   ├── EventCaptureService.swift   # 事件捕获聚合器
│   │   └── BashOutputAnalyzer.swift    # Bash stdout 正则分析
│   │
│   ├── Classifier/
│   │   ├── EventClassifier.swift       # 事件分类 + 分级 (核心)
│   │   └── PatternRules.swift          # 测试框架匹配规则库
│   │
│   ├── Notification/
│   │   ├── NotificationQueue.swift     # 通知队列 + 去重 + 节流
│   │   └── SoundPlayer.swift           # 通知声音播放
│   │
│   ├── Hooks/
│   │   ├── HookSocketServer.swift      # Unix Socket 服务器 (复用)
│   │   └── HookInstaller.swift         # Hook 安装器 (改造)
│   │
│   ├── State/
│   │   └── PulseStore.swift            # 中央 actor 状态管理器
│   │
│   └── Terminal/
│       ├── TmuxController.swift        # Tmux 操作 (复用)
│       ├── TmuxTargetFinder.swift      # Tmux 窗格查找 (复用)
│       ├── ProcessTreeBuilder.swift    # 进程树构建 (复用)
│       └── TerminalFocusHelper.swift   # 终端聚焦辅助 (新建)
│
├── UI/
│   ├── Views/
│   │   ├── NotchView.swift             # 主视图 (改造)
│   │   ├── NotificationCardView.swift  # 通知卡片 (新建)
│   │   ├── TimelineView.swift          # 历史时间线 (新建)
│   │   └── StatusIndicatorView.swift   # 状态小圆点 (新建)
│   │
│   ├── Components/
│   │   ├── NotchShape.swift            # 刘海形状 (复用)
│   │   ├── EventIcon.swift             # 事件类型 icon (新建)
│   │   └── PulseAnimation.swift        # 脉冲动画 (新建)
│   │
│   └── Styles/
│       └── PulseColors.swift           # 颜色常量
│
├── Resources/
│   ├── claude-pulse-hook.py            # Hook 脚本 (改造)
│   └── Assets.xcassets
│
└── VibePulse.entitlements
```

---

## 6. Hook 脚本设计

`claude-pulse-hook.py` 基于 `claude-island-state.py` 改造，核心新增是在 `PostToolUse` / `PostToolUseFailure` 阶段捕获 Bash 工具的额外数据。

### 6.1 新增捕获的字段

| 字段 | 来源 | 用途 |
|------|------|------|
| `stdout` | `data.get("tool_result", {}).get("stdout")` | Bash 输出文本，用于测试/构建结果分析 |
| `stderr` | `data.get("tool_result", {}).get("stderr")` | 错误输出 |
| `exit_code` | `data.get("tool_result", {}).get("exitCode")` | 进程退出码 |
| `bash_command` | `tool_input.get("command")` | 执行的 Bash 命令 |

### 6.2 关键修改点

```python
# claude-pulse-hook.py 中的关键差异

SOCKET_PATH = "/tmp/claude-pulse.sock"

# PostToolUse 阶段 -- 捕获 Bash stdout/exit code
elif event == "PostToolUse":
    state["status"] = "processing"
    state["tool"] = data.get("tool_name")
    state["tool_input"] = tool_input

    tool_use_id_from_event = data.get("tool_use_id")
    if tool_use_id_from_event:
        state["tool_use_id"] = tool_use_id_from_event

    # --- Vibe Pulse 新增: 捕获 Bash 工具输出 ---
    tool_name = data.get("tool_name", "")
    if tool_name in ("Bash", "bash", "execute_command"):
        tool_result = data.get("tool_result", {})
        state["stdout"] = _truncate(tool_result.get("stdout", ""), 2048)
        state["stderr"] = _truncate(tool_result.get("stderr", ""), 1024)
        state["exit_code"] = tool_result.get("exitCode")
        state["bash_command"] = tool_input.get("command", "")

# PostToolUseFailure 阶段 -- 同样捕获
elif event == "PostToolUseFailure":
    state["status"] = "processing"
    state["tool"] = data.get("tool_name")
    state["tool_input"] = tool_input
    state["tool_error"] = data.get("error") or data.get("message")

    tool_use_id_from_event = data.get("tool_use_id")
    if tool_use_id_from_event:
        state["tool_use_id"] = tool_use_id_from_event

    # --- Vibe Pulse 新增: 捕获失败输出 ---
    tool_name = data.get("tool_name", "")
    if tool_name in ("Bash", "bash", "execute_command"):
        tool_result = data.get("tool_result", {})
        state["stdout"] = _truncate(tool_result.get("stdout", ""), 2048)
        state["stderr"] = _truncate(tool_result.get("stderr", ""), 1024)
        state["exit_code"] = tool_result.get("exitCode")
        state["bash_command"] = tool_input.get("command", "")


def _truncate(text, max_len):
    """截断长文本，保留末尾（通常包含测试结果摘要）"""
    if not text or len(text) <= max_len:
        return text
    return "...\n" + text[-max_len:]
```

### 6.3 注册的 Hook 事件

Vibe Pulse 需要注册的 Hook 事件（相比 Vibe Notch 的精简子集）：

| 事件 | 用途 |
|------|------|
| `PostToolUse` | 捕获 Bash stdout/exit code（核心） |
| `PostToolUseFailure` | 捕获失败的工具输出 |
| `PermissionRequest` | 权限请求通知（保留交互能力） |
| `Stop` | 检测任务完成 |
| `StopFailure` | 检测 API 错误导致的停止 |
| `Notification` | 捕获 idle_prompt（Claude 提问） |
| `SessionStart` | 追踪新会话 |
| `SessionEnd` | 清理会话 |

相比 Vibe Notch **移除**了：`PreToolUse`（不需要预先跟踪工具）、`UserPromptSubmit`（不需要跟踪用户输入）、`SubagentStart/Stop`（不需要子 agent 追踪）、`PreCompact/PostCompact`（不关注压缩状态）、`PermissionDenied`（不需要）。

---

## 7. 关键设计决策

### 决策 1: 正则匹配 vs LLM 推理进行事件分类

**选择**: 正则匹配

| 方案 | 优点 | 缺点 |
|------|------|------|
| 正则匹配 | 延迟 <1ms，零成本，离线可用，确定性输出 | 需要维护规则库，无法处理非标准输出 |
| 本地 LLM | 语义理解能力强 | 延迟 100ms+，资源消耗大，macOS 集成复杂 |
| API 调用 | 最强理解能力 | 延迟 1s+，有成本，依赖网络 |

**理由**: 测试框架和构建工具的输出高度结构化，正则匹配完全够用。Vibe Pulse 作为实时通知工具，延迟敏感度极高，1ms 的分类延迟远优于其他方案。规则库随版本迭代可以逐步扩充。

### 决策 2: 独立 App vs Vibe Notch 插件

**选择**: 独立 App

| 方案 | 优点 | 缺点 |
|------|------|------|
| 独立 App | 职责清晰，可独立迭代，安装/卸载互不影响 | 代码复用需要手动同步 |
| Vibe Notch 插件 | 代码共享，单一安装入口 | 架构耦合，Vibe Notch 的聊天功能拖累性能 |

**理由**: Vibe Pulse 和 Vibe Notch 的用户画像不同。Vibe Notch 面向想要全量监控和聊天交互的用户，Vibe Pulse 面向只需要智能通知的用户。独立 App 保证各自的简洁性。通过源码级复用（复制 + 精简）保持一致性，复用代码使用相同的 Swift module 约定。

### 决策 3: 独立 Socket 路径 vs 共享 Vibe Notch Socket

**选择**: 独立路径 `/tmp/claude-pulse.sock`

**理由**: 允许 Vibe Pulse 和 Vibe Notch 同时运行而不冲突。用户可以同时使用两者：Vibe Notch 提供完整监控，Vibe Pulse 提供精简通知。Hook 脚本需要独立安装，但共享 `settings.json` 中的 hooks 配置（Claude Code 支持同一事件注册多个 hook）。

### 决策 4: 通知历史存储方式

**选择**: 内存 + 轻量 JSON 文件

| 方案 | 优点 | 缺点 |
|------|------|------|
| 纯内存 | 最简实现 | App 重启后历史丢失 |
| SQLite | 查询灵活，可存大量历史 | 引入数据库依赖，过度设计 |
| JSON 文件 | 简单，可持久化，人类可读 | 不适合大量数据查询 |

**理由**: 通知历史只保留最近 50 条，数据量极小。运行时在内存中操作（`[NotificationRecord]`），App 进入后台或定时（每 30s）写入 `~/Library/Application Support/VibePulse/history.json`。启动时加载。对 50 条记录而言，JSON 序列化/反序列化的开销可忽略。

### 决策 5: stdout 截断策略 -- 保留尾部

**选择**: 保留尾部 2048 字符

**理由**: 测试框架的结果摘要（passed/failed 计数、失败用例名）几乎总是出现在输出的最后几行。保留尾部而非头部可以最大化信息价值。2048 字符的上限在 Unix Socket 传输中开销可忽略（< 3KB JSON），同时覆盖绝大多数测试摘要。
