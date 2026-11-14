import SwiftUI

extension PercentageMetricKind {
    var chartColor: Color {
        switch self {
        case .gpuCore:
            return .blue
        case .memory:
            return .mint
        case .videoEngine:
            return .indigo
        case .videoDecode:
            return .purple
        }
    }
}

struct UsageHistorySeries: Identifiable {
    let id: String
    let color: Color
    let segments: [[PlottedHistoryPoint]]
    let fillArea: Bool
    let lineWidth: CGFloat

    init(
        id: String,
        color: Color,
        segments: [[PlottedHistoryPoint]],
        fillArea: Bool = true,
        lineWidth: CGFloat = 1.5
    ) {
        self.id = id
        self.color = color
        self.segments = segments
        self.fillArea = fillArea
        self.lineWidth = lineWidth
    }

    var hasAnyPoint: Bool {
        segments.contains { !$0.isEmpty }
    }
}

/// Native SwiftUI Canvas renderer for rolling 0–100% GPU utilization history.
/// Preserves gaps for unavailable reads instead of dropping to 0%.
struct UsageHistoryChartView: View {
    let series: [UsageHistorySeries]
    let maxSamples: Int
    let showDetailedGrid: Bool
    let verticalGridColumns: Int
    let showsEmptyPlaceholder: Bool
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(
        series: [UsageHistorySeries],
        maxSamples: Int = 60,
        showDetailedGrid: Bool = true,
        verticalGridColumns: Int = 6,
        showsEmptyPlaceholder: Bool = true,
        cornerRadius: CGFloat = 6
    ) {
        self.series = series
        self.maxSamples = max(2, maxSamples)
        self.showDetailedGrid = showDetailedGrid
        self.verticalGridColumns = verticalGridColumns
        self.showsEmptyPlaceholder = showsEmptyPlaceholder
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                guard size.width > 1, size.height > 1 else { return }
                drawGrid(in: &context, size: size)

                for item in series {
                    drawSeries(item, in: &context, size: size)
                }
            }

            if showsEmptyPlaceholder, showDetailedGrid, !hasData {
                Text("Collecting samples…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(wellBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var hasData: Bool {
        series.contains { $0.hasAnyPoint }
    }

    private var wellBackgroundColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let horizontalFractions: [CGFloat] = showDetailedGrid ? [0.25, 0.5, 0.75] : [0.5]
        let gridColor = Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06)

        for fraction in horizontalFractions {
            let y = size.height * (1.0 - fraction)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }

        guard showDetailedGrid, verticalGridColumns > 1 else { return }

        for index in 1..<verticalGridColumns {
            let x = size.width * (CGFloat(index) / CGFloat(verticalGridColumns))
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawSeries(_ item: UsageHistorySeries, in context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = 1.5
        let plotHeight = max(1, size.height - inset * 2)
        let denom = CGFloat(max(1, maxSamples - 1))

        for segment in item.segments where !segment.isEmpty {
            let points: [CGPoint] = segment.map { point in
                let x = size.width * (CGFloat(point.slotIndex) / denom)
                let y = inset + plotHeight * (1.0 - CGFloat(point.fraction))
                return CGPoint(x: x, y: y)
            }

            if points.count == 1, let single = points.first {
                let radius = max(1.6, item.lineWidth)
                let dotRect = CGRect(
                    x: single.x - radius,
                    y: single.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(item.color))
                continue
            }

            var linePath = Path()
            linePath.move(to: points[0])
            for pt in points.dropFirst() {
                linePath.addLine(to: pt)
            }

            if item.fillArea {
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                areaPath.addLine(to: CGPoint(x: points[0].x, y: size.height))
                areaPath.closeSubpath()

                let topOpacity: Double = series.count > 1 ? 0.14 : 0.34
                let bottomOpacity: Double = series.count > 1 ? 0.01 : 0.04
                context.fill(
                    areaPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            item.color.opacity(topOpacity),
                            item.color.opacity(bottomOpacity)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            context.stroke(
                linePath,
                with: .color(item.color),
                style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
