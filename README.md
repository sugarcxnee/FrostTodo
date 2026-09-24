# FrostTodo

简约、冷色调的原生 macOS 待办与计时应用。支持任务管理、任务计时、时间段记录、完整历史追溯，并与系统日历（Apple 日历 / iCloud 日历）联动：计时开始、暂停、结束、任务完成时自动创建或更新日历事件。数据全部保存在本机，不上传服务器。

## 技术栈

- SwiftUI + SwiftData + EventKit + UserNotifications + MenuBarExtra
- 原生 macOS 14 Sonoma 起，推荐 Xcode 16 及以上
- 测试框架：Swift Testing（全项目统一）
- 语言模式：Swift 5 模式（工具链 6.0），核心服务标注 @MainActor
- App Sandbox 已启用，带日历访问 entitlement

## 功能概览

- 任务管理：收件箱、今天、计划、已完成、标签、项目视图；快速添加、编辑、删除、完成与取消完成；手动拖拽排序；搜索与四种排序（手动、创建时间、截止日期、优先级）。
- 任务计时：开始、暂停、继续、停止、完成；每次开始到结束记录为一个 TimeSession；暂停结束当前时间段、继续开新时间段；跨天计时；应用重启或崩溃后自动恢复计时状态；防重复开始同一任务；切换任务自动结束当前计时。
- 倒计时（类番茄钟）：设置中配置默认专注与休息时长，任务基本信息中可按任务自定义（自定义优先，未设置回落默认），休息为 0 即纯倒计时；专注到点自动进入休息并结束当段时间（日历更新为计时记录），休息到点自动回到专注（新时间段与日历事件）；随时可手动结束，结束时与正计时一致记录到日历；支持重启恢复；左栏常驻倒计时与正计时面板，菜单栏同步显示倒计时剩余。
- 历史记录：任务、计时、时间段、日历、设置、通知六类事件全量记录；按类型、任务、日期范围、标签、项目筛选；标题与详情搜索；正序倒序；按天分组；分页加载；导出 JSON 与 CSV；二次确认清空并留痕；按天数或条数的保留策略清理并留痕。
- 日历联动：计时创建 `[计时中] 任务名` 事件（结束时间取预计时长或默认 15 分钟）；暂停或停止更新结束时间、标题为 `[计时记录] 任务名` 并写入实际时长；任务完成更新为 `[已完成] 任务名` 或创建 `[完成记录] 任务名`（完成时间起 5 分钟止）；事件备注含任务 ID、Session ID、实际时长、状态与备注摘要；事件 URL 为 `frosttodo://task/<任务ID>` 支持回跳；自动创建专用日历 FrostTodo；事件被手动删除时自动重建；权限被拒或无日历时优雅降级，本地功能不受影响；侧边栏展示今日日程（含全天事件）。
- 菜单栏：常驻显示当前计时任务与已用时间，提供暂停、继续、停止、完成与快速添加。
- 通知：任务截止提醒、计时达到预计时长提醒。
- 快捷键：Command+N 快速添加；Command+Shift+T 开始或暂停计时；Command+Shift+D 完成当前任务。
- 设置：写入日历开关、默认日历选择、开始即建事件与完成事件开关、默认预计时长、外观（跟随系统、浅色、深色）、历史保留策略、清除已完成任务、清空历史、导出 JSON。

## 目录结构

```
FrostTodo/
├── Package.swift                  SPM 构建定义（swift test 测试门禁入口）
├── project.yml                    XcodeGen 配置（生成正式 .xcodeproj）
├── Support/
│   ├── Info.plist                 权限描述与 frosttodo URL Scheme
│   └── FrostTodo.entitlements     App Sandbox + 日历访问 + 用户选择文件读写
├── Sources/FrostTodoApp/          @main 入口、全局快捷键命令、MenuBarExtra
├── Sources/FrostTodo/
│   ├── Models/                    TodoTask、TimeSession、HistoryEvent、AppSettings、TimerSnapshot、CountdownSnapshot
│   ├── Protocols/                 ClockProviding、HistoryRecording、CalendarProviding、NotificationCentering、TimerObserving
│   ├── Services/                  Persistence、Task、Timer、Countdown、History、CalendarSync、EventKit、Mock、Notification、Settings、ShortcutRouter、Export
│   ├── ViewModels/                App、TaskList、History、Settings、Timer
│   └── Views/                     Theme、MainView 三栏、Sidebar、TaskList、TaskDetail、Timer、History、Settings、MenuBar
└── Tests/FrostTodoTests/          按阶段组织的 16 个测试套件，共 113 例
```

## 构建与运行

方式一（推荐，完整沙盒与权限）：

```bash
xcodegen generate          # 已提交生成好的 FrostTodo.xcodeproj，可跳过
open FrostTodo.xcodeproj   # Xcode 中选 FrostTodo scheme，Command+R 运行
```

方式二（命令行构建 App）：

```bash
xcodebuild -project FrostTodo.xcodeproj -scheme FrostTodo -configuration Debug build
```

方式三（SPM 开发调试，注意不带沙盒与 entitlements，日历权限不可用）：

```bash
swift run FrostTodoApp
```

