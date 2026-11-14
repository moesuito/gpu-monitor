import Foundation

/// Coletor de fallback que executa `/usr/sbin/ioreg -r -c IOAccelerator -d 1 -a`
/// em segundo plano e interpreta a saída XML plist estruturada (independente da ordem das chaves).
struct IORegFallbackCollector: GPUCollecting {
    static let defaultExecutablePath = "/usr/sbin/ioreg"

    private let executablePath: String
    private let timeoutSeconds: TimeInterval

    init(
        executablePath: String = IORegFallbackCollector.defaultExecutablePath,
        timeoutSeconds: TimeInterval = 2.0
    ) {
        self.executablePath = executablePath
        self.timeoutSeconds = timeoutSeconds
    }

    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot {
        let data = try runIORegPlistCommand()
        let entries = try Self.parsePlistData(data)
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
            source: .ioregFallback,
            timestamp: Date()
        )
    }

    private func runIORegPlistCommand() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-r", "-c", "IOAccelerator", "-d", "1", "-a"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timedOutFlag = TimeoutFlag()
        let timeoutWorkItem = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            timedOutFlag.markTimedOut()
            process.terminate()
        }

        do {
            try process.run()
        } catch {
            throw GPUCollectionError.fallbackProcessFailed(error.localizedDescription)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeoutSeconds,
            execute: timeoutWorkItem
        )

        // Ler stdout antes de aguardar término evita deadlock caso o buffer do pipe encha.
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWorkItem.cancel()

        if timedOutFlag.isTimedOut {
            throw GPUCollectionError.fallbackProcessFailed("tempo limite excedido")
        }

        guard process.terminationStatus == 0 else {
            let errText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = errText.isEmpty ? "status \(process.terminationStatus)" : errText
            throw GPUCollectionError.fallbackProcessFailed(detail)
        }

        return outputData
    }

    static func parsePlistData(_ data: Data) throws -> [RawAcceleratorEntry] {
        guard !data.isEmpty else {
            return []
        }

        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw GPUCollectionError.fallbackParsingFailed
        }

        let dictionaries: [[String: Any]]
        if let array = plistObject as? [[String: Any]] {
            dictionaries = array
        } else if let single = plistObject as? [String: Any] {
            dictionaries = [single]
        } else {
            throw GPUCollectionError.fallbackParsingFailed
        }

        return dictionaries.enumerated().compactMap { index, dict in
            let entryID = Self.extractEntryID(from: dict, fallbackIndex: index)
            let entryName = dict["IORegistryEntryName"] as? String
            let ioClass = dict["IOClass"] as? String
            let bundleIdentifier = dict["CFBundleIdentifier"] as? String
            let pciPrimaryMatch = dict["IOPCIPrimaryMatch"] as? String
            let modelName = GPUPerformanceParser.parseRegistryString(from: dict["model"])
            let stats = dict["PerformanceStatistics"] as? [String: Any]

            return RawAcceleratorEntry(
                entryID: entryID,
                entryName: entryName,
                ioClass: ioClass,
                bundleIdentifier: bundleIdentifier,
                pciPrimaryMatch: pciPrimaryMatch,
                pciVendorID: nil,
                pciDeviceID: nil,
                pciModelName: nil,
                acceleratorModelName: modelName,
                performanceStatistics: stats
            )
        }
    }

    private static func extractEntryID(from dict: [String: Any], fallbackIndex: Int) -> UInt64 {
        if let uintVal = dict["IORegistryEntryID"] as? UInt64 {
            return uintVal
        }
        if let intVal = dict["IORegistryEntryID"] as? Int, intVal >= 0 {
            return UInt64(intVal)
        }
        if let numVal = dict["IORegistryEntryID"] as? NSNumber {
            return numVal.uint64Value
        }
        return UInt64(fallbackIndex + 1)
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}
