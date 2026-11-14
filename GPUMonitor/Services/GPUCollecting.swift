import Foundation

protocol GPUCollecting: Sendable {
    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot
}

/// Coletor composto que usa IOKit diretamente como caminho principal e `ioreg -a` estruturado como fallback.
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
