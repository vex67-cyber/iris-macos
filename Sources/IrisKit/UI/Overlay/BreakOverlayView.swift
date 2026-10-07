import SwiftUI

/// 全屏休息浮层。
///
/// 微休息：一个安静的大倒计时环 + 一句远处眺望的提示。
/// 长休息：呼吸引导 / 眼部运动 + 细倒计时环，鼓励真正离开屏幕。
public struct BreakOverlayView: View {

    let context: OverlayContext
    let onSkip: () -> Void
    let onPostpone: () -> Void
    let onGuideChange: (LongBreakGuide) -> Void

    @State private var tipIndex = 0
    @State private var controlsVisible: Bool
    @State private var tipTimer: Timer?
    /// 长休息引导方式在浮层内可切换，因此用本地状态持有
    @State private var guide: LongBreakGuide
    /// 壁纸（自动刷新，图片到达后淡入）
    @ObservedObject private var wallpaper = WallpaperStore.shared

    public init(context: OverlayContext,
                onSkip: @escaping () -> Void,
                onPostpone: @escaping () -> Void,
                onGuideChange: @escaping (LongBreakGuide) -> Void,
                controlsInitiallyVisible: Bool = false) {
        self.context = context
        self.onSkip = onSkip
        self.onPostpone = onPostpone
        self.onGuideChange = onGuideChange
        _guide = State(initialValue: context.guide)
        _controlsVisible = State(initialValue: controlsInitiallyVisible)
    }

    private var accent: Color { IrisPalette.accent(for: context.kind) }

    public var body: some View {
        ZStack {
            IrisPalette.overlayBackground(for: context.kind)
                .ignoresSafeArea()

            wallpaperLayer

            driftingGlow
                .opacity(wallpaper.image == nil ? 1 : 0.55)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                centerpiece
                Spacer(minLength: 16)
                if context.showTip { tipView }
                Spacer(minLength: 18)
                controls
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 44)
            .padding(.top, 52)
        }
        .irisOverlay(alignment: .bottomLeading) { creditLabel }
        .preferredColorScheme(.dark)
        .onAppear {
            startTipRotation()
            revealControls()
        }
        .onDisappear { tipTimer?.invalidate() }
    }

    // MARK: - 壁纸与背景

    /// 休息壁纸：铺满、可调模糊与暗度，加载完成后柔和淡入。
    @ViewBuilder
    private var wallpaperLayer: some View {
        if let image = wallpaper.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: context.wallpaperBlur)
                .overlay(Color.black.opacity(context.wallpaperDim))
                .ignoresSafeArea()
                .transition(.opacity)
                .id(wallpaper.token)
                .irisAnimation(.easeInOut(duration: 1.4), value: wallpaper.token)
        }
    }

    /// 图片来源署名（尊重摄影师）。
    @ViewBuilder
    private var creditLabel: some View {
        if wallpaper.image != nil, !wallpaper.credit.isEmpty {
            Text(wallpaper.credit)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.30))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
    }

    // MARK: - 背景光晕

    private var driftingGlow: some View {
        // 两个要点：
        // 1. 超大的光斑必须挂在 Color.clear 的 overlay 上，
        //    否则它会撑大 ZStack，把顶部标签和底部按钮顶到屏幕外面去。
        // 2. 漂移用隐式动画（GPU 合成），不要用高频心跳重绘 —— 那是这台机器上最大的一笔 CPU 开销。
        Color.clear
            .overlay(
                // 用同样 1 秒一次的心跳驱动漂移。
                // ⚠️ 这里绝对不能用 .repeatForever 的隐式动画：实测浮层关闭后
                // SwiftUI 的动画引擎仍会以 60fps 空转，App 永久占用 ~10% CPU。
                // 心跳定时器会随视图一起销毁（TickClock.deinit 里 invalidate），所以是安全的。
                TickerView(interval: 1.0) { tl in
                    let t = tl.timeIntervalSinceReferenceDate
                    Circle()
                        .fill(RadialGradient(colors: [accent.opacity(0.26), accent.opacity(0.05), .clear],
                                             center: .center, startRadius: 24, endRadius: 560))
                        .frame(width: 1150, height: 1150)
                        .offset(x: sin(t / 19) * 84, y: cos(t / 26) * 62)
                }
                .allowsHitTesting(false)
            )
            .ignoresSafeArea()
    }

    // MARK: - 顶部标签

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: context.kind == .long ? "figure.walk.motion" : "eye")
                .font(.system(size: 14, weight: .semibold))
            Text(context.kind == .long
                 ? L10n.s("长休息 · 让眼睛放个假", "Long break · let your eyes breathe")
                 : L10n.s("微休息 · 看看远处", "Micro break · look far away"))
                .font(.system(size: 15, weight: .semibold))
                .kerning(0.4)
        }
        .foregroundColor(accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(accent.opacity(0.12)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }

    // MARK: - 中央内容

    @ViewBuilder
    private var centerpiece: some View {
        switch context.kind {
        case .micro:
            countdownRing(size: 300)
        case .long:
            longBreakContent
        }
    }

    private func countdownRing(size: CGFloat) -> some View {
        // 心跳只要 1 次/秒：环由 GPU 上的 CABasicAnimation 补间，视觉完全连续，
        // 但 SwiftUI 不再每秒重绘 60 次全屏图层（这是浮层最大的开销来源）。
        TickerView(interval: 1.0) { tl in
            let remaining = max(0, context.endsAt.timeIntervalSince(tl))
            let fraction = context.total > 0 ? remaining / context.total : 0
            ZStack {
                GPURing(fraction: fraction,
                        lineWidth: 14,
                        colors: IrisPalette.ringNSColors(for: context.kind, urgent: remaining <= 5.5),
                        animationDuration: 1.0)
                    .frame(width: size, height: size)
                VStack(spacing: 8) {
                    Text(verbatim: Fmt.countdown(remaining))
                        .font(.system(size: size * 0.23, weight: .medium, design: .rounded))
                        .irisMonospacedDigit()
                        .foregroundColor(.white)
                    Text(L10n.s("保持放松", "Stay relaxed"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(width: size, height: size)
        }
    }

    private var longBreakContent: some View {
        VStack(spacing: 18) {
            guidePicker

            TickerView(interval: 1.0) { tl in
                let remaining = max(0, context.endsAt.timeIntervalSince(tl))
                let fraction = context.total > 0 ? remaining / context.total : 0
                VStack(spacing: 14) {
                    ZStack {
                        GPURing(fraction: fraction,
                                lineWidth: 4,
                                colors: IrisPalette.ringNSColors(for: .long, urgent: false),
                                animationDuration: 1.0,
                                glowOpacity: 0)
                            .frame(width: 330, height: 330)
                        Group {
                            switch guide {
                            case .breathing:
                                BreathingGuideView(accent: accent, size: 268)
                            case .exercise:
                                EyeExerciseGuideView(accent: accent, size: 268)
                            }
                        }
                    }
                    .frame(width: 330, height: 330)

                    Text(L10n.s("还有 \(Fmt.countdown(remaining))", "\(Fmt.countdown(remaining)) left"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .irisMonospacedDigit()
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
    }

    private var guidePicker: some View {
        HStack(spacing: 4) {
            ForEach(LongBreakGuide.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { guide = option }
                    onGuideChange(option)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.symbolName).font(.system(size: 11, weight: .semibold))
                        Text(option.title).font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(guide == option ? accent.opacity(0.25) : Color.white.opacity(0.05)))
                    .foregroundColor(guide == option ? .white : .white.opacity(0.55))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 小贴士

    private var tipView: some View {
        Text(BreakTips.tip(for: context.kind, index: tipIndex))
            .font(.system(size: 16.5, weight: .regular))
            .foregroundColor(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)
            .id(tipIndex)
            .transition(.opacity)
            .irisAnimation(.easeInOut(duration: 0.7), value: tipIndex)
    }

    private func startTipRotation() {
        tipTimer?.invalidate()
        guard context.showTip else { return }
        tipTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation { tipIndex += 1 }
            }
        }
    }

    // MARK: - 底部操作

    private var controls: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                if context.allowPostpone {
                    OverlayButton(title: L10n.s("推迟 \(context.postponeMinutes) 分钟", "Postpone \(context.postponeMinutes) min"),
                                  icon: "clock.arrow.circlepath",
                                  enabled: context.postponesLeft > 0,
                                  action: onPostpone)
                }
                if context.allowSkip {
                    if context.strictSkip {
                        HoldToConfirmButton(title: L10n.s("长按跳过", "Hold to skip"), duration: 3, action: onSkip)
                    } else {
                        OverlayButton(title: L10n.s("跳过", "Skip"),
                                      icon: "forward.end.fill",
                                      action: onSkip)
                    }
                }
            }
            Text(hintText)
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.34))
        }
        .opacity(controlsVisible ? 1 : 0)
    }

    /// 延迟 1.2 秒再显示操作按钮：让休息先"开始"，也避免误触。
    private func revealControls() {
        guard !controlsVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.45)) { controlsVisible = true }
        }
    }

    private var hintText: String {
        if context.allowPostpone && context.postponesLeft == 0 {
            return L10n.s("推迟次数已用完，让眼睛休息一下吧", "No postpones left — enjoy the rest")
        }
        if context.captureInput {
            return L10n.s("Esc 推迟 · ⌘. 跳过", "Esc postpones · ⌘. skips")
        }
        return L10n.s("休息一下，对眼睛好一点", "A short rest does your eyes good")
    }
}

