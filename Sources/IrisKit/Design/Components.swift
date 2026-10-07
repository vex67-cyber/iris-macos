import AppKit
import SwiftUI

// MARK: - App 标记

/// 明目的品牌标记：渐变圆角方块 + 眼睛符号。
public struct AppMark: View {
    public var size: CGFloat
    public var glyph: String

    public init(size: CGFloat = 24, glyph: String = "eye") {
        self.size = size
        self.glyph = glyph
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(IrisPalette.workGradient)
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundColor(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: IrisPalette.teal.opacity(0.35), radius: size * 0.18, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

// MARK: - 进度环

/// 倒计时环：`fraction` 表示剩余比例（1 → 0），从顶部顺时针收缩。
public struct ProgressRing: View {
    public var fraction: Double
    public var lineWidth: CGFloat
    public var gradient: AngularGradient
    public var trackOpacity: Double
    public var showsGlow: Bool
    /// 是否给 fraction 变化加平滑动画。
    /// 由高频心跳（TickerView）驱动时必须关掉：否则每一帧都会再叠加一层 0.6 秒动画，白白翻倍开销。
    public var animated: Bool

    public init(fraction: Double,
                lineWidth: CGFloat = 10,
                gradient: AngularGradient = IrisPalette.ringGradient(for: .micro, urgent: false),
                trackOpacity: Double = 0.10,
                showsGlow: Bool = true,
                animated: Bool = true) {
        self.fraction = fraction
        self.lineWidth = lineWidth
        self.gradient = gradient
        self.trackOpacity = trackOpacity
        self.showsGlow = showsGlow
        self.animated = animated
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(trackOpacity),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, fraction)))
                .stroke(gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: showsGlow ? IrisPalette.teal.opacity(0.35) : .clear,
                        radius: lineWidth * 0.6)
        }
        .modifier(RingAnimation(animated: animated, fraction: fraction))
    }
}

/// 只在需要时挂上平滑动画。
private struct RingAnimation: ViewModifier {
    let animated: Bool
    let fraction: Double

    func body(content: Content) -> some View {
        if animated {
            content.irisAnimation(.easeInOut(duration: 0.6), value: fraction)
        } else {
            content
        }
    }
}

// MARK: - 按钮

/// 主操作按钮：渐变填充、白字、悬停微亮、按下微缩。
public struct PrimaryActionButton: View {
    public var title: String
    public var systemImage: String?
    public var gradient: LinearGradient
    public var action: () -> Void

    @State private var hovering = false

    public init(_ title: String, systemImage: String? = nil,
                gradient: LinearGradient = IrisPalette.workGradient,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.gradient = gradient
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: IrisMetrics.controlRadius, style: .continuous)
                    .fill(gradient)
                    .brightness(hovering ? 0.06 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: IrisMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

/// 次要按钮：中性底色 + 细描边。
public struct SecondaryActionButton: View {
    public var title: String
    public var systemImage: String?
    public var isEnabled: Bool
    public var tint: Color
    public var action: () -> Void

    @State private var hovering = false

    public init(_ title: String, systemImage: String? = nil,
                isEnabled: Bool = true, tint: Color = .primary,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .foregroundColor(isEnabled ? tint : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: IrisMetrics.controlRadius, style: .continuous)
                    .fill(Color.primary.opacity(isEnabled ? (hovering ? 0.10 : 0.055) : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IrisMetrics.controlRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: IrisMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .onHover { hovering = $0 && isEnabled }
        .accessibilityLabel(title)
    }
}

/// 按下微缩的通用按钮样式。
public struct PressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .irisAnimation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 图标按钮（popover 底栏）。
public struct IconActionButton: View {
    public var systemName: String
    public var help: String
    public var tint: Color
    public var action: () -> Void

    @State private var hovering = false

    public init(systemName: String, help: String, tint: Color = .secondary,
                action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .foregroundColor(hovering ? tint : tint.opacity(0.75))
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - 卡片

/// 轻量卡片：系统设置风格的分组容器。
public struct IrisCard<Content: View>: View {
    public var padding: CGFloat
    public var radius: CGFloat
    private let content: Content

    public init(padding: CGFloat = 14, radius: CGFloat = IrisMetrics.cardRadius,
                @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

/// 小统计块。
public struct StatTile: View {
    public var icon: String
    public var value: String
    public var label: String
    public var tint: Color

    public init(icon: String, value: String, label: String, tint: Color = IrisPalette.teal) {
        self.icon = icon
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .irisMonospacedDigit()
                .foregroundColor(.primary)
                .irisNumericTransition()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// 状态胶囊。
public struct StatusPill: View {
    public var text: String
    public var color: Color
    public var pulsing: Bool

    public init(text: String, color: Color, pulsing: Bool = false) {
        self.text = text
        self.color = color
        self.pulsing = pulsing
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: pulsing ? 4 : 0)
                .opacity(pulsing ? 0.6 : 1)
                .irisAnimation(pulsing
                           ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                           : .default,
                           value: pulsing)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - 窗口内毛玻璃

/// 真·窗口背景模糊（SwiftUI Material 在透明无边框窗口里拿不到背后内容）。
public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var isEmphasized: Bool

    public init(material: NSVisualEffectView.Material = .hudWindow,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
                isEmphasized: Bool = false) {
        self.material = material
        self.blendingMode = blendingMode
        self.isEmphasized = isEmphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
    }
}

// MARK: - 分隔线

public struct IrisDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}
