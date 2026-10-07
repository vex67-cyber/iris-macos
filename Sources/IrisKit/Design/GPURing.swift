import AppKit
import QuartzCore
import SwiftUI

// MARK: - GPU 进度环
//
// 为什么不用 SwiftUI 的 Shape 画这个环：
// 休息浮层是铺满整块屏幕的，SwiftUI 每次因心跳更新都会重绘整块
// 2880×1800 的 backing store（约 520 万像素），实测占 8–10% CPU。
// 改用 CAShapeLayer + conic 渐变后，环的推进完全由 GPU 合成，
// SwiftUI 只需每秒更新一次目标值（配合线性 CABasicAnimation 补间，视觉上依然连续），
// CPU 降到 1% 以内，而且比原来更顺滑。

public struct GPURing: NSViewRepresentable {

    /// 剩余比例：1 → 0
    public var fraction: Double
    public var lineWidth: CGFloat
    /// 环形渐变色（建议首尾同色，形成闭环）
    public var colors: [NSColor]
    public var trackColor: NSColor
    /// 从当前值过渡到新值的时长（与心跳间隔一致即可无缝衔接）
    public var animationDuration: CFTimeInterval
    /// 外发光强度（0 = 不要辉光）
    public var glowOpacity: CGFloat

    public init(fraction: Double,
                lineWidth: CGFloat,
                colors: [NSColor],
                trackColor: NSColor = NSColor(white: 1, alpha: 0.10),
                animationDuration: CFTimeInterval = 1.0,
                glowOpacity: CGFloat = 0.20) {
        self.fraction = fraction
        self.lineWidth = lineWidth
        self.colors = colors
        self.trackColor = trackColor
        self.animationDuration = animationDuration
        self.glowOpacity = glowOpacity
    }

    public func makeNSView(context: Context) -> RingLayerView {
        RingLayerView()
    }

    public func updateNSView(_ view: RingLayerView, context: Context) {
        view.update(fraction: fraction,
                    lineWidth: lineWidth,
                    colors: colors,
                    trackColor: trackColor,
                    duration: animationDuration,
                    glowOpacity: glowOpacity)
    }
}

public final class RingLayerView: NSView {

    private let trackLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    private var currentFraction: Double = 1
    private var lineWidth: CGFloat = 0
    private var didConfigure = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        trackLayer.fillColor = nil
        trackLayer.lineCap = .round

        glowLayer.fillColor = nil
        glowLayer.lineCap = .round
        glowLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        glowLayer.strokeStart = 0
        glowLayer.strokeEnd = 1

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)

        maskLayer.fillColor = nil
        maskLayer.lineCap = .round
        maskLayer.strokeColor = NSColor.white.cgColor
        maskLayer.strokeStart = 0
        maskLayer.strokeEnd = 1
        gradientLayer.mask = maskLayer

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    public override func layout() {
        super.layout()
        let radius = max(1, min(bounds.width, bounds.height) / 2 - lineWidth / 2 - 2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // 从 12 点开始、顺时针走一整圈：y 轴向上的坐标系里，起始角 π/2，
        // clockwise: true 即视觉上的顺时针，strokeEnd 会沿着这个方向增长。
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: .pi / 2, endAngle: -.pi * 1.5, clockwise: true)

        trackLayer.frame = bounds
        glowLayer.frame = bounds
        maskLayer.frame = bounds
        gradientLayer.frame = bounds

        trackLayer.path = path
        glowLayer.path = path
        maskLayer.path = path

        trackLayer.lineWidth = lineWidth
        glowLayer.lineWidth = lineWidth * 2.1
        maskLayer.lineWidth = lineWidth
    }

    func update(fraction: Double,
                lineWidth: CGFloat,
                colors: [NSColor],
                trackColor: NSColor,
                duration: CFTimeInterval,
                glowOpacity: CGFloat) {

        let geometryChanged = abs(lineWidth - self.lineWidth) > 0.01 || !didConfigure
        self.lineWidth = lineWidth
        didConfigure = true

        trackLayer.strokeColor = trackColor.cgColor
        gradientLayer.colors = colors.map { $0.cgColor }
        glowLayer.strokeColor = (colors.first ?? .white).withAlphaComponent(glowOpacity).cgColor
        glowLayer.isHidden = glowOpacity <= 0.001

        if geometryChanged { needsLayout = true }

        let target = CGFloat(max(0.0001, min(1, fraction)))
        guard abs(Double(target) - currentFraction) > 0.0005 else { return }

        // 用 presentation layer 的当前值作为起点，避免动画叠加时跳变
        let from = maskLayer.presentation()?.strokeEnd ?? CGFloat(currentFraction)

        maskLayer.strokeEnd = target
        glowLayer.strokeEnd = target
        currentFraction = Double(target)

        guard duration > 0, window != nil else { return }
        for (layer, key) in [(maskLayer, "strokeEnd"), (glowLayer, "strokeEnd")] {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: "iris.progress")
        }
    }
}

// MARK: - SwiftUI 配色 → NSColor

public extension IrisPalette {
    /// 给 GPU 环用的 NSColor 渐变（首尾同色，闭环无接缝）
    static func ringNSColors(for kind: BreakKind, urgent: Bool) -> [NSColor] {
        if urgent {
            return [nsColor(amber), nsColor(coral), nsColor(amber)]
        }
        switch kind {
        case .long:
            return [nsColor(aqua), nsColor(indigo), nsColor(violet), nsColor(aqua)]
        case .micro:
            return [nsColor(teal), nsColor(aqua), nsColor(mint), nsColor(teal)]
        }
    }

    static func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }
}
