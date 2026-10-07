import AppKit
import SwiftUI

// MARK: - 复用组件

struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

struct Row<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, icon: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 14)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct RowDivider: View {
    var body: some View {
        IrisDivider().padding(.leading, 14)
    }
}

// MARK: - 通用

struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    var calls: PopoverCalls

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        PaneHeader(title: L10n.s("通用", "General"),
                   subtitle: L10n.s("明目常驻菜单栏，按你的节奏安静地提醒休息。",
                                    "Iris lives in the menu bar and nudges you gently."))

        SettingsGroup(L10n.s("提醒", "Reminders")) {
            Row(L10n.s("开启护眼提醒", "Enable reminders"),
                subtitle: L10n.s("关闭后计时暂停，菜单栏图标变为斜杠眼睛", "Turning off pauses the timer")) {
                Toggle("", isOn: $settings.remindersEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("菜单栏显示", "Menu bar display")) {
                Picker("", selection: $settings.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 168)
            }
        }

        SettingsGroup(L10n.s("智能", "Smart")) {
            Row(L10n.s("空闲时自动重置", "Reset when you're away"),
                subtitle: L10n.s("离开电脑就当作已经休息过，回来重新开始一轮",
                                 "Being away counts as rest — no overdue nagging")) {
                Toggle("", isOn: $settings.idleResetEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.idleResetEnabled {
                RowDivider()
                Row(L10n.s("空闲判定", "Away threshold")) {
                    Picker("", selection: $settings.idleThreshold) {
                        Text(L10n.s("1 分钟", "1 min")).tag(60.0)
                        Text(L10n.s("2 分钟", "2 min")).tag(120.0)
                        Text(L10n.s("3 分钟", "3 min")).tag(180.0)
                        Text(L10n.s("5 分钟", "5 min")).tag(300.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
            RowDivider()
            Row(L10n.s("全屏时暂缓提醒", "Defer while fullscreen"),
                subtitle: L10n.s("看电影、打游戏、演示时不打扰", "For movies, games, presentations")) {
                Toggle("", isOn: $settings.deferFullscreen)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.deferFullscreen {
                RowDivider()
                Row(L10n.s("仅在播放声音时暂缓", "Only when audio is playing"),
                    subtitle: L10n.s("推荐开启：全屏写代码、看文档时照常提醒；关闭后任何全屏应用都不会被打断",
                                     "Recommended: fullscreen coding still gets reminders")) {
                    Toggle("", isOn: $settings.deferOnlyWhenPlayingMedia)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            RowDivider()
            Row(L10n.s("连续输入时等一个停顿", "Wait for a natural pause"),
                subtitle: L10n.s("正在打字时不硬打断，等手停下来再提醒（最多等 60 秒）",
                                 "Don't interrupt mid-typing — wait up to 60 s for a pause")) {
                Toggle("", isOn: $settings.waitForNaturalPause)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("开会时自动暂停", "Auto-pause in meetings"),
                subtitle: L10n.s("检测到麦克风或摄像头被占用就暂停，散会后自动恢复",
                                 "Pauses while the microphone or camera is in use")) {
                Toggle("", isOn: $settings.pauseDuringMeetings)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("免打扰时段", "Quiet hours"),
                subtitle: L10n.s("例如午休时间不打扰；跨午夜也支持（如 22:00 – 08:00）",
                                 "Time ranges work across midnight too")) {
                Toggle("", isOn: $settings.quietHoursEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.quietHoursEnabled {
                RowDivider()
                Row(L10n.s("时间段", "Time range")) {
                    HStack(spacing: 6) {
                        hourPicker($settings.quietStartHour)
                        Text("–").foregroundColor(.secondary)
                        hourPicker($settings.quietEndHour)
                    }
                }
            }
        }

        SettingsGroup(L10n.s("系统集成", "System")) {
            Row(L10n.s("登录时自动启动", "Launch at login"),
                subtitle: LaunchAtLogin.statusDescription) {
                Toggle("", isOn: Binding(get: { launchAtLogin },
                                         set: { setLaunchAtLogin($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if LaunchAtLogin.requiresApproval {
                RowDivider()
                Row(L10n.s("需要你在系统设置中批准", "Waiting for approval"),
                    subtitle: L10n.s("「系统设置 → 通用 → 登录项」中允许「明目」",
                                     "Allow Iris under System Settings › General › Login Items")) {
                    Button(L10n.s("打开系统设置", "Open Settings")) {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                }
            }
            RowDivider()
            Row(L10n.s("系统通知", "System notifications"),
                subtitle: L10n.s("休息前 30 秒发一条通知（首次开启会请求授权）",
                                 "A notification 30 s before each break")) {
                Toggle("", isOn: Binding(get: { settings.notificationsEnabled },
                                         set: { enableNotifications($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.notificationsEnabled {
                RowDivider()
                Row(L10n.s("提前 30 秒通知", "Notify 30 s ahead")) {
                    Toggle("", isOn: $settings.preBreakNotice)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }

        SettingsGroup(L10n.s("快捷键", "Shortcuts")) {
            Row(L10n.s("立即休息", "Take a break now")) {
                shortcutBadge("⌃⌥⌘B")
            }
            RowDivider()
            Row(L10n.s("暂停 / 恢复", "Pause / resume")) {
                shortcutBadge("⌃⌥⌘P")
            }
        }

        HStack {
            Spacer()
            Button {
                Confirm.present(
                    title: L10n.s("恢复默认设置？", "Restore default settings?"),
                    message: L10n.s("统计数据与壁纸缓存不会被删除。", "Statistics and cached wallpapers are kept."),
                    confirmTitle: L10n.s("恢复", "Restore")) {
                    settings.resetToDefaults()
                }
            } label: {
                Text(L10n.s("恢复默认设置", "Restore defaults"))
            }
        }
        .padding(.top, 2)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    private func hourPicker(_ binding: Binding<Int>) -> some View {
        Picker("", selection: binding) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 92)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let error = LaunchAtLogin.set(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
        if let error {
            NSLog("Iris: launch at login failed: \(error)")
        }
    }

    private func enableNotifications(_ enabled: Bool) {
        guard enabled else {
            settings.notificationsEnabled = false
            return
        }
        Notifier.shared.requestAuthorization { granted in
            settings.notificationsEnabled = granted
        }
    }
}

// MARK: - 休息

struct BreaksPane: View {
    @ObservedObject var settings: AppSettings

    // 注意：这里不要观察 BreakScheduler。
    // 调度器每 0.5 秒发布一次心跳，一旦被设置窗口观察到，
    // 整个设置界面（含壁纸预览的大图模糊）就会 2 次/秒重绘，CPU 直接飙到 40%。

    var body: some View {
        PaneHeader(title: L10n.s("休息", "Breaks"),
                   subtitle: L10n.s("经典 20-20-20：每 20 分钟，看 6 米外 20 秒。由美国眼科学会推荐。",
                                    "The classic 20-20-20 rule, recommended by the AAO."))

        SettingsGroup(L10n.s("节奏预设", "Preset")) {
            VStack(alignment: .leading, spacing: 9) {
                Picker("", selection: Binding(get: { settings.preset },
                                              set: { settings.apply($0) })) {
                    ForEach(ReminderPreset.allCases.filter { $0 != .custom }) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(settings.preset.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
        }

        SettingsGroup(L10n.s("微休息", "Micro breaks")) {
            Row(L10n.s("间隔", "Interval"),
                subtitle: L10n.s("每隔多久提醒一次", "How often to remind you")) {
                Stepper(value: minutes(\.microInterval), in: 5...60, step: 5) {
                    Text(Fmt.interval(settings.microInterval))
                        .font(.system(size: 12.5))
                        .irisMonospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
            }
            RowDivider()
            Row(L10n.s("时长", "Duration")) {
                Picker("", selection: $settings.microDuration) {
                    Text(L10n.s("10 秒", "10 s")).tag(10.0)
                    Text(L10n.s("20 秒", "20 s")).tag(20.0)
                    Text(L10n.s("30 秒", "30 s")).tag(30.0)
                    Text(L10n.s("45 秒", "45 s")).tag(45.0)
                    Text(L10n.s("60 秒", "60 s")).tag(60.0)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
        }

        SettingsGroup(L10n.s("长休息", "Long breaks")) {
            Row(L10n.s("启用长休息", "Enable long breaks"),
                subtitle: L10n.s("建议起身走动、看向窗外", "Stand up and look out the window")) {
                Toggle("", isOn: $settings.longEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.longEnabled {
                RowDivider()
                Row(L10n.s("间隔", "Interval")) {
                    Picker("", selection: $settings.longInterval) {
                        Text(Fmt.interval(30 * 60)).tag(30 * 60.0)
                        Text(Fmt.interval(45 * 60)).tag(45 * 60.0)
                        Text(Fmt.interval(60 * 60)).tag(60 * 60.0)
                        Text(Fmt.interval(90 * 60)).tag(90 * 60.0)
                        Text(Fmt.interval(120 * 60)).tag(120 * 60.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                RowDivider()
                Row(L10n.s("时长", "Duration")) {
                    Picker("", selection: $settings.longDuration) {
                        Text(Fmt.minutes(3 * 60)).tag(3 * 60.0)
                        Text(Fmt.minutes(5 * 60)).tag(5 * 60.0)
                        Text(Fmt.minutes(10 * 60)).tag(10 * 60.0)
                        Text(Fmt.minutes(15 * 60)).tag(15 * 60.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
        }

        SettingsGroup(L10n.s("交互", "Interaction")) {
            Row(L10n.s("允许跳过", "Allow skipping"),
                subtitle: L10n.s("休息时显示「跳过」按钮", "Show a Skip button on the break screen")) {
                Toggle("", isOn: $settings.allowSkip)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("严格模式", "Strict mode"),
                subtitle: L10n.s("必须长按 3 秒才能跳过，给冲动一个缓冲",
                                 "Hold for 3 seconds to skip")) {
                Toggle("", isOn: $settings.strictSkip)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.allowSkip)
            }
            RowDivider()
            Row(L10n.s("允许推迟", "Allow postponing"),
                subtitle: L10n.s("最多连续推迟 2 次", "Up to 2 consecutive postpones")) {
                Toggle("", isOn: $settings.allowPostpone)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.allowPostpone {
                RowDivider()
                Row(L10n.s("推迟时长", "Postpone by")) {
                    Picker("", selection: $settings.postponeMinutes) {
                        Text(Fmt.minutes(2 * 60)).tag(2)
                        Text(Fmt.minutes(5 * 60)).tag(5)
                        Text(Fmt.minutes(10 * 60)).tag(10)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
            RowDivider()
            Row(L10n.s("专注模式：接管键盘", "Focus mode: capture input"),
                subtitle: L10n.s("休息期间键盘输入不再发送到其他应用；关闭则只是温和提醒",
                                 "While on, keystrokes stop reaching other apps during a break")) {
                Toggle("", isOn: $settings.captureInput)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("休息前预告", "Pre-break preview"),
                subtitle: L10n.s("开始前 10–30 秒在屏幕顶部出现倒计时胶囊",
                                 "A countdown capsule appears 10–30 s before")) {
                Toggle("", isOn: $settings.previewEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }

        SettingsGroup(L10n.s("休息内容", "Break content")) {
            Row(L10n.s("显示护眼小贴士", "Show eye-care tips")) {
                Toggle("", isOn: $settings.showTip)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("长休息引导", "Long break guide"),
                subtitle: L10n.s("也可以随时在休息浮层上切换", "Switcheable on the break screen")) {
                Picker("", selection: $settings.longBreakGuide) {
                    ForEach(LongBreakGuide.allCases) { guide in
                        Text(guide.title).tag(guide)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
        }
    }

    private func minutes(_ keyPath: ReferenceWritableKeyPath<AppSettings, TimeInterval>) -> Binding<Int> {
        Binding(get: { Int(settings[keyPath: keyPath] / 60) },
                set: { settings[keyPath: keyPath] = Double($0) * 60 })
    }
}

// MARK: - 壁纸

struct WallpaperPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = WallpaperStore.shared

    var body: some View {
        PaneHeader(title: L10n.s("休息壁纸", "Break wallpaper"),
                   subtitle: L10n.s("休息时换一张好风景，让眼睛真的看向远方。图片来自免费公共 API，无需 API Key。",
                                    "A fresh view on every break, from free public APIs."))

        preview

        HStack(spacing: 10) {
            if store.isDownloading {
                ProgressView().controlSize(.small)
                Text(L10n.s("正在下载…", "Downloading…"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if !store.credit.isEmpty {
                Text(store.credit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(L10n.s("还没有壁纸", "No wallpaper yet"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(L10n.s("换一张", "Shuffle")) {
                store.refresh(source: settings.wallpaperSource,
                              policy: settings.wallpaperRefresh,
                              force: true)
            }
            .disabled(settings.wallpaperSource == .none || store.isDownloading)
        }

        SettingsGroup(L10n.s("来源", "Source")) {
            ForEach(Array(WallpaperSource.allCases.enumerated()), id: \.element.id) { index, source in
                if index > 0 { RowDivider() }
                Button {
                    settings.wallpaperSource = source
                    if source == .none {
                        store.clear()
                    } else {
                        store.refresh(source: source, policy: settings.wallpaperRefresh, force: true)
                    }
                } label: {
                    sourceRow(source)
                }
                .buttonStyle(.plain)
            }
        }

        SettingsGroup(L10n.s("显示", "Display")) {
            Row(L10n.s("刷新频率", "Refresh"),
                subtitle: L10n.s("高清图较大，长休息刷新更省流量", "Full-size photos are heavy — long-break is a good default")) {
                Picker("", selection: $settings.wallpaperRefresh) {
                    ForEach(WallpaperRefresh.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            RowDivider()
            Row(L10n.s("背景暗度", "Dim")) {
                HStack(spacing: 8) {
                    Image(systemName: IrisCompat.symbolName("circle.lefthalf.filled", fallback: "circle"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(value: $settings.wallpaperDim, in: 0.25...0.85)
                        .frame(width: 150)
                }
            }
            RowDivider()
            Row(L10n.s("背景模糊", "Blur")) {
                HStack(spacing: 8) {
                    Image(systemName: IrisCompat.symbolName("drop", fallback: "drop"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(value: $settings.wallpaperBlur, in: 0...40)
                        .frame(width: 150)
                }
            }
        }

        SettingsGroup(L10n.s("缓存", "Cache")) {
            Row(L10n.s("已缓存 \(store.cacheCount) 张", "\(store.cacheCount) cached"),
                subtitle: L10n.s("壁纸存在本机，断网时也能用", "Stored locally so breaks work offline")) {
                Button(L10n.s("清除缓存", "Clear cache")) {
                    Confirm.present(
                        title: L10n.s("清除壁纸缓存？", "Clear wallpaper cache?"),
                        message: L10n.s("下次休息时会重新下载。", "A new wallpaper will download on the next break."),
                        confirmTitle: L10n.s("清除", "Clear")) {
                        store.clearCache()
                    }
                }
                .disabled(store.cacheCount == 0)
            }
        }

        Text(L10n.s("图片来自必应每日壁纸与 Lorem Picsum（Unsplash 图库）。仅在启用壁纸时访问网络，不会发送任何个人信息。",
                    "Images from Bing daily wallpapers and Lorem Picsum (Unsplash). Network access only happens while wallpapers are enabled."))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.08, blue: 0.10),
                                    Color(red: 0.05, green: 0.11, blue: 0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            if let image = store.previewImage ?? store.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: settings.wallpaperBlur * 0.45)
                    .overlay(Color.black.opacity(settings.wallpaperDim))
                    .transition(.opacity)
                    .id(store.token)
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: 0.55)
                        .stroke(IrisPalette.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: IrisCompat.symbolName("eye", fallback: "eye"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.s("微休息 · 看看远处", "Micro break · look far away"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Text(L10n.s("看向 6 米以外的地方，让眼睛对焦远方", "Look at something 20 feet away"))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 6)
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .irisAnimation(.easeInOut(duration: 1.0), value: store.token)
    }

    private func sourceRow(_ source: WallpaperSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: source.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(IrisPalette.violet)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title).font(.system(size: 12.5))
                Text(source.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if settings.wallpaperSource == source {
                Image(systemName: IrisCompat.symbolName("checkmark.circle.fill", fallback: "checkmark.circle.fill"))
                    .font(.system(size: 14))
                    .foregroundColor(IrisPalette.teal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 声音

struct SoundPane: View {
    @ObservedObject var settings: AppSettings
    private let previewPlayer = SoundPlayer()

    var body: some View {
        PaneHeader(title: L10n.s("声音", "Sound"),
                   subtitle: L10n.s("使用 macOS 自带提示音，轻柔不打扰。",
                                    "Uses the built-in macOS alert sounds."))

        SettingsGroup(L10n.s("提示音", "Sounds")) {
            Row(L10n.s("开启提示音", "Enable sounds")) {
                Toggle("", isOn: $settings.soundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            RowDivider()
            Row(L10n.s("休息开始时", "Break starts")) {
                soundPicker(selection: $settings.startSound)
            }
            RowDivider()
            Row(L10n.s("休息结束时", "Break ends")) {
                soundPicker(selection: $settings.endSound)
            }
            RowDivider()
            Row(L10n.s("音量", "Volume")) {
                HStack(spacing: 8) {
                    Image(systemName: IrisCompat.symbolName("speaker.fill", fallback: "speaker.fill"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Slider(value: $settings.soundVolume, in: 0...1)
                        .frame(width: 140)
                    Image(systemName: IrisCompat.symbolName("speaker.wave.3.fill", fallback: "speaker.wave.3.fill"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(!settings.soundEnabled)

        Text(L10n.s("提示音只在你休息时响起。如果觉得吵，可以只留结束音或全部关闭。",
                    "Sounds only play around breaks."))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }

    private func soundPicker(selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: selection) {
                ForEach(SoundPlayer.choices) { choice in
                    Text(choice.displayName).tag(choice.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116)

            Button(L10n.s("试听", "Preview")) {
                previewPlayer.play(selection.wrappedValue, volume: settings.soundVolume)
            }
        }
    }
}

// MARK: - 统计

struct StatsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var stats: StatsStore

    private var days: [DayRecord] { stats.recentDays(14) }
    private var microLabel: String { L10n.s("微休息", "Micro") }
    private var longLabel: String { L10n.s("长休息", "Long") }

    private var chartItems: [IrisBarChart.Item] {
        days.enumerated().map { index, day in
            IrisBarChart.Item(id: index,
                              date: day.day,
                              primary: day.microTaken,
                              secondary: day.longTaken)
        }
    }

    var body: some View {
        PaneHeader(title: L10n.s("统计", "Statistics"),
                   subtitle: L10n.s("所有数据只保存在这台 Mac 上，不联网、不上传。",
                                    "Everything stays on this Mac."))

        HStack(spacing: 10) {
            StatTile(icon: "checkmark.circle.fill",
                     value: "\(stats.today.totalBreaks)",
                     label: L10n.s("今日休息", "Breaks today"),
                     tint: IrisPalette.teal)
            StatTile(icon: "hourglass",
                     value: Fmt.duration(stats.today.restSeconds),
                     label: L10n.s("今日时长", "Time today"),
                     tint: IrisPalette.aqua)
            StatTile(icon: "flame.fill",
                     value: "\(stats.streak(goal: settings.dailyGoal))",
                     label: L10n.s("连续达标", "Day streak"),
                     tint: IrisPalette.amber)
            StatTile(icon: "sum",
                     value: "\(stats.allTime.totalBreaks)",
                     label: L10n.s("累计休息", "All time"),
                     tint: IrisPalette.indigo)
        }

        SettingsGroup(L10n.s("最近 14 天", "Last 14 days")) {
            IrisBarChart(items: chartItems,
                         primaryLabel: microLabel,
                         secondaryLabel: longLabel)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }

        SettingsGroup(L10n.s("目标", "Goal")) {
            Row(L10n.s("每日休息目标", "Daily break goal"),
                subtitle: L10n.s("达标的天数会累计成连续记录", "Keep the streak alive")) {
                Stepper(value: $settings.dailyGoal, in: 2...24) {
                    Text(L10n.s("\(settings.dailyGoal) 次", "\(settings.dailyGoal) times"))
                        .font(.system(size: 12.5))
                        .irisMonospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
            RowDivider()
            Row(L10n.s("今日进度", "Today's progress")) {
                HStack(spacing: 8) {
                    Text("\(min(stats.today.totalBreaks, settings.dailyGoal))/\(settings.dailyGoal)")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .irisMonospacedDigit()
                    ProgressView(value: min(1, Double(stats.today.totalBreaks) / Double(max(1, settings.dailyGoal))))
                        .frame(width: 110)
                }
            }
        }

        HStack {
            Spacer()
            Button {
                Confirm.present(
                    title: L10n.s("清除所有统计数据？", "Clear all statistics?"),
                    message: L10n.s("此操作无法撤销。", "This cannot be undone."),
                    confirmTitle: L10n.s("清除", "Clear")) {
                    stats.clearAll()
                }
            } label: {
                Text(L10n.s("清除统计数据", "Clear statistics"))
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - 关于

struct AboutPane: View {
    @ObservedObject var settings: AppSettings
    var onReplayOnboarding: () -> Void

    /// 版本号从 bundle 读，免得和 Info.plist 走散。
    /// 快照工具跑在 bundle 外面，读不到就显示「开发版本」。
    private var versionText: String {
        guard let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !v.isEmpty else {
            return L10n.s("开发版本", "Development build")
        }
        return L10n.s("版本 \(v) · 为 macOS 打造", "Version \(v) · Made for macOS")
    }

    var body: some View {
        VStack(spacing: 10) {
            AppMark(size: 76)
            Text(L10n.s("明目", "Iris"))
                .font(.system(size: 21, weight: .semibold))
            Text(L10n.s("让眼睛，歇一会儿。", "Give your eyes a moment."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(versionText)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        IrisCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: IrisCompat.symbolName("20.circle", fallback: "circle"))
                        .foregroundColor(IrisPalette.teal)
                    Text(L10n.s("20-20-20 法则", "The 20-20-20 rule"))
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(L10n.s("每看屏幕 20 分钟，就望向 20 英尺（约 6 米）以外的地方，至少 20 秒。这是美国眼科学会（AAO）推荐的做法——盯屏幕时眨眼次数会减半，眼睛容易干涩。",
                            "Every 20 minutes, look at something 20 feet away for at least 20 seconds — recommended by the AAO."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(L10n.s("了解详情（美国眼科学会）", "Learn more at the AAO"),
                     destination: URL(string: "https://www.aao.org/eye-health/tips-prevention/computer-usage")!)
                    .font(.system(size: 12))
            }
        }

        SettingsGroup(L10n.s("隐私", "Privacy")) {
            Row(L10n.s("数据只存在本机", "Your data stays local"),
                subtitle: L10n.s("统计与设置保存在本地；除壁纸功能外不访问网络。",
                                 "Statistics and settings are stored locally. The only network access is the optional wallpaper.")) {
                Image(systemName: IrisCompat.symbolName("lock.shield", fallback: "lock.shield"))
                    .foregroundColor(IrisPalette.mint)
            }
            RowDivider()
            Row(L10n.s("不需要任何系统权限", "No system permissions"),
                subtitle: L10n.s("不使用摄像头、不监听键盘、不读取屏幕内容。",
                                 "No camera, no keylogging, no screen reading.")) {
                Image(systemName: IrisCompat.symbolName("hand.raised", fallback: "hand.raised"))
                    .foregroundColor(IrisPalette.mint)
            }
        }

        SettingsGroup(L10n.s("授权", "License")) {
            Row(L10n.s("PolyForm Noncommercial 1.0.0", "PolyForm Noncommercial 1.0.0"),
                subtitle: L10n.s("自己用、学习研究、学校等非营利机构使用免费；公司等商业用途需要单独授权。",
                                 "Free for personal, academic and other noncommercial use. Commercial use requires a separate license.")) {
                Link(L10n.s("查看协议", "View"),
                     destination: URL(string: "https://github.com/vex67-cyber/iris-macos/blob/main/LICENSE")!)
                    .font(.system(size: 12))
            }
        }

        SettingsGroup(L10n.s("快捷键", "Shortcuts")) {
            Row(L10n.s("立即休息", "Take a break now")) { Text("⌃⌥⌘B").foregroundColor(.secondary) }
            RowDivider()
            Row(L10n.s("暂停 / 恢复", "Pause / resume")) { Text("⌃⌥⌘P").foregroundColor(.secondary) }
            RowDivider()
            Row(L10n.s("推迟休息（休息浮层上）", "Postpone (on break screen)")) { Text("Esc").foregroundColor(.secondary) }
        }

        HStack {
            Button(L10n.s("重新观看欢迎引导", "Replay welcome tour")) { onReplayOnboarding() }
            Spacer()
            Button(L10n.s("退出明目", "Quit Iris")) { NSApp.terminate(nil) }
        }
        .padding(.top, 2)

        Text(L10n.s("© 2026 明目 · 用 SwiftUI 与 AppKit 构建，向 Time Out、Stretchly、LookAway 致敬。",
                    "© 2026 Iris · Built with SwiftUI and AppKit, inspired by Time Out, Stretchly and LookAway."))
            .font(.system(size: 11))
            .foregroundColor(.secondary.opacity(0.75))
    }
}
