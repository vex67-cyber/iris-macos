import Foundation

/// 休息时轮播的护眼小贴士。
///
/// 文案取自 AAO（美国眼科学会）20-20-20 建议与实践检验，语气温暖不训人。
public enum BreakTips {

    public static var micro: [String] {
        [
            L10n.s("看向 6 米以外的地方，让眼睛对焦远方", "Look at something at least 20 ft (6 m) away"),
            L10n.s("慢慢眨眼 10 次，给眼睛补一层泪膜", "Blink slowly 10 times to rewet your eyes"),
            L10n.s("20 英尺约等于 6 米，大概就是马路对面的距离", "20 feet ≈ 6 m — about a road's width away"),
            L10n.s("闭上眼睛两秒，感受眼皮的温度", "Close your eyes for two seconds and feel the warmth"),
            L10n.s("把视线移到天花板，再慢慢移回屏幕", "Move your gaze to the ceiling, then slowly back"),
            L10n.s("看看窗外最远的那栋楼，或者一片云", "Find the farthest building out the window"),
            L10n.s("让眼睛跟着远处的东西轻轻移动，不要盯着不动", "Let your eyes drift slowly, don't stare"),
            L10n.s("屏幕亮度与房间相当就好，别比环境亮太多", "Keep screen brightness close to your room's"),
        ]
    }

    public static var long: [String] {
        [
            L10n.s("站起来走两步，顺便接一杯水", "Stand up, stretch, and grab a glass of water"),
            L10n.s("肩膀放松，下巴微收，把背挺直一点", "Relax your shoulders, tuck your chin, straighten up"),
            L10n.s("望向窗外，顺便伸个懒腰", "Look out the window and stretch"),
            L10n.s("用温热的手心轻捂眼睛 10 秒", "Cup your warm palms over your eyes for 10 s"),
            L10n.s("屏幕最好略低于视线，距离一臂左右", "Keep the screen slightly below eye level, an arm's length away"),
            L10n.s("眨眨眼，深呼吸，再眨眨眼", "Blink, breathe deeply, blink again"),
            L10n.s("滴一两滴人工泪液，如果眼睛发干的话", "A drop of artificial tears helps if your eyes feel dry"),
            L10n.s("让眼睛休息，是今天最划算的投资", "Resting your eyes is the best investment today"),
        ]
    }

    public static func tips(for kind: BreakKind) -> [String] {
        kind == .long ? long : micro
    }

    public static func tip(for kind: BreakKind, index: Int) -> String {
        let list = tips(for: kind)
        guard !list.isEmpty else { return "" }
        return list[((index % list.count) + list.count) % list.count]
    }
}
