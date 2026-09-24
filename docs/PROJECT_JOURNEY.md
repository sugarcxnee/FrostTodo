# FrostTodo 项目过程与实现记录

本文档面向协作者与后续维护者，完整记录 FrostTodo 从零到可发布版本的演进过程、每一阶段的设计决策、实现要点与踩坑记录。功能与使用说明见根目录 README。

## 一、项目背景与目标

FrostTodo 是一款原生 macOS 待办与计时应用：简约冷色调、本地优先，核心特色是"任务计时与系统日历联动"——计时开始、暂停、结束、任务完成时在 Apple 日历中创建或更新事件，配合完整的历史记录体系，让每一段专注时间可追溯、可统计、可导出。

硬性约束：禁止 WebView 套壳；SwiftUI + SwiftData + EventKit + UserNotifications + MenuBarExtra；最低 macOS 14；App Sandbox；全项目（UI、通知、日历事件、文档、测试数据）不使用 emoji，视觉标识一律用 SF Symbols 或 `[计时中]` 这类纯文本标签；测试框架统一为 Swift Testing；开发过程执行严格测试门禁——每阶段先写测试、运行确认红灯、实现后全绿才允许进入下一阶段。

## 二、技术选型与工程结构

| 决策 | 选择 | 理由 |
|---|---|---|
| 构建体系 | SPM（`swift test` 跑门禁）+ XcodeGen 生成 .xcodeproj | 测试全自动离线运行；正式 App 的沙盒与 entitlements 由 XcodeGen 配置 |
| 语言模式 | Swift 5 模式，核心服务 `@MainActor` | SwiftData @Model 与 EKEventStore 非 Sendable，严格并发收益低于成本 |
| 模块划分 | 库目标 FrostTodo + 可执行目标 FrostTodoApp | 测试经 `@testable import` 覆盖全部逻辑层 |
| 可测试性 | ClockProviding / CalendarProviding / NotificationCentering / HistoryRecording 协议 + Mock | 时钟可手动推进，EventKit 与通知完全 Mock，测试离线毫秒级 |

数据模型五个 SwiftData @Model：TodoTask（含任务级倒计时配置）、TimeSession（级联删除）、HistoryEvent、AppSettings（单例）、TimerSnapshot 与 CountdownSnapshot（重启恢复）。Schema 走 VersionedSchema + 空迁移计划占位；后续新增字段一律用带默认值的轻量迁移（stored 属性内联默认值），实测旧存储无损升级。

## 三、阶段过程记录（严格测试门禁）

### 阶段 1：骨架与数据层（19 测试）

模型默认值、状态流转幂等性、级联删除、内存容器跨 context 可见性、设置单例。踩坑两处：`Package.swift` 中 `swiftLanguageModes` 参数必须放在 `targets` 之后；本机 SDK 中 `MigrationStage` 是具体类型而非 `any` 协议、`ModelContainer` 需用 `Schema(versionedSchema:)` 初始化——都与常见教程写法不同。

### 阶段 2：计时引擎（17 测试）

TimerService 状态机 idle/running/paused：开始建 running Session，暂停切段，继续开新段，停止或完成复位。两个关键设计：

- **恢复策略 = 快照 + 数据推导**。TimerSnapshot 只存 activeTaskID、phase 与本轮起始时间；累计时长永远"从该时间之后已结束的 Session 求和"推导，不存增量计数。崩溃产生的脏快照（Session 已结束但快照还是 running）恢复时安全降级为 paused；计时中任务被删则复位 idle。
- **并发防护**。重复开始同一任务抛错；切换任务自动停旧开新；对已完成任务开始计时抛错。

### 阶段 3：历史体系（31 测试）

HistoryEvent 20 余种类型（task/timer/session/calendar/settings/notification/countdown/history 六族），HistoryService 统一写入、筛选（类型/任务/日期/标签/项目/搜索）、排序、分页、JSON+CSV 导出、保留策略清理留痕。

最重要的设计是**事务语义**：业务操作与历史写入在同一逻辑单元内一次 save，任一失败即 rollback——保证"操作成功必有历史，失败无残留"。踩坑：SwiftData 的 `ModelContext.rollback()` 只撤销待保存变更，**不还原已注册模型的内存属性**（例如已把 session.endAt 赋值再回滚，内存里 endAt 仍是新值）。解法是每次风险操作前对快照/Session/任务做内存状态捕获，catch 中手动 restore。这个坑在 TimerService 里以 capture/restore 扩展的形式系统性解决。

### 阶段 4：日历联动（16 测试）

CalendarProviding 协议隔离 EventKit；CalendarSyncService 实现 TimerObserving 挂在计时器上。事件生命周期：`[计时中]`（开始，结束时间取预计时长或默认 15 分钟）→ `[计时记录]`（暂停/停止，写实际时长）→ `[已完成]`（完成时更新）或 `[完成记录]`（无关联事件时新建，完成时间起 5 分钟）。备注含任务 ID、Session ID、实际时长、状态、备注摘要；URL 为 `frosttodo://task/<UUID>` 可回跳。

