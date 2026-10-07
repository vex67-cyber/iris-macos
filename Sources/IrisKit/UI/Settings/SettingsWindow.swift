import AppKit
import SwiftUI

/// 设置窗口的当前分页（可以在窗口已存在时切换）。
public final class SettingsNavigation: ObservableObject {
    @Published public var pane: SettingsPane = .general
    public init() {}
}

/// 设置窗口：System Settings 风格的侧边栏 + 内容区。
final class SettingsWindowController {

    private let container: AppContainer
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(container: AppContainer) {
        self.container = container
    }

    func show(pane: SettingsPane) {
        navigation.pane = pane
        if window == nil { createWindow() }
        guard let window else { return }
        NSApp.irisActivate()
        window.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let root = SettingsRootView(navigation: navigation,
                                    settings: container.settings,
                                    stats: container.stats,
                                    calls: container.popoverCalls,
                                    onReplayOnboarding: { [weak self] in
                                        self?.window?.orderOut(nil)
                                        self?.container.onOpenOnboarding?()
                                    })

        let hosting = NSHostingController(rootView: root)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered,
                         defer: false)
        w.contentViewController = hosting
        w.title = L10n.s("明目设置", "Iris Settings")
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace]
        w.minSize = NSSize(width: 720, height: 480)
        w.center()
        window = w
    }
}

/// 侧边栏分页图标：白字形 + 品牌色渐变底 + 一丝阴影（系统设置里就是这种质感）。
private struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(LinearGradient(colors: [pane.tint.opacity(0.95), pane.tint],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: pane.symbolName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
            )
            .shadow(color: .black.opacity(0.16), radius: 1.2, y: 0.5)
    }
}

// MARK: - 根视图

public struct SettingsRootView: View {

    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var settings: AppSettings
    @ObservedObject var stats: StatsStore
    var calls: PopoverCalls
    var onReplayOnboarding: () -> Void

    public init(navigation: SettingsNavigation,
                settings: AppSettings,
                stats: StatsStore,
                calls: PopoverCalls,
                onReplayOnboarding: @escaping () -> Void) {
        self.navigation = navigation
        self.settings = settings
        self.stats = stats
        self.calls = calls
        self.onReplayOnboarding = onReplayOnboarding
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var sidebar: some View {
        // 系统设置那种侧边栏的关键是「窗口背后的半透明材质」，
        // 纯色背景一眼就廉价。这里垫一层 NSVisualEffectView(.sidebar)。
        ZStack(alignment: .top) {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)

            List(selection: Binding(get: { navigation.pane },
                                    set: { navigation.pane = $0 ?? .general })) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title).font(.system(size: 13))
                    } icon: {
                        PaneIcon(pane: pane)
                    }
                    .tag(pane)
                    .padding(.vertical, 1)
                }
            }
            .listStyle(.sidebar)
            .irisHideScrollBackground()
            .padding(.top, 28)
        }
        .frame(width: 196)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch navigation.pane {
                case .general:
                    GeneralPane(settings: settings, calls: calls)
                case .breaks:
                    BreaksPane(settings: settings)
                case .wallpaper:
                    WallpaperPane(settings: settings)
                case .sound:
                    SoundPane(settings: settings)
                case .stats:
                    StatsPane(settings: settings, stats: stats)
                case .about:
                    AboutPane(settings: settings, onReplayOnboarding: onReplayOnboarding)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .irisHideScrollBackground()
    }
}
