import AppKit
import Foundation
import SwiftUI

/// 设置窗口的分页。
public enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case breaks
    case wallpaper
    case sound
    case stats
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return L10n.s("通用", "General")
        case .breaks: return L10n.s("休息", "Breaks")
        case .wallpaper: return L10n.s("壁纸", "Wallpaper")
        case .sound: return L10n.s("声音", "Sound")
        case .stats: return L10n.s("统计", "Statistics")
        case .about: return L10n.s("关于", "About")
        }
    }

    public var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .breaks: return "eye"
        case .wallpaper: return IrisCompat.symbolName("photo.on.rectangle.angled", fallback: "photo")
        case .sound: return "speaker.wave.2"
        case .stats: return "chart.bar.xaxis"
        case .about: return "info.circle"
        }
    }

    public var tint: Color {
        switch self {
        case .general: return .gray
        case .breaks: return IrisPalette.teal
        case .wallpaper: return IrisPalette.violet
        case .sound: return IrisPalette.indigo
        case .stats: return IrisPalette.mint
        case .about: return IrisPalette.aqua
        }
    }
}

/// 依赖装配中心。所有状态在此创建并互相接线。
public final class AppContainer: ObservableObject {

    public static let shared = AppContainer()

    public let settings: AppSettings
    public let stats: StatsStore
    public let monitor: SystemMonitor
    public let scheduler: BreakScheduler
    public let sounds: SoundPlayer
    public let overlay: BreakOverlayController
    public let hud: TransientHUDController

    /// 由 AppKit 层注入
    public var onOpenSettings: ((SettingsPane) -> Void)?
    public var onOpenOnboarding: (() -> Void)?
    public var onClosePopover: (() -> Void)?

    private var activityToken: NSObjectProtocol?
    private var started = false

    private init() {
        settings = AppSettings()
        stats = StatsStore()
        monitor = SystemMonitor()
        sounds = SoundPlayer()
        scheduler = BreakScheduler(settings: settings, stats: stats, monitor: monitor)
        overlay = BreakOverlayController()
        hud = TransientHUDController()
        wire()
    }

    // MARK: - 启动

    public func start() {
        guard !started else { return }
        started = true

        // 防止 App Nap 让计时器变慢（但不阻止系统休眠）
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "明目 · 护眼提醒")

        monitor.start()
        monitor.onReturnFromAway = { [weak self] in
            self?.scheduler.handleSystemReturn()
        }

        HotKeyCenter.shared.onBreakNow = { [weak self] in self?.scheduler.takeBreakNow() }
        HotKeyCenter.shared.onTogglePause = { [weak self] in self?.scheduler.togglePause() }
        HotKeyCenter.shared.register()

        // 提前把第一张壁纸准备好，休息时无需等待
        WallpaperStore.shared.refresh(source: settings.wallpaperSource,
                                      policy: settings.wallpaperRefresh)

        scheduler.start()
    }

    // MARK: - 接线

    private func wire() {
        scheduler.onBreakWillStart = { [weak self] kind, lead in
            self?.handlePreview(kind: kind, lead: lead)
        }
        scheduler.onBreakStart = { [weak self] kind, date in
            self?.handleBreakStart(kind: kind, at: date)
        }
        scheduler.onBreakEnd = { [weak self] kind, outcome in
            self?.handleBreakEnd(kind: kind, outcome: outcome)
        }
        scheduler.onReturnFromAway = { [weak self] away in
            self?.hud.showWelcomeBack(away: away,
                                      nextBreakIn: self?.scheduler.timeUntilNextBreak ?? 0)
        }

        overlay.onSkip = { [weak self] in self?.scheduler.skip() }
        overlay.onPostpone = { [weak self] in self?.scheduler.postpone() }
        overlay.onGuideChange = { [weak self] guide in self?.settings.longBreakGuide = guide }

        hud.onStartNow = { [weak self] in self?.scheduler.takeBreakNow() }
    }

    // MARK: - 事件处理

    private func handlePreview(kind: BreakKind, lead: TimeInterval) {
        hud.showPreview(kind: kind, lead: lead)

        if settings.notificationsEnabled && settings.preBreakNotice && lead >= 25 {
            Notifier.shared.post(
                title: kind == .long
                    ? L10n.s("长休息马上开始", "Long break starting")
                    : L10n.s("该让眼睛歇歇了", "Time for an eye break"),
                body: L10n.s("还有半分钟，收拾一下手头的事", "About 30 seconds to a good stopping point"))
        }
    }

    private func handleBreakStart(kind: BreakKind, at date: Date) {
        hud.dismiss()
        onClosePopover?()

        let fallback = kind == .micro ? settings.microDuration : settings.longDuration
        let endsAt = scheduler.breakEndsAt ?? date.addingTimeInterval(fallback)

        let context = OverlayContext(
            kind: kind,
            startsAt: date,
            endsAt: endsAt,
            allowSkip: settings.allowSkip,
            strictSkip: settings.strictSkip,
            allowPostpone: settings.allowPostpone,
            postponeMinutes: settings.postponeMinutes,
            postponesLeft: scheduler.postponesLeft,
            showTip: settings.showTip,
            captureInput: settings.captureInput,
            guide: settings.longBreakGuide,
            wallpaperDim: settings.wallpaperDim,
            wallpaperBlur: settings.wallpaperBlur)

        // 休息壁纸：免费公共 API，按策略自动刷新（有缓存则立即显示）
        WallpaperStore.shared.refresh(source: settings.wallpaperSource,
                                      policy: settings.wallpaperRefresh)

        if settings.soundEnabled {
            sounds.play(settings.startSound, volume: settings.soundVolume)
        }
        overlay.present(context)
    }

    private func handleBreakEnd(kind: BreakKind, outcome: BreakOutcome) {
        overlay.dismiss()
        hud.dismiss()
        if settings.soundEnabled, outcome == .completed {
            sounds.play(settings.endSound, volume: settings.soundVolume)
        }
    }

    // MARK: - 提供给 SwiftUI 的操作闭包

    public var popoverCalls: PopoverCalls {
        var calls = PopoverCalls()

        calls.takeBreakNow = { [weak self] in
            self?.scheduler.takeBreakNow()
            self?.onClosePopover?()
        }
        calls.postponeNext = { [weak self] in self?.scheduler.postponeNext() }
        calls.skip = { [weak self] in self?.scheduler.skip() }
        calls.postpone = { [weak self] in self?.scheduler.postpone() }
        calls.pause = { [weak self] minutes in self?.scheduler.pause(minutes: minutes) }
        calls.pauseUntilTomorrow = { [weak self] in self?.scheduler.pauseUntilTomorrow() }
        calls.resume = { [weak self] in self?.scheduler.resume() }
        calls.openSettings = { [weak self] in
            self?.onClosePopover?()
            self?.onOpenSettings?(.general)
        }
        calls.openStats = { [weak self] in
            self?.onClosePopover?()
            self?.onOpenSettings?(.stats)
        }
        calls.openOnboarding = { [weak self] in
            self?.onClosePopover?()
            self?.onOpenOnboarding?()
        }
        calls.quit = {
            Notifier.shared.cancelAll()
            NSApp.terminate(nil)
        }
        return calls
    }
}
