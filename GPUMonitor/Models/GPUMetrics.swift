import Foundation
import CoreFoundation

/// Represents a parsed numeric driver metric value.
enum MetricValue: Equatable, Sendable {
    case available(Double)
    case unavailable

    var numericValue: Double? {
        guard case .available(let value) = self else { return nil }
        return value
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Returns true when the raw numeric value falls outside the expected [0, 100] percentage range.
    var isOutOfPercentageRange: Bool {
        guard case .available(let value) = self else { return false }
        return value < 0 || value > 100
    }

    /// Returns the visual progress bar fraction clamped to [0.0, 1.0] without altering the raw value.
    var clampedPercentageFraction: Double {
        guard case .available(let value) = self else { return 0 }
        let clamped = min(max(value, 0), 100)
        return clamped / 100.0
    }
}

/// The five percentage utilization indicators exposed under PerformanceStatistics.
enum PercentageMetricKind: String, CaseIterable, Identifiable, Sendable {
    case gpuCore = "GPU Core Utilization %"
    case device = "Device Utilization %"
    case memory = "GPU Memory Utilization %"
    case videoEngine = "GPU Video Engine Utilization %"
    case videoDecode = "GPU Video Decode Utilization %"

    var id: String { rawValue }

    var registryKey: String { rawValue }

    var displayLabel: String {
        switch self {
        case .gpuCore:
            return "GPU Core"
        case .device:
            return "Device Utilization"
        case .memory:
            return "Memory Utilization"
        case .videoEngine:
            return "Video Engine"
        case .videoDecode:
            return "Video Decode"
        }
    }
}

enum GPUVendor: Equatable, Hashable, Sendable {
    case nvidia
    case intel
    case amd
    case apple
    case other(UInt32)
    case unknown

    var displayLabel: String? {
        switch self {
        case .nvidia: return "NVIDIA"
        case .intel: return "Intel"
        case .amd: return "AMD"
        case .apple: return "Apple"
        case .other, .unknown: return nil
        }
    }
}

enum DataSourceKind: Equatable, Sendable {
    case ioKit
    case ioregFallback

    var label: String {
        switch self {
        case .ioKit: return "IOKit"
        case .ioregFallback: return "ioreg (fallback)"
        }
    }
}

/// Metadata describing an IOAccelerator device discovered in IORegistry.
struct GPUDeviceDescriptor: Identifiable, Equatable, Hashable, Sendable {
    let id: UInt64
    let displayName: String
    let hasReliableModelName: Bool
    let vendor: GPUVendor
    let vendorID: UInt32?
    let deviceID: UInt32?
    let ioClass: String?
    let bundleIdentifier: String?
    let entryName: String?

    var shortHexID: String {
        String(format: "0x%llx", id)
    }

    var pickerLabel: String {
        if hasReliableModelName {
            return "\(displayName) (\(shortHexID))"
        }
        if let ioClass, !ioClass.isEmpty {
            return "\(displayName) — \(ioClass) (\(shortHexID))"
        }
        return "\(displayName) (\(shortHexID))"
    }
}

struct GPUParsedStatistics: Equatable, Sendable {
    let metrics: [PercentageMetricKind: MetricValue]
    let temperatureC: MetricValue
}

/// Raw entry collected from IORegistry (or fallback) prior to device selection.
struct RawAcceleratorEntry: Sendable {
    let entryID: UInt64
    let entryName: String?
    let ioClass: String?
    let bundleIdentifier: String?
    let pciPrimaryMatch: String?
    let pciVendorID: UInt32?
    let pciDeviceID: UInt32?
    let pciModelName: String?
    let acceleratorModelName: String?
    let parsedStatistics: GPUParsedStatistics?