// MARK: - 深色浮层按钮

struct OverlayButton: View {
    var title: String
    var icon: String?
    var enabled: Bool = true
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11.5, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 18)
            .frame(height: 34)
            .foregroundColor(.white.opacity(enabled ? (hovering ? 1 : 0.85) : 0.3))
            .background(Capsule().fill(Color.white.opacity(hovering && enabled ? 0.15 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// 长按确认按钮：按住 3 秒才生效，进度用填充表示（严格模式专用）。
struct HoldToConfirmButton: View {
    var title: String
    var duration: Double
    var action: () -> Void

    @State private var progress: Double = 0
    @State private var pressing = false
    @State private var timer: Timer?

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08))

            GeometryReader { geo in
                Capsule()
                    .fill(IrisPalette.coral.opacity(0.55))
                    .frame(width: geo.size.width * progress)
            }

            HStack(spacing: 6) {
                Image(systemName: pressing ? "hand.tap.fill" : "hand.tap")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(pressing ? L10n.s("继续按住…", "Keep holding…") : title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white.opacity(0.85))
        }
        .frame(width: 158, height: 34)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startPressing() }
                .onEnded { _ in cancelPressing() }
        )
        .onDisappear { timer?.invalidate() }
    }

    private func startPressing() {
        guard !pressing else { return }
        pressing = true
        let start = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            let p = Date().timeIntervalSince(start) / duration
            if p >= 1 {
                t.invalidate()
                progress = 0
                pressing = false
                DispatchQueue.main.async { action() }
            } else {
                progress = p
            }
        }
    }

    private func cancelPressing() {
        guard pressing else { return }
        timer?.invalidate()
        timer = nil
        pressing = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}
