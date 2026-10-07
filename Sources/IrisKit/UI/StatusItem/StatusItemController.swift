import AppKit
import SwiftUI

/// 菜单栏图标 + 弹窗 + 右键菜单。
///
/// 自己管理 `NSStatusItem`（而非 SwiftUI 的 MenuBarExtra）：
/// 后者在 macOS 26 上如果图标被用户从控制中心关闭会直接杀掉进程，
/// 且没有公开 API 可以关闭 popover。
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let container: AppContainer
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var lastKey = ""

    init(container: AppContainer) {
        self.container = container
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let root = PopoverView(scheduler: container.scheduler,
                               settings: container.settings,
                               stats: container.stats,
                               calls: container.popoverCalls)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: PopoverView.width, height: PopoverView.height)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        // 由调度器的心跳驱动刷新（0.5s），避免 Combine 的隔离麻烦
        container.scheduler.onTick = { [weak self] _ in self?.refresh() }
        refresh()
    }

    // MARK: - 交互

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRight {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        NSApp.irisActivate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    // MARK: - 图标状态

    func refresh() {
        guard let button = statusItem.button else { return }
        let scheduler = container.scheduler
        let settings = container.settings

        var symbol = "eye"
        var title = ""

        switch scheduler.phase {
        case .working:
            symbol = "eye"
            if settings.menuBarDisplay == .iconAndTime {
                title = " " + Fmt.compactCountdown(scheduler.timeUntilNextBreak)
            }
        case .breaking:
            symbol = "eye.fill"
            if settings.menuBarDisplay == .iconAndTime {
                title = " " + Fmt.countdown(scheduler.breakRemaining)
            }
        case .paused:
            symbol = "eye.slash"
        }

        let key = symbol + "|" + title
        guard key != lastKey else { return }
        lastKey = key

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "明目") {
            image.isTemplate = true
            button.image = image
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
        ])
        button.toolTip = tooltip()

        // 自动化冒烟测试时的自检输出（正常使用不会打印）
        if ProcessInfo.processInfo.environment["IRIS_SMOKE_TEST"] != nil, !Self.didLogSmoke {
            Self.didLogSmoke = true
            let phase = scheduler.phase.isWorking ? "working"
                : (scheduler.phase.isBreaking ? "breaking" : "paused")
            let line = "[smoke] 菜单栏图标已就绪 · symbol=\(symbol) title=\(title.isEmpty ? "(无)" : title)"
                + " · phase=\(phase) · 距下次休息 \(Int(scheduler.timeUntilNextBreak))s\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    private static var didLogSmoke = false

    private func tooltip() -> String {
        let scheduler = container.scheduler
        switch scheduler.phase {
        case .working:
            return L10n.s("明目 · 距下次休息 \(Fmt.countdown(scheduler.timeUntilNextBreak))",
                          "Iris · next break in \(Fmt.countdown(scheduler.timeUntilNextBreak))")
        case .breaking(let kind):
            return L10n.s("明目 · \(kind.title)中，还剩 \(Fmt.countdown(scheduler.breakRemaining))",
                          "Iris · \(kind.title), \(Fmt.countdown(scheduler.breakRemaining)) left")
        case .paused:
            return L10n.s("明目 · 已暂停", "Iris · paused")
        }
    }

    // MARK: - 右键菜单

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        let status = NSMenuItem(title: tooltip(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if container.scheduler.phase.isBreaking {
            menu.addItem(item(L10n.s("结束休息", "End break"), #selector(menuSkip)))
        } else {
            menu.addItem(item(L10n.s("立即休息", "Take a break now"), #selector(menuTakeBreak)))
        }

        if container.scheduler.phase.isPaused {
            menu.addItem(item(L10n.s("恢复提醒", "Resume reminders"), #selector(menuResume)))
        } else {
            let pause = NSMenuItem(title: L10n.s("暂停提醒", "Pause reminders"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(item(L10n.s("暂停 30 分钟", "Pause for 30 minutes"), #selector(menuPause30)))
            sub.addItem(item(L10n.s("暂停 1 小时", "Pause for 1 hour"), #selector(menuPause60)))
            sub.addItem(item(L10n.s("暂停到明早 8:30", "Pause until tomorrow 8:30"), #selector(menuPauseTomorrow)))
            pause.submenu = sub
            menu.addItem(pause)
        }

        menu.addItem(.separator())
        menu.addItem(item(L10n.s("设置…", "Settings…"), #selector(menuSettings), key: ","))
        menu.addItem(item(L10n.s("欢迎引导", "Welcome tour"), #selector(menuOnboarding)))
        menu.addItem(.separator())
        menu.addItem(item(L10n.s("退出明目", "Quit Iris"), #selector(menuQuit), key: "q"))

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuTakeBreak() {
        container.scheduler.takeBreakNow()
    }

    @objc private func menuSkip() {
        container.scheduler.skip()
    }

    @objc private func menuResume() {
        container.scheduler.resume()
    }

    @objc private func menuPause30() {
        container.scheduler.pause(minutes: 30)
    }

    @objc private func menuPause60() {
        container.scheduler.pause(minutes: 60)
    }

    @objc private func menuPauseTomorrow() {
        container.scheduler.pauseUntilTomorrow()
    }

    @objc private func menuSettings() {
        container.onOpenSettings?(.general)
    }

    @objc private func menuOnboarding() {
        container.onOpenOnboarding?()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
