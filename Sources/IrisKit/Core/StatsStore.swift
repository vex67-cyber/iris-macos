import Foundation

/// 护眼统计数据：按天记录，落盘为 JSON，全部本地存储、不联网。
public final class StatsStore: ObservableObject {

    @Published public private(set) var days: [DayRecord] = []

    private let fileURL: URL
    private let calendar = Calendar.current

    /// 只保留最近 400 天，防止文件无限增长。
    private let retentionDays = 400

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? StatsStore.defaultFileURL()
        load()
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Iris", isDirectory: true)
    }

    public static func defaultFileURL() -> URL {
        let dir = defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stats.json")
    }

    // MARK: - Recording

    /// 记录一次休息结局。
    public func record(kind: BreakKind, outcome: BreakOutcome, seconds: Int, at date: Date = Date()) {
        let key = calendar.startOfDay(for: date)
        var rec = existing(for: key) ?? DayRecord(day: key)

        switch outcome {
        case .completed:
            switch kind {
            case .micro: rec.microTaken += 1
            case .long: rec.longTaken += 1
            }
            rec.restSeconds += max(0, seconds)
        case .skipped:
            rec.skipped += 1
        case .postponed:
            rec.postponed += 1
        }

        upsert(rec)
    }

    /// 直接写入一条完整记录（测试用）。
    public func upsert(_ record: DayRecord) {
        if let idx = days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: record.day) }) {
            days[idx] = record
        } else {
            days.append(record)
        }
        days.sort { $0.day < $1.day }
        prune()
        save()
    }

    public func clearAll() {
        days = []
        save()
    }

    // MARK: - Queries

    public func existing(for day: Date) -> DayRecord? {
        let key = calendar.startOfDay(for: day)
        return days.first { calendar.isDate($0.day, inSameDayAs: key) }
    }

    public func record(for day: Date) -> DayRecord {
        existing(for: day) ?? DayRecord(day: calendar.startOfDay(for: day))
    }

    /// 今天的成绩单。
    public var today: DayRecord {
        record(for: Date())
    }

    /// 全部时间的合计。
    public var allTime: DayRecord {
        var total = DayRecord(day: .distantPast)
        for d in days {
            total.microTaken += d.microTaken
            total.longTaken += d.longTaken
            total.skipped += d.skipped
            total.postponed += d.postponed
            total.restSeconds += d.restSeconds
        }
        return total
    }

    /// 最近 n 天(含今天)，从旧到新，缺失的天补零。
    public func recentDays(_ n: Int, endingAt date: Date = Date()) -> [DayRecord] {
        let end = calendar.startOfDay(for: date)
        return (0..<n).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: end) ?? end
            return record(for: day)
        }
    }

    /// 连续达标天数。若今天尚未达标，不打断此前的连续记录。
    public func streak(goal: Int, endingAt date: Date = Date()) -> Int {
        var count = 0
        var cursor = calendar.startOfDay(for: date)

        // 今天未达标时，从昨天开始算（今天还有机会）。
        if record(for: cursor).totalBreaks < goal {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        while record(for: cursor).totalBreaks >= goal {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            if count > retentionDays { break }
        }
        return count
    }

    /// 今天是否达标。
    public func isTodayGoalMet(goal: Int) -> Bool {
        today.totalBreaks >= goal
    }

    // MARK: - Persistence

    private func prune() {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        days.removeAll { $0.day < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([DayRecord].self, from: data) {
            days = decoded.sorted { $0.day < $1.day }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(days) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
