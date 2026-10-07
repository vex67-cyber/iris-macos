// 明目（Mingmu）· 调度器等价测试（xUnit）
//
// 这些用例与 macOS 版 Tests/IrisKitTests/SchedulerTests.swift 一一对应，
// 用来证明 Windows 移植后的行为与 macOS 版一致。
//
// 运行：dotnet test

using System;
using Xunit;

namespace Mingmu.Core.Tests;

/// <summary>可手动推进的时钟：起点固定为「今天上午 10 点」，避免午夜前后跑测试跨天失败。</summary>
internal sealed class TestClock
{
    public DateTime Now { get; set; } = DateTime.Today.AddHours(10);
    public void Advance(double seconds) => Now = Now.AddSeconds(seconds);
}

internal sealed class StubStatus : ISystemStatus
{
    public TimeSpan IdleTime { get; set; } = TimeSpan.Zero;
    public bool IsScreenLocked { get; set; }
    public bool IsSystemAsleep { get; set; }
    public bool IsFullscreenApp { get; set; }
    public bool IsAudioPlaying { get; set; }
    public bool IsMicrophoneInUse { get; set; }
    public bool IsCameraInUse { get; set; }
}

/// <summary>每个测试一套隔离环境。</summary>
internal sealed class World
{
    public TestClock Clock { get; } = new();
    public StubStatus Status { get; } = new();
    public SchedulerSettings Settings { get; } = new();
    public StatsStore Stats { get; }
    public BreakScheduler Scheduler { get; }

    public World()
    {
        Settings.ApplyPreset("classic");
        Settings.DeferFullscreen = false;            // 需要时单独打开
        Settings.DeferOnlyWhenPlayingMedia = false;  // 同上
        Settings.WaitForNaturalPause = false;        // 默认关，避免干扰其它用例
        Settings.PauseDuringMeetings = false;        // 同上
        Settings.PreviewEnabled = false;
        Stats = new StatsStore(null);       // 纯内存，不落盘
        Scheduler = new BreakScheduler(Settings, Stats, Status, () => Clock.Now);
    }

    /// <summary>推进时间并让调度器心跳一次。</summary>
    public void Advance(double seconds)
    {
        Clock.Advance(seconds);
        Scheduler.Tick();
    }
}

public class SchedulerTests
{
    private static void AssertClose(double seconds, double expected, double tolerance = 1.0)
        => Assert.True(Math.Abs(seconds - expected) <= tolerance,
                       $"期望 {expected:F0} 秒，实际 {seconds:F0} 秒");

    // ── 基本节奏 ────────────────────────────────────────────────────

    [Fact]
    public void 到点前不打扰_到点后进入微休息()
    {
        var w = new World();
        w.Advance(20 * 60 - 1);
        Assert.True(w.Scheduler.IsWorking);

        w.Advance(2);
        Assert.Equal(BreakKind.Micro, w.Scheduler.CurrentBreak);
    }

