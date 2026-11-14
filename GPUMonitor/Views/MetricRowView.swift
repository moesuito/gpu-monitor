import SwiftUI

struct MetricRowView: View {
    let kind: PercentageMetricKind
    let value: MetricValue
    let segments: [[PlottedHistoryPoint]]
    let maxSamples: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(indicatorColor)
                        .frame(width: 7, height: 7)
                        .offset(y: -0.5)

                    Text(kind.displayLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 4)

                    Text(MetricFormatter.formatPercentage(value))
                        .font(.system(size: 11.5, weight: value.isAvailable ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(valueColor)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.09))

                        if value.isAvailable {
                            let width = max(0, geometry.size.width * value.clampedPercentageFraction)
                            Capsule(style: .continuous)
                                .fill(indicatorColor)
                                .frame(width: width)
                        }
                    }
                }
                .frame(height: 3.5)
                .accessibilityHidden(true)

                UsageHistoryChartView(
                    series: [
                        UsageHistorySeries(
                            id: kind.id,
                            color: indicatorColor,
                            segments: segments,
                            fillArea: true,
                            lineWidth: 1.35
                        )
                    ],
                    maxSamples: maxSamples,
                    showDetailedGrid: true,
                    verticalGridColumns: 3,
                    showsEmptyPlaceholder: false,
                    cornerRadius: 5
                )
                .frame(height: 54)

                if value.isOutOfPercentageRange {
                    Label(
                        "Unexpected (>100% / <0%)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: isSelected ? 1.0 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(kind.registryKey)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.displayLabel)
        .accessibilityValue(MetricFormatter.formatPercentage(value))
    }

    private var indicatorColor: Color {
        value.isOutOfPercentageRange ? .orange : kind.chartColor
    }

    private var valueColor: Color {
        if !value.isAvailable {
            return .secondary
        }
        if value.isOutOfPercentageRange {
            return .orange
        }
        return .primary
    }

    private var cardBackgroundColor: Color {
        if isSelected {
            return kind.chartColor.opacity(colorScheme == .dark ? 0.12 : 0.08)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.03)
    }

    private var cardBorderColor: Color {
        if isSelected {
            return kind.chartColor.opacity(0.45)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07)
    }
}
