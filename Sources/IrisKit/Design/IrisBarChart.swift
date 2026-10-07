import SwiftUI

/// 手写的堆叠柱状图（不依赖 Swift Charts —— 它需要 macOS 13+）。
///
/// 微休息在下、长休息在上，柱顶标注当日总数。
public struct IrisBarChart: View {

    public struct Item: Identifiable {
        public let id: Int
        public let date: Date
        public let primary: Int
        public let secondary: Int

        public init(id: Int, date: Date, primary: Int, secondary: Int) {
            self.id = id
            self.date = date
            self.primary = primary
            self.secondary = secondary
        }

        var total: Int { primary + secondary }
    }

    public var items: [Item]
    public var primaryLabel: String
    public var secondaryLabel: String
    public var primaryColor: Color
    public var secondaryColor: Color
    public var plotHeight: CGFloat

    public init(items: [Item],
                primaryLabel: String,
                secondaryLabel: String,
                primaryColor: Color = IrisPalette.teal,
                secondaryColor: Color = IrisPalette.indigo,
                plotHeight: CGFloat = 120) {
        self.items = items
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.plotHeight = plotHeight
    }

    private var maxTotal: Int {
        max(1, items.map { $0.total }.max() ?? 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(items) { item in
                    column(item)
                }
            }
            .frame(height: plotHeight + 30)
            .overlay(baseline, alignment: .bottom)
        }
    }

    private var baseline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.bottom, 14)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Spacer()
            legendDot(primaryColor, primaryLabel)
            legendDot(secondaryColor, secondaryLabel)
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func column(_ item: Item) -> some View {
        VStack(spacing: 4) {
            Text(item.total > 0 ? "\(item.total)" : " ")
                .font(.system(size: 9, weight: .medium))
                .irisMonospacedDigit()
                .foregroundColor(.secondary)
                .frame(height: 11)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .frame(height: plotHeight)
                stackedBar(item)
                    .frame(height: barHeight(item))
            }
            .frame(height: plotHeight)

            Text(dayLabel(item))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(height: 11)
                .opacity(item.id % 2 == 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .help(tooltip(item))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Fmt.shortDate(item.date))：\(item.total) \(L10n.s("次休息", "breaks"))")
    }

    private func barHeight(_ item: Item) -> CGFloat {
        guard item.total > 0 else { return 0 }
        return max(5, CGFloat(item.total) / CGFloat(maxTotal) * (plotHeight - 5))
    }

    private func stackedBar(_ item: Item) -> some View {
        let total = max(1, item.total)
        let height = barHeight(item)
        let hasBoth = item.primary > 0 && item.secondary > 0
        let gap: CGFloat = hasBoth ? 2 : 0

        let primaryHeight = item.primary > 0
            ? max(4, height * CGFloat(item.primary) / CGFloat(total) - gap / 2)
            : 0
        let secondaryHeight = item.secondary > 0
            ? max(4, height * CGFloat(item.secondary) / CGFloat(total) - gap / 2)
            : 0

        return VStack(spacing: gap) {
            if secondaryHeight > 0 {
                segment(height: secondaryHeight, color: secondaryColor)
            }
            if primaryHeight > 0 {
                segment(height: primaryHeight, color: primaryColor)
            }
        }
    }

    private func segment(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: height)
    }

    private func dayLabel(_ item: Item) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isChinese ? "zh_Hans_CN" : "en_US")
        f.dateFormat = "d"
        return f.string(from: item.date)
    }

    private func tooltip(_ item: Item) -> String {
        L10n.s("\(Fmt.shortDate(item.date)) · 微休息 \(item.primary) 次 · 长休息 \(item.secondary) 次",
               "\(Fmt.shortDate(item.date)) · \(item.primary) micro · \(item.secondary) long")
    }
}
