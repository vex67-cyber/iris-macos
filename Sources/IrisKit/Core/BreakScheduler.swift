import Combine
import Foundation

/// 护眼调度器 —— 整个 App 的心脏。
///
/// 设计要点（参考 Time Out / Stretchly / LookAway 的成功经验）：
/// - 双周期：微休息 + 长休息，各自独立计时
/// - 空闲感知：离开电脑视为自然休息，回来重置计时而不是立刻"补罚"
/// - 全屏/演示/观影时自动缓期，结束之后才提醒
/// - 休息前温柔预告，休息中可推迟（计次），严格模式下长按才能跳过
public final class BreakScheduler: ObservableObject {
    // MARK: - 常量

    /// 连续推迟次数上限（防无限逃避）
    public static let maxConsecutivePostpones = 2
    /// 微休息预告提前量（秒）
    public static let microPreviewLead: TimeInterval = 10
    /// 长休息预告提前量（秒）
    public static let longPreviewLead: TimeInterval = 30
    /// 微休息临近长休息时的合并窗口（秒）
    private static let mergeWindow: TimeInterval = 90
    /// 判定「用户正在连续输入」的空闲阈值（秒）——低于它说明手没停过
    private static let typingIdleThreshold: TimeInterval = 5
    /// 为了等一个自然停顿，最多把提醒推迟多久（秒）
    private static let naturalPauseGrace: TimeInterval = 60

    // MARK: - Published 状态

    @Published public private(set) var phase: SchedulerPhase = .working
    @Published public private(set) var nextMicroAt: Date
    @Published public private(set) var nextLongAt: Date
    @Published public private(set) var breakStartedAt: Date?
    @Published public private(set) var breakEndsAt: Date?
    /// 心跳：所有时间相关的 UI 都基于它刷新
    @Published public private(set) var now: Date
    /// 连续推迟次数
    @Published public private(set) var consecutivePostpones = 0
    /// 当前自动暂停的原因（会议中 / 免打扰时段），UI 可据此显示
    @Published public private(set) var autoPauseReason: String?

    // MARK: - 回调

    /// 休息即将开始（预览提示）
    public var onBreakWillStart: ((BreakKind, TimeInterval) -> Void)?
    /// 休息开始
    public var onBreakStart: ((BreakKind, Date) -> Void)?
    /// 休息结束（completed / skipped / postponed）
    public var onBreakEnd: ((BreakKind, BreakOutcome) -> Void)?
    /// 离开后归来
    public var onReturnFromAway: ((TimeInterval) -> Void)?
    /// 每次心跳（0.5s）后触发，供菜单栏等 AppKit 层刷新
    public var onTick: ((Date) -> Void)?

    // MARK: - 依赖

    private let settings: AppSettings
    private let stats: StatsStore
    private let monitor: SystemStatusProviding
    private let clock: () -> Date

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// 已经预告过的"下一个休息时刻"，避免重复预告
    private var previewedFor: Date?
    private var isAway = false
    private var awayStartedAt: Date?
    private var pausedAt: Date?

    // MARK: - Init

    public init(settings: AppSettings,
                stats: StatsStore,
                monitor: SystemStatusProviding,
                clock: @escaping () -> Date = { Date() }) {
        self.settings = settings
        self.stats = stats
        self.monitor = monitor
        self.clock = clock
        let now = clock()
        self.now = now
        self.nextMicroAt = now.addingTimeInterval(settings.microInterval)
        self.nextLongAt = now.addingTimeInterval(settings.longInterval)
        observeRhythmChanges()
    }

    // MARK: - 生命周期

