import SwiftUI

private func smoothstep(_ x: Double) -> Double {
    let t = max(0, min(1, x))
    return t * t * (3 - 2 * t)
}

// MARK: - 深呼吸引导

/// 4 秒吸气 / 6 秒呼气的呼吸圆圈。
public struct BreathingGuideView: View {
    public var accent: Color
    public var size: CGFloat

    private let inhaleDuration: Double = 4
    private let exhaleDuration: Double = 6

    public init(accent: Color, size: CGFloat) {
        self.accent = accent
        self.size = size
    }

    public var body: some View {
        TickerView(interval: 1.0 / 15.0) { tl in
            let cycle = inhaleDuration + exhaleDuration
            let t = tl.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let inhaling = t < inhaleDuration
            let local = inhaling ? t / inhaleDuration : (t - inhaleDuration) / exhaleDuration
            let eased = smoothstep(local)
            let scale = inhaling ? (0.66 + 0.34 * eased) : (1.0 - 0.34 * eased)
            let secondsLeft = Int(ceil(inhaling ? inhaleDuration - t : cycle - t))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1.5)

                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.38), accent.opacity(0.06)],
                                         center: .center, startRadius: 6, endRadius: size * 0.5))
                    .scaleEffect(scale)

                Circle()
                    .stroke(accent.opacity(0.6), lineWidth: 2)
                    .scaleEffect(scale)

                VStack(spacing: 5) {
                    Text(inhaling ? L10n.s("吸气", "Breathe in") : L10n.s("呼气", "Breathe out"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Text("\(max(1, secondsLeft))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .irisMonospacedDigit()
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - 眼部运动引导

/// 一组跟练式眼部运动：左右 / 上下 / 画圆 / 对角 / 眨眼 / 远眺。
public struct EyeExerciseGuideView: View {

    struct Step {
        enum Motion { case horizontal, vertical, circle, diagonal, blink, distant }
        let motion: Motion
        let title: String
        let hint: String
        let seconds: Double
    }

    private var steps: [Step] {
        [
            Step(motion: .horizontal,
                 title: L10n.s("左右移动", "Left & right"),
                 hint: L10n.s("跟着圆点，慢慢左右看", "Follow the dot slowly"),
                 seconds: 4.5),
            Step(motion: .vertical,
                 title: L10n.s("上下移动", "Up & down"),
                 hint: L10n.s("抬头，低头，不要动头", "Eyes only — keep your head still"),
                 seconds: 4.5),
            Step(motion: .circle,
                 title: L10n.s("画个圆", "Draw a circle"),
                 hint: L10n.s("让眼球顺时针转一圈", "Roll your eyes clockwise"),
                 seconds: 5),
            Step(motion: .diagonal,
                 title: L10n.s("对角线", "Diagonal"),
                 hint: L10n.s("左上、右下，交替看", "Upper-left, lower-right"),
                 seconds: 4.5),
            Step(motion: .blink,
                 title: L10n.s("用力眨眼", "Blink firmly"),
                 hint: L10n.s("完整地眨 3 次", "Three full blinks"),
                 seconds: 4),
            Step(motion: .distant,
                 title: L10n.s("望向远方", "Look far away"),
                 hint: L10n.s("看最远的地方，直到它变清晰", "Find the farthest thing you can see"),
                 seconds: 5),
        ]
    }

    public var accent: Color
    public var size: CGFloat

    public init(accent: Color, size: CGFloat) {
        self.accent = accent
        self.size = size
    }

    private var cycleLength: Double {
        steps.reduce(0) { $0 + $1.seconds }
    }

    public var body: some View {
        TickerView(interval: 1.0 / 15.0) { tl in
            let t = tl.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleLength)
            let (step, local) = currentStep(at: t)

            VStack(spacing: 16) {
                stage(for: step, local: local)
                    .frame(width: size * 0.92, height: size * 0.62)

                VStack(spacing: 3) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Text(step.hint)
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(width: size, height: size * 0.92)
        }
    }

    private func currentStep(at t: Double) -> (Step, Double) {
        var acc = 0.0
        for step in steps {
            if t < acc + step.seconds {
                return (step, (t - acc) / step.seconds)
            }
            acc += step.seconds
        }
        return (steps[steps.count - 1], 1)
    }

    @ViewBuilder
    private func stage(for step: Step, local: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let angle = local * 2 * .pi

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )

                switch step.motion {
                case .horizontal:
                    guideDot
                        .position(x: w / 2 + sin(angle) * w * 0.33, y: h / 2)
                case .vertical:
                    guideDot
                        .position(x: w / 2, y: h / 2 - sin(angle) * h * 0.32)
                case .circle:
                    guideDot
                        .position(x: w / 2 + cos(angle) * w * 0.3,
                                  y: h / 2 + sin(angle) * h * 0.32)
                case .diagonal:
                    guideDot
                        .position(x: w / 2 + sin(angle) * w * 0.3,
                                  y: h / 2 - sin(angle) * h * 0.32)
                case .blink:
                    Image(systemName: IrisCompat.symbolName("eye", fallback: "eye"))
                        .font(.system(size: 46, weight: .light))
                        .foregroundColor(accent)
                        .scaleEffect(x: 1, y: max(0.12, abs(cos(local * .pi * 3))), anchor: .center)
                case .distant:
                    ZStack {
                        Circle()
                            .stroke(accent.opacity(0.25), lineWidth: 1)
                            .frame(width: 60, height: 60)
                            .scaleEffect(1 + local * 1.6)
                            .opacity(1 - local)
                        guideDot
                            .scaleEffect(1 - local * 0.55)
                    }
                    .position(x: w / 2, y: h / 2)
                }
            }
        }
    }

    private var guideDot: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 44, height: 44)
            Circle()
                .fill(accent)
                .frame(width: 20, height: 20)
                .shadow(color: accent.opacity(0.9), radius: 10)
        }
    }
}
