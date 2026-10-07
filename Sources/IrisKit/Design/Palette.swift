import SwiftUI

/// 明目（Iris）的色彩体系。
///
/// 主色是一组"舒缓的青色 → 天蓝 → 靛蓝"，取自护眼场景需要的冷静与安宁；
/// 提醒临期时用琥珀色，庆祝/完成用薄荷绿。
public enum IrisPalette {

    // MARK: - 基础色

    /// 明目青（主色）
    public static let teal = Color(red: 0.20, green: 0.78, blue: 0.71)
    /// 天蓝
    public static let aqua = Color(red: 0.33, green: 0.70, blue: 0.98)
    /// 靛蓝（长休息）
    public static let indigo = Color(red: 0.49, green: 0.55, blue: 0.97)
    /// 紫罗兰（长休息渐变尾）
    public static let violet = Color(red: 0.64, green: 0.51, blue: 0.98)
    /// 薄荷（完成）
    public static let mint = Color(red: 0.40, green: 0.86, blue: 0.64)
    /// 琥珀（临期提醒）
    public static let amber = Color(red: 0.98, green: 0.68, blue: 0.26)
    /// 珊瑚（跳过 / 警示）
    public static let coral = Color(red: 0.96, green: 0.48, blue: 0.45)

    // MARK: - 渐变

    /// 微休息 / 工作状态
    public static var workGradient: LinearGradient {
        LinearGradient(colors: [teal, aqua], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 长休息
    public static var longGradient: LinearGradient {
        LinearGradient(colors: [aqua, indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 休息进行中
    public static var restGradient: LinearGradient {
        LinearGradient(colors: [teal, mint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 临期（< 1 分钟）
    public static var urgentGradient: LinearGradient {
        LinearGradient(colors: [amber, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 环形渐变

    public static func ringGradient(for kind: BreakKind?, urgent: Bool) -> AngularGradient {
        let colors: [Color]
        if urgent {
            colors = [amber, coral, amber]
        } else {
            switch kind {
            case .long: colors = [aqua, indigo, violet, aqua]
            case .micro: colors = [teal, aqua, mint, teal]
            case nil: colors = [teal, aqua, teal]
            }
        }
        return AngularGradient(colors: colors, center: .center,
                               startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    /// 浮层背景（深色渐变）
    public static func overlayBackground(for kind: BreakKind) -> LinearGradient {
        let colors: [Color] = kind == .long
            ? [Color(red: 0.05, green: 0.06, blue: 0.13),
               Color(red: 0.07, green: 0.09, blue: 0.19),
               Color(red: 0.04, green: 0.05, blue: 0.10)]
            : [Color(red: 0.04, green: 0.08, blue: 0.10),
               Color(red: 0.05, green: 0.11, blue: 0.14),
               Color(red: 0.03, green: 0.06, blue: 0.08)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 浮层中心光晕
    public static func overlayGlow(for kind: BreakKind) -> RadialGradient {
        let color = kind == .long ? indigo : teal
        return RadialGradient(colors: [color.opacity(0.28), color.opacity(0.06), .clear],
                              center: .center, startRadius: 10, endRadius: 620)
    }

    // MARK: - 语义色

    public static func accent(for kind: BreakKind) -> Color {
        kind == .long ? indigo : teal
    }

    /// 悬停背景（遵循 HIG：只改透明度，不插入新控件）
    public static func hoverBackground(_ hovering: Bool, pressed: Bool = false) -> Color {
        if pressed { return Color.primary.opacity(0.15) }
        return Color.primary.opacity(hovering ? 0.08 : 0.03)
    }
}

/// 版式常量（对齐 macOS HIG：body 13pt、caption 10-11pt、间距 4/8/12/16/20）。
public enum IrisMetrics {
    public static let popoverWidth: CGFloat = 340
    public static let contentPadding: CGFloat = 14
    public static let cardRadius: CGFloat = 12
    public static let controlRadius: CGFloat = 6
    public static let rowSpacing: CGFloat = 8
}
