import Foundation
import Testing
@testable import IrisKit

// 用 swift-testing（CLT 自带，不需要 XCTest）。

/// 可手动推进的时钟，让调度器测试完全确定。
///
/// 起点固定为"今天上午 10 点"：既落在今天（StatsStore 按天归档），
/// 又能推进几个小时而不跨天（否则午夜前后跑测试会随机失败）。
final class TestClock {
    var now: Date

    init(_ start: Date = TestClock.safeStart()) { now = start }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    static func safeStart() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

final class StubMonitor: SystemStatusProviding {
    var idleSeconds: TimeInterval = 0
    var isScreenLocked = false
    var isSystemAsleep = false
    var isFullscreenApp = false
}

/// 每个测试一套隔离的世界（独立的时钟、偏好 suite、临时统计文件）。
final class TestWorld {
    let clock: TestClock
    let monitor: StubMonitor
    let settings: AppSettings
    let stats: StatsStore
    let scheduler: BreakScheduler

    private let suiteName: String
    private let statsURL: URL

    init() {
        let clock = TestClock()
        let monitor = StubMonitor()

        let suiteName = "iris-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let settings = AppSettings(defaults: defaults)
        settings.apply(.classic)
        settings.allowSkip = true
        settings.allowPostpone = true
        settings.strictSkip = false
        settings.idleResetEnabled = true
        settings.idleThreshold = 120
        settings.deferFullscreen = false
        settings.previewEnabled = false
        settings.remindersEnabled = true

        let statsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-test-\(UUID().uuidString).json")
        let stats = StatsStore(fileURL: statsURL)

        let scheduler = BreakScheduler(settings: settings,
                                       stats: stats,
                                       monitor: monitor,
                                       clock: { clock.now })

        self.clock = clock
        self.monitor = monitor
        self.settings = settings
        self.stats = stats
        self.scheduler = scheduler
        self.suiteName = suiteName
        self.statsURL = statsURL
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: statsURL)
    }

    /// 推进时间并让调度器心跳一次。
    func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        scheduler.tickForTesting()
    }
}

@Suite("护眼调度器")
final class SchedulerTests {

    // MARK: 基本节奏

    @Test("到点前不打扰，到点后进入微休息")
    func microBreakFiresAfterInterval() {
        let w = TestWorld()
        w.scheduler.start()

        w.advance(20 * 60 - 1)
        #expect(w.scheduler.phase.isWorking)

        w.advance(2)
        #expect(w.scheduler.phase.currentBreakKind == .micro)
    }

    @Test("完整休息后重置计时并记入统计")
    func completingMicroBreakRecordsStats() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(20 * 60 + 1)
        #expect(w.scheduler.phase.currentBreakKind == .micro)

