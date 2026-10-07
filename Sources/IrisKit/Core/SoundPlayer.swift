import AppKit
import Foundation

/// 系统提示音。使用 macOS 自带的 /System/Library/Sounds，无需打包音频资源。
public final class SoundPlayer {

    public struct Choice: Identifiable, Hashable, Sendable {
        public let name: String
        public let zh: String
        public let en: String
        public var id: String { name }

        public var displayName: String { L10n.s(zh, en) }
    }

    public static let choices: [Choice] = [
        Choice(name: "Glass", zh: "玻璃", en: "Glass"),
        Choice(name: "Ping", zh: "清脆", en: "Ping"),
        Choice(name: "Tink", zh: "轻敲", en: "Tink"),
        Choice(name: "Blow", zh: "呼吸", en: "Blow"),
        Choice(name: "Purr", zh: "呼噜", en: "Purr"),
        Choice(name: "Bottle", zh: "水滴", en: "Bottle"),
    ]

    /// 缓存已加载的音效（避免每次从磁盘读）。
    private var cache: [String: NSSound] = [:]
    /// 正在播放的音效，播完要主动回收
    private var playing = Set<String>()

    public init() {}

    /// 播放一次系统提示音。
    ///
    /// 注意：NSSound 播放结束后，CoreAudio 的渲染线程仍会继续空转
    /// （实测让 App 在休息浮层期间稳定占用 ~10% CPU，且会一直持续）。
    /// 所以播完必须显式 stop 并释放实例 —— 这是本项目里最"隐蔽"的一处性能坑。
    public func play(_ choiceName: String, volume: Double) {
        guard let sound = sound(named: choiceName) else { return }

        sound.stop()
        sound.volume = Float(max(0, min(1, volume)))
        sound.play()
        playing.insert(choiceName)

        let cleanup = sound.duration + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanup) { [weak self] in
            guard let self, self.playing.contains(choiceName) else { return }
            sound.stop()
            self.playing.remove(choiceName)
            // 连实例一起释放，让 CoreAudio 彻底收工
            self.cache[choiceName] = nil
        }
    }

    private func sound(named name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let sound = NSSound(named: NSSound.Name(name)) else { return nil }
        cache[name] = sound
        return sound
    }
}