    init(
        entryID: UInt64,
        entryName: String?,
        ioClass: String?,
        bundleIdentifier: String?,
        pciPrimaryMatch: String?,
        pciVendorID: UInt32?,
        pciDeviceID: UInt32?,
        pciModelName: String?,
        acceleratorModelName: String?,
        performanceStatistics: [String: Any]?
    ) {
        self.entryID = entryID
        self.entryName = entryName
        self.ioClass = ioClass
        self.bundleIdentifier = bundleIdentifier
        self.pciPrimaryMatch = pciPrimaryMatch
        self.pciVendorID = pciVendorID
        self.pciDeviceID = pciDeviceID
        self.pciModelName = pciModelName
        self.acceleratorModelName = acceleratorModelName
        if let performanceStatistics {
            let parsed = GPUPerformanceParser.parsePerformanceStatistics(performanceStatistics)
            self.parsedStatistics = GPUParsedStatistics(
                metrics: parsed.metrics,
                temperatureC: parsed.temperatureC
            )
        } else {
            self.parsedStatistics = nil
        }
    }

    func makeDescriptor() -> GPUDeviceDescriptor {
        let vendor = Self.resolveVendor(
            pciVendorID: pciVendorID,
            pciPrimaryMatch: pciPrimaryMatch,
            bundleIdentifier: bundleIdentifier,
            ioClass: ioClass
        )
        let reliableModel = Self.resolveReliableModelName(
            pciModelName: pciModelName,
            acceleratorModelName: acceleratorModelName,
            vendor: vendor
        )
        return GPUDeviceDescriptor(
            id: entryID,
            displayName: reliableModel ?? "Detected GPU",
            hasReliableModelName: reliableModel != nil,
            vendor: vendor,
            vendorID: pciVendorID,
            deviceID: pciDeviceID,
            ioClass: ioClass,
            bundleIdentifier: bundleIdentifier,
            entryName: entryName
        )
    }

    static func resolveVendor(
        pciVendorID: UInt32?,
        pciPrimaryMatch: String?,
        bundleIdentifier: String?,
        ioClass: String?
    ) -> GPUVendor {
        // Explicit parent PCI vendor-id is authoritative when present.
        if let pciVendorID {
            switch pciVendorID {
            case 0x10de: return .nvidia
            case 0x8086: return .intel
            case 0x1002: return .amd
            case 0x106b: return .apple
            default: return .other(pciVendorID)
            }
        }

        // Without parent PCI vendor-id (e.g. ioreg -d 1 fallback), rely only on unambiguous matching hints.
        let primary = pciPrimaryMatch?.lowercased() ?? ""
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let klass = ioClass?.lowercased() ?? ""

        let matchesNvidia = primary.contains("10de")
            || bundle == "com.nullmoth.nvaccel"
            || bundle.hasPrefix("com.nvidia.")
            || klass == "nvaccel"

        let matchesIntel = primary.contains("8086")
            || bundle.contains("intel")
            || klass.contains("intel")

        let matchesAMD = primary.contains("1002")
            || bundle.contains("amd")
            || bundle.contains("radeon")
            || klass.contains("amd")
            || klass.contains("radeon")

        let matchesApple = bundle.contains("applegpu")
            || klass.hasPrefix("agx")

        let hits = [matchesNvidia, matchesIntel, matchesAMD, matchesApple].filter { $0 }.count
        if hits == 1 {
            if matchesNvidia { return .nvidia }
            if matchesIntel { return .intel }
            if matchesAMD { return .amd }
            if matchesApple { return .apple }
        }

        return .unknown
    }

    static func resolveReliableModelName(
        pciModelName: String?,
        acceleratorModelName: String?,
        vendor: GPUVendor
    ) -> String? {
        for candidate in [pciModelName, acceleratorModelName] {
            guard let cleaned = cleanModelString(candidate) else { continue }
            if isConsistent(modelName: cleaned, with: vendor) {
                return cleaned
            }
        }
        return nil
    }

    static func cleanModelString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let genericPlaceholders: Set<String> = [
            "display", "vga", "gfx0", "igpu", "pegp", "gpu",
            "nvaccel", "ioaccelerator", "unknown", "generic"
        ]
        if genericPlaceholders.contains(trimmed.lowercased()) {
            return nil
        }
        return trimmed
    }

