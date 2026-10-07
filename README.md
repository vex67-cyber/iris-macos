# 明目 · Iris

**简体中文** · [English](README.en.md)

> 让眼睛，歇一会儿。

一款原生 macOS 护眼提醒 App。纯 SwiftUI + AppKit 手写，**零第三方依赖**，完全本地运行。

```
每看屏幕 20 分钟，望向 20 英尺（约 6 米）外的地方，至少 20 秒。
                                    —— 美国眼科学会（AAO）20-20-20 法则
```

---

## 它长什么样

| 菜单栏弹窗 | 休息浮层 |
| --- | --- |
| ![菜单栏弹窗](docs/screenshots/popover-working-light.jpg) | ![休息浮层](docs/screenshots/overlay-micro.jpg) |

| 长休息 · 呼吸引导 | 长休息 · 眼部运动 |
| --- | --- |
| ![呼吸](docs/screenshots/overlay-long-breathing.jpg) | ![眼操](docs/screenshots/overlay-long-exercise.jpg) |

| 统计 | 壁纸 | 欢迎引导 |
| --- | --- | --- |
| ![统计](docs/screenshots/settings-stats.jpg) | ![壁纸](docs/screenshots/settings-wallpaper.jpg) | ![引导](docs/screenshots/onboarding-2.jpg) |

> 所有截图由 `swift run IrisSnapshot` 离屏渲染生成，与真实界面一致。

---

## 特性

### 休息节奏
- **微休息**：默认每 20 分钟一次、每次 20 秒（经典 20-20-20）
- **长休息**：默认每 60 分钟一次、5 分钟，鼓励真正离开屏幕
- 三档预设（经典 / 轻松 / 严格）+ 完全自定义；临近的长休息会智能合并掉微休息

### 不打扰优先
- **空闲感知**：离开电脑超过 2 分钟就当作已经休息过，回来重新开始一轮——绝不"补罚"
- **全屏缓期**：看电影、打游戏时自动暂缓，退出全屏后补上。默认只在「全屏 + 系统正在播放声音」时生效——全屏写代码、看文档照常提醒（否则开发者会永远收不到提醒）
- **开会时自动暂停**：检测到麦克风或摄像头被占用就暂停提醒，散会后自动恢复（不需要任何权限）
- **免打扰时段**：可以设一段时间（比如午休）完全不打扰，支持跨午夜
- **连续打字不硬打断**：手一直没停时先等等，找到一个自然停顿再提醒（最多等 60 秒）
- **温和模式**（默认）：浮层不抢键盘焦点，不打断输入；可切到**专注模式**接管键盘
- **休息前预告**：开始前 10–30 秒，屏幕顶部出现倒计时胶囊，还能点「现在开始」

### 休息体验
- 全屏浮层，**所有显示器**同时显示，盖得住全屏 App
- 微休息：极简倒计时环 + 轮播护眼小贴士
- 长休息：**4-7 秒呼吸引导** 与 **6 组眼部运动（跟练圆点）** 可随时切换
- 温柔但不软弱：**Esc = 推迟 5 分钟**（比跳过更安全），严格模式下需**长按 3 秒**才能跳过，连续推迟最多 2 次
- 结束时柔和提示音（可选/可试听/可调音量）

### 休息壁纸
- 来源：**必应每日壁纸** 与 **Lorem Picsum**（均免费、免 API Key）
- 自动按策略刷新：每次休息 / 每次长休息 / 每天
- 本地缓存最近 8 张（自动缩放到视网膜屏够用的尺寸），**断网也能用**；图片到达时柔和淡入
- 暗度与模糊可调，并自动署名摄影师

### 菜单栏
- 常驻菜单栏，图标随状态变化（工作中 / 休息中 / 已暂停），可显示倒计时
- 左键：弹窗（倒计时、立即休息、推迟、暂停、今日成绩）
- 右键：快捷菜单（立即休息 / 暂停 30 分钟 / 1 小时 / 到明早 / 设置 / 退出）

### 统计
- 今日休息次数、休息时长、连续达标天数、累计次数
- 最近 14 天堆叠柱状图（微休息 / 长休息分开着色）
- 全部数据存在本机，可一键清除