    public func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        rescheduleFromNow()
        if !settings.remindersEnabled {
            phase = .paused(.disabled)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 心跳

    private func tick() {
        let date = clock()
        now = date
        defer { onTick?(date) }

        handleSettingsGate()
        handleAutoPauseGate()

        switch phase {
        case .paused(let reason):
            if case .manual(let until) = reason, let until, date >= until {
                resume()
            }
            return

        case .breaking:
            // 系统睡眠 / 锁屏期间结束的休息，静默收尾
            if monitor.isSystemAsleep || monitor.isScreenLocked {
                finishBreak(.completed, silent: true)
                return
            }
            if let end = breakEndsAt, date >= end {
                finishBreak(.completed)
            }
            return

        case .working:
            break
        }

        // —— 工作状态 ——

        // 锁屏 / 睡眠：视为离开
        if monitor.isSystemAsleep || monitor.isScreenLocked {
            markAway(at: date)
            return
        }

        // 空闲：视为自然休息
        if settings.idleResetEnabled && monitor.idleSeconds >= settings.idleThreshold {
            markAway(at: date.addingTimeInterval(-monitor.idleSeconds))
            return
        }

        // 微休息临近长休息 → 合并成一次长休息
        if date >= nextMicroAt, settings.longEnabled, nextLongAt > date,
           nextLongAt.timeIntervalSince(date) <= BreakScheduler.mergeWindow {
            nextMicroAt = nextLongAt
        }

        let longDue = settings.longEnabled && date >= nextLongAt
        let microDue = date >= nextMicroAt

        if longDue || microDue {
            let kind: BreakKind = longDue ? .long : .micro
            let dueAt = kind == .long ? nextLongAt : nextMicroAt

            // 正在连续打字时不硬打断：等一个自然停顿再弹，最多等 60 秒
            if settings.waitForNaturalPause,
               monitor.idleSeconds < BreakScheduler.typingIdleThreshold,
               date.timeIntervalSince(dueAt) < BreakScheduler.naturalPauseGrace {
                return
            }

            // 全屏（观影 / 演示）时缓期，退出后补上
            if shouldDeferForFullscreen {
                let grace: TimeInterval = kind == .long
                    ? max(settings.longInterval, 10 * 60)
                    : max(settings.microInterval, 5 * 60)
                if date.timeIntervalSince(dueAt) > grace {
                    // 逾期太久（比如看了一部电影），重新开始一轮
                    if kind == .long {
                        nextLongAt = date.addingTimeInterval(settings.longInterval)
                    } else {
                        nextMicroAt = date.addingTimeInterval(settings.microInterval)
                    }
                }
                return
            }

            beginBreak(kind, at: date)
            return
        }

        maybePreview(at: date)
    }

    // MARK: - 状态迁移

    /// 休息总开关
    private func handleSettingsGate() {
        if !settings.remindersEnabled {
            guard !(phase == .paused(.disabled)) else { return }
            if phase.isBreaking { finishBreak(.skipped, silent: true) }
            phase = .paused(.disabled)
            pausedAt = dateNow()
            return
        }
        if phase == .paused(.disabled) {
            rescheduleFromNow()
            pausedAt = nil
            phase = .working
        }
    }

    /// 开始休息
    public func beginBreak(_ kind: BreakKind, at date: Date) {
        guard phase.isWorking else { return }
        let duration = kind == .micro ? settings.microDuration : settings.longDuration
        phase = .breaking(kind)
        breakStartedAt = date
        breakEndsAt = date.addingTimeInterval(duration)
        previewedFor = nil
        now = date
        onBreakStart?(kind, date)
    }

    /// 立即休息（用户主动）
    public func takeBreakNow() {
        guard phase.isWorking else { return }
        beginBreak(nextBreakKind, at: clock())
    }

    /// 结束 / 跳过 / 推迟当前的休息（统一收口）
    public func finishBreak(_ outcome: BreakOutcome, silent: Bool = false) {
        guard case .breaking(let kind) = phase, let started = breakStartedAt else { return }
        let date = clock()
        let elapsed = date.timeIntervalSince(started)

        switch outcome {
        case .completed:
            let planned = kind == .micro ? settings.microDuration : settings.longDuration
            let seconds = Int(min(max(0, elapsed), planned))
            stats.record(kind: kind, outcome: .completed, seconds: seconds, at: date)
            consecutivePostpones = 0

        case .skipped:
            stats.record(kind: kind, outcome: .skipped, seconds: 0, at: date)

        case .postponed:
            break // postpone() 里已记账
        }

        phase = .working
        breakStartedAt = nil
        breakEndsAt = nil
        now = date

        switch kind {
        case .micro:
            nextMicroAt = date.addingTimeInterval(settings.microInterval)
        case .long:
            nextMicroAt = date.addingTimeInterval(settings.microInterval)
            nextLongAt = date.addingTimeInterval(settings.longInterval)
        }

        if !silent {
            onBreakEnd?(kind, outcome)
        }
    }

    /// 跳过（需允许；严格模式下由 UI 长按确认后调用）
    public func skip() {
        guard settings.allowSkip else { return }
        finishBreak(.skipped)
    }

    /// 推迟（计次，超过上限后不再允许）
    public func postpone() {
        guard case .breaking(let kind) = phase else { return }
        guard settings.allowPostpone,
              consecutivePostpones < BreakScheduler.maxConsecutivePostpones else { return }

        let date = clock()
        consecutivePostpones += 1
        stats.record(kind: kind, outcome: .postponed, seconds: 0, at: date)

        let delay = Double(settings.postponeMinutes) * 60
        if kind == .long {
            nextLongAt = date.addingTimeInterval(delay)
        } else {
            nextMicroAt = date.addingTimeInterval(delay)
        }

        phase = .working
        breakStartedAt = nil
        breakEndsAt = nil
        previewedFor = nil
        now = date
        onBreakEnd?(kind, .postponed)
    }

    /// 还可以推迟几次
    public var postponesLeft: Int {
        max(0, BreakScheduler.maxConsecutivePostpones - consecutivePostpones)
    }

    /// 工作状态下推迟"下一次"休息（我正在收尾，再给 5 分钟）。
    public func postponeNext() {
        guard phase.isWorking, settings.allowPostpone else { return }
        guard consecutivePostpones < BreakScheduler.maxConsecutivePostpones else { return }

        let date = clock()
        let kind = nextBreakKind
        consecutivePostpones += 1
        stats.record(kind: kind, outcome: .postponed, seconds: 0, at: date)

        let delay = Double(settings.postponeMinutes) * 60
        if kind == .long {
            nextLongAt = nextLongAt.addingTimeInterval(delay)
        } else {
            nextMicroAt = nextMicroAt.addingTimeInterval(delay)
        }
        previewedFor = nil
        now = date
    }

    // MARK: - 暂停 / 恢复

    public func pause(until: Date?) {
        guard !phase.isPaused else { return }
        if phase.isBreaking { finishBreak(.skipped, silent: true) }
        phase = .paused(.manual(until: until))
        pausedAt = clock()
    }

    public func pause(minutes: Int) {
        pause(until: clock().addingTimeInterval(Double(minutes) * 60))
    }

    /// 暂停到明天早上（明天的 8:30，或若已过则次日）
    public func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: clock()) ?? clock()
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = 8
        comps.minute = 30
        let target = cal.date(from: comps) ?? tomorrow
        pause(until: target)
    }

    public func resume() {
        let date = clock()
        if let pausedAt {
            let delta = date.timeIntervalSince(pausedAt)
            nextMicroAt = nextMicroAt.addingTimeInterval(delta)
            nextLongAt = nextLongAt.addingTimeInterval(delta)
        }
        pausedAt = nil
        self.phase = .working
        now = date
    }

    /// 切换暂停状态（快捷键用）
    public func togglePause() {
        if phase.isPaused {
            resume()
        } else {
            pause(minutes: 30)
        }
    }

    // MARK: - 离开 / 归来

    private func markAway(at startDate: Date) {
        guard !isAway else { return }
        isAway = true
        awayStartedAt = startDate
        previewedFor = nil
    }

    /// 由系统监听（解锁 / 唤醒）触发。
    public func handleSystemReturn() {
        guard isAway, let started = awayStartedAt else { return }
        let date = clock()
        let away = date.timeIntervalSince(started)
        isAway = false
        awayStartedAt = nil

        guard settings.idleResetEnabled, away >= settings.idleThreshold else { return }

        // 回来后开始全新的一轮，而不是立刻"补罚"
        nextMicroAt = date.addingTimeInterval(settings.microInterval)
        if settings.longEnabled, away >= max(settings.longDuration, 5 * 60) {
            nextLongAt = date.addingTimeInterval(settings.longInterval)
        }
        previewedFor = nil
        onReturnFromAway?(away)
    }

    // MARK: - 预告

    private func maybePreview(at date: Date) {
        guard settings.previewEnabled else { return }
        let kind = nextBreakKind
        let due = kind == .long ? nextLongAt : nextMicroAt
        let lead = kind == .long ? BreakScheduler.longPreviewLead : BreakScheduler.microPreviewLead
        let remaining = due.timeIntervalSince(date)
        guard remaining > 0, remaining <= lead else { return }
        guard previewedFor != due else { return }
        previewedFor = due
        onBreakWillStart?(kind, remaining)
    }

    // MARK: - 派生状态（UI 用）

    /// 下一次休息是什么类型
    public var nextBreakKind: BreakKind {
        guard settings.longEnabled else { return .micro }
        return nextLongAt <= nextMicroAt ? .long : .micro
    }

    /// 下一次休息的时刻
    public var nextBreakAt: Date {
        guard settings.longEnabled else { return nextMicroAt }
        return min(nextMicroAt, nextLongAt)
    }

    /// 距下一次休息的秒数
    public var timeUntilNextBreak: TimeInterval {
        max(0, nextBreakAt.timeIntervalSince(now))
    }

    /// 当前休息剩余秒数
    public var breakRemaining: TimeInterval {
        guard let end = breakEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// 环的进度：剩余比例（1 → 0）
    public var remainingFraction: Double {
        switch phase {
        case .breaking:
            let total = phase.currentBreakKind == .long ? settings.longDuration : settings.microDuration
            guard total > 0 else { return 0 }
            return min(1, breakRemaining / total)
        case .working:
            let kind = nextBreakKind
            let total = kind == .long ? settings.longInterval : settings.microInterval
            guard total > 0 else { return 0 }
            return min(1, timeUntilNextBreak / total)
        case .paused:
            return 0
        }
    }

    // MARK: - 内部

    /// 会议与免打扰时段 → 自动暂停（原因消失后自动恢复一整轮）。
    ///
    /// 和手动暂停的区别：这里不记录暂停时长，恢复时直接重排，
    /// 因为开完会 / 午休结束本身就相当于休息过了。
    private func handleAutoPauseGate() {
        let reason = currentAutoPauseReason()

        if let reason {
            if case .paused(.system) = phase { return }
            if case .paused(.manual) = phase { return }   // 手动暂停优先
            if phase.isBreaking { finishBreak(.skipped, silent: true) }
            phase = .paused(.system)
            autoPauseReason = reason
            return
        }

        if case .paused(.system) = phase {
            autoPauseReason = nil
            rescheduleFromNow()
            phase = .working
        }
    }

    private func currentAutoPauseReason() -> String? {
        if settings.pauseDuringMeetings, monitor.isMicrophoneInUse || monitor.isCameraInUse {
            return L10n.s("会议中", "In a meeting")
        }
        if settings.quietHoursEnabled, isInQuietHours(clock()) {
            return L10n.s("免打扰时段", "Quiet hours")
        }
        return nil
    }

    /// 判断某个时刻是否落在免打扰时段内（支持跨午夜，例如 22 → 8）。
    private func isInQuietHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let start = settings.quietStartHour
        let end = settings.quietEndHour
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }

    /// 是否该因为「全屏」而缓期。
    ///
    /// 关键区分：全屏**看电影/打游戏**该缓期，但全屏**写代码/看文档**不该——
    /// 后者如果也缓期，开发者会永远收不到提醒（这是实测踩到的坑）。
    /// 因此默认只在「全屏 + 系统正在播放声音」时缓期，
    /// 用户也可以在设置里改回「任何全屏都缓期」。
    private var shouldDeferForFullscreen: Bool {
        guard settings.deferFullscreen, monitor.isFullscreenApp else { return false }
        guard settings.deferOnlyWhenPlayingMedia else { return true }
        return monitor.isAudioPlaying
    }

    /// 单元测试用：手动推进一次心跳。
    func tickForTesting() { tick() }

    private func dateNow() -> Date { clock() }

    private func rescheduleFromNow() {
        let date = clock()
        nextMicroAt = date.addingTimeInterval(settings.microInterval)
        nextLongAt = date.addingTimeInterval(settings.longInterval)
        previewedFor = nil
        now = date
    }

    /// 用户在设置里改了节奏参数 → 重新排期
    private func observeRhythmChanges() {
        func rescheduleOn<T>(_ publisher: Published<T>.Publisher) {
            publisher
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self, self.phase.isWorking else { return }
                    self.rescheduleFromNow()
                }
                .store(in: &self.cancellables)
        }

        rescheduleOn(settings.$microInterval)
        rescheduleOn(settings.$microDuration)
        rescheduleOn(settings.$longInterval)
        rescheduleOn(settings.$longDuration)
        rescheduleOn(settings.$longEnabled)
    }
}
