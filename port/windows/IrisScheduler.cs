// 明目（Mingmu）· Windows 版调度器参考实现
//
// 这是 macOS 版 BreakScheduler.swift 的等价移植，只有纯逻辑、不依赖任何 UI 框架，
// 因此可以直接放进任何 .NET 工程并单元测试（配套测试见 IrisSchedulerTests.cs）。
//
// 设计要点（与 macOS 版逐条一致）：
//   · 所有时间判断基于「绝对时刻」，而不是累加计数 —— 睡眠/卡顿/时钟跳变都不会让计时漂移
//   · 调度器自己不起定时器：由宿主每 500ms 调用一次 Tick()，方便测试与控制频率
//   · 空闲 = 已经休息过：离开超过阈值回来后给一整轮新周期，绝不"补罚"
//   · 全屏时缓期，退出全屏后补上；逾期超过一整个周期则直接重排

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Mingmu.Core;

public enum BreakKind { Micro, Long }

public enum BreakOutcome { Completed, Skipped, Postponed }

public enum PhaseKind { Working, Breaking, Paused }

public enum PauseReason { Manual, Disabled, System }

public sealed class SchedulerSettings
{
    public TimeSpan MicroInterval { get; set; } = TimeSpan.FromMinutes(20);
    public TimeSpan MicroDuration { get; set; } = TimeSpan.FromSeconds(20);
    public bool LongEnabled { get; set; } = true;
    public TimeSpan LongInterval { get; set; } = TimeSpan.FromMinutes(60);
    public TimeSpan LongDuration { get; set; } = TimeSpan.FromMinutes(5);

    public bool AllowSkip { get; set; } = true;
    public bool StrictSkip { get; set; }
    public bool AllowPostpone { get; set; } = true;
    public TimeSpan PostponeFor { get; set; } = TimeSpan.FromMinutes(5);

    public bool PreviewEnabled { get; set; } = true;
    public bool IdleResetEnabled { get; set; } = true;
    public TimeSpan IdleThreshold { get; set; } = TimeSpan.FromMinutes(2);
    public bool DeferFullscreen { get; set; } = true;
    public bool RemindersEnabled { get; set; } = true;

    /// <summary>应用中某个节奏预设（与 macOS 版三档预设一致）。</summary>
    public void ApplyPreset(string preset)
    {
        switch (preset)
        {
            case "classic":
                MicroInterval = TimeSpan.FromMinutes(20); MicroDuration = TimeSpan.FromSeconds(20);
                LongInterval = TimeSpan.FromMinutes(60); LongDuration = TimeSpan.FromMinutes(5);
                break;
            case "relaxed":
                MicroInterval = TimeSpan.FromMinutes(30); MicroDuration = TimeSpan.FromSeconds(30);
                LongInterval = TimeSpan.FromMinutes(90); LongDuration = TimeSpan.FromMinutes(10);
                break;
            case "strict":
                MicroInterval = TimeSpan.FromMinutes(10); MicroDuration = TimeSpan.FromSeconds(20);
                LongInterval = TimeSpan.FromMinutes(45); LongDuration = TimeSpan.FromMinutes(5);
                break;
        }
    }
}

/// <summary>系统状态抽象：Windows 上用 GetLastInputInfo / SystemEvents / SHQueryUserNotificationState 实现。</summary>
public interface ISystemStatus
{
    TimeSpan IdleTime { get; }
    bool IsScreenLocked { get; }
    bool IsSystemAsleep { get; }
    bool IsFullscreenApp { get; }
}

/// <summary>一天的护眼成绩单（与 macOS 版字段一致，便于数据互导）。</summary>
public sealed class DayRecord
{
    [JsonPropertyName("day")] public DateTime Day { get; set; }
    [JsonPropertyName("microTaken")] public int MicroTaken { get; set; }
    [JsonPropertyName("longTaken")] public int LongTaken { get; set; }
    [JsonPropertyName("skipped")] public int Skipped { get; set; }
    [JsonPropertyName("postponed")] public int Postponed { get; set; }
    [JsonPropertyName("restSeconds")] public int RestSeconds { get; set; }

    [JsonIgnore] public int TotalBreaks => MicroTaken + LongTaken;
}

/// <summary>按天统计，落盘为 JSON（%LOCALAPPDATA%\Mingmu\stats.json）。</summary>
public sealed class StatsStore
{
    private readonly List<DayRecord> _days = new();
    private readonly string? _path;
    private const int RetentionDays = 400;

