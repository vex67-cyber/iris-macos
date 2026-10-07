import Foundation
import SwiftUI

/// 全部用户偏好。一个单例、一份 UserDefaults，UI 全部通过 `@Published` 驱动。
public final class AppSettings: ObservableObject {

    /// 偏好存储位置。
    ///
    /// 作为独立 .app 运行时用应用自身的偏好域（com.zlr.iris）最规范；
    /// 用 `swift run` 调试时进程没有 bundle id，就退回到一个显式 suite 以便持久化。
    /// （不能拿自己的 bundle id 当 suite name —— Foundation 会警告且行为未定义。）
    public static let defaults: UserDefaults = {
        if Bundle.main.bundleIdentifier != nil { return .standard }
        return UserDefaults(suiteName: "com.zlr.iris.dev") ?? .standard
    }()

    private let d: UserDefaults

    private enum K {
        static let microInterval = "microInterval"
        static let microDuration = "microDuration"
        static let longEnabled = "longEnabled"
        static let longInterval = "longInterval"
        static let longDuration = "longDuration"
        static let allowSkip = "allowSkip"
        static let strictSkip = "strictSkip"
        static let allowPostpone = "allowPostpone"
        static let postponeMinutes = "postponeMinutes"
        static let captureInput = "captureInput"
        static let previewEnabled = "previewEnabled"
        static let idleResetEnabled = "idleResetEnabled"
        static let idleThreshold = "idleThreshold"
        static let deferFullscreen = "deferFullscreen"
        static let remindersEnabled = "remindersEnabled"
        static let showTip = "showTip"
        static let menuBarDisplay = "menuBarDisplay"
        static let soundEnabled = "soundEnabled"
        static let startSound = "startSound"
        static let endSound = "endSound"
        static let soundVolume = "soundVolume"
        static let notificationsEnabled = "notificationsEnabled"
        static let preBreakNotice = "preBreakNotice"
        static let longBreakGuide = "longBreakGuide"
        static let dailyGoal = "dailyGoal"
        static let hasOnboarded = "hasOnboarded"
        static let preset = "preset"
        static let wallpaperSource = "wallpaperSource"
        static let wallpaperRefresh = "wallpaperRefresh"
        static let wallpaperDim = "wallpaperDim"
        static let wallpaperBlur = "wallpaperBlur"
    }

    public static func registerDefaults(in defaults: UserDefaults = AppSettings.defaults) {
        defaults.register(defaults: [
            K.microInterval: 20 * 60.0,
            K.microDuration: 20.0,
            K.longEnabled: true,
            K.longInterval: 60 * 60.0,
            K.longDuration: 5 * 60.0,
            K.allowSkip: true,
            K.strictSkip: false,
            K.allowPostpone: true,
            K.postponeMinutes: 5,
            K.captureInput: false,
            K.previewEnabled: true,
            K.idleResetEnabled: true,
            K.idleThreshold: 120.0,
            K.deferFullscreen: true,
            K.remindersEnabled: true,
            K.showTip: true,
            K.menuBarDisplay: MenuBarDisplay.iconAndTime.rawValue,
            K.soundEnabled: true,
            K.startSound: "Glass",
            K.endSound: "Ping",
            K.soundVolume: 0.35,
            K.notificationsEnabled: false,
            K.preBreakNotice: false,
            K.longBreakGuide: LongBreakGuide.breathing.rawValue,
            K.dailyGoal: 8,
            K.hasOnboarded: false,
            K.preset: ReminderPreset.classic.rawValue,
            K.wallpaperSource: WallpaperSource.bing.rawValue,
            K.wallpaperRefresh: WallpaperRefresh.everyLongBreak.rawValue,
            K.wallpaperDim: 0.62,
            K.wallpaperBlur: 16.0,
        ])
    }

    // MARK: - 休息节奏

    /// 微休息间隔（秒）
    @Published public var microInterval: TimeInterval = 20 * 60 {
        didSet { d.set(microInterval, forKey: K.microInterval); becomeCustomIfNeeded() }
    }
    /// 微休息时长（秒）
    @Published public var microDuration: TimeInterval = 20 {
        didSet { d.set(microDuration, forKey: K.microDuration); becomeCustomIfNeeded() }
    }
    /// 是否启用长休息
    @Published public var longEnabled: Bool = true {
        didSet { d.set(longEnabled, forKey: K.longEnabled) }
    }
    /// 长休息间隔（秒）
    @Published public var longInterval: TimeInterval = 60 * 60 {
        didSet { d.set(longInterval, forKey: K.longInterval); becomeCustomIfNeeded() }
    }
    /// 长休息时长（秒）
    @Published public var longDuration: TimeInterval = 5 * 60 {
        didSet { d.set(longDuration, forKey: K.longDuration); becomeCustomIfNeeded() }
    }

    // MARK: - 交互

