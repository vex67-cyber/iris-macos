import AppKit
import SwiftUI

/// 首次启动的欢迎引导窗口。
final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private let container: AppContainer
    private var window: NSWindow?

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    func show() {
        if window == nil { createWindow() }
        guard let window else { return }
        NSApp.irisActivate()
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    private func createWindow() {
        let root = OnboardingView(settings: container.settings) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingController(rootView: root)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 566),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered,
                         defer: false)
        w.contentViewController = hosting
        w.title = L10n.s("欢迎使用明目", "Welcome to Iris")
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
    }

    private func close() {
        window?.orderOut(nil)
    }

    /// 直接关掉窗口 = 跳过引导，不要再骚扰用户。
    func windowWillClose(_ notification: Notification) {
        container.settings.hasOnboarded = true
    }
}

// MARK: - 引导界面

public struct OnboardingView: View {

    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void

    @State private var step = 0
    @State private var preset: ReminderPreset = .classic
    @State private var launchAtLogin = true

    private let stepCount = 4

    public init(settings: AppSettings, onFinish: @escaping () -> Void, initialStep: Int = 0) {
        self.settings = settings
        self.onFinish = onFinish
        _step = State(initialValue: max(0, min(3, initialStep)))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                heroBackground
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: ruleStep
                    case 2: rhythmStep
                    default: readyStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
                .padding(.horizontal, 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            IrisDivider()
            navigationBar
        }
        .frame(width: 560, height: 566)
    }

    // MARK: 背景

    private var heroBackground: some View {
        ZStack {
            LinearGradient(colors: [IrisPalette.teal.opacity(0.16),
                                    IrisPalette.indigo.opacity(0.10),
                                    Color.clear],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(IrisPalette.teal.opacity(0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -150, y: -170)
            Circle()
                .fill(IrisPalette.violet.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 160, y: -140)
        }
        .clipped()
    }

    // MARK: 步骤 1 · 欢迎

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            AppMark(size: 96, glyph: "eye")
            Text(L10n.s("明目", "Iris"))
                .font(.system(size: 30, weight: .semibold))
            Text(L10n.s("让眼睛，歇一会儿。", "Give your eyes a moment."))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Text(L10n.s("每 20 分钟提醒你望向远处 20 秒。\n不打断思路，不打扰专注。",
                        "A gentle nudge to look away every 20 minutes."))
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
    }

    // MARK: 步骤 2 · 法则

    private var ruleStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(L10n.s("每 20 分钟，看向 20 英尺外，休息 20 秒",
                        "Every 20 minutes, look 20 feet away for 20 seconds"))
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                numberCard("20", L10n.s("分钟", "minutes"), "clock")
                numberCard("20", L10n.s("英尺 ≈ 6 米", "feet ≈ 6 m"), "ruler")
                numberCard("20", L10n.s("秒", "seconds"), "hourglass")
            }

            Text(L10n.s("这是美国眼科学会（AAO）推荐的做法：盯屏幕时眨眼次数会减半，\n定期把视线移向远处，能让眼睛重新润湿、放松对焦。",
                        "Recommended by the AAO: screen time halves your blink rate; looking away lets your eyes re-wet and refocus."))
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 430)
            Spacer()
        }
    }

    private func numberCard(_ number: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(IrisPalette.teal)
            Text(number)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .irisMonospacedDigit()
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
        }
        .frame(width: 128, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: 步骤 3 · 节奏

    private var rhythmStep: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 18)
            Text(L10n.s("选择你的节奏", "Pick your rhythm"))
                .font(.system(size: 18, weight: .semibold))
            Text(L10n.s("之后随时可以在设置里调整", "You can change this anytime in Settings"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                presetRow(.classic, recommended: true)
                presetRow(.relaxed, recommended: false)
                presetRow(.strict, recommended: false)
            }
            .padding(.top, 6)
            Spacer()
        }
    }

    private func presetRow(_ option: ReminderPreset, recommended: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { preset = option }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(preset == option ? IrisPalette.teal : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.title).font(.system(size: 13.5, weight: .medium))
                        if recommended {
                            Text(L10n.s("推荐", "Recommended"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(IrisPalette.teal.opacity(0.18)))
                                .foregroundColor(IrisPalette.teal)
                        }
                    }
                    Text(option.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: preset == option ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(preset == option ? IrisPalette.teal : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(preset == option ? IrisPalette.teal.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(preset == option ? IrisPalette.teal.opacity(0.45) : Color.primary.opacity(0.07),
                                  lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 步骤 4 · 就绪

    private var readyStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 14)
            AppMark(size: 68, glyph: "eye")
            Text(L10n.s("一切就绪", "All set"))
                .font(.system(size: 22, weight: .semibold))
            Text(L10n.s("明目已经在菜单栏待命 —— 就是那个眼睛图标。",
                        "Iris is waiting in your menu bar."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            IrisCard {
                VStack(spacing: 0) {
                    Row(L10n.s("登录时自动启动", "Launch at login"),
                        subtitle: L10n.s("推荐开启，护眼不该靠记性", "Recommended")) {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    RowDivider()
                    Row(L10n.s("快捷键", "Shortcuts"),
                        subtitle: L10n.s("立即休息 · 暂停 / 恢复", "Break now · pause / resume")) {
                        Text("⌃⌥⌘B / ⌃⌥⌘P")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    RowDivider()
                    Row(L10n.s("左键点图标", "Left-click the icon"),
                        subtitle: L10n.s("查看倒计时、立即休息、暂停", "Countdown, break now, pause")) {
                        Image(systemName: IrisCompat.symbolName("cursorarrow.click", fallback: "cursorarrow"))
                            .foregroundColor(.secondary)
                    }
                    RowDivider()
                    Row(L10n.s("右键点图标", "Right-click the icon"),
                        subtitle: L10n.s("快捷菜单，不用打开窗口", "A quick menu")) {
                        Image(systemName: IrisCompat.symbolName("cursorarrow.click.2", fallback: "cursorarrow"))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: 430)

            Spacer()
        }
    }

    // MARK: 底部导航

    private var navigationBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? IrisPalette.teal : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel(L10n.s("第 \(step + 1) 步，共 \(stepCount) 步",
                                       "Step \(step + 1) of \(stepCount)"))

            Spacer()

            if step > 0 {
                Button(L10n.s("上一步", "Back")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step -= 1 }
                }
            }

            Button(step == stepCount - 1 ? L10n.s("开始使用", "Get started") : L10n.s("继续", "Continue")) {
                advance()
            }
            .keyboardShortcut(.defaultAction)
            .irisProminentButton()
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(VisualEffectBlur(material: .headerView, blendingMode: .withinWindow))
    }

    private func advance() {
        if step < stepCount - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        settings.apply(preset)
        settings.hasOnboarded = true
        if launchAtLogin != LaunchAtLogin.isEnabled {
            LaunchAtLogin.set(launchAtLogin)
        }
        onFinish()
    }
}
