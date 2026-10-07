import Foundation
import Testing
@testable import IrisKit

@Suite("统计仓库")
final class StatsTests {

    private func makeStore() -> (StatsStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-stats-\(UUID().uuidString).json")
        return (StatsStore(fileURL: url), url)
    }

    @Test("按天累计各类结局")
    func recordsAccumulate() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(kind: .micro, outcome: .completed, seconds: 20)
        store.record(kind: .micro, outcome: .completed, seconds: 20)
        store.record(kind: .long, outcome: .completed, seconds: 300)
        store.record(kind: .micro, outcome: .skipped, seconds: 0)
        store.record(kind: .micro, outcome: .postponed, seconds: 0)

        #expect(store.today.microTaken == 2)
        #expect(store.today.longTaken == 1)
        #expect(store.today.skipped == 1)
        #expect(store.today.postponed == 1)
        #expect(store.today.restSeconds == 340)
        #expect(store.today.totalBreaks == 3)
    }

    @Test("落盘后可以重新读回")
    func persistenceRoundTrip() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(kind: .long, outcome: .completed, seconds: 300)

        let reloaded = StatsStore(fileURL: url)
        #expect(reloaded.today.longTaken == 1)
        #expect(reloaded.today.restSeconds == 300)
    }

    @Test("最近 N 天补零且按时间升序")
    func recentDaysAreZeroFilled() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let cal = Calendar.current
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: Date())!
        store.upsert(DayRecord(day: cal.startOfDay(for: threeDaysAgo), microTaken: 5))

        let days = store.recentDays(5)
        #expect(days.count == 5)
        #expect(days[0].day < days[4].day)
        #expect(days[1].microTaken == 5)
        #expect(days[4].microTaken == 0)
    }

    @Test("连续达标不会因为今天还没达标而清零")
    func streakProtectsToday() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let cal = Calendar.current
        for offset in 1...3 {
            let day = cal.date(byAdding: .day, value: -offset, to: Date())!
            store.upsert(DayRecord(day: cal.startOfDay(for: day), microTaken: 8))
        }
        #expect(store.streak(goal: 8) == 3)

        store.upsert(DayRecord(day: cal.startOfDay(for: Date()), microTaken: 8))
        #expect(store.streak(goal: 8) == 4)
    }

    @Test("累计统计汇总所有天数")
    func allTimeAggregates() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let cal = Calendar.current
        store.upsert(DayRecord(day: cal.startOfDay(for: Date()), microTaken: 3, longTaken: 1, restSeconds: 60))
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        store.upsert(DayRecord(day: cal.startOfDay(for: yesterday), microTaken: 4, longTaken: 2, restSeconds: 600))

        #expect(store.allTime.totalBreaks == 10)
        #expect(store.allTime.restSeconds == 660)
    }

    @Test("清除后磁盘上也是空的")
    func clearAll() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(kind: .micro, outcome: .completed, seconds: 20)
        store.clearAll()
        #expect(store.today.totalBreaks == 0)
        #expect(StatsStore(fileURL: url).days.isEmpty)
    }
}

@Suite("设置与格式化")
final class SettingsTests {

    @Test("预设会写入对应节奏参数")
    func presetAppliesValues() {
        let name = "iris-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        settings.apply(.relaxed)

        #expect(settings.microInterval == 30 * 60)
        #expect(settings.microDuration == 30)
        #expect(settings.longInterval == 90 * 60)
        #expect(settings.preset == .relaxed)

        // 手动改动后应切换为"自定义"
        settings.microDuration = 45
        #expect(settings.preset == .custom)
    }

    @Test("偏好写入后能读回")
    func settingsPersist() {
        let name = "iris-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        settings.microInterval = 42 * 60
        settings.wallpaperSource = .picsum

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.microInterval == 42 * 60)
        #expect(reloaded.wallpaperSource == .picsum)
    }

    @Test("倒计时格式化")
    func countdownFormat() {
        #expect(Fmt.countdown(0) == "0:00")
        #expect(Fmt.countdown(20) == "0:20")
        #expect(Fmt.countdown(754) == "12:34")
        #expect(Fmt.countdown(3723) == "1:02:03")
        #expect(Fmt.compactCountdown(45) == "45s")
        #expect(Fmt.compactCountdown(12 * 60) == "12m")
        #expect(Fmt.compactCountdown(2 * 3600) == "2h")
    }
}