    [Fact]
    public void 完整休息后重置计时并记入统计()
    {
        var w = new World();
        w.Advance(20 * 60 + 1);
        Assert.Equal(BreakKind.Micro, w.Scheduler.CurrentBreak);

        w.Advance(20);
        Assert.True(w.Scheduler.IsWorking);
        Assert.Equal(1, w.Stats.Today.MicroTaken);
        Assert.Equal(20, w.Stats.Today.RestSeconds);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 20 * 60);
    }

    [Fact]
    public void 长休息到点时优先于微休息()
    {
        var w = new World();
        w.Advance(60 * 60 + 1);
        Assert.Equal(BreakKind.Long, w.Scheduler.CurrentBreak);
    }

    [Fact]
    public void 长休息结束后两个计时器都重置()
    {
        var w = new World();
        w.Advance(60 * 60 + 1);
        w.Advance(5 * 60);

        Assert.True(w.Scheduler.IsWorking);
        Assert.Equal(1, w.Stats.Today.LongTaken);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 20 * 60);
    }

    [Fact]
    public void 临近的长休息会合并掉微休息()
    {
        var w = new World();
        w.Advance(60 * 60 - 60);
        Assert.True(w.Scheduler.IsWorking, "长休息还差 60 秒，此时不该休息");

        w.Advance(61);
        Assert.Equal(BreakKind.Long, w.Scheduler.CurrentBreak);
    }

    // ── 跳过与推迟 ──────────────────────────────────────────────────

    [Fact]
    public void 跳过会记录并给一个完整的新周期()
    {
        var w = new World();
        w.Advance(20 * 60 + 1);
        w.Scheduler.Skip();

        Assert.True(w.Scheduler.IsWorking);
        Assert.Equal(1, w.Stats.Today.Skipped);
        Assert.Equal(0, w.Stats.Today.MicroTaken);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 20 * 60);
    }

    [Fact]
    public void 关闭允许跳过后_跳过无效()
    {
        var w = new World();
        w.Settings.AllowSkip = false;
        w.Advance(20 * 60 + 1);
        w.Scheduler.Skip();
        Assert.True(w.Scheduler.IsBreaking);
    }

    [Fact]
    public void 推迟最多连续两次()
    {
        var w = new World();
        w.Advance(20 * 60 + 1);

        w.Scheduler.Postpone();
        Assert.True(w.Scheduler.IsWorking);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 5 * 60);
        Assert.Equal(1, w.Stats.Today.Postponed);

        w.Advance(5 * 60 + 1);
        w.Scheduler.Postpone();
        Assert.Equal(0, w.Scheduler.PostponesLeft);

        w.Advance(5 * 60 + 1);
        Assert.True(w.Scheduler.IsBreaking);
        w.Scheduler.Postpone();                 // 第三次应被拒绝
        Assert.True(w.Scheduler.IsBreaking);
    }

    [Fact]
    public void 工作状态下也能推迟下一次休息()
    {
        var w = new World();
        w.Scheduler.PostponeNext();
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 25 * 60);
    }

    // ── 智能行为 ────────────────────────────────────────────────────

    [Fact]
    public void 离开电脑时不打扰_回来重新开始一轮()
    {
        var w = new World();

        w.Status.IdleTime = TimeSpan.FromMinutes(8);
        w.Advance(8 * 60);
        Assert.True(w.Scheduler.IsWorking, "人不在时不应该弹出休息");

        w.Status.IdleTime = TimeSpan.FromMinutes(30);
        w.Advance(22 * 60);
        Assert.True(w.Scheduler.IsWorking, "离开超过一整个周期也不该补罚");

        w.Status.IdleTime = TimeSpan.Zero;
        w.Scheduler.HandleReturn();
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 20 * 60);
    }

    [Fact]
    public void 短暂离开不影响节奏()
    {
        var w = new World();
        w.Advance(5 * 60);

        w.Status.IdleTime = TimeSpan.FromSeconds(30);   // 只是停下看了会儿窗外
        w.Advance(30);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 14 * 60 + 30, 2);
    }

    [Fact]
    public void 全屏观影时缓期_退出全屏后补上提醒()
    {
        var w = new World();
        w.Settings.DeferFullscreen = true;

        w.Status.IsFullscreenApp = true;
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsWorking, "全屏时不该打扰");

        w.Status.IsFullscreenApp = false;
        w.Scheduler.Tick();
        Assert.True(w.Scheduler.IsBreaking, "退出全屏后应补上这次提醒");
    }

    // ── 自动判断（会议 / 免打扰 / 自然停顿）────────────────────────

    [Fact]
    public void 开会时自动暂停_散会后自动恢复全新一轮()
    {
        var w = new World();
        w.Settings.PauseDuringMeetings = true;
        w.Status.IsMicrophoneInUse = true;

        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsPaused, "开会时不该弹提醒");
        Assert.Equal(PauseKind.System, w.Scheduler.PauseState);
        Assert.Equal(AutoPauseCause.Meeting, w.Scheduler.AutoPause);

        w.Status.IsMicrophoneInUse = false;
        w.Scheduler.Tick();
        Assert.True(w.Scheduler.IsWorking);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 20 * 60);
    }

    [Fact]
    public void 摄像头占用也算会议中()
    {
        var w = new World();
        w.Settings.PauseDuringMeetings = true;
        w.Status.IsCameraInUse = true;
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsPaused);
    }

    [Fact]
    public void 关掉开会自动暂停后照常提醒()
    {
        var w = new World();
        w.Status.IsMicrophoneInUse = true;   // World 默认已关掉该开关
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsBreaking);
    }

    [Fact]
    public void 免打扰时段内不提醒_时段结束后恢复()
    {
        var w = new World();                 // 时钟起点是今天 10:00
        w.Settings.QuietHoursEnabled = true;
        w.Settings.QuietStartHour = 9;
        w.Settings.QuietEndHour = 11;

        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsPaused);
        Assert.Equal(AutoPauseCause.QuietHours, w.Scheduler.AutoPause);

        w.Settings.QuietHoursEnabled = false;
        w.Scheduler.Tick();
        Assert.True(w.Scheduler.IsWorking);
    }

    [Fact]
    public void 免打扰时段支持跨午夜()
    {
        var w = new World();
        w.Settings.QuietHoursEnabled = true;
        w.Settings.QuietStartHour = 22;
        w.Settings.QuietEndHour = 8;         // 22:00 – 08:00

        // 起点 10:00 不在时段内 → 正常提醒
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsBreaking);

        // 拨到 23:00 → 落在时段内
        var w2 = new World();
        w2.Clock.Now = DateTime.Today.AddHours(23);
        w2.Settings.QuietHoursEnabled = true;
        w2.Settings.QuietStartHour = 22;
        w2.Settings.QuietEndHour = 8;
        w2.Advance(20 * 60 + 1);
        Assert.True(w2.Scheduler.IsPaused);
    }

    [Fact]
    public void 连续打字时不硬打断_手停下来立刻提醒()
    {
        var w = new World();
        w.Settings.WaitForNaturalPause = true;

        w.Status.IdleTime = TimeSpan.Zero;   // 一直在打字
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsWorking, "正在打字时应该等一个自然停顿");

        w.Status.IdleTime = TimeSpan.FromSeconds(10);   // 手停了
        w.Scheduler.Tick();
        Assert.True(w.Scheduler.IsBreaking);
    }

    [Fact]
    public void 自然停顿最多等六十秒()
    {
        var w = new World();
        w.Settings.WaitForNaturalPause = true;

        w.Status.IdleTime = TimeSpan.Zero;
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsWorking);

        w.Advance(61);                       // 超过宽限
        Assert.True(w.Scheduler.IsBreaking);
    }

    [Fact]
    public void 全屏写代码照常提醒_全屏且有声音才缓期()
    {
        var w = new World();
        w.Settings.DeferFullscreen = true;
        w.Settings.DeferOnlyWhenPlayingMedia = true;   // 默认值

        w.Status.IsFullscreenApp = true;
        w.Status.IsAudioPlaying = false;               // 全屏写代码
        w.Advance(20 * 60 + 1);
        Assert.True(w.Scheduler.IsBreaking, "全屏写代码不该被缓期，否则永远收不到提醒");

        var w2 = new World();
        w2.Settings.DeferFullscreen = true;
        w2.Settings.DeferOnlyWhenPlayingMedia = true;
        w2.Status.IsFullscreenApp = true;
        w2.Status.IsAudioPlaying = true;               // 在看电影
        w2.Advance(20 * 60 + 1);
        Assert.True(w2.Scheduler.IsWorking, "看电影时应该缓期");
    }

    // ── 暂停 ────────────────────────────────────────────────────────

    [Fact]
    public void 暂停冻结计时_恢复后继续()
    {
        var w = new World();
        w.Advance(5 * 60);
        var remaining = w.Scheduler.TimeUntilNextBreak;

        w.Scheduler.Pause(TimeSpan.FromMinutes(30));
        Assert.True(w.Scheduler.IsPaused);

        w.Advance(10 * 60);
        Assert.True(w.Scheduler.IsPaused);

        w.Scheduler.Resume();
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, remaining.TotalSeconds);
    }

    [Fact]
    public void 暂停到点自动恢复()
    {
        var w = new World();
        w.Scheduler.Pause(TimeSpan.FromMinutes(15));
        w.Advance(15 * 60 + 1);
        Assert.True(w.Scheduler.IsWorking);
    }

    [Fact]
    public void 关闭提醒会暂停_重新开启时重排一整轮()
    {
        var w = new World();
        w.Settings.RemindersEnabled = false;
        w.Scheduler.Tick();
        Assert.True(w.Scheduler.IsPaused);

        w.Advance(60 * 60);
        w.Settings.RemindersEnabled = true;
        w.Scheduler.Tick();
        Assert.True(w.Scheduler.IsWorking);
        AssertClose(w.Scheduler.TimeUntilNextBreak.TotalSeconds, 20 * 60);
    }

    // ── 预告 ────────────────────────────────────────────────────────

    [Fact]
    public void 同一个休息时刻只预告一次()
    {
        var w = new World();
        w.Settings.PreviewEnabled = true;
        var count = 0;
        w.Scheduler.BreakWillStart += (_, _) => count++;

        w.Advance(20 * 60 - 9);
        Assert.Equal(1, count);

        w.Advance(3);
        Assert.Equal(1, count);
    }

    // ── 手动休息与结束 ──────────────────────────────────────────────

    [Fact]
    public void 立即休息马上进入休息状态()
    {
        var w = new World();
        w.Scheduler.TakeBreakNow();
        Assert.True(w.Scheduler.IsBreaking);
        Assert.Equal(BreakKind.Micro, w.Scheduler.CurrentBreak);
    }

    [Fact]
    public void 休息到时长自动结束并记入统计()
    {
        var w = new World();
        w.Scheduler.TakeBreakNow();
        w.Advance(20);
        Assert.True(w.Scheduler.IsWorking);
        Assert.Equal(1, w.Stats.Today.MicroTaken);
    }

    [Fact]
    public void 锁屏期间到点的休息会静默结束()
    {
        var w = new World();
        w.Scheduler.TakeBreakNow();

        w.Status.IsScreenLocked = true;
        w.Advance(25);
        Assert.True(w.Scheduler.IsWorking);
    }
}