    public StatsStore(string? filePath = null)
    {
        _path = filePath;
        Load();
    }

    public IReadOnlyList<DayRecord> Days => _days;

    public DayRecord Today => For(DateTime.Today);

    /// <summary>取某天的记录；不存在则创建（改动会保留，便于 UI 直接改字段）。</summary>
    public DayRecord For(DateTime day)
    {
        var key = day.Date;
        var found = Find(key);
        if (found == null)
        {
            found = new DayRecord { Day = key };
            _days.Add(found);
        }
        return found;
    }

    private DayRecord? Find(DateTime day) => _days.Find(d => d.Day.Date == day.Date);

    private int TotalBreaksOn(DateTime day) => Find(day)?.TotalBreaks ?? 0;

    private static bool IsEmpty(DayRecord r) =>
        r.TotalBreaks == 0 && r.Skipped == 0 && r.Postponed == 0 && r.RestSeconds == 0;

    public void Record(BreakKind kind, BreakOutcome outcome, int seconds, DateTime? at = null)
    {
        var rec = For(at ?? DateTime.Now);
        switch (outcome)
        {
            case BreakOutcome.Completed:
                if (kind == BreakKind.Micro) rec.MicroTaken++; else rec.LongTaken++;
                rec.RestSeconds += Math.Max(0, seconds);
                break;
            case BreakOutcome.Skipped: rec.Skipped++; break;
            case BreakOutcome.Postponed: rec.Postponed++; break;
        }
        Save();
    }

    /// <summary>连续达标天数；今天尚未达标时不打断已有记录。</summary>
    public int Streak(int goal, DateTime? today = null)
    {
        var cursor = (today ?? DateTime.Today).Date;
        var count = 0;
        if (TotalBreaksOn(cursor) < goal) cursor = cursor.AddDays(-1);   // 今天还有机会
        while (count <= RetentionDays && TotalBreaksOn(cursor) >= goal)
        {
            count++;
            cursor = cursor.AddDays(-1);
        }
        return count;
    }

    public void Clear() { _days.Clear(); Save(); }

    private void Load()
    {
        if (_path == null || !System.IO.File.Exists(_path)) return;
        try
        {
            var json = System.IO.File.ReadAllText(_path);
            var loaded = JsonSerializer.Deserialize<List<DayRecord>>(json);
            if (loaded != null) { _days.Clear(); _days.AddRange(loaded); }
        }
        catch { /* 数据损坏时当作空统计，不打扰用户 */ }
    }

