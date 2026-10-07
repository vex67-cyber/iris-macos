import SwiftUI

/// `TimelineView` 的替代品（TimelineView 需要 macOS 12，而我们要支持 Big Sur）。
///
/// 用法与 TimelineView 一致：`TickerView(interval: 1/30) { date in ... }`
public struct TickerView<Content: View>: View {

    private let interval: TimeInterval
    private let content: (Date) -> Content

    @StateObject private var clock = TickClock()

    public init(interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.content = content
    }

    public var body: some View {
        content(clock.now)
            .onAppear { clock.start(interval: interval) }
            .onDisappear { clock.stop() }
    }
}

/// 按固定间隔发布当前时间的心跳源。
final class TickClock: ObservableObject {

    @Published var now = Date()

    private var timer: Timer?

    func start(interval: TimeInterval) {
        stop()
        now = Date()
        let t = Timer(timeInterval: max(0.02, interval), repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        t.tolerance = interval * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
