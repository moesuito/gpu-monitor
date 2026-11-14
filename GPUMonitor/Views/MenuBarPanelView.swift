import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: GPUMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            if let errorMessage = viewModel.lastErrorMessage {
                errorBanner(errorMessage)
            }

            if viewModel.hasMultipleDevices {
                deviceSelectorSection
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(PercentageMetricKind.allCases) { kind in
                    MetricRowView(
                        title: kind.displayLabel,
                        value: viewModel.metricValue(for: kind)
                    )
                }
            }

            Divider()

            temperatureRow

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Os indicadores são fornecidos pelo driver, podem ter atraso e não identificam o aplicativo ou codec responsável.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                footerRow
            }
        }
        .padding(14)
        .frame(width: 348)
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.gpuDisplayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let snapshot = viewModel.currentSnapshot, snapshot.source == .ioregFallback {
                    Text("Fonte alternativa: ioreg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var deviceSelectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                "Dispositivo",
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
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Falha na leitura da GPU")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private var temperatureRow: some View {
        HStack(spacing: 8) {
            Label("Temperatura", systemImage: "thermometer.medium")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Text(MetricFormatter.formatTemperature(viewModel.temperatureValue))
                .font(.system(size: 12.5, weight: viewModel.temperatureValue.isAvailable ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(viewModel.temperatureValue.isAvailable ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Temperatura")
        .accessibilityValue(MetricFormatter.formatTemperature(viewModel.temperatureValue))
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)

                Text("Última leitura: \(viewModel.lastSuccessfulReadFormatted)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Sair") {
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
}
