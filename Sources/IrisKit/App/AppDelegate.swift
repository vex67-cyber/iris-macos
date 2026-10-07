import AppKit
import SwiftUI

public final class IrisAppDelegate: NSObject, NSApplicationDelegate {

    private let container = AppContainer.shared
    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install(target: self)

        container.onOpenSettings = { [weak self] pane in self?.showSettings(pane: pane) }
        container.onOpenOnboarding = { [weak self] in self?.showOnboarding() }

        let controller = StatusItemController(container: container)
        statusItemController = controller
        container.onClosePopover = { [weak controller] in controller?.closePopover() }

        container.start()

        // IRIS_SMOKE_TEST=1 用于自动化冒烟测试：不弹任何窗口
        let isSmokeTest = ProcessInfo.processInfo.environment["IRIS_SMOKE_TEST"] != nil
        if !container.settings.hasOnboarded, !isSmokeTest {
            showOnboarding()
        }

        // IRIS_OPEN_SETTINGS=1 用于性能测量：启动后自动打开设置窗口
        if ProcessInfo.processInfo.environment["IRIS_OPEN_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showSettings(pane: .wallpaper)
            }
        }

        // IRIS_FORCE_BREAK=<秒> 用于性能测量：N 秒后自动开始一次休息（浮层最吃性能的场景）
        if let raw = ProcessInfo.processInfo.environment["IRIS_FORCE_BREAK"], let delay = Double(raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.container.scheduler.takeBreakNow()
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 窗口

    func showSettings(pane: SettingsPane) {
        let controller = settingsController ?? SettingsWindowController(container: container)
        settingsController = controller
        controller.show(pane: pane)
    }

    func showOnboarding() {
        let controller = onboardingController ?? OnboardingWindowController(container: container)
        onboardingController = controller
        controller.show()
    }

    // MARK: - 菜单动作

    @objc func menuAbout(_ sender: Any?) {
        showSettings(pane: .about)
    }

    @objc func menuTakeBreak(_ sender: Any?) {
        container.scheduler.takeBreakNow()
    }

    @objc func menuTogglePause(_ sender: Any?) {
        container.scheduler.togglePause()
    }

    @objc func menuSettings(_ sender: Any?) {
        showSettings(pane: .general)
    }

    @objc func menuWelcome(_ sender: Any?) {
        showOnboarding()
    }
}
