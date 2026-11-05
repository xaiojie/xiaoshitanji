import SwiftUI
import Charts

/// 图表拖动选点的公共件：找最近的数据点、选中气泡、触感反馈。
enum ChartProbe {
    /// 手指停在某个横坐标上时，取离它最近的一条数据。
    static func nearest<Item>(to date: Date?, in items: [Item], date dateOf: (Item) -> Date) -> Item? {
        guard let date else { return nil }
        return items.min { abs(dateOf($0).timeIntervalSince(date)) < abs(dateOf($1).timeIntervalSince(date)) }
    }

    /// 「10月30日」这种短日期，气泡和提示都用它。
    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }
}

/// 拖动时浮在被选中点上方的读数气泡。
struct ChartProbeBubble: View {
    let title: String
    let value: String
    var detail: String?
    var onDark = false

    private var foreground: Color { onDark ? Theme.surface : Theme.ink }
    private var secondary: Color { onDark ? Theme.surface.opacity(0.72) : Theme.mutedInk }
    private var background: Color { onDark ? Color.white.opacity(0.16) : Theme.surface }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(secondary)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(foreground)
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(background, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(onDark ? Color.white.opacity(0.14) : Theme.ink.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(onDark ? 0.28 : 0.14), radius: 8, y: 3)
        .fixedSize()
    }
}

extension View {
    /// 选中点变化时给一次轻微触感，滑过柱子才有「咔哒」感。
    func chartProbeFeedback(_ probe: Date?) -> some View {
        sensoryFeedback(.selection, trigger: probe)
    }

    /// 图表下方那行「按住图表左右拖动」的小提示。
    func chartProbeHint(_ text: String = "按住图表左右拖动，可以看每一天的数值。") -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.mutedInk)
    }
}

/// 给选中项描一层深色底，没选中的自动变淡。
extension ShapeStyle where Self == Color {
    static func probeDim(_ base: Color, selected: Bool, dimmed: Double = 0.38) -> Color {
        selected ? base : base.opacity(dimmed)
    }
}
