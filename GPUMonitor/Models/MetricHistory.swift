import Foundation

/// Single timestamped metric reading stored in the rolling history buffer.
struct MetricHistoryPoint: Equatable, Sendable {
    let timestamp: Date
    let value: MetricValue
}

/// Plotted sample aligned to a fixed-capacity rolling time grid.
struct PlottedHistoryPoint: Equatable, Sendable {
    let slotIndex: Int
    let fraction: Double
}

/// Stores bounded per-metric usage history for percentage indicators without mixing devices or summing metrics.
struct MetricHistoryBuffer: Equatable, Sendable {
    let maxSamples: Int
    private(set) var deviceID: UInt64?
    private var series: [PercentageMetricKind: [MetricHistoryPoint]]

    init(maxSamples: Int = 60) {
        precondition(maxSamples >= 2, "maxSamples must be at least 2")
        self.maxSamples = maxSamples
        self.deviceID = nil
        self.series = Dictionary(
            uniqueKeysWithValues: PercentageMetricKind.allCases.map { ($0, []) }
        )
    }

    /// Appends each percentage indicator independently. Resets buffers if the active GPU changes.
    mutating func recordSnapshot(_ snapshot: GPUSnapshot) {
        if let currentDeviceID = deviceID, currentDeviceID != snapshot.device.id {
            resetSeriesKeepingNilDevice()
        }
        deviceID = snapshot.device.id

        for kind in PercentageMetricKind.allCases {
            let value = snapshot.metrics[kind] ?? .unavailable
            append(MetricHistoryPoint(timestamp: snapshot.timestamp, value: value), to: kind)
        }
    }

    /// Records an unavailable gap across all indicators when a read fails so missing polls are never plotted as 0%.
    mutating func recordFailure(at timestamp: Date = Date()) {
        guard deviceID != nil else { return }
        for kind in PercentageMetricKind.allCases {
            append(MetricHistoryPoint(timestamp: timestamp, value: .unavailable), to: kind)
        }
    }

    mutating func reset() {
        deviceID = nil
        resetSeriesKeepingNilDevice()
    }

    func points(for kind: PercentageMetricKind) -> [MetricHistoryPoint] {
        series[kind] ?? []
    }

    /// Returns the peak raw value over available samples in the current window, or nil if all samples are unavailable.
    func peakValue(for kind: PercentageMetricKind) -> Double? {
        let valid = points(for: kind).compactMap { $0.value.numericValue }
        return valid.max()
    }

    /// Splits the rolling series into contiguous segments of available samples aligned to the right edge.
    /// Unavailable gaps break the line instead of dropping to 0%, and visual heights clamp to [0, 1].
    func contiguousAvailableSegments(for kind: PercentageMetricKind) -> [[PlottedHistoryPoint]] {
        let items = points(for: kind)
        guard !items.isEmpty else { return [] }

        let startSlot = max(0, maxSamples - items.count)
        var segments: [[PlottedHistoryPoint]] = []
        var activeSegment: [PlottedHistoryPoint] = []

        for (offset, point) in items.enumerated() {
            if point.value.isAvailable {
                activeSegment.append(
                    PlottedHistoryPoint(
                        slotIndex: startSlot + offset,
                        fraction: point.value.clampedPercentageFraction
                    )
                )
            } else if !activeSegment.isEmpty {
                segments.append(activeSegment)
                activeSegment.removeAll(keepingCapacity: true)
            }
        }

        if !activeSegment.isEmpty {
            segments.append(activeSegment)
        }

        return segments
    }

    private mutating func append(_ point: MetricHistoryPoint, to kind: PercentageMetricKind) {
        var list = series[kind] ?? []
        list.append(point)
        if list.count > maxSamples {
            list.removeFirst(list.count - maxSamples)
        }
        series[kind] = list
    }

    private mutating func resetSeriesKeepingNilDevice() {
        for kind in PercentageMetricKind.allCases {
            series[kind] = []
        }
    }
}