## 权限说明

- 首次使用日历功能时应用会请求完整日历访问权限（NSCalendarsFullAccessUsageDescription 已配置）。
- 拒绝授权后应用完全可用：任务、计时、历史不受影响，仅不写日历；设置页会提示前往“系统设置 - 隐私与安全性 - 日历”开启。
- 导出文件通过 NSSavePanel 选择位置，沙盒内仅访问用户选定文件。

## 测试

全部测试离线可跑（EventKit、通知中心均通过协议抽象注入 Mock，时钟使用 ManualClock）：

```bash
swift test
```

最近一次结果：

```
Test run with 134 tests in 19 suites passed after 0.469 seconds.
```

各阶段测试文件与用例数：

| 阶段 | 测试文件 | 用例数 |
|---|---|---|
| 1 骨架与数据层 | Phase1ModelTests / Phase1PersistenceTests / Phase1SettingsTests / Phase1MigrationTests | 19 |
| 2 计时与 Session | Phase2TimerServiceTests | 17 |
| 3 历史记录 | Phase3HistoryServiceTests / Phase3BusinessIntegrationTests / Phase3HistoryExportTests | 31 |
| 4 日历联动 | Phase4CalendarServiceTests | 16 |
| 5 UI 与交互 | Phase5ViewModelsTests（四个套件） | 19 |
| 6 菜单栏通知快捷键导出 | Phase6MenuNotificationShortcutExportTests | 11 |
| 7 倒计时 | Phase7CountdownTests（两个套件） | 18 |
| 回归 | RegressionQuickAddPlannedViewTests | 3 |

开发过程严格执行测试门禁：每阶段先写测试（确认红灯）再实现，全部通过后才进入下一阶段；无跳过、无删除测试。

## 设计决策与假设

1. 语言模式取 Swift 5：SwiftData @Model 与 EventKit 类型非 Sendable，Swift 6 严格并发收益低于成本；核心服务均已标注 @MainActor 并在单线程使用 ModelContext。
2. 计时恢复基于“快照 + 数据推导”：TimerSnapshot 记录 activeTaskID、phase 与本轮开始时间，累计时长总是从该时间之后已结束的 Session 求和，崩溃产生的脏快照（Session 已结束但快照仍为 running）在恢复时安全降级为暂停。
3. 事务语义：业务操作与历史写入在同一逻辑单元内一次保存，任一失败即回滚上下文并恢复模型内存状态，保证“操作成功必有历史、失败无残留”。日历同步属于外部副作用，失败不回滚本地操作，改记 calendar.syncFailed 历史。
4. 智能视图定义：收件箱为无开始且无截止日期的未完成任务；今天为已开始或今日到期的未完成任务；计划为开始日期在未来的未完成任务。
5. 历史按标签与项目筛选依赖任务类事件 payload 中的 tags 与 project 字段，非任务类事件不参与该两类筛选。
6. 历史时间戳保证同批写入严格递增（相差 1 毫秒），确保排序与分组稳定。
7. 专用日历命名 FrostTodo，优先使用本地 Source 创建；设置中的默认日历失效时自动重建并记忆新 ID。

## 已知限制

- 倒计时重启恢复为单步追赶：应用关闭期间若跨过多个阶段，恢复时只进入下一阶段并以当前时间重新起算，不回补错过的周期；期间的正计时时长仍完整记录。
- 数据导出 JSON 暂未提供导入功能；一致性校验通过解码往返完成。
- 通过 `swift run` 运行时无沙盒与权限描述，日历联动不可用，请使用 Xcode 工程运行。
- 界面文案为简体中文，未做国际化。
- MenuBarExtra 的计时文字每秒刷新一次，长时间运行可能有小幅 CPU 占用。

## 验收对照

1. 项目可在 Xcode 中编译运行：xcodebuild BUILD SUCCEEDED，见上文命令。
2. 首次启动正确请求日历权限：Info.plist 描述 + requestFullAccessToEvents。
3. 创建、编辑、完成、删除任务：TaskService 全覆盖（阶段 1、3 测试）。
4. 开始、暂停、继续、停止计时并记录多个时间段：阶段 2 测试。
5. 计时开始、结束、任务完成时日历事件创建或更新：阶段 4 测试。
6. 日历事件包含任务 ID、实际时长、完成状态、回跳 URL：阶段 4 字段断言。
7. 菜单栏显示当前计时任务与时间：MenuBarTimerView 与 MenuBarLabelView。
8. 重启后任务与计时记录不丢失：SwiftData 持久化 + 恢复测试。
9. 日历权限被拒绝时优雅降级：deniedAccessSkipsSync 等测试。
10. 冷色调简约界面并支持深色模式：FrostTheme 动态颜色。
11. 历史可记录、查询、筛选、导出、清理：阶段 3 与 5 测试。
12. 全部阶段测试通过且有运行记录：134 例全绿，见上。
13. 提供 README 与测试：本文档与 Tests 目录。
14. 全项目无 emoji：已按 Unicode 区段扫描全部源码与文档，结果为空。
15. 无被跳过或删除的测试：未使用 XCTSkip 或 disabled，测试仅增未减。
