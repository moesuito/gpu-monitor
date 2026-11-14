import SwiftUI

struct MetricRowView: View {
    let title: String
    let value: MetricValue

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(MetricFormatter.formatPercentage(value))
                    .font(.system(size: 12.5, weight: value.isAvailable ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.10))

                    if value.isAvailable {
                        let width = max(0, geometry.size.width * value.clampedPercentageFraction)
                        Capsule(style: .continuous)
                            .fill(barColor)
                            .frame(width: width)
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            if value.isOutOfPercentageRange {
                Label(
                    "Valor inesperado (esperado entre 0% e 100%)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(MetricFormatter.formatPercentage(value))
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

    private var barColor: Color {
        if value.isOutOfPercentageRange {
            return .orange
        }
        return .accentColor
    }
}
