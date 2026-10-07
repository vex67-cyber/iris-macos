import AppKit
import CoreAudio
import CoreGraphics
import CoreMediaIO
import Foundation

/// 系统状态提供者 —— 抽成协议便于单元测试注入假数据。
public protocol SystemStatusProviding: AnyObject {
    var idleSeconds: TimeInterval { get }
    var isScreenLocked: Bool { get }
    var isSystemAsleep: Bool { get }
    var isFullscreenApp: Bool { get }
    /// 系统当前是否有声音在播放（用来区分"看电影"与"全屏写代码"）
    var isAudioPlaying: Bool { get }
    /// 麦克风是否被占用（开会 / 语音中）
    var isMicrophoneInUse: Bool { get }
    /// 摄像头是否被占用（视频会议中）
    var isCameraInUse: Bool { get }
}

public extension SystemStatusProviding {
    var isAudioPlaying: Bool { false }
    var isMicrophoneInUse: Bool { false }
    var isCameraInUse: Bool { false }
}

/// 监听：空闲时长、锁屏、休眠、前台全屏应用。
public final class SystemMonitor: ObservableObject, SystemStatusProviding {

    @Published public private(set) var idleSeconds: TimeInterval = 0
    @Published public private(set) var isScreenLocked = false
    @Published public private(set) var isSystemAsleep = false
    @Published public private(set) var isFullscreenApp = false
    @Published public private(set) var isAudioPlaying = false
    @Published public private(set) var isMicrophoneInUse = false
    @Published public private(set) var isCameraInUse = false

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
            self?.refreshAudio()
            self?.refreshCaptureDevices()
        }
        fullscreenTimer?.tolerance = 1.0

        refreshIdle()
        refreshFullscreen()
        refreshAudio()
        refreshCaptureDevices()
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

    // MARK: - Audio

    private func refreshAudio() {
        isAudioPlaying = SystemMonitor.isAudioPlayingNow()
    }

    /// 默认输出设备上是否有进程正在播放音频（CoreAudio 公开 API，无需权限）。
    ///
    /// 用途：区分「全屏看电影/打游戏」（该缓期）与「全屏写代码」（不该缓期）。
    public static func isAudioPlayingNow() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &deviceAddress, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return false }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &running) == noErr else {
            return false
        }
        return running != 0
    }

    // MARK: - 摄像头 / 麦克风占用（判断是否在开会）

    private func refreshCaptureDevices() {
        isMicrophoneInUse = SystemMonitor.isMicrophoneInUseNow()
        isCameraInUse = SystemMonitor.isCameraInUseNow()
    }

    /// 默认输入设备（麦克风）是否被任何进程占用。
    /// 不需要任何权限：这只是设备状态，不是音频内容。
    public static func isMicrophoneInUseNow() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &deviceAddress, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return false }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &running) == noErr else {
            return false
        }
        return running != 0
    }

    /// 是否有摄像头正在被使用（视频会议 / 拍照）。
    /// 用 CoreMediaIO 的设备状态查询，读取的是"是否在运行"，不涉及画面内容。
    public static func isCameraInUseNow() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                           &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: max(1, count))
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                        &address, 0, nil, dataSize, &used, &devices) == noErr else { return false }

        for device in devices where device != 0 {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

            guard CMIOObjectHasProperty(device, &runningAddress) else { continue }
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, runningSize, &used, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
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