    private static func isConsistent(modelName: String, with vendor: GPUVendor) -> Bool {
        let lower = modelName.lowercased()
        switch vendor {
        case .intel:
            return !lower.contains("nvidia") && !lower.contains("geforce") && !lower.contains("radeon")
        case .amd:
            return !lower.contains("nvidia") && !lower.contains("geforce") && !lower.contains("intel")
        case .nvidia:
            return !lower.contains("intel") && !lower.contains("radeon")
        case .apple:
            return !lower.contains("nvidia") && !lower.contains("intel") && !lower.contains("radeon")
        case .other, .unknown:
            return true
        }
    }
}

enum DeviceSelectionReason: Equatable, Sendable {
    case singleDevice
    case autoSelectedNvidia(totalDevices: Int)
    case userSelected(totalDevices: Int)
    case ambiguousFallbackToFirst(totalDevices: Int, nvidiaCandidateCount: Int)
}

struct DeviceSelectionResult: Sendable {
    let selectedEntry: RawAcceleratorEntry
    let selectedDescriptor: GPUDeviceDescriptor
    let allDescriptors: [GPUDeviceDescriptor]
    let reason: DeviceSelectionReason
    let isAmbiguous: Bool
}

enum DeviceSelectionPolicy {
    static func selectDevice(
        from entries: [RawAcceleratorEntry],
        preferredDeviceID: UInt64?
    ) throws -> DeviceSelectionResult {
        guard !entries.isEmpty else {
            throw GPUCollectionError.noAcceleratorFound
        }

        let sorted = entries.sorted { $0.entryID < $1.entryID }
        let descriptors = sorted.map { $0.makeDescriptor() }

        if sorted.count == 1 {
            return DeviceSelectionResult(
                selectedEntry: sorted[0],
                selectedDescriptor: descriptors[0],
                allDescriptors: descriptors,
                reason: .singleDevice,
                isAmbiguous: false
            )
        }

        if let preferredDeviceID,
           let idx = sorted.firstIndex(where: { $0.entryID == preferredDeviceID }) {
            return DeviceSelectionResult(
                selectedEntry: sorted[idx],
                selectedDescriptor: descriptors[idx],
                allDescriptors: descriptors,
                reason: .userSelected(totalDevices: sorted.count),
                isAmbiguous: false
            )
        }

        let nvidiaIndices = descriptors.indices.filter { descriptors[$0].vendor == .nvidia }
        if nvidiaIndices.count == 1, let idx = nvidiaIndices.first {
            return DeviceSelectionResult(
                selectedEntry: sorted[idx],
                selectedDescriptor: descriptors[idx],
                allDescriptors: descriptors,
                reason: .autoSelectedNvidia(totalDevices: sorted.count),
                isAmbiguous: false
            )
        }

        // Ambiguous devices: never mislabel another GPU as NVIDIA; deterministically pick the first and warn.
        return DeviceSelectionResult(
            selectedEntry: sorted[0],
            selectedDescriptor: descriptors[0],
            allDescriptors: descriptors,
            reason: .ambiguousFallbackToFirst(
                totalDevices: sorted.count,
                nvidiaCandidateCount: nvidiaIndices.count
            ),
            isAmbiguous: true
        )
    }
}

/// Complete snapshot of a single GPU reading.
struct GPUSnapshot: Equatable, Sendable {
    let device: GPUDeviceDescriptor
    let availableDevices: [GPUDeviceDescriptor]
    let selectionReason: DeviceSelectionReason
    let isAmbiguousDeviceSelection: Bool
    let metrics: [PercentageMetricKind: MetricValue]
    let temperatureC: MetricValue
    let source: DataSourceKind
    let timestamp: Date

    var coreUtilization: MetricValue {
        metrics[.gpuCore] ?? .unavailable
    }

    var hasAnyReadableMetric: Bool {
        if temperatureC.isAvailable { return true }
        return metrics.values.contains(where: \.isAvailable)
    }
}

enum GPUCollectionError: LocalizedError, Equatable, Sendable {
    case ioKitFailure(kernReturn: Int32)
    case noAcceleratorFound
    case performanceStatisticsUnavailable
    case fallbackProcessFailed(String)
    case fallbackParsingFailed

