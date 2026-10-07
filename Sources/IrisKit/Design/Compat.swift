import AppKit
import SwiftUI

// MARK: - 跨版本兼容层（macOS 11 Big Sur → macOS 27）
//
// 一套代码覆盖所有系统：新系统用新 API，老系统优雅降级。
// 所有判断都收敛在这里，业务代码不必写 #available。

public enum IrisCompat {

    /// 当前系统版本描述，例如 "26.5"
    public static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    /// 是否支持 SF Symbols 之外的新特性（示例：用于文案提示）
    public static var isLegacySystem: Bool {
        if #available(macOS 12.0, *) { return false }
        return true
    }

    private static var symbolCache: [String: String] = [:]

    /// 取第一个在当前系统上真实存在的 SF Symbol。
    /// 老系统的符号库较旧（`figure.walk.motion`、`eyes` 等要 macOS 13+），
    /// 缺符号时 SwiftUI 会渲染成空白，所以这里做一次探测与回退。
    public static func symbolName(_ preferred: String, fallback: String) -> String {
        if let cached = symbolCache[preferred] { return cached }
        var result = "circle"
        if NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil {
            result = preferred
        } else if NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil {
            result = fallback
        }
        symbolCache[preferred] = result
        return result
    }
}

// MARK: - NSApplication

public extension NSApplication {
    /// `activate()` 无参版本是 macOS 14+。
    func irisActivate() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - SwiftUI 修饰符兼容

public extension View {

    /// `animation(_:value:)` 是 macOS 12+，老系统直接不带动画。
    @ViewBuilder
    func irisAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        if #available(macOS 12.0, *) {
            self.animation(animation, value: value)
        } else {
            self
        }
    }

    /// `overlay(alignment:content:)` 是 macOS 12+。
    @ViewBuilder
    func irisOverlay<V: View>(alignment: Alignment, @ViewBuilder content: () -> V) -> some View {
        if #available(macOS 12.0, *) {
            self.overlay(alignment: alignment) { content() }
        } else {
            self.overlay(content(), alignment: alignment)
        }
    }

    /// 等宽数字是 macOS 12+。
    @ViewBuilder
    func irisMonospacedDigit() -> some View {
        if #available(macOS 12.0, *) {
            self.monospacedDigit()
        } else {
            self
        }
    }

    /// `scrollContentBackground` 是 macOS 13+。
    @ViewBuilder
    func irisHideScrollBackground() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// 数值滚动的 contentTransition 是 macOS 13+。
    @ViewBuilder
    func irisNumericTransition() -> some View {
        if #available(macOS 13.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }

    /// 主按钮：新系统用系统样式，老系统用自带样式兜底。
    @ViewBuilder
    func irisProminentButton() -> some View {
        if #available(macOS 12.0, *) {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(IrisProminentButtonStyle())
        }
    }
}

/// macOS 11 上代替 `.borderedProminent` 的样式。
struct IrisProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(IrisPalette.teal.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - 确认弹窗（NSAlert，macOS 11 到 27 都可用）

public enum Confirm {

    /// 危险操作前的确认。用 AppKit 原生警告框，避免 SwiftUI alert 的版本差异。
    public static func present(title: String,
                               message: String,
                               confirmTitle: String,
                               cancelTitle: String = L10n.s("取消", "Cancel"),
                               destructive: Bool = true,
                               onConfirm: @escaping () -> Void) {
        // 给主线程一个机会把按钮的按下状态画完，再弹模态框
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = destructive ? .warning : .informational
            alert.addButton(withTitle: confirmTitle)
            alert.addButton(withTitle: cancelTitle)
            NSApp.irisActivate()
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                onConfirm()
            }
        }
    }
}
