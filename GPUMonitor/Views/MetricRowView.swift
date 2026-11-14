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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(indicatorColor)
                        .frame(width: 8, height: 8)
                        .offset(y: -0.5)

                    Text(kind.displayLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(MetricFormatter.formatPercentage(value))
                        .font(.system(size: 12, weight: value.isAvailable ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
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
                .frame(height: 4)
                .accessibilityHidden(true)

                UsageHistoryChartView(
                    series: [
                        UsageHistorySeries(
                            id: kind.id,
                            color: indicatorColor,
                            segments: segments,
                            fillArea: true,
                            lineWidth: 1.25
                        )
                    ],
                    maxSamples: maxSamples,
                    showDetailedGrid: false,
                    cornerRadius: 4
                )
                .frame(height: 18)

                if value.isOutOfPercentageRange {
                    Label(
                        "Unexpected value (expected 0%–100%)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