public class StatsTests
{
    [Fact]
    public void 按天累计各类结局()
    {
        var stats = new StatsStore(null);
        stats.Record(BreakKind.Micro, BreakOutcome.Completed, 20);
        stats.Record(BreakKind.Micro, BreakOutcome.Completed, 20);
        stats.Record(BreakKind.Long, BreakOutcome.Completed, 300);
        stats.Record(BreakKind.Micro, BreakOutcome.Skipped, 0);
        stats.Record(BreakKind.Micro, BreakOutcome.Postponed, 0);

        Assert.Equal(2, stats.Today.MicroTaken);
        Assert.Equal(1, stats.Today.LongTaken);
        Assert.Equal(1, stats.Today.Skipped);
        Assert.Equal(1, stats.Today.Postponed);
        Assert.Equal(340, stats.Today.RestSeconds);
        Assert.Equal(3, stats.Today.TotalBreaks);
    }

    [Fact]
    public void 连续达标不会因为今天还没达标而清零()
    {
        var stats = new StatsStore(null);
        for (var i = 1; i <= 3; i++)
        {
            var rec = stats.For(DateTime.Today.AddDays(-i));
            rec.MicroTaken = 8;
        }
        Assert.Equal(3, stats.Streak(8));

        stats.For(DateTime.Today).MicroTaken = 8;
        Assert.Equal(4, stats.Streak(8));
    }
}
