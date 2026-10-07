import AppKit
import SwiftUI
import IrisKit

// 明目（Iris）· 休息浮层性能基准
//
// 用受控变体逐个测量"整块全屏浮层"里每个元素的 CPU 成本，
// 找出真正的开销来源（而不是靠猜）。
//
// 用法：swift run IrisOverlayBench <变体> [秒数]
//   变体：empty | bg | glow | glowanim | wallpaper | ring | guide | full

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "full"
let duration = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 10 : 10

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let accent = IrisPalette.teal
let wallpaperImage: NSImage? = WallpaperStore.shared.image
let kind = BreakKind.micro

// 与真实浮层一致的背景
@ViewBuilder
func background() -> some View {
    ZStack {
        IrisPalette.overlayBackground(for: kind).ignoresSafeArea()
        if variant == "wallpaper" || variant == "full", let image = wallpaperImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: 16)
                .overlay(Color.black.opacity(0.62))
                .ignoresSafeArea()
        }
    }
}

func glow(animated: Bool) -> some View {
    Color.clear
        .overlay(
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.26), accent.opacity(0.05), .clear],
                                     center: .center, startRadius: 24, endRadius: 560))
                .frame(width: 1150, height: 1150)
                .offset(x: animated ? 84 : 0, y: animated ? 62 : 0)
                .modifier(BenchGlowAnimation(enabled: animated))
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
}

struct BenchGlowAnimation: ViewModifier {
    let enabled: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .modifier(BenchAnimationModifier(enabled: enabled, on: on))
            .onAppear { on = true }
    }
}

struct BenchAnimationModifier: ViewModifier {
    let enabled: Bool
    let on: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.irisAnimation(.easeInOut(duration: 21).repeatForever(autoreverses: true), value: on)
        } else {
            content
        }
    }
}

// 1 秒一次心跳的 GPU 环
func gpuRing() -> some View {
    let context = OverlayContext(kind: kind,
                                 startsAt: Date(),
                                 endsAt: Date().addingTimeInterval(20),
                                 allowSkip: true, strictSkip: false,
                                 allowPostpone: true, postponeMinutes: 5, postponesLeft: 2,
                                 showTip: true, captureInput: false, guide: .breathing)
    return TickerView(interval: 1.0) { tl in
        let remaining = max(0, context.endsAt.timeIntervalSince(tl))
        let fraction = context.total > 0 ? remaining / context.total : 0
        ZStack {
            GPURing(fraction: fraction,
                    lineWidth: 14,
                    colors: IrisPalette.ringNSColors(for: kind, urgent: remaining <= 5.5),
                    animationDuration: 1.0)
                .frame(width: 300, height: 300)
            Text(verbatim: Fmt.countdown(remaining))
                .font(.system(size: 69, weight: .medium, design: .rounded))
                .irisMonospacedDigit()
                .foregroundColor(.white)
        }
        .frame(width: 300, height: 300)
    }
}

// ── 纯音效变体：启动时播一次，然后静置测量
if variant == "sound" || variant == "soundcleanup" {
    let player = SoundPlayer()
    if variant == "sound" {
        // 直接播，不做任何回收（旧实现的行为）
        if let snd = NSSound(named: NSSound.Name("Glass")) {
            snd.volume = 0.35
            snd.play()
        }
    } else {
        player.play("Glass", volume: 0.35)
    }
    let rootView = Color.black.ignoresSafeArea()
    for screen in NSScreen.screens {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }
    Bookkeeping.retain(player)

    RunLoop.main.run(until: Date().addingTimeInterval(2.5))   // 让声音播完
    func cpu() -> Double {
        var u = rusage()
        guard getrusage(RUSAGE_SELF, &u) == 0 else { return 0 }
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec)/1e6
             + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec)/1e6
    }
    let t0 = cpu()
    RunLoop.main.run(until: Date().addingTimeInterval(duration))
    let used = cpu() - t0
    FileHandle.standardError.write(Data(String(format: "%-12s CPU %5.1f%%  (声音播完后的静置期)\n", (variant as NSString).utf8String!, used/duration*100).utf8))
    exit(0)
}

let root: AnyView

switch variant {
case "empty":
    root = AnyView(Color.black.ignoresSafeArea())
case "bg":
    root = AnyView(background())
case "glow":
    root = AnyView(ZStack { background(); glow(animated: false) })
case "glowanim":
    root = AnyView(ZStack { background(); glow(animated: true) })
case "wallpaper":
    root = AnyView(background())
case "ring":
    root = AnyView(ZStack { background(); gpuRing() })
case "guide":
    root = AnyView(ZStack { background(); BreathingGuideView(accent: accent, size: 268) })
case "full":
    root = AnyView(
        ZStack {
            background()
            glow(animated: true)
            VStack {
                Spacer()
                gpuRing()
                Spacer()
                Text("看向 6 米以外的地方，让眼睛对焦远方")
                    .font(.system(size: 16.5))
                    .foregroundColor(.white.opacity(0.72))
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    )
default:
    root = AnyView(Color.red)
}

for screen in NSScreen.screens {
    let panel = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let hosting = NSHostingView(rootView: root)
    hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
    panel.contentView = hosting
    panel.setFrame(screen.frame, display: true)
    panel.orderFrontRegardless()
}

// 自报 CPU 用量（用 rusage，精确到微秒）
func cpuSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    let u = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    let s = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    return u + s
}

Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
RunLoop.main.run(until: Date().addingTimeInterval(2))   // 预热

let start = cpuSeconds()
RunLoop.main.run(until: Date().addingTimeInterval(duration))
let used = cpuSeconds() - start

FileHandle.standardError.write(Data(String(format: "%-12s CPU %5.1f%%\n", (variant as NSString).utf8String!, used / duration * 100).utf8))
exit(0)

enum Bookkeeping {
    nonisolated(unsafe) static var storage: [Any] = []
    static func retain(_ object: Any) { storage.append(object) }
}