### 隐私
- **不需要任何系统权限**：不用摄像头、不监听键盘（全局快捷键走 Carbon API）、不读取屏幕内容
- **不联网**，除非你启用壁纸功能；统计与设置永远只存在本地
- 无账号、无遥测、无订阅提示

---

## 安装

### 下载 DMG（推荐）

👉 **[下载最新版](https://github.com/vex67-cyber/iris-macos/releases/latest)** · `Mingmu-1.0.0.dmg` · 3.4 MB · 需要 macOS 12+ · Apple Silicon

1. 双击打开 DMG，把「明目」拖进「应用程序」文件夹
2. 首次打开请**右键点图标 → 打开**（应用未做 Apple 公证，直接双击会被 Gatekeeper 拦下；之后就能正常双击了）
3. 若仍提示无法验证，执行一次：`xattr -dr com.apple.quarantine /Applications/明目.app`

> Intel 芯片的 Mac 请用下面的源码构建方式（本项目自带编译脚本）。

### 从源码构建（Intel Mac / 开发者）

需要 macOS 12+ 与 Xcode Command Line Tools。

```bash
git clone https://github.com/vex67-cyber/iris-macos.git && cd iris-macos

./scripts/build-app.sh          # 编译 → 生成图标 → 组装 .app → 签名
./scripts/install.sh --open     # 安装到「应用程序」并启动
./scripts/make-dmg.sh           # 打包成可分发的 DMG（含拖拽安装界面）
```

构建产物在 `dist/明目.app`，可以直接双击运行或拖进「应用程序」。

### 首次启动
1. 出现欢迎引导（三步：了解 20-20-20 → 选节奏 → 开机自启）
2. 之后**明目常驻菜单栏**，就是那个眼睛图标
3. 左键点图标看倒计时，右键点图标有快捷菜单

---

## 使用

### 快捷键（全局有效）

| 快捷键 | 作用 |
| --- | --- |
| `⌃⌥⌘B` | 立即休息 |
| `⌃⌥⌘P` | 暂停 / 恢复提醒 |
| `Esc`（休息浮层上） | 推迟 5 分钟 |
| `⌘.`（休息浮层上） | 跳过 |

### 设置项一览

| 分页 | 内容 |
| --- | --- |
| 通用 | 提醒开关、菜单栏显示、空闲重置与阈值、全屏缓期、开机自启、系统通知、快捷键、恢复默认 |
| 休息 | 节奏预设、微休息间隔/时长、长休息、跳过与推迟、专注模式、预告、小贴士、长休息引导方式 |
| 壁纸 | 来源、刷新策略、暗度、模糊、缓存管理 |
| 声音 | 提示音开关、开始/结束音色与试听、音量 |
| 统计 | 四项成绩单、14 天图表、每日目标、清除数据 |
| 关于 | 20-20-20 说明、隐私承诺、快捷键、重新观看引导 |

---

## 技术说明

### 架构

```
Sources/
├── Iris/                    # 可执行入口（仅 10 行）
├── IrisKit/
│   ├── App/                 # AppDelegate、依赖装配、主菜单
│   ├── Core/                # 调度器、设置、统计、系统监听、壁纸、声音、快捷键
│   ├── Design/              # 色板、组件、兼容层、心跳、自绘柱状图
│   └── UI/                  # 菜单栏弹窗、休息浮层、设置窗口、欢迎引导、浮层胶囊
└── IrisSnapshot/            # 离屏渲染工具（把界面渲染成 PNG 以审阅设计）
```

- **调度器**（`BreakScheduler`）是心脏：所有时间判断都基于日期而非累加计数，
  因此睡眠/唤醒、系统卡顿都不会让计时漂移；心跳 0.5 秒一次，驱动全部 UI
- **系统监听**（`SystemMonitor`）只用公开 API：`CGEventSource` 取空闲时长、
  `CGWindowListCopyWindowInfo` 判全屏、`NSWorkspace` + 分布式通知监听锁屏与休眠
- 休息浮层里的动画全部由 GPU 完成（`CAShapeLayer` + 基线动画），SwiftUI 每秒只更新一次目标值，
  这样既不重绘整块屏幕，也避免了一个隐蔽的坑：`repeatForever` 隐式动画在浮层关闭后仍会让渲染循环空转，
  实测会造成 10% CPU 与一倍内存占用
- **没有使用** `MenuBarExtra`（macOS 26 上图标被用户从控制中心关闭会导致进程直接退出），
  也没用 SwiftUI `Settings` scene（LSUIElement 应用的设置窗口会跑到别的 App 后面），
  而是自管 `NSStatusItem` + `NSPopover` + 自建设置窗口，行为完全可控
- 休息浮层用 `NSPanel(.nonactivatingPanel)`，`orderFrontRegardless()` 不抢焦点，
  并重写 `acceptsFirstMouse` 保证第一次点击就生效

### 关于 SDK 版本（重要）

本机只装了 Command Line Tools，而 **macOS 27 SDK 把 SwiftUI 的 `@State` 等改成了宏，
宏插件只随完整 Xcode 分发**，因此构建脚本固定使用仍以 property wrapper 实现 `@State` 的
`MacOSX26.5.sdk`：

```bash
swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

如果你装了完整 Xcode，直接 `swift build` 也能过（可用 `IRIS_SDK` 指定 SDK）。

### 系统兼容性

- **代码层面按 macOS 11 (Big Sur) 编写**：`Design/Compat.swift` 把
  `foregroundStyle`、`animation(_:value:)`、`monospacedDigit`、`Material`、
  SwiftUI `Alert`、`TimelineView`、Swift Charts、`async/await`、`SMAppService`
  等较新 API 全部做了降级路径（自绘图表、自写心跳视图、回调式网络、LaunchAgent 兜底）
- **实际产物为 macOS 12+**：Swift 6.4 工具链把最低部署目标钳制在 12.0，换旧工具链可下探到 11
- **macOS 26 / 27 已在真机验证**：编译、运行、壁纸下载、菜单栏全部正常

### 已知限制

- 开机自启使用 `SMAppService`（macOS 13+）；ad-hoc 签名下系统可能要求在
  「系统设置 → 通用 → 登录项」中手动批准（设置页会显示状态并提供跳转按钮）
- macOS 11 / 12 上改用 LaunchAgent（`~/Library/LaunchAgents/com.zlr.iris.loginitem.plist`）
- 全屏检测是最佳努力实现：依赖 `CGWindowList` 的窗口尺寸比对，刘海屏与"自动隐藏菜单栏"下可能不准
- 系统通知需要授权，默认关闭；不授权也不影响使用（休息浮层本身就是提醒）

---

## Windows 版本？

目前还没有。但仓库里备好了一份**完整的移植规格书**：

- [`docs/windows-port-spec.md`](docs/windows-port-spec.md) —— 行为规格、平台 API 映射、UI 规格、设计 token、验收清单、工作量估算
- [`port/windows/`](port/windows/) —— **C# 调度器参考实现 + 20 个等价单元测试**，可直接拷进 .NET 工程

任何人在 Windows 上用 .NET（WPF/WinUI）照着实现，即可 1:1 还原行为。

## 设计参考

功能与交互参考了这些产品的成功经验：

- **Time Out**（macOS 老牌）：双层休息、空闲重置、可跳过
- **Stretchly**（开源）：推迟计次、休息前预告、严格模式
- **LookAway**：上下文感知暂停（全屏/会议）、菜单栏倒计时
- **DeskRest**：只在合适的时机打扰
- **护眼宝**：轻量、不锁屏、可一键关闭的提醒

科学依据来自 **AAO（美国眼科学会）** 的 20-20-20 建议，以及"提醒类 App 的依从性是关键"
的相关研究结论：因此明目把"不烦人"当成一等公民——空闲重置、全屏缓期、
Esc 推迟优先于跳过、关闭提醒只是暂停而不是卸载。

---

## 授权

MIT License。图标、代码均为本项目原创。

© 2026 明目 · 用 SwiftUI 手写，向 Time Out、Stretchly、LookAway 致敬。
