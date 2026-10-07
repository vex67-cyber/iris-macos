import SwiftUI

/// 菜单栏弹窗上的操作。
public struct PopoverCalls {
    public var takeBreakNow: () -> Void = {}
    public var postponeNext: () -> Void = {}
    public var skip: () -> Void = {}
    public var postpone: () -> Void = {}
    public var pause: (Int) -> Void = { _ in }
    public var pauseUntilTomorrow: () -> Void = {}
    public var resume: () -> Void = {}
    public var openSettings: () -> Void = {}
    public var openStats: () -> Void = {}
    public var openOnboarding: () -> Void = {}
    public var quit: () -> Void = {}

    public init() {}
}

/// 菜单栏弹窗主界面。
public struct PopoverView: View {

    @ObservedObject var scheduler: BreakScheduler
    @ObservedObject var settings: AppSettings
    @ObservedObject var stats: StatsStore
    var calls: PopoverCalls

    public static let width: CGFloat = IrisMetrics.popoverWidth
    public static let height: CGFloat = 408

    public init(scheduler: BreakScheduler,
                settings: AppSettings,
                stats: StatsStore,
                calls: PopoverCalls) {
        self.scheduler = scheduler
        self.settings = settings
        self.stats = stats
        self.calls = calls
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            hero
            actionArea
            Spacer(minLength: 10)
            IrisDivider()
            todayRow
            footer
        }
        .frame(width: Self.width, height: Self.height)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            AppMark(size: 22)
            Text(L10n.s("明目", "Iris"))
                .font(.system(size: 13.5, weight: .semibold))
            Spacer()
            StatusPill(text: statusText, color: statusColor, pulsing: scheduler.phase.isBreaking)
        }
        .padding(.horizontal, IrisMetrics.contentPadding)
        .padding(.top, 13)
    }

    private var statusText: String {
        switch scheduler.phase {
        case .working: return L10n.s("工作中", "Focusing")
        case .breaking(let kind): return kind.title
        case .paused(.manual): return L10n.s("已暂停", "Paused")
        case .paused(.disabled): return L10n.s("已关闭", "Off")
        case .paused(.system): return scheduler.autoPauseReason ?? L10n.s("自动暂停", "Auto-paused")
        }
    }

    private var statusColor: Color {
        switch scheduler.phase {
        case .working: return IrisPalette.teal
        case .breaking: return IrisPalette.indigo
        case .paused: return .secondary
        }
    }

    // MARK: - 主视觉

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(fraction: ringFraction,
                             lineWidth: 11,
                             gradient: IrisPalette.ringGradient(for: ringKind, urgent: isUrgent),
                             trackOpacity: 0.09)
                    .frame(width: 164, height: 164)

                VStack(spacing: 3) {
                    if scheduler.phase.isPaused {
                        Image(systemName: IrisCompat.symbolName("pause.circle.fill", fallback: "pause.circle.fill"))
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.secondary)
                    } else {
                        Text(heroValue)
                            .font(.system(size: 36, weight: .medium, design: .rounded))
                            .irisMonospacedDigit()
                            .foregroundColor(.primary)
                            .irisNumericTransition()
                            .irisAnimation(.default, value: heroValue)
                    }
                    Text(heroCaption)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: heroKindSymbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(heroKindText)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
        .padding(.top, 14)
    }

    private var ringFraction: Double {
        if case .paused = scheduler.phase { return 0.0001 }
        return scheduler.remainingFraction
    }

    private var ringKind: BreakKind? {
        switch scheduler.phase {
        case .breaking(let kind): return kind
        case .working: return scheduler.nextBreakKind
        case .paused: return nil
        }
    }

    private var isUrgent: Bool {
        scheduler.phase.isWorking && scheduler.timeUntilNextBreak <= 60
    }

    private var heroValue: String {
        switch scheduler.phase {
        case .working: return Fmt.countdown(scheduler.timeUntilNextBreak)
        case .breaking: return Fmt.countdown(scheduler.breakRemaining)
        case .paused: return ""
        }
    }

    private var heroCaption: String {
        switch scheduler.phase {
        case .working: return L10n.s("距下次休息", "Until next break")
        case .breaking: return L10n.s("休息剩余", "Break remaining")
        case .paused(.manual(let until)):
            if let until {
                return L10n.s("\(Fmt.clock(until)) 恢复", "Resumes at \(Fmt.clock(until))")
            }
            return L10n.s("暂停中", "Paused")
        case .paused(.disabled):
            return L10n.s("提醒已关闭", "Reminders off")
        case .paused(.system):
            return scheduler.autoPauseReason ?? L10n.s("自动暂停", "Auto-paused")
        }
    }

    private var heroKindSymbol: String {
        switch scheduler.phase {
        case .breaking(let kind): return kind.symbolName
        case .working: return scheduler.nextBreakKind.symbolName
        case .paused: return "moon.zzz"
        }
    }

    private var heroKindText: String {
        switch scheduler.phase {
        case .working:
            let kind = scheduler.nextBreakKind
            if kind == .long {
                return L10n.s("接下来：长休息 · \(Fmt.minutes(settings.longDuration))",
                              "Next: long break · \(Fmt.minutes(settings.longDuration))")
            }
            return L10n.s("每 \(Fmt.interval(settings.microInterval)) 一次微休息",
                          "Micro break every \(Fmt.interval(settings.microInterval))")
        case .breaking(let kind):
            return kind == .long
                ? L10n.s("起身走走，望望远处", "Stand up, look far away")
                : L10n.s("看向 6 米以外的地方", "Look 20 feet away")
        case .paused:
            return L10n.s("计时已暂停", "Timer paused")
        }
    }

    // MARK: - 操作区

    @ViewBuilder
    private var actionArea: some View {
        HStack(spacing: 8) {
            switch scheduler.phase {
            case .working:
                PrimaryActionButton(L10n.s("立即休息", "Break now"), systemImage: "eye") {
                    calls.takeBreakNow()
                }
                SecondaryActionButton(L10n.s("推迟 \(settings.postponeMinutes) 分钟", "Postpone \(settings.postponeMinutes) min"),
                                      systemImage: "clock.arrow.circlepath",
                                      isEnabled: settings.allowPostpone && scheduler.postponesLeft > 0) {
                    calls.postponeNext()
                }
            case .breaking:
                SecondaryActionButton(L10n.s("推迟", "Postpone"),
                                      systemImage: "clock.arrow.circlepath",
                                      isEnabled: scheduler.postponesLeft > 0) {
                    calls.postpone()
                }
                SecondaryActionButton(L10n.s("跳过", "Skip"),
                                      systemImage: "forward.end",
                                      isEnabled: settings.allowSkip) {
                    calls.skip()
                }
            case .paused(.disabled):
                PrimaryActionButton(L10n.s("开启提醒", "Turn on"), systemImage: "play.fill") {
                    settings.remindersEnabled = true
                }
            case .paused(.system):
                // 会议 / 免打扰时段：不提供"恢复"，否则会被立刻重新暂停
                SecondaryActionButton(L10n.s("结束后自动恢复", "Resumes automatically"),
                                      systemImage: "moon.zzz",
                                      isEnabled: false) {}
            case .paused:
                PrimaryActionButton(L10n.s("恢复提醒", "Resume"), systemImage: "play.fill") {
                    calls.resume()
                }
                SecondaryActionButton(L10n.s("设置", "Settings"), systemImage: "gearshape") {
                    calls.openSettings()
                }
            }
        }
        .padding(.horizontal, IrisMetrics.contentPadding)
        .padding(.top, 16)
    }

    // MARK: - 今日成绩

    private var todayRow: some View {
        HStack(spacing: 8) {
            miniStat(icon: "checkmark.circle.fill",
                     value: "\(stats.today.totalBreaks)",
                     label: L10n.s("今日休息", "Breaks today"),
                     tint: IrisPalette.teal)
            miniStat(icon: "hourglass",
                     value: stats.today.restSeconds > 0 ? Fmt.duration(stats.today.restSeconds) : "—",
                     label: L10n.s("休息时长", "Time rested"),
                     tint: IrisPalette.aqua)
            miniStat(icon: "flame.fill",
                     value: "\(stats.streak(goal: settings.dailyGoal))",
                     label: L10n.s("连续达标", "Day streak"),
                     tint: IrisPalette.amber)
        }
        .padding(.horizontal, IrisMetrics.contentPadding)
        .padding(.vertical, 11)
        .onTapGesture { calls.openStats() }
    }

    private func miniStat(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .irisMonospacedDigit()
                .foregroundColor(.primary)
                .irisNumericTransition()
                .irisAnimation(.default, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 3) {
            IconActionButton(systemName: "gearshape", help: L10n.s("设置", "Settings")) {
                calls.openSettings()
            }
            IconActionButton(systemName: "chart.bar.xaxis", help: L10n.s("统计", "Statistics")) {
                calls.openStats()
            }

            Menu {
                if scheduler.phase.isPaused {
                    Button(L10n.s("恢复提醒", "Resume reminders")) { calls.resume() }
                    Divider()
                }
                Button(L10n.s("暂停 30 分钟", "Pause for 30 minutes")) { calls.pause(30) }
                Button(L10n.s("暂停 1 小时", "Pause for 1 hour")) { calls.pause(60) }
                Button(L10n.s("暂停到明早", "Pause until tomorrow")) { calls.pauseUntilTomorrow() }
                Divider()
                Toggle(L10n.s("开启护眼提醒", "Enable reminders"), isOn: Binding(
                    get: { settings.remindersEnabled },
                    set: { settings.remindersEnabled = $0 }))
            } label: {
                Image(systemName: IrisCompat.symbolName("pause.circle", fallback: "pause.circle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.s("暂停 / 恢复", "Pause / resume"))

            Spacer()

            IconActionButton(systemName: "power", help: L10n.s("退出明目", "Quit Iris")) {
                calls.quit()
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 9)
    }
}