    /// 允许跳过休息
    @Published public var allowSkip: Bool = true {
        didSet { d.set(allowSkip, forKey: K.allowSkip) }
    }
    /// 严格模式：需要长按 3 秒才能跳过
    @Published public var strictSkip: Bool = false {
        didSet { d.set(strictSkip, forKey: K.strictSkip) }
    }
    /// 允许推迟休息
    @Published public var allowPostpone: Bool = true {
        didSet { d.set(allowPostpone, forKey: K.allowPostpone) }
    }
    /// 推迟的时长（分钟）
    @Published public var postponeMinutes: Int = 5 {
        didSet { d.set(postponeMinutes, forKey: K.postponeMinutes) }
    }
    /// 专注模式：休息时接管键盘（否则只是温和提醒，不打断输入）
    @Published public var captureInput: Bool = false {
        didSet { d.set(captureInput, forKey: K.captureInput) }
    }
    /// 休息前 5 秒预告
    @Published public var previewEnabled: Bool = true {
        didSet { d.set(previewEnabled, forKey: K.previewEnabled) }
    }

    // MARK: - 智能

    /// 离开电脑（空闲）时自动重置计时
    @Published public var idleResetEnabled: Bool = true {
        didSet { d.set(idleResetEnabled, forKey: K.idleResetEnabled) }
    }
    /// 空闲判定阈值（秒）
    @Published public var idleThreshold: TimeInterval = 120 {
        didSet { d.set(idleThreshold, forKey: K.idleThreshold) }
    }
    /// 全屏（观影 / 演示）时暂缓提醒
    @Published public var deferFullscreen: Bool = true {
        didSet { d.set(deferFullscreen, forKey: K.deferFullscreen) }
    }

    // MARK: - 外观与菜单栏

    /// 提醒总开关
    @Published public var remindersEnabled: Bool = true {
        didSet { d.set(remindersEnabled, forKey: K.remindersEnabled) }
    }
    /// 休息浮层上显示护眼小贴士
    @Published public var showTip: Bool = true {
        didSet { d.set(showTip, forKey: K.showTip) }
    }
    /// 菜单栏显示方式
    @Published public var menuBarDisplay: MenuBarDisplay = .iconAndTime {
        didSet { d.set(menuBarDisplay.rawValue, forKey: K.menuBarDisplay) }
    }
    /// 长休息时的引导内容
    @Published public var longBreakGuide: LongBreakGuide = .breathing {
        didSet { d.set(longBreakGuide.rawValue, forKey: K.longBreakGuide) }
    }

    // MARK: - 声音

    @Published public var soundEnabled: Bool = true {
        didSet { d.set(soundEnabled, forKey: K.soundEnabled) }
    }
    @Published public var startSound: String = "Glass" {
        didSet { d.set(startSound, forKey: K.startSound) }
    }
    @Published public var endSound: String = "Ping" {
        didSet { d.set(endSound, forKey: K.endSound) }
    }
    @Published public var soundVolume: Double = 0.35 {
        didSet { d.set(soundVolume, forKey: K.soundVolume) }
    }

    // MARK: - 系统集成

    @Published public var notificationsEnabled: Bool = false {
        didSet { d.set(notificationsEnabled, forKey: K.notificationsEnabled) }
    }
    @Published public var preBreakNotice: Bool = false {
        didSet { d.set(preBreakNotice, forKey: K.preBreakNotice) }
    }

    // MARK: - 休息壁纸

    /// 壁纸来源（免费、免 Key 的公共 API）
    @Published public var wallpaperSource: WallpaperSource = .bing {
        didSet { d.set(wallpaperSource.rawValue, forKey: K.wallpaperSource) }
    }
    /// 自动刷新策略
    @Published public var wallpaperRefresh: WallpaperRefresh = .everyLongBreak {
        didSet { d.set(wallpaperRefresh.rawValue, forKey: K.wallpaperRefresh) }
    }
    /// 暗色遮罩强度（0–0.85），保证浮层文字清晰
    @Published public var wallpaperDim: Double = 0.62 {
        didSet { d.set(wallpaperDim, forKey: K.wallpaperDim) }
    }
    /// 背景模糊半径
    @Published public var wallpaperBlur: Double = 16 {
        didSet { d.set(wallpaperBlur, forKey: K.wallpaperBlur) }
    }

    // MARK: - 目标与状态

    /// 每日休息目标（次）
    @Published public var dailyGoal: Int = 8 {
        didSet { d.set(dailyGoal, forKey: K.dailyGoal) }
    }
    /// 是否已完成首次引导
    @Published public var hasOnboarded: Bool = false {
        didSet { d.set(hasOnboarded, forKey: K.hasOnboarded) }
    }
    /// 当前节奏预设
    @Published public var preset: ReminderPreset = .classic {
        didSet { d.set(preset.rawValue, forKey: K.preset) }
    }

