import AppKit
import SwiftUI
import IrisKit

// 明目（Iris）· 离屏渲染器
//
// 把关键界面渲染成 PNG，用于在没有相机的环境里审阅与迭代设计。
// 用法：swift run IrisSnapshot [输出目录]

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                    ? CommandLine.arguments[1]
                    : FileManager.default.currentDirectoryPath + "/snapshots")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// MARK: - 环境

final class StubMonitor: SystemStatusProviding {
    var idleSeconds: TimeInterval = 0
    var isScreenLocked = false
    var isSystemAsleep = false
    var isFullscreenApp = false
}

struct SnapshotBackground: View {
    var dark: Bool
    var body: some View {
        (dark ? Color(white: 0.135) : Color(white: 0.966))
    }
}

@discardableResult
func snapshot<V: View>(_ name: String, size: CGSize, dark: Bool = false,
                       settle: TimeInterval = 0.06,
                       @ViewBuilder content: () -> V) -> Bool {
    let wrapped = content()
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, dark ? .dark : .light)

    let hosting = NSHostingView(rootView: wrapped)
    hosting.frame = NSRect(origin: .zero, size: size)

    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = hosting
    // 挪到屏幕外渲染：alpha 保持 1 才能让 AppKit 控件（开关等）画出激活态，
    // 同时窗口落在可见范围之外，不会打扰正在睡觉的用户。
    window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
    window.orderBack(nil)

    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(settle))

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        print("✗ \(name): bitmap failed")
        return false
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window.orderOut(nil)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("✗ \(name): png failed")
        return false
    }
    let url = outputDir.appendingPathComponent("\(name).png")
    do {
        try data.write(to: url)
        print("✓ \(url.path)")
        return true
    } catch {
        print("✗ \(name): \(error)")
        return false
    }
}

// MARK: - 示例数据

AppSettings.registerDefaults()
let settings = AppSettings()

let stats = StatsStore(fileURL: outputDir.appendingPathComponent("_sample-stats.json"))
let cal = Calendar.current
let pattern: [(Int, Int)] = [(6, 1), (9, 2), (5, 1), (10, 2), (7, 1), (4, 0), (11, 2),
                             (8, 1), (6, 1), (7, 2), (9, 1), (5, 1), (8, 2), (7, 1)]
for (offset, counts) in pattern.enumerated() {
    guard let day = cal.date(byAdding: .day, value: -(pattern.count - 1 - offset), to: Date()) else { continue }
    stats.upsert(DayRecord(day: cal.startOfDay(for: day),
                           microTaken: counts.0,
                           longTaken: counts.1,
                           skipped: offset % 4,
                           postponed: offset % 3,
                           restSeconds: counts.0 * 20 + counts.1 * 300))
}

let monitor = StubMonitor()
let scheduler = BreakScheduler(settings: settings, stats: stats, monitor: monitor)
let calls = PopoverCalls()

// MARK: - 菜单栏弹窗

snapshot("popover-working-light", size: CGSize(width: 340, height: 452)) {
    PopoverView(scheduler: scheduler, settings: settings, stats: stats, calls: calls)
        .background(SnapshotBackground(dark: false))
}

snapshot("popover-working-dark", size: CGSize(width: 340, height: 452), dark: true) {
    PopoverView(scheduler: scheduler, settings: settings, stats: stats, calls: calls)
        .background(SnapshotBackground(dark: true))
}

scheduler.beginBreak(.micro, at: Date())
snapshot("popover-breaking-light", size: CGSize(width: 340, height: 452)) {
    PopoverView(scheduler: scheduler, settings: settings, stats: stats, calls: calls)
        .background(SnapshotBackground(dark: false))
}

scheduler.finishBreak(.completed, silent: true)
scheduler.pause(minutes: 30)
snapshot("popover-paused-dark", size: CGSize(width: 340, height: 452), dark: true) {
    PopoverView(scheduler: scheduler, settings: settings, stats: stats, calls: calls)
        .background(SnapshotBackground(dark: true))
}
scheduler.resume()

// MARK: - 休息浮层

let screen = CGSize(width: 1440, height: 900)

let microContext = OverlayContext(kind: .micro,
                                  startsAt: Date(),
                                  endsAt: Date().addingTimeInterval(20),
                                  allowSkip: true, strictSkip: false,
                                  allowPostpone: true, postponeMinutes: 5, postponesLeft: 2,
                                  showTip: true, captureInput: false, guide: .breathing)

snapshot("overlay-micro", size: screen) {
    BreakOverlayView(context: microContext, onSkip: {}, onPostpone: {}, onGuideChange: { _ in },
                     controlsInitiallyVisible: true)
}