降级矩阵：权限拒绝直接跳过同步（不刷失败历史）；默认日历失效自动创建专用日历 FrostTodo 并记忆；日历只读且无法创建时记 `calendar.syncFailed` 历史但本地计时不受影响；事件被用户手动删除时下次更新自动重建（`calendar.eventRebuilt`）。日历同步是外部副作用，失败不回滚本地操作，与阶段 3 的"同生共死"事务刻意区分。

### 阶段 5：UI 与交互（19 测试）

MVVM：TaskListViewModel（六视图筛选、搜索、四种排序）、HistoryViewModel（分页分组）、SettingsViewModel、TimerViewModel。三栏 NavigationSplitView + 冷色动态主题（NSColor 动态色支持深色模式）。

### 阶段 6：菜单栏、通知、快捷键、导出（11 测试）

MenuBarExtra 常驻计时；截止提醒与预计时长提醒（参数全部 Mock 断言）；ShortcutRouter 纯逻辑键位映射 + 菜单命令；ExportService 全量 JSON 导出（任务嵌套 Session、设置、历史）。

### 阶段 7：迭代修复与新功能（后续多轮）

这一阶段全部来自实际使用反馈，按时间顺序：

1. **计划视图列表整列消失 bug**。快速添加输入框的 @State 挂在整个 TaskListView 上，逐键重算触发 List 对 SwiftData 模型行重新 diff，叠加 List(selection:) 用 @Model 对象做 tag，行被错误丢弃；视图又没观察 TaskListViewModel，刷新全靠偶然。修复：QuickAddBar 拆独立子视图、视图 @ObservedObject 观察 ViewModel、行选择改 UUID tag。回归测试三例锁定契约。
2. **类番茄钟倒计时**。CountdownService 阶段状态机驱动 TimerService，专注/休息时长可配（休息 0 即纯倒计时），专注到点切段进休息、休息到点开新段回专注，自然/手动结束都走 Session 结束路径更新日历；CountdownSnapshot 支持重启恢复。
3. **任务级倒计时配置**。设置存默认值，TodoTask 存可选覆盖（专注/休息逐项回落），编辑历史记录"跟随默认 -> X 分钟"。
4. **轮数**。任务与设置两级轮数；完成最后一轮专注即自然结束（不进最终休息）；纯倒计时多轮连续不切段（单 Session 覆盖全程），面板显示"专注 × 轮数"的总时长与总进度。
5. **正计时与倒计时生命周期联动**。新增 CountdownCoordinating：正计时以任何方式结束（手动停止、完成任务、切换任务、手动完成/删除任务）时倒计时自动同步结束（reason: timer-stopped），倒计时自身结束触发的 timer.stop 经 isEnding 防重入，不产生重复历史。
6. **任务详情自动保存**。移除"保存修改"按钮，全字段防抖自动保存（0.4 秒，离开页面兜底保存）；TaskService.update 对无实际变更的调用不写历史（契约测试锁定），连续输入合并为一条编辑记录；卡片右上角"已自动保存"淡入淡出轻提示。

## 四、架构现状

```
App 入口（FrostTodoApp + MenuBarExtra + 快捷键命令）
        │
   AppViewModel（组合根：构建并接线全部服务与子 ViewModel）
        │
┌───────┴────────────────────────────────────────┐
│ TaskService    TimerService    CountdownService │
│      │             │ └── CountdownCoordinating  │
│      │             ├── observer: CalendarSyncService（TimerObserving）
│      └── timerService（完成任务前联动停止计时）      │
│ HistoryService（同事务历史写入，全部服务共用）       │
│ SettingsService / NotificationService / Export  │
└────────────────────────────────────────────────┘
        │
SwiftData（PersistenceService：内存/磁盘、Schema V1、迁移占位）
```

关键约定：所有 ModelContext 操作在主线程；历史写入只经 HistoryService；业务+历史同 save，日历为外部副作用单独降级；倒计时一切时间由 targetEndAt 推导、正计时累计由 Session 求和推导，快照只存推导所需的最小状态。

## 五、测试体系

153 例 Swift Testing 测试，`swift test` 离线全绿（ManualClock 推进时间，EventKit/通知 Mock）。按阶段文件组织（Phase1-7 + 回归套件），另有契约级测试（无变更不写历史、联动结束单条历史）。测试策略上每次功能或修复都先补红灯测试再实现；测试只增不减，无 XCTSkip/disabled。

## 六、已知限制与后续方向

- 倒计时重启恢复为单步追赶：关闭期间跨过多个阶段只进入下一阶段重新起算，不回补周期（期间正计时时长完整保留）。
- JSON 导出暂无导入；番茄钟之外未做更多专注模式。
- 后续可做：iCloud 同步（模型已模块化）、小组件、快捷指令、frosttodo:// 回跳落地处理、多语言。

## 七、构建与验证命令速查

```bash
swift test                  # 153 例全绿（约 0.5 秒）
xcodegen generate           # 由 project.yml 重新生成 FrostTodo.xcodeproj
xcodebuild -project FrostTodo.xcodeproj -scheme FrostTodo \
  -configuration Debug build    # App 构建验证
open FrostTodo.xcodeproj    # Xcode 中 Command+R 运行（完整沙盒与日历权限）
```
