import Foundation
import IOKit

/// Lê métricas e metadados de dispositivos `IOAccelerator` diretamente via IOKit/IORegistry.
struct IOKitGPUCollector: GPUCollecting {
    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot {
        let entries = try readAcceleratorEntries()
        let selection = try DeviceSelectionPolicy.selectDevice(
            from: entries,
            preferredDeviceID: preferredDeviceID
        )

        guard let parsed = selection.selectedEntry.parsedStatistics else {
            throw GPUCollectionError.performanceStatisticsUnavailable
        }

        return GPUSnapshot(
            device: selection.selectedDescriptor,
            availableDevices: selection.allDescriptors,
            selectionReason: selection.reason,
            isAmbiguousDeviceSelection: selection.isAmbiguous,
            metrics: parsed.metrics,
            temperatureC: parsed.temperatureC,
            source: .ioKit,
            timestamp: Date()
        )
    }

    private func readAcceleratorEntries() throws -> [RawAcceleratorEntry] {
        guard let matching = IOServiceMatching("IOAccelerator") else {
            throw GPUCollectionError.ioKitFailure(kernReturn: KERN_FAILURE)
        }

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            throw GPUCollectionError.ioKitFailure(kernReturn: kr)
        }
        defer { IOObjectRelease(iterator) }

        var entries: [RawAcceleratorEntry] = []

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var entryID: UInt64 = 0
            let idResult = IORegistryEntryGetRegistryEntryID(service, &entryID)
            guard idResult == KERN_SUCCESS else { continue }

            let entryName = Self.readEntryName(service)
            let ioClass = Self.readCFProperty(service, key: "IOClass") as? String
            let bundleIdentifier = Self.readCFProperty(service, key: "CFBundleIdentifier") as? String
            let pciPrimaryMatch = Self.readCFProperty(service, key: "IOPCIPrimaryMatch") as? String
            let acceleratorModel = GPUPerformanceParser.parseRegistryString(
                from: Self.readCFProperty(service, key: "model")
            )
            let performanceStatistics = Self.readCFProperty(service, key: "PerformanceStatistics") as? [String: Any]
            let pciMetadata = Self.readParentPCIMetadata(for: service)

            entries.append(
                RawAcceleratorEntry(
                    entryID: entryID,
                    entryName: entryName,
                    ioClass: ioClass,
                    bundleIdentifier: bundleIdentifier,
                    pciPrimaryMatch: pciPrimaryMatch,
                    pciVendorID: pciMetadata.vendorID,
                    pciDeviceID: pciMetadata.deviceID,
                    pciModelName: pciMetadata.modelName,
                    acceleratorModelName: acceleratorModel,
                    performanceStatistics: performanceStatistics
                )
            )
        }

        return entries
    }

    private static func readCFProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private static func readEntryName(_ entry: io_registry_entry_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        let kr = nameBuffer.withUnsafeMutableBufferPointer { buffer -> kern_return_t in
            guard let baseAddress = buffer.baseAddress else { return KERN_FAILURE }
            return IORegistryEntryGetName(entry, baseAddress)
        }
        guard kr == KERN_SUCCESS else { return nil }
        let name = String(cString: nameBuffer)
        return name.isEmpty ? nil : name
    }

    private static func readParentPCIMetadata(
        for service: io_registry_entry_t
    ) -> (vendorID: UInt32?, deviceID: UInt32?, modelName: String?) {
        var current: io_registry_entry_t = service
        IOObjectRetain(current)
        defer {
            if current != 0 {
                IOObjectRelease(current)
            }
        }

        for _ in 0..<5 {
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            current = 0

            guard kr == KERN_SUCCESS, parent != 0 else { break }
            current = parent

            if IOObjectConformsTo(current, "IOPCIDevice") != 0 {
                let vendorData = readCFProperty(current, key: "vendor-id") as? Data
                let deviceData = readCFProperty(current, key: "device-id") as? Data
                let modelRaw = readCFProperty(current, key: "model")
                return (
                    GPUPerformanceParser.parseLittleEndianUInt32(from: vendorData),
                    GPUPerformanceParser.parseLittleEndianUInt32(from: deviceData),
                    GPUPerformanceParser.parseRegistryString(from: modelRaw)
                )
            }
        }

        return (nil, nil, nil)
    }
}
