import AppKit
import CoreGraphics
import Foundation

/// 系统状态提供者 —— 抽成协议便于单元测试注入假数据。
public protocol SystemStatusProviding: AnyObject {
    var idleSeconds: TimeInterval { get }
    var isScreenLocked: Bool { get }
    var isSystemAsleep: Bool { get }
    var isFullscreenApp: Bool { get }
}

/// 监听：空闲时长、锁屏、休眠、前台全屏应用。
public final class SystemMonitor: ObservableObject, SystemStatusProviding {

    @Published public private(set) var idleSeconds: TimeInterval = 0
    @Published public private(set) var isScreenLocked = false
    @Published public private(set) var isSystemAsleep = false
    @Published public private(set) var isFullscreenApp = false

    /// 从"离开"状态恢复（解锁 / 唤醒）时回调。
    public var onReturnFromAway: (() -> Void)?

    private var pollTimer: Timer?
    private var fullscreenTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        registerWorkspaceObservers()
        registerDistributedObservers()

        // 空闲时长：0.5s 轮询（读取成本极低）
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshIdle()
        }
        pollTimer?.tolerance = 0.25

        // 全屏检测：2s 轮询（CGWindowList 成本略高，不必太频繁）
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshFullscreen()
        }
        fullscreenTimer?.tolerance = 1.0

        refreshIdle()
        refreshFullscreen()
    }

    public func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        fullscreenTimer?.invalidate(); fullscreenTimer = nil
        let wc = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        observers.forEach { wc.removeObserver($0); dc.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - Idle

    private func refreshIdle() {
        idleSeconds = SystemMonitor.currentIdleSeconds()
    }

    /// 距上一次键鼠输入过去了多少秒（无需任何权限）。
    public static func currentIdleSeconds() -> TimeInterval {
        // kCGAnyInputEventType = 0xFFFFFFFF
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    // MARK: - Fullscreen

    private func refreshFullscreen() {
        isFullscreenApp = SystemMonitor.detectFullscreenApp()
    }

    /// 最佳努力的全屏检测。
    ///
    /// 用两种信号：
    /// 1. Dock 的 "Fullscreen Backdrop" 窗口存在 → 有 App 正处于全屏（读取窗口名需要录屏权限，读不到就跳过）
    /// 2. 某个普通层窗口的尺寸与任意一块屏幕完全一致（容差 2pt）
    ///
    /// 注意：`NSMenu.menuBarVisible` 已废弃且不可靠（实测恒为 true），不使用。
    public static func detectFullscreenApp() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in windowList {
            // 信号 1：Dock 的全屏背景板
            if let owner = info[kCGWindowOwnerName as String] as? String, owner == "Dock",
               let name = info[kCGWindowName as String] as? String, name == "Fullscreen Backdrop" {
                return true
            }

            // 信号 2：普通层窗口铺满屏幕
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == myPID { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 100, bounds.height > 100 else { continue }

            for screen in NSScreen.screens {
                let f = screen.frame
                if abs(bounds.width - f.width) <= 2, abs(bounds.height - f.height) <= 2 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Observers

    private func registerWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        observe(nc, NSWorkspace.willSleepNotification) { [weak self] in
            self?.isSystemAsleep = true
        }
        observe(nc, NSWorkspace.didWakeNotification) { [weak self] in
            self?.isSystemAsleep = false
            self?.onReturnFromAway?()
        }
        observe(nc, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.isSystemAsleep = true
        }
        observe(nc, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.isSystemAsleep = false
            self?.onReturnFromAway?()
        }
        observe(nc, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            // 快速用户切换 / 锁屏
            self?.isScreenLocked = true
        }
        observe(nc, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.isScreenLocked = false
            self?.onReturnFromAway?()
        }
    }

    private func registerDistributedObservers() {
        let dc = DistributedNotificationCenter.default()
        observe(dc, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.isScreenLocked = true
        }
        observe(dc, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.isScreenLocked = false
            self?.onReturnFromAway?()
        }
        observe(dc, Notification.Name("com.apple.screensaver.didstart")) { [weak self] in
            self?.isScreenLocked = true
        }
        observe(dc, Notification.Name("com.apple.screensaver.didstop")) { [weak self] in
            self?.isScreenLocked = false
            self?.onReturnFromAway?()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            action()
        }
        observers.append(token)
    }
}