    var errorDescription: String? {
        switch self {
        case .ioKitFailure(let kr):
            return "Failed to query IOKit (code \(kr))."
        case .noAcceleratorFound:
            return "No IOAccelerator device found in IORegistry."
        case .performanceStatisticsUnavailable:
            return "PerformanceStatistics dictionary is unavailable for this device."
        case .fallbackProcessFailed(let detail):
            return "Failed to run ioreg fallback reader: \(detail)"
        case .fallbackParsingFailed:
            return "Unable to parse structured ioreg output."
        }
    }
}

enum GPUPerformanceParser {
    static let temperatureKey = "Temperature(C)"

    static func parsePerformanceStatistics(
        _ dict: [String: Any]?
    ) -> (metrics: [PercentageMetricKind: MetricValue], temperatureC: MetricValue) {
        var parsedMetrics: [PercentageMetricKind: MetricValue] = [:]
        for kind in PercentageMetricKind.allCases {
            parsedMetrics[kind] = parseNumericValue(dict?[kind.registryKey])
        }
        let temp = parseNumericValue(dict?[temperatureKey])
        return (parsedMetrics, temp)
    }

    static func parseNumericValue(_ raw: Any?) -> MetricValue {
        guard let raw else { return .unavailable }

        // Never use `raw is Bool` because __NSCFNumber(0) and __NSCFNumber(1) bridge to Bool in Swift.
        // CFBooleanGetTypeID() reliably distinguishes true CFBoolean/Bool values from CFNumber(0/1).
        let cfType = raw as CFTypeRef
        if CFGetTypeID(cfType) == CFBooleanGetTypeID() {
            return .unavailable
        }

        let doubleValue: Double?
        switch raw {
        case let value as Int:
            doubleValue = Double(value)
        case let value as Int64:
            doubleValue = Double(value)
        case let value as UInt64:
            doubleValue = Double(value)
        case let value as Int32:
            doubleValue = Double(value)
        case let value as UInt32:
            doubleValue = Double(value)
        case let value as Double:
            doubleValue = value
        case let value as Float:
            doubleValue = Double(value)
        case let number as NSNumber:
            doubleValue = number.doubleValue
        default:
            doubleValue = nil
        }

        guard let value = doubleValue, value.isFinite else {
            return .unavailable
        }

        return .available(value)
    }

    static func parseLittleEndianUInt32(from data: Data?) -> UInt32? {
        guard let data, data.count >= MemoryLayout<UInt32>.size else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    static func parseRegistryString(from value: Any?) -> String? {
        if let str = value as? String {
            return str.replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = value as? Data {
            return String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

enum MetricFormatter {
    static func formatPercentage(_ metric: MetricValue) -> String {
        guard case .available(let value) = metric else {
            return "Unavailable"
        }
        return "\(formatNumber(value))%"
    }

    static func formatTemperature(_ metric: MetricValue) -> String {
        guard case .available(let value) = metric else {
            return "Unavailable"
        }
        return "\(formatNumber(value)) °C"
    }

    static func formatMenuBarTitle(_ metric: MetricValue) -> String {
        guard case .available(let value) = metric else {
            return "GPU —"
        }
        if metric.isOutOfPercentageRange {
            return "GPU \(formatNumber(value))% !"
        }
        return "GPU \(formatNumber(value))%"
    }

    static func formatNumber(_ value: Double) -> String {
        let normalized = (value == 0) ? 0 : value // avoid "-0"

        if normalized.rounded(.towardZero) == normalized,
           normalized >= Double(Int64.min / 2),
           normalized <= Double(Int64.max / 2) {
            return String(Int64(normalized))
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        // Preserve enough decimal places near 0 or 100 so out-of-range values never display as 0% or 100%.
        if (normalized > 100 && normalized < 100.01) || (normalized < 0 && normalized > -0.01) {
            formatter.maximumFractionDigits = 4
        } else {
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: normalized)) ?? String(normalized)
    }
}
