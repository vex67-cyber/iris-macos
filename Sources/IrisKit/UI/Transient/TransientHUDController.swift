import AppKit
import SwiftUI

/// 顶部居中的临时胶囊提示（休息预告 / 归来问候）。
/// 用独立的无边框面板，不抢焦点、不打断输入。
public final class TransientHUDController {

    /// 用户点"现在开始"
    public var onStartNow: (() -> Void)?

    private var window: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    public init() {}

    // MARK: - 内容

    public func showPreview(kind: BreakKind, lead: TimeInterval) {
        show(PreviewPill(kind: kind, lead: lead, onStartNow: { [weak self] in
            self?.dismiss()
            self?.onStartNow?()
        }), duration: lead + 0.6)
    }

    public func showWelcomeBack(away: TimeInterval, nextBreakIn: TimeInterval) {
        show(WelcomeBackPill(away: away, nextBreakIn: nextBreakIn), duration: 5.5)
    }

    // MARK: - 窗口

    private func show<V: View>(_ view: V, duration: TimeInterval) {
        dismiss()

        let hosting = NSHostingView(rootView: view.preferredColorScheme(.dark))
        let size = hosting.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting

        let screen = activeScreen()
        let x = screen.frame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1

        window = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    public func dismiss() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let panel = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
    }
}

// MARK: - 休息预告胶囊

public struct PreviewPill: View {
    let kind: BreakKind
    let lead: TimeInterval
    let onStartNow: () -> Void

    @State private var start = Date()

    public init(kind: BreakKind, lead: TimeInterval, onStartNow: @escaping () -> Void) {
        self.kind = kind
        self.lead = lead
        self.onStartNow = onStartNow
    }

    private var accent: Color { IrisPalette.accent(for: kind) }

    public var body: some View {
        TickerView(interval: 0.2) { tl in
            let remaining = max(0, lead - tl.timeIntervalSince(start))
            content(remaining: remaining)
        }
        .frame(width: 402, height: 46)
        .background(HUDBackground())
        .padding(9)
    }

    private func content(remaining: TimeInterval) -> some View {
        HStack(spacing: 12) {
            ZStack {
                ProgressRing(fraction: lead > 0 ? remaining / lead : 0,
                             lineWidth: 2.5,
                             gradient: IrisPalette.ringGradient(for: kind, urgent: false),
                             trackOpacity: 0.15,
                             showsGlow: false)
                    .frame(width: 26, height: 26)
                Image(systemName: kind == .long ? "figure.walk.motion" : "eye")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(kind == .long
                     ? L10n.s("长休息即将开始", "Long break starting soon")
                     : L10n.s("微休息即将开始", "Micro break starting soon"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(L10n.s("还有 \(Int(remaining.rounded(.up))) 秒 · 收拾一下手头的事",
                            "\(Int(remaining.rounded(.up)))s left · find a good stopping point"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .irisMonospacedDigit()
            }

            Spacer(minLength: 0)

            Button(action: onStartNow) {
                Text(L10n.s("现在开始", "Start now"))
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.13)))
                    .foregroundColor(.white.opacity(0.92))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
    }
}

// MARK: - 归来问候胶囊

public struct WelcomeBackPill: View {
    let away: TimeInterval
    let nextBreakIn: TimeInterval

    public init(away: TimeInterval, nextBreakIn: TimeInterval) {
        self.away = away
        self.nextBreakIn = nextBreakIn
    }

    public var body: some View {
        HStack(spacing: 11) {
            Image(systemName: IrisCompat.symbolName("sparkles", fallback: "sparkles"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(IrisPalette.mint)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.s("欢迎回来，刚才休息了 \(Fmt.duration(Int(away)))",
                            "Welcome back — you rested \(Fmt.duration(Int(away)))"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(L10n.s("下一轮提醒在 \(Fmt.minutes(nextBreakIn)) 后",
                            "Next reminder in \(Fmt.minutes(nextBreakIn))"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .fixedSize()
        .background(HUDBackground())
        .padding(9)
    }
}

// MARK: - 胶囊背景

private struct HUDBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.22)
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
    }
}