let longContext = OverlayContext(kind: .long,
                                 startsAt: Date(),
                                 endsAt: Date().addingTimeInterval(300),
                                 allowSkip: true, strictSkip: true,
                                 allowPostpone: true, postponeMinutes: 5, postponesLeft: 1,
                                 showTip: true, captureInput: false, guide: .breathing)

snapshot("overlay-long-breathing", size: screen) {
    BreakOverlayView(context: longContext, onSkip: {}, onPostpone: {}, onGuideChange: { _ in },
                     controlsInitiallyVisible: true)
}

let exerciseContext = OverlayContext(kind: .long,
                                     startsAt: Date(),
                                     endsAt: Date().addingTimeInterval(300),
                                     allowSkip: true, strictSkip: false,
                                     allowPostpone: false, postponeMinutes: 5, postponesLeft: 0,
                                     showTip: true, captureInput: false, guide: .exercise)

snapshot("overlay-long-exercise", size: screen) {
    BreakOverlayView(context: exerciseContext, onSkip: {}, onPostpone: {}, onGuideChange: { _ in })
}

// MARK: - 设置窗口

let navigation = SettingsNavigation()
for pane in SettingsPane.allCases {
    navigation.pane = pane
    snapshot("settings-\(pane.rawValue)", size: CGSize(width: 760, height: 540)) {
        SettingsRootView(navigation: navigation,
                         settings: settings,
                         stats: stats,
                         calls: calls,
                         onReplayOnboarding: {})
    }
    snapshot("settings-\(pane.rawValue)-dark", size: CGSize(width: 760, height: 540), dark: true) {
        SettingsRootView(navigation: navigation,
                         settings: settings,
                         stats: stats,
                         calls: calls,
                         onReplayOnboarding: {})
    }
}

// MARK: - 欢迎引导

for step in 0..<4 {
    snapshot("onboarding-\(step + 1)", size: CGSize(width: 560, height: 566)) {
        OnboardingView(settings: settings, onFinish: {}, initialStep: step)
    }
}

// MARK: - 浮层胶囊

snapshot("pill-preview", size: CGSize(width: 420, height: 70), dark: true) {
    PreviewPill(kind: .micro, lead: 10, onStartNow: {})
        .background(Color(white: 0.32))
}

snapshot("pill-welcome-back", size: CGSize(width: 380, height: 70), dark: true) {
    WelcomeBackPill(away: 6 * 60, nextBreakIn: 20 * 60)
        .background(Color(white: 0.32))
}

// MARK: - 控件渲染自检（开关的激活态 / 色板）

snapshot("dev-controls", size: CGSize(width: 420, height: 260)) {
    VStack(alignment: .leading, spacing: 14) {
        Toggle("常量 true", isOn: .constant(true)).toggleStyle(.switch)
        Toggle("常量 false", isOn: .constant(false)).toggleStyle(.switch)
        Toggle("绑定 longEnabled=TRUE", isOn: .constant(true)).toggleStyle(.switch)
        Toggle("绑定 longEnabled=FALSE", isOn: .constant(false)).toggleStyle(.switch)
        HStack(spacing: 10) {
            ForEach(Array([IrisPalette.teal, IrisPalette.aqua, IrisPalette.indigo,
                           IrisPalette.violet, IrisPalette.mint, IrisPalette.amber].enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 30, height: 18)
            }
        }
        Text("开关状态自检 / 色板").font(.system(size: 12)).foregroundColor(.secondary)
    }
    .padding(24)
    .background(SnapshotBackground(dark: false))
}

// 品牌标记自检：各尺寸下的 AppMark 应该和 Dock 里的图标长得一样
snapshot("dev-appmark", size: CGSize(width: 470, height: 170)) {
    HStack(alignment: .center, spacing: 18) {
        AppMark(size: 96)
        AppMark(size: 68)
        AppMark(size: 40)
        AppMark(size: 22)
        AppMark(size: 16)
    }
    .padding(24)
    .background(SnapshotBackground(dark: false))
}

// 进度环的"部分进度"状态（验证 GPU 环的弧长与方向）
let partialContext = OverlayContext(kind: .micro,
                                    startsAt: Date().addingTimeInterval(-14),
                                    endsAt: Date().addingTimeInterval(6),
                                    allowSkip: true, strictSkip: false,
                                    allowPostpone: true, postponeMinutes: 5, postponesLeft: 2,
                                    showTip: false, captureInput: false, guide: .breathing)

snapshot("overlay-micro-progress", size: screen) {
    BreakOverlayView(context: partialContext, onSkip: {}, onPostpone: {}, onGuideChange: { _ in },
                     controlsInitiallyVisible: true)
}

print("\n快照输出目录：\(outputDir.path)")
exit(0)