    /// 正在应用预设（此时不要判定为"自定义"）
    private var isApplyingPreset = false
    /// 正在从磁盘载入（init 期间的赋值不应触发"自定义"判定）
    private var isLoading = true

    // MARK: - Init

    public init(defaults: UserDefaults? = nil) {
        d = defaults ?? AppSettings.defaults
        AppSettings.registerDefaults(in: d)
        microInterval = d.double(forKey: K.microInterval)
        microDuration = d.double(forKey: K.microDuration)
        longEnabled = d.bool(forKey: K.longEnabled)
        longInterval = d.double(forKey: K.longInterval)
        longDuration = d.double(forKey: K.longDuration)
        allowSkip = d.bool(forKey: K.allowSkip)
        strictSkip = d.bool(forKey: K.strictSkip)
        allowPostpone = d.bool(forKey: K.allowPostpone)
        postponeMinutes = d.integer(forKey: K.postponeMinutes)
        captureInput = d.bool(forKey: K.captureInput)
        previewEnabled = d.bool(forKey: K.previewEnabled)
        idleResetEnabled = d.bool(forKey: K.idleResetEnabled)
        idleThreshold = d.double(forKey: K.idleThreshold)
        deferFullscreen = d.bool(forKey: K.deferFullscreen)
        remindersEnabled = d.bool(forKey: K.remindersEnabled)
        showTip = d.bool(forKey: K.showTip)
        menuBarDisplay = MenuBarDisplay(rawValue: d.string(forKey: K.menuBarDisplay) ?? "") ?? .iconAndTime
        longBreakGuide = LongBreakGuide(rawValue: d.string(forKey: K.longBreakGuide) ?? "") ?? .breathing
        soundEnabled = d.bool(forKey: K.soundEnabled)
        startSound = d.string(forKey: K.startSound) ?? "Glass"
        endSound = d.string(forKey: K.endSound) ?? "Ping"
        soundVolume = d.double(forKey: K.soundVolume)
        notificationsEnabled = d.bool(forKey: K.notificationsEnabled)
        preBreakNotice = d.bool(forKey: K.preBreakNotice)
        dailyGoal = d.integer(forKey: K.dailyGoal)
        hasOnboarded = d.bool(forKey: K.hasOnboarded)
        preset = ReminderPreset(rawValue: d.string(forKey: K.preset) ?? "") ?? .classic
        wallpaperSource = WallpaperSource(rawValue: d.string(forKey: K.wallpaperSource) ?? "") ?? .bing
        wallpaperRefresh = WallpaperRefresh(rawValue: d.string(forKey: K.wallpaperRefresh) ?? "") ?? .everyLongBreak
        wallpaperDim = d.double(forKey: K.wallpaperDim)
        wallpaperBlur = d.double(forKey: K.wallpaperBlur)
        isLoading = false
    }

    // MARK: - Presets

    /// 应用一个节奏预设。
    public func apply(_ preset: ReminderPreset) {
        guard let v = preset.values else {
            self.preset = .custom
            return
        }
        isApplyingPreset = true
        microInterval = v.microInterval
        microDuration = v.microDuration
        longInterval = v.longInterval
        longDuration = v.longDuration
        isApplyingPreset = false
        self.preset = preset
    }

    /// 手动调整任一节奏参数后，自动切换到"自定义"。
    private func becomeCustomIfNeeded() {
        guard !isLoading, !isApplyingPreset else { return }
        if preset != .custom { preset = .custom }
    }

    /// 恢复出厂设置（保留统计数据与引导状态）。
    public func resetToDefaults() {
        apply(.classic)
        allowSkip = true
        strictSkip = false
        allowPostpone = true
        postponeMinutes = 5
        captureInput = false
        previewEnabled = true
        idleResetEnabled = true
        idleThreshold = 120
        deferFullscreen = true
        showTip = true
        menuBarDisplay = .iconAndTime
        longBreakGuide = .breathing
        soundEnabled = true
        startSound = "Glass"
        endSound = "Ping"
        soundVolume = 0.35
        notificationsEnabled = false
        preBreakNotice = false
        dailyGoal = 8
        remindersEnabled = true
        wallpaperSource = .bing
        wallpaperRefresh = .everyLongBreak
        wallpaperDim = 0.62
        wallpaperBlur = 16
    }
}

/// 长休息的引导内容。
public enum LongBreakGuide: String, CaseIterable, Identifiable, Sendable {
    case breathing
    case exercise

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breathing: return L10n.s("深呼吸", "Breathe")
        case .exercise: return L10n.s("眼部运动", "Eye exercise")
        }
    }

    public var symbolName: String {
        switch self {
        case .breathing: return IrisCompat.symbolName("wind", fallback: "arrow.up.arrow.down")
        case .exercise: return IrisCompat.symbolName("eyes", fallback: "eye")
        }
    }
}