        w.advance(20)
        #expect(w.scheduler.phase.isWorking)
        #expect(w.stats.today.microTaken == 1)
        #expect(w.stats.today.restSeconds == 20)
        #expect(abs(w.scheduler.timeUntilNextBreak - 20 * 60) < 1)
    }

    @Test("长休息到点时优先于微休息")
    func longBreakHasPriority() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(60 * 60 + 1)
        #expect(w.scheduler.phase.currentBreakKind == .long)
    }

    @Test("长休息结束后两个计时器都重置")
    func longBreakResetsBothTimers() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(60 * 60 + 1)
        w.advance(5 * 60)

        #expect(w.scheduler.phase.isWorking)
        #expect(w.stats.today.longTaken == 1)
        #expect(abs(w.scheduler.timeUntilNextBreak - 20 * 60) < 1)
    }

    @Test("临近的长休息会合并掉微休息")
    func microMergesIntoImminentLongBreak() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(60 * 60 - 60)
        #expect(w.scheduler.phase.isWorking)

        w.advance(61)
        #expect(w.scheduler.phase.currentBreakKind == .long)
    }

    // MARK: 跳过与推迟

    @Test("跳过会记录并给一个完整的新周期")
    func skipRecordsAndGrantsFreshInterval() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(20 * 60 + 1)
        w.scheduler.skip()

        #expect(w.scheduler.phase.isWorking)
        #expect(w.stats.today.skipped == 1)
        #expect(w.stats.today.microTaken == 0)
        #expect(abs(w.scheduler.timeUntilNextBreak - 20 * 60) < 1)
    }

    @Test("关闭允许跳过后，跳过无效")
    func skipBlockedWhenDisallowed() {
        let w = TestWorld()
        w.settings.allowSkip = false
        w.scheduler.start()
        w.advance(20 * 60 + 1)
        w.scheduler.skip()
        #expect(w.scheduler.phase.isBreaking)
    }

    @Test("推迟最多连续两次")
    func postponeIsLimited() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(20 * 60 + 1)

        w.scheduler.postpone()
        #expect(w.scheduler.phase.isWorking)
        #expect(abs(w.scheduler.timeUntilNextBreak - 5 * 60) < 1)
        #expect(w.stats.today.postponed == 1)

        w.advance(5 * 60 + 1)
        w.scheduler.postpone()
        #expect(w.scheduler.postponesLeft == 0)

        w.advance(5 * 60 + 1)
        #expect(w.scheduler.phase.isBreaking)
        w.scheduler.postpone()
        #expect(w.scheduler.phase.isBreaking)
    }

    @Test("工作状态下也能推迟下一次休息")
    func postponeNext() {
        let w = TestWorld()
        w.scheduler.start()
        w.scheduler.postponeNext()
        #expect(abs(w.scheduler.timeUntilNextBreak - 25 * 60) < 1)
    }

    // MARK: 智能行为

    @Test("离开电脑时不打扰，回来重新开始一轮")
    func idleResetsCycle() {
        let w = TestWorld()
        w.scheduler.start()

        // 离开 8 分钟（超过空闲阈值）
        w.monitor.idleSeconds = 8 * 60
        w.advance(8 * 60)
        #expect(w.scheduler.phase.isWorking, "人不在时不应该弹出休息")

        // 离开超过一整个周期也不该"补罚"
        w.monitor.idleSeconds = 30 * 60
        w.advance(22 * 60)
        #expect(w.scheduler.phase.isWorking)

        // 回来：开始全新一轮
        w.monitor.idleSeconds = 0
        w.scheduler.handleSystemReturn()
        #expect(abs(w.scheduler.timeUntilNextBreak - 20 * 60) < 1)
    }

    @Test("短暂离开（未达阈值）不影响节奏")
    func shortIdleDoesNotReset() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(5 * 60)

        w.monitor.idleSeconds = 30   // 只是停下来看了会儿窗外
        w.advance(30)
        // 从开始算起过了 5 分 30 秒，剩余应为 14 分 30 秒
        #expect(abs(w.scheduler.timeUntilNextBreak - (14 * 60 + 30)) < 2)
    }

    @Test("全屏观影时缓期，退出全屏后补上提醒")
    func fullscreenDefersReminder() {
        let w = TestWorld()
        w.settings.deferFullscreen = true
        w.scheduler.start()

        // 一直在全屏 → 到点也不打扰
        w.monitor.isFullscreenApp = true
        w.advance(20 * 60 + 1)
        #expect(w.scheduler.phase.isWorking)

        // 退出全屏 → 补上这次提醒
        w.monitor.isFullscreenApp = false
        w.scheduler.tickForTesting()
        #expect(w.scheduler.phase.isBreaking)
    }

    // MARK: 暂停

    @Test("暂停冻结计时，恢复后继续")
    func pausePreservesRemaining() {
        let w = TestWorld()
        w.scheduler.start()
        w.advance(5 * 60)
        let remaining = w.scheduler.timeUntilNextBreak

        w.scheduler.pause(minutes: 30)
        #expect(w.scheduler.phase.isPaused)

        w.advance(10 * 60)
        #expect(w.scheduler.phase.isPaused)

        w.scheduler.resume()
        #expect(abs(w.scheduler.timeUntilNextBreak - remaining) < 1)
    }

    @Test("暂停到点自动恢复")
    func pauseAutoResumes() {
        let w = TestWorld()
        w.scheduler.start()
        w.scheduler.pause(minutes: 15)
        w.advance(15 * 60 + 1)
        #expect(w.scheduler.phase.isWorking)
    }

    @Test("关闭提醒会暂停，重新打开时重新开始一轮")
    func disablingRemindersResets() {
        let w = TestWorld()
        w.scheduler.start()
        w.settings.remindersEnabled = false
        w.scheduler.tickForTesting()
        #expect(w.scheduler.phase.isPaused)

        w.advance(60 * 60)
        w.settings.remindersEnabled = true
        w.scheduler.tickForTesting()
        #expect(w.scheduler.phase.isWorking)
        #expect(abs(w.scheduler.timeUntilNextBreak - 20 * 60) < 1)
    }

    // MARK: 预告

    @Test("同一个休息时刻只预告一次")
    func previewFiresOnce() {
        let w = TestWorld()
        w.settings.previewEnabled = true
        var previews: [BreakKind] = []
        w.scheduler.onBreakWillStart = { kind, _ in previews.append(kind) }
        w.scheduler.start()

        w.advance(20 * 60 - 9)
        #expect(previews.count == 1)

        w.advance(3)
        #expect(previews.count == 1)
    }

    // MARK: 手动休息

    @Test("立即休息马上进入休息状态")
    func takeBreakNow() {
        let w = TestWorld()
        w.scheduler.start()
        w.scheduler.takeBreakNow()
        #expect(w.scheduler.phase.isBreaking)
        #expect(w.scheduler.phase.currentBreakKind == .micro)
    }

    @Test("休息到时长自动结束并记入统计")
    func breakEndsAutomatically() {
        let w = TestWorld()
        w.scheduler.start()
        w.scheduler.takeBreakNow()
        w.advance(20)
        #expect(w.scheduler.phase.isWorking)
        #expect(w.stats.today.microTaken == 1)
    }

    @Test("锁屏期间到点的休息会静默结束")
    func breakEndsQuietlyWhileLocked() {
        let w = TestWorld()
        w.scheduler.start()
        w.scheduler.takeBreakNow()

        w.monitor.isScreenLocked = true
        w.advance(25)
        #expect(w.scheduler.phase.isWorking)
    }
}
