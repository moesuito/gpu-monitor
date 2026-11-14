import Foundation

protocol GPUCollecting: Sendable {
    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot
}

/// Composite collector that queries IOKit directly first and falls back to structured `ioreg -a`.
struct CompositeGPUCollector: GPUCollecting {
    private let primary: any GPUCollecting
    private let fallback: any GPUCollecting

    init(
        primary: any GPUCollecting = IOKitGPUCollector(),
        fallback: any GPUCollecting = IORegFallbackCollector()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot {
        do {
            return try primary.collectSnapshot(preferredDeviceID: preferredDeviceID)
        } catch let primaryError {
            do {
                return try fallback.collectSnapshot(preferredDeviceID: preferredDeviceID)
            } catch {
                throw primaryError
            }
        }
    }
}
