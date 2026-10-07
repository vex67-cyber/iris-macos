import Foundation

// MARK: - Break kinds & outcomes

/// 休息类型：微休息（20 秒级别的远眺）与长休息（几分钟的彻底放松）。
public enum BreakKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case micro
    case long

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .micro: return L10n.s("微休息", "Micro break")
        case .long: return L10n.s("长休息", "Long break")
        }
    }

    public var symbolName: String {
        switch self {
        case .micro: return "eye"
        case .long: return IrisCompat.symbolName("figure.walk.motion", fallback: "figure.walk")
        }
    }
}

/// 一次休息的结局。
public enum BreakOutcome: String, Codable, Sendable {
    /// 完整休息结束
    case completed
    /// 用户提前跳过
    case skipped
    /// 用户推迟
    case postponed
}

/// 提醒节奏预设。
public enum ReminderPreset: String, CaseIterable, Identifiable, Sendable {
    case classic
    case relaxed
    case strict
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: return L10n.s("经典 20-20-20", "Classic 20-20-20")
        case .relaxed: return L10n.s("轻松", "Relaxed")
        case .strict: return L10n.s("严格", "Strict")
        case .custom: return L10n.s("自定义", "Custom")
        }
    }

    public var subtitle: String {
        switch self {
        case .classic: return L10n.s("每 20 分钟休息 20 秒，每小时长休息 5 分钟", "20s every 20min · 5min every hour")
        case .relaxed: return L10n.s("每 30 分钟休息 30 秒，每 90 分钟长休息 10 分钟", "30s every 30min · 10min every 90min")
        case .strict: return L10n.s("每 10 分钟休息 20 秒，每 45 分钟长休息 5 分钟", "20s every 10min · 5min every 45min")
        case .custom: return L10n.s("按自己的节奏来", "Your own rhythm")
        }
    }

    public var symbolName: String {
        switch self {
        case .classic: return IrisCompat.symbolName("20.circle", fallback: "circle")
        case .relaxed: return IrisCompat.symbolName("leaf", fallback: "leaf")
        case .strict: return IrisCompat.symbolName("shield.lefthalf.filled", fallback: "shield")
        case .custom: return IrisCompat.symbolName("slider.horizontal.3", fallback: "slider.horizontal.3")
        }
    }

    /// (microInterval, microDuration, longInterval, longDuration) 单位：秒
    public var values: (microInterval: TimeInterval, microDuration: TimeInterval,
                        longInterval: TimeInterval, longDuration: TimeInterval)? {
        switch self {
        case .classic: return (20 * 60, 20, 60 * 60, 5 * 60)
        case .relaxed: return (30 * 60, 30, 90 * 60, 10 * 60)
        case .strict:  return (10 * 60, 20, 45 * 60, 5 * 60)
        case .custom:  return nil
        }
    }
}

/// 菜单栏要显示什么。
public enum MenuBarDisplay: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case iconAndTime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconOnly: return L10n.s("仅图标", "Icon only")
        case .iconAndTime: return L10n.s("图标 + 倒计时", "Icon + countdown")
        }
    }
}

// MARK: - Day record

/// 一天的护眼成绩单。
public struct DayRecord: Codable, Equatable, Identifiable, Sendable {
    public var day: Date
    public var microTaken: Int
    public var longTaken: Int
    public var skipped: Int
    public var postponed: Int
    /// 真正用于休息的秒数（完成的休息计入）
    public var restSeconds: Int

    public init(day: Date, microTaken: Int = 0, longTaken: Int = 0,
                skipped: Int = 0, postponed: Int = 0, restSeconds: Int = 0) {
        self.day = day
        self.microTaken = microTaken
        self.longTaken = longTaken
        self.skipped = skipped
        self.postponed = postponed
        self.restSeconds = restSeconds
    }

    public var id: Date { day }
    public var totalBreaks: Int { microTaken + longTaken }
}

// Forward-compatible decoding：以后新增字段不会让旧数据解码失败。
extension DayRecord {
    private enum CodingKeys: String, CodingKey {
        case day, microTaken, longTaken, skipped, postponed, restSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Date.self, forKey: .day)
        microTaken = try c.decodeIfPresent(Int.self, forKey: .microTaken) ?? 0
        longTaken = try c.decodeIfPresent(Int.self, forKey: .longTaken) ?? 0
        skipped = try c.decodeIfPresent(Int.self, forKey: .skipped) ?? 0
        postponed = try c.decodeIfPresent(Int.self, forKey: .postponed) ?? 0
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 0
    }
}

// MARK: - Scheduler primitives

/// 暂停原因。
public enum PauseReason: Equatable, Sendable {
    /// 用户主动暂停（until 为 nil 表示无限期）
    case manual(until: Date?)
    /// 用户在设置里关闭了提醒
    case disabled
    /// 系统层面：锁屏 / 睡眠
    case system

    public var isSystemLevel: Bool {
        if case .system = self { return true }
        return false
    }
}

/// 调度器当前所处的大状态。
public enum SchedulerPhase: Equatable, Sendable {
    case working
    case breaking(BreakKind)
    case paused(PauseReason)

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    public var isBreaking: Bool {
        if case .breaking = self { return true }
        return false
    }

    public var currentBreakKind: BreakKind? {
        if case .breaking(let kind) = self { return kind }
        return nil
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}
