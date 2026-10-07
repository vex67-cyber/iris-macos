import Foundation

/// 轻量本地化：中英文案就近书写，跟随系统语言。
public enum L10n {
    public enum Language: String {
        case chinese = "zh"
        case english = "en"
    }

    public static let language: Language = {
        for pref in Locale.preferredLanguages {
            let code = pref.lowercased()
            if code.hasPrefix("zh") { return .chinese }
            if code.hasPrefix("en") { return .english }
        }
        // 默认中文（开发者的主要用户群）
        return .chinese
    }()

    public static var isChinese: Bool { language == .chinese }

    /// 就近双语：`L10n.s("中文", "English")`
    public static func s(_ zh: String, _ en: String) -> String {
        language == .chinese ? zh : en
    }
}

/// 格式化工具。
public enum Fmt {
    /// 倒计时："12:34"、"1:02:03"、"0:20"
    public static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// 菜单栏用的紧凑倒计时："12m"、"45s"、"1h"
    public static func compactCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        if total >= 3600 { return "\(total / 3600)h" }
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }

    /// "20 秒" / "20s"
    public static func seconds(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return L10n.s("\(s) 秒", "\(s)s")
    }

    /// "20 分钟" / "20 min"
    public static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return L10n.s("\(m) 分钟", "\(m) min")
    }

    /// 人性化的间隔描述，如 "1 小时 30 分钟"
    public static func interval(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        if total < 60 { return L10n.s("\(total) 分钟", "\(total) min") }
        let h = total / 60
        let m = total % 60
        if m == 0 { return L10n.s("\(h) 小时", "\(h) hr") }
        return L10n.s("\(h) 小时 \(m) 分钟", "\(h) hr \(m) min")
    }

    /// 成绩单用的时长："1 小时 12 分" / "12 分钟" / "不足 1 分钟"
    public static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return L10n.s("不足 1 分钟", "<1 min") }
        let m = seconds / 60
        if m < 60 { return L10n.s("\(m) 分钟", "\(m) min") }
        let h = m / 60
        let r = m % 60
        if r == 0 { return L10n.s("\(h) 小时", "\(h) hr") }
        return L10n.s("\(h) 小时 \(r) 分钟", "\(h) hr \(r) min")
    }

    /// 时刻："23:41"
    public static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }

    /// 日期："10月6日" / "Oct 6"
    public static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isChinese ? "zh_Hans_CN" : "en_US")
        f.dateFormat = L10n.isChinese ? "M月d日" : "MMM d"
        return f.string(from: date)
    }

    /// 星期："周一" / "Mon"
    public static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isChinese ? "zh_Hans_CN" : "en_US")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
