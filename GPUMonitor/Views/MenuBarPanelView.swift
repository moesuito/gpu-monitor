import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: GPUMonitorViewModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection

            if let errorMessage = viewModel.lastErrorMessage {
                errorBanner(errorMessage)
            }

            heroGaugesSection

            SectionHeaderDivider(title: "Usage History")

            usageHistoryCard

            SectionHeaderDivider(title: "Metrics")

            VStack(alignment: .leading, spacing: 5) {
                ForEach(PercentageMetricKind.allCases) { kind in
                    let isSelected = viewModel.selectedHistoryMode == .metric(kind)
                    MetricRowView(
                        kind: kind,
                        value: viewModel.metricValue(for: kind),
                        segments: viewModel.history.contiguousAvailableSegments(for: kind),
                        maxSamples: viewModel.history.maxSamples,
                        isSelected: isSelected,
                        onSelect: {
                            viewModel.selectHistoryMetric(kind)
                        }
                    )
                }
            }

            SectionHeaderDivider(title: "Details")

            detailsSection

            Text("Indicators are provided by the driver, may lag, and do not identify the responsible app or codec.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            launchAtLoginSection

            footerRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .frame(width: 356)
        .onAppear {
            viewModel.syncLoginItemState()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("GPU Monitor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(viewModel.gpuDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if let snapshot = viewModel.currentSnapshot, snapshot.source == .ioregFallback {
                Text("ioreg")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
        }
    }

    private var heroGaugesSection: some View {
        let temperature = viewModel.temperatureValue
        let core = viewModel.metricValue(for: .gpuCore)

        return HStack(alignment: .top, spacing: 28) {
            Spacer(minLength: 0)

            CircularGaugeView(
                title: "Temperature",
                centerText: temperatureCenterText(for: temperature),
                unavailableSubtitle: temperature.isAvailable ? nil : MetricFormatter.formatTemperature(temperature),
                accessibilityValue: MetricFormatter.formatTemperature(temperature),
                trimFraction: thermalGaugeFraction(for: temperature),
                ringColor: thermalColor(for: temperature),
                textColor: temperature.isAvailable ? .primary : .secondary
            )

            CircularGaugeView(
                title: PercentageMetricKind.gpuCore.displayLabel,
                centerText: coreCenterText(for: core),
                unavailableSubtitle: core.isAvailable ? nil : MetricFormatter.formatPercentage(core),
                accessibilityValue: MetricFormatter.formatPercentage(core),
                trimFraction: core.isAvailable ? core.clampedPercentageFraction : nil,
                ringColor: core.isOutOfPercentageRange ? .orange : PercentageMetricKind.gpuCore.chartColor,
                textColor: coreTextColor(for: core)
            )

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var usageHistoryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                historySelectionIndicator

                Spacer(minLength: 4)

                Menu {
                    Button("All Percentages") {
                        viewModel.selectedHistoryMode = .all
                    }
                    Divider()
                    ForEach(PercentageMetricKind.allCases) { kind in
                        Button(kind.displayLabel) {
                            viewModel.selectedHistoryMode = .metric(kind)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedHistoryMode.shortLabel)
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            UsageHistoryChartView(
                series: heroHistorySeries,
                maxSamples: viewModel.history.maxSamples,
                showDetailedGrid: true,
                cornerRadius: 6
            )
            .frame(height: 62)

            HStack {
                Text("\(viewModel.history.maxSamples)s window")
                Spacer()
                Text("0–100%")
                Spacer()
                Text("Now")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var historySelectionIndicator: some View {
        switch viewModel.selectedHistoryMode {
        case .all:
            HStack(spacing: 5) {
                HStack(spacing: 2) {
                    ForEach(PercentageMetricKind.allCases) { kind in
                        Circle()
                            .fill(kind.chartColor)
                            .frame(width: 5, height: 5)
                    }
                }
                Text("All Indicators")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        case .metric(let kind):
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(kind.chartColor)
                    .frame(width: 8, height: 8)
                Text(kind.displayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("· Peak \(viewModel.peakPercentageFormatted(for: kind))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroHistorySeries: [UsageHistorySeries] {
        switch viewModel.selectedHistoryMode {
        case .all:
            return PercentageMetricKind.allCases.map { kind in
                UsageHistorySeries(
                    id: kind.id,
                    color: kind.chartColor,
                    segments: viewModel.history.contiguousAvailableSegments(for: kind),
                    fillArea: true,
                    lineWidth: 1.3
                )
            }
        case .metric(let kind):
            let current = viewModel.metricValue(for: kind)
            return [
                UsageHistorySeries(
                    id: kind.id,
                    color: current.isOutOfPercentageRange ? .orange : kind.chartColor,
                    segments: viewModel.history.contiguousAvailableSegments(for: kind),
                    fillArea: true,
                    lineWidth: 1.65
                )
            ]
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            if viewModel.hasMultipleDevices {
                deviceSelectorSection
            }

            if let snapshot = viewModel.currentSnapshot {
                detailRow(label: "Source", value: snapshot.source.label)
            }

            detailRow(label: "Last read", value: viewModel.lastSuccessfulReadFormatted)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var deviceSelectorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let banner = viewModel.selectionStatusBanner {
                Label(
                    banner,
                    systemImage: viewModel.currentSnapshot?.isAmbiguousDeviceSelection == true
                        ? "exclamationmark.circle.fill"
                        : "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(
                    viewModel.currentSnapshot?.isAmbiguousDeviceSelection == true
                        ? Color.orange
                        : Color.secondary
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            Picker(
                "Device",
                selection: Binding(
                    get: { viewModel.effectiveSelectedDeviceID },
                    set: { viewModel.selectDevice($0) }
                )
            ) {
                ForEach(viewModel.availableDevices) { device in
                    Text(device.pickerLabel).tag(device.id)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text("Failed to read GPU metrics")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { viewModel.isLaunchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .foregroundStyle(.secondary)

            if let loginMessage = viewModel.loginItemMessage {
                Text(loginMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .controlSize(.small)
        }
    }

    private var statusDotColor: Color {
        if viewModel.lastErrorMessage != nil {
            return .orange
        }
        if viewModel.currentSnapshot != nil {
            return .green
        }
        return .secondary
    }

    private var statusText: String {
        if viewModel.lastErrorMessage != nil {
            return "Read error"
        }
        if viewModel.currentSnapshot != nil {
            return "Monitoring"
        }
        return "Waiting…"
    }

    private func temperatureCenterText(for value: MetricValue) -> String {
        guard value.isAvailable else { return "—" }
        return MetricFormatter.formatTemperature(value)
    }

    private func coreCenterText(for value: MetricValue) -> String {
        guard value.isAvailable else { return "—" }
        return MetricFormatter.formatPercentage(value)
    }

    private func coreTextColor(for value: MetricValue) -> Color {
        if !value.isAvailable { return .secondary }
        if value.isOutOfPercentageRange { return .orange }
        return .primary
    }

    private func thermalGaugeFraction(for value: MetricValue) -> Double? {
        guard case .available(let celsius) = value else { return nil }
        return min(max((celsius - 20.0) / 80.0, 0.08), 1.0)
    }

    private func thermalColor(for value: MetricValue) -> Color {
        guard case .available(let celsius) = value else { return .secondary }
        switch celsius {
        case ..<60:
            return .blue
        case ..<75:
            return .teal
        case ..<88:
            return .orange
        default:
            return .red
        }
    }
}

private struct CircularGaugeView: View {
    let title: String
    let centerText: String
    let unavailableSubtitle: String?
    let accessibilityValue: String
    let trimFraction: Double?
    let ringColor: Color
    let textColor: Color

    private let diameter: CGFloat = 58
    private let lineWidth: CGFloat = 5.5

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)

                if let trimFraction {
                    Circle()
                        .trim(from: 0, to: trimFraction)
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.25), value: trimFraction)
                }

                Text(centerText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 7)
                    .foregroundStyle(textColor)
            }
            .frame(width: diameter, height: diameter)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                if let unavailableSubtitle {
                    Text(unavailableSubtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}

private struct SectionHeaderDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            hairline
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
                .fixedSize()
            hairline
        }
        .padding(.vertical, 1)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.75)
    }
}
