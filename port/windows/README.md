# Windows 移植参考代码

本目录是给 **Windows 版** 准备的起点，包含：

| 文件 | 内容 |
|---|---|
| `IrisScheduler.cs` | 调度器 + 设置 + 统计的完整参考实现（纯逻辑，无 UI 依赖） |
| `IrisSchedulerTests.cs` | 与 macOS 版一一对应的 xUnit 测试（20 个用例） |

完整的行为规格、UI 规格、平台 API 映射、设计 token 与验收清单见 **[`docs/windows-port-spec.md`](../../docs/windows-port-spec.md)**。

## ⚠️ 关于这份代码的诚实说明

它是在 macOS 上照着**已经过 28 个单元测试验证**的 Swift 版本逐条翻译的，
但**编写环境没有 .NET SDK，因此尚未编译、尚未运行过**。
逻辑与 macOS 版一致，测试用例也是对应的——请在 Windows 上第一次构建时把测试跑通再继续写 UI。

## ⚠️ 与 macOS 版的差距

参考实现对应的是 macOS 版 **1.0** 的调度器。macOS 版 1.1 新增的三条智能判断
（开会自动暂停、免打扰时段、连续输入等停顿）与 5 个设置项**尚未移植到这里**，
行为规格见 [`docs/windows-port-spec.md`](../../docs/windows-port-spec.md) 的 §3.3.1。
移植时应一并补上，并照 §10 的验收清单加测试。

## 怎么用

```bash
# 1. 建工程（Windows 上，需要 .NET 8 SDK）
dotnet new classlib -n Mingmu.Core -f net8.0
cd Mingmu.Core
rm Class1.cs
# 2. 把本目录的两个 .cs 拷进来
# 3. 建测试工程
cd ..
dotnet new xunit -n Mingmu.Core.Tests -f net8.0
cd Mingmu.Core.Tests
dotnet add reference ../Mingmu.Core
# 把 IrisSchedulerTests.cs 拷进来
dotnet test        # 20 个用例应当全绿
```

## 宿主需要做的事（调度器之外）

调度器自己**不起定时器**，由宿主驱动：

```csharp
var timer = new System.Timers.Timer(500);        // 500ms 心跳
timer.Elapsed += (_, _) => scheduler.Tick();     // 注意切回 UI 线程更新界面
timer.Start();

// 系统事件（锁屏 / 睡眠唤醒）→ 让调度器知道「人回来了」
SystemEvents.SessionSwitch += (_, _) => scheduler.HandleReturn();
SystemEvents.PowerModeChanged += (_, e) => { if (e.Mode == PowerModes.Resume) scheduler.HandleReturn(); };

// 订阅回调
scheduler.BreakStarted += kind => overlay.Show(kind);   // 全屏浮层
scheduler.BreakWillStart += (kind, lead) => pill.Show(kind, lead);  // 顶部预告胶囊
scheduler.BreakEnded += (kind, outcome) => { overlay.Hide(); PlaySound(outcome); };
scheduler.ReturnedFromAway += away => pill.ShowWelcomeBack(away);
```

`ISystemStatus` 用 Windows API 实现（`GetLastInputInfo` / `SystemEvents` /
`SHQueryUserNotificationState`），具体做法见规格书 §4。

## 建议的工程结构

```
Mingmu.sln
├── Mingmu.Core/            # 本目录的调度器、设置、统计（可直接跑测试）
├── Mingmu.Platform/        # ISystemStatus 的 Windows 实现、托盘、热键、音效
├── Mingmu.App/             # WPF/WinUI：托盘弹窗、全屏浮层、设置窗口、首次引导
└── Mingmu.Core.Tests/      # 本目录的测试
```