    private void Save()
    {
        if (_path == null) return;
        try
        {
            var cutoff = DateTime.Today.AddDays(-RetentionDays);
            _days.RemoveAll(d => d.Day < cutoff);
            _days.Sort((a, b) => a.Day.CompareTo(b.Day));
            // 空记录不落盘（只保留真正有数据的日期）
            var meaningful = _days.FindAll(d => !IsEmpty(d));
            var dir = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_path, JsonSerializer.Serialize(meaningful,
                new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}

/// <summary>
/// 护眼调度器。宿主每 500ms 调用一次 <see cref="Tick"/>，并在系统事件（解锁/唤醒）时调用
/// <see cref="HandleReturn"/>。
/// </summary>
public sealed class BreakScheduler
{
    public const int MaxConsecutivePostpones = 2;
    public static readonly TimeSpan MicroPreviewLead = TimeSpan.FromSeconds(10);
    public static readonly TimeSpan LongPreviewLead = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan MergeWindow = TimeSpan.FromSeconds(90);

    private readonly SchedulerSettings _settings;
    private readonly StatsStore _stats;
    private readonly ISystemStatus _status;
    private readonly Func<DateTime> _clock;

    private bool _isAway;
    private DateTime _awayStartedAt;
    private DateTime _pausedAt;
    private DateTime? _pausedUntil;
    private DateTime? _previewedFor;

    public PhaseKind Phase { get; private set; } = PhaseKind.Working;
    public BreakKind? CurrentBreak { get; private set; }
    public DateTime NextMicroAt { get; private set; }
    public DateTime NextLongAt { get; private set; }
    public DateTime? BreakStartedAt { get; private set; }
    public DateTime? BreakEndsAt { get; private set; }
    public DateTime Now { get; private set; }
    public int ConsecutivePostpones { get; private set; }
    public string? StatusDetail { get; private set; }

    public event Action<BreakKind, TimeSpan>? BreakWillStart;   // 预告胶囊
    public event Action<BreakKind>? BreakStarted;               // 显示浮层 + 开始音
    public event Action<BreakKind, BreakOutcome>? BreakEnded;   // 收起浮层 + 结束音
    public event Action<TimeSpan>? ReturnedFromAway;            // 归来问候

    public BreakScheduler(SchedulerSettings settings, StatsStore stats, ISystemStatus status,
                          Func<DateTime>? clock = null)
    {
        _settings = settings;
        _stats = stats;
        _status = status;
        _clock = clock ?? (() => DateTime.Now);

        Now = _clock();
        NextMicroAt = Now + settings.MicroInterval;
        NextLongAt = Now + settings.LongInterval;
    }

    // ── 派生状态（UI 用） ────────────────────────────────────────────

    public bool IsWorking => Phase == PhaseKind.Working;
    public bool IsBreaking => Phase == PhaseKind.Breaking;
    public bool IsPaused => Phase == PhaseKind.Paused;

    public BreakKind NextBreakKind =>
        _settings.LongEnabled && NextLongAt <= NextMicroAt ? BreakKind.Long : BreakKind.Micro;

    public DateTime NextBreakAt => _settings.LongEnabled
        ? (NextMicroAt < NextLongAt ? NextMicroAt : NextLongAt)
        : NextMicroAt;

    public TimeSpan TimeUntilNextBreak => Max(TimeSpan.Zero, NextBreakAt - Now);

    public TimeSpan BreakRemaining => BreakEndsAt.HasValue
        ? Max(TimeSpan.Zero, BreakEndsAt.Value - Now)
        : TimeSpan.Zero;

    /// <summary>环的进度：剩余比例（1 → 0）。</summary>
    public double RemainingFraction
    {
        get
        {
            if (IsBreaking)
            {
                var total = (CurrentBreak == BreakKind.Long ? _settings.LongDuration : _settings.MicroDuration).TotalSeconds;
                return total <= 0 ? 0 : Math.Min(1, BreakRemaining.TotalSeconds / total);
            }
            if (IsWorking)
            {
                var kind = NextBreakKind;
                var total = (kind == BreakKind.Long ? _settings.LongInterval : _settings.MicroInterval).TotalSeconds;
                return total <= 0 ? 0 : Math.Min(1, TimeUntilNextBreak.TotalSeconds / total);
            }
            return 0;
        }
    }

    public int PostponesLeft => Math.Max(0, MaxConsecutivePostpones - ConsecutivePostpones);

    // ── 心跳 ────────────────────────────────────────────────────────

    public void Tick()
    {
        Now = _clock();
        HandleSettingsGate();

        if (Phase == PhaseKind.Paused)
        {
            if (_pausedUntil.HasValue && Now >= _pausedUntil.Value) Resume();
            return;
        }

        if (Phase == PhaseKind.Breaking)
        {
            if (_status.IsSystemAsleep || _status.IsScreenLocked)
            {
                FinishBreak(BreakOutcome.Completed, silent: true);
                return;
            }
            if (BreakEndsAt.HasValue && Now >= BreakEndsAt.Value) FinishBreak(BreakOutcome.Completed);
            return;
        }

        // ── 工作中 ──
        if (_status.IsSystemAsleep || _status.IsScreenLocked) { MarkAway(Now); return; }

        if (_settings.IdleResetEnabled && _status.IdleTime >= _settings.IdleThreshold)
        {
            MarkAway(Now - _status.IdleTime);
            return;
        }

        // 微休息即将到点、而长休息就在 90 秒内 → 并入长休息
        var kind = BreakKind.Micro;
        var due = NextMicroAt;
        if (Now >= NextMicroAt && _settings.LongEnabled && NextLongAt > Now &&
            NextLongAt - Now <= MergeWindow)
        {
            NextMicroAt = NextLongAt;
        }

        var longDue = _settings.LongEnabled && Now >= NextLongAt;
        var microDue = Now >= NextMicroAt;
        if (longDue || microDue)
        {
            kind = longDue ? BreakKind.Long : BreakKind.Micro;
            var dueAt = kind == BreakKind.Long ? NextLongAt : NextMicroAt;

            if (_settings.DeferFullscreen && _status.IsFullscreenApp)
            {
                var grace = kind == BreakKind.Long
                    ? MaxTime(_settings.LongInterval, TimeSpan.FromMinutes(10))
                    : MaxTime(_settings.MicroInterval, TimeSpan.FromMinutes(5));
                if (Now - dueAt > grace)
                {
                    if (kind == BreakKind.Long) NextLongAt = Now + _settings.LongInterval;
                    else NextMicroAt = Now + _settings.MicroInterval;
                }
                return;
            }

            BeginBreak(kind, Now);
            return;
        }

        MaybePreview();
    }

    private void HandleSettingsGate()
    {
        if (!_settings.RemindersEnabled)
        {
            if (Phase == PhaseKind.Paused && StatusDetail == "disabled") return;
            if (Phase == PhaseKind.Breaking) FinishBreak(BreakOutcome.Skipped, silent: true);
            Phase = PhaseKind.Paused;
            StatusDetail = "disabled";
            _pausedAt = Now;
            return;
        }
        if (Phase == PhaseKind.Paused && StatusDetail == "disabled")
        {
            RescheduleFromNow();
            StatusDetail = null;
            Phase = PhaseKind.Working;
        }
    }

    // ── 状态迁移 ────────────────────────────────────────────────────

    public void BeginBreak(BreakKind kind, DateTime? at = null)
    {
        if (!IsWorking) return;
        var now = at ?? _clock();
        var duration = kind == BreakKind.Micro ? _settings.MicroDuration : _settings.LongDuration;

        Phase = PhaseKind.Breaking;
        CurrentBreak = kind;
        BreakStartedAt = now;
        BreakEndsAt = now + duration;
        _previewedFor = null;
        Now = now;

        BreakStarted?.Invoke(kind);
    }

    /// <summary>用户主动「立即休息」。</summary>
    public void TakeBreakNow() { if (IsWorking) BeginBreak(NextBreakKind); }

    public void FinishBreak(BreakOutcome outcome, bool silent = false)
    {
        if (Phase != PhaseKind.Breaking || !BreakStartedAt.HasValue) return;
        var kind = CurrentBreak ?? BreakKind.Micro;
        var now = _clock();
        var elapsed = now - BreakStartedAt.Value;

        switch (outcome)
        {
            case BreakOutcome.Completed:
                var planned = kind == BreakKind.Micro ? _settings.MicroDuration : _settings.LongDuration;
                var seconds = (int)Math.Min(Math.Max(0, elapsed.TotalSeconds), planned.TotalSeconds);
                _stats.Record(kind, BreakOutcome.Completed, seconds, now);
                ConsecutivePostpones = 0;
                break;
            case BreakOutcome.Skipped:
                _stats.Record(kind, BreakOutcome.Skipped, 0, now);
                break;
            case BreakOutcome.Postponed:
                break; // 已在 Postpone() 里记账
        }

        Phase = PhaseKind.Working;
        CurrentBreak = null;
        BreakStartedAt = null;
        BreakEndsAt = null;
        Now = now;

        NextMicroAt = now + _settings.MicroInterval;
        if (kind == BreakKind.Long) NextLongAt = now + _settings.LongInterval;

        if (!silent) BreakEnded?.Invoke(kind, outcome);
    }

    /// <summary>跳过当前休息（严格模式下由 UI 长按确认后调用）。</summary>
    public void Skip()
    {
        if (!_settings.AllowSkip) return;
        FinishBreak(BreakOutcome.Skipped);
    }

    /// <summary>推迟当前休息（计次，超过上限后不再生效）。</summary>
    public void Postpone()
    {
        if (Phase != PhaseKind.Breaking) return;
        if (!_settings.AllowPostpone || ConsecutivePostpones >= MaxConsecutivePostpones) return;

        var now = _clock();
        var kind = CurrentBreak ?? BreakKind.Micro;
        ConsecutivePostpones++;
        _stats.Record(kind, BreakOutcome.Postponed, 0, now);

        if (kind == BreakKind.Long) NextLongAt = now + _settings.PostponeFor;
        else NextMicroAt = now + _settings.PostponeFor;

        Phase = PhaseKind.Working;
        CurrentBreak = null;
        BreakStartedAt = null;
        BreakEndsAt = null;
        _previewedFor = null;
        Now = now;

        BreakEnded?.Invoke(kind, BreakOutcome.Postponed);
    }

    /// <summary>工作状态下推迟「下一次」休息（我正在收尾，再给 5 分钟）。</summary>
    public void PostponeNext()
    {
        if (!IsWorking || !_settings.AllowPostpone) return;
        if (ConsecutivePostpones >= MaxConsecutivePostpones) return;

        var now = _clock();
        var kind = NextBreakKind;
        ConsecutivePostpones++;
        _stats.Record(kind, BreakOutcome.Postponed, 0, now);

        if (kind == BreakKind.Long) NextLongAt += _settings.PostponeFor;
        else NextMicroAt += _settings.PostponeFor;

        _previewedFor = null;
        Now = now;
    }

    // ── 暂停 / 恢复 ─────────────────────────────────────────────────

    public void Pause(TimeSpan? duration = null)
    {
        if (Phase == PhaseKind.Paused) return;
        if (Phase == PhaseKind.Breaking) FinishBreak(BreakOutcome.Skipped, silent: true);
        Phase = PhaseKind.Paused;
        StatusDetail = null;
        _pausedAt = _clock();
        _pausedUntil = duration.HasValue ? _pausedAt + duration.Value : (DateTime?)null;
    }

    public void PauseUntilTomorrow()
    {
        var tomorrow = DateTime.Today.AddDays(1).AddHours(8.5);
        var now = _clock();
        if (tomorrow <= now) tomorrow = tomorrow.AddDays(1);
        Pause(tomorrow - now);
    }

    public void Resume()
    {
        if (Phase != PhaseKind.Paused) return;
        var now = _clock();
        if (_pausedAt != default)
        {
            var shift = now - _pausedAt;         // 暂停期间计时冻结
            NextMicroAt += shift;
            NextLongAt += shift;
        }
        _pausedAt = default;
        _pausedUntil = null;
        Phase = PhaseKind.Working;
        StatusDetail = null;
        Now = now;
    }

    public void TogglePause()
    {
        if (IsPaused) Resume();
        else Pause(TimeSpan.FromMinutes(30));
    }

    // ── 离开 / 归来 ─────────────────────────────────────────────────

    private void MarkAway(DateTime startedAt)
    {
        if (_isAway) return;
        _isAway = true;
        _awayStartedAt = startedAt;
        _previewedFor = null;
    }

    /// <summary>由系统事件触发：解锁、唤醒、会话恢复。</summary>
    public void HandleReturn()
    {
        if (!_isAway) return;
        var now = _clock();
        var away = now - _awayStartedAt;
        _isAway = false;

        if (!_settings.IdleResetEnabled || away < _settings.IdleThreshold) return;

        NextMicroAt = now + _settings.MicroInterval;
        if (_settings.LongEnabled && away >= MaxTime(_settings.LongDuration, TimeSpan.FromMinutes(5)))
            NextLongAt = now + _settings.LongInterval;

        _previewedFor = null;
        ReturnedFromAway?.Invoke(away);
    }

    // ── 预告 ────────────────────────────────────────────────────────

    private void MaybePreview()
    {
        if (!_settings.PreviewEnabled) return;
        var kind = NextBreakKind;
        var due = kind == BreakKind.Long ? NextLongAt : NextMicroAt;
        var lead = kind == BreakKind.Long ? LongPreviewLead : MicroPreviewLead;
        var remaining = due - Now;

        if (remaining <= TimeSpan.Zero || remaining > lead) return;
        if (_previewedFor.HasValue && _previewedFor.Value == due) return;

        _previewedFor = due;
        BreakWillStart?.Invoke(kind, remaining);
    }

    // ── 内部工具 ────────────────────────────────────────────────────

    private void RescheduleFromNow()
    {
        var now = _clock();
        NextMicroAt = now + _settings.MicroInterval;
        NextLongAt = now + _settings.LongInterval;
        _previewedFor = null;
        Now = now;
    }

    /// <summary>宿主改了节奏参数后调用（等同于 macOS 版里监听设置变化的效果）。</summary>
    public void SettingsChanged()
    {
        if (IsWorking) RescheduleFromNow();
    }

    private static TimeSpan Max(TimeSpan a, TimeSpan b) => a > b ? a : b;
    private static TimeSpan MaxTime(TimeSpan a, TimeSpan b) => a > b ? a : b;
}
