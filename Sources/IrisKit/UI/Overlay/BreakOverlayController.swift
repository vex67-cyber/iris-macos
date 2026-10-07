import AppKit
import SwiftUI

/// 一次休息浮层所需的全部上下文（不可变快照）。
public struct OverlayContext: Equatable {
    public var kind: BreakKind
    public var startsAt: Date
    public var endsAt: Date
    public var allowSkip: Bool
    public var strictSkip: Bool
    public var allowPostpone: Bool
    public var postponeMinutes: Int
    public var postponesLeft: Int
    public var showTip: Bool
    public var captureInput: Bool
    public var guide: LongBreakGuide
    public var wallpaperDim: Double
    public var wallpaperBlur: Double

    public init(kind: BreakKind, startsAt: Date, endsAt: Date,
                allowSkip: Bool, strictSkip: Bool,
                allowPostpone: Bool, postponeMinutes: Int, postponesLeft: Int,
                showTip: Bool, captureInput: Bool, guide: LongBreakGuide,
                wallpaperDim: Double = 0.62, wallpaperBlur: Double = 16) {
        self.kind = kind
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allowSkip = allowSkip
        self.strictSkip = strictSkip
        self.allowPostpone = allowPostpone
        self.postponeMinutes = postponeMinutes
        self.postponesLeft = postponesLeft
        self.showTip = showTip
        self.captureInput = captureInput
        self.guide = guide
        self.wallpaperDim = wallpaperDim
        self.wallpaperBlur = wallpaperBlur
    }

    public var total: TimeInterval { max(1, endsAt.timeIntervalSince(startsAt)) }
}

/// 浮层窗口：无边框、非激活面板，可以盖住全屏 App 与菜单栏。
final class BreakOverlayWindow: NSPanel {

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        // 第一次点击就生效，而不是被"唤醒"吞掉
        acceptsMouseMovedEvents = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 第一次点击就生效（否则点击会被"唤醒窗口"吞掉）。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 管理所有屏幕上的浮层窗口。
public final class BreakOverlayController {

    /// 用户点击"跳过"
    public var onSkip: (() -> Void)?
    /// 用户点击"推迟"
    public var onPostpone: (() -> Void)?
    /// 用户在长休息里切换引导方式（呼吸 / 眼操）
    public var onGuideChange: ((LongBreakGuide) -> Void)?
    /// 用户点击"现在开始"（预告胶囊里）
    public var onStartNow: (() -> Void)?

    private var windows: [BreakOverlayWindow] = []
    private var isPresenting = false
    private var escMonitor: Any?

    public init() {}

    public var isVisible: Bool { isPresenting }

    // MARK: - Present / dismiss

    public func present(_ context: OverlayContext) {
        dismiss(animated: false)
        isPresenting = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        for screen in NSScreen.screens {
            let window = BreakOverlayWindow(screen: screen)
            let view = BreakOverlayView(
                context: context,
                onSkip: { [weak self] in self?.onSkip?() },
                onPostpone: { [weak self] in self?.onPostpone?() },
                onGuideChange: { [weak self] guide in self?.onGuideChange?(guide) }
            )
            let hosting = FirstMouseHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)

            window.contentView = hosting
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0

            // orderFrontRegardless：不抢焦点，但一定盖在最上面
            window.orderFrontRegardless()
            window.animator().alphaValue = 1

            windows.append(window)
        }

        if context.captureInput {
            // 专注模式：真正接管键盘
            windows.first?.becomesKeyOnlyIfNeeded = false
            windows.first?.makeKey()
            NSApp.irisActivate()
        }

        installEscapeMonitor()
    }

    public func dismiss(animated: Bool = true) {
        guard !windows.isEmpty || isPresenting else { return }
        isPresenting = false
        removeEscapeMonitor()

        let toClose = windows
        windows.removeAll()

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for w in toClose { w.animator().alphaValue = 0 }
            } completionHandler: {
                for w in toClose { w.orderOut(nil) }
            }
        } else {
            for w in toClose { w.orderOut(nil) }
        }
    }

    // MARK: - 键盘

    /// Esc = 推迟（比直接跳过更安全）；⌘. = 跳过。
    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresenting else { return event }
            if event.keyCode == 53 { // Esc
                self.onPostpone?()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "." {
                self.onSkip?()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
