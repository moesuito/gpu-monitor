import XCTest
@testable import GPUMonitor

final class GPUMonitorTests: XCTestCase {
    func testParsesValidPerformanceStatistics() {
        let dict: [String: Any] = [
            "GPU Core Utilization %": 11,
            "Device Utilization %": 14,
            "GPU Memory Utilization %": 2,
            "GPU Video Engine Utilization %": 0,
            "GPU Video Decode Utilization %": 37,
            "Temperature(C)": 58
        ]

        let parsed = GPUPerformanceParser.parsePerformanceStatistics(dict)

        XCTAssertEqual(parsed.metrics[.gpuCore], .available(11))
        XCTAssertEqual(parsed.metrics[.device], .available(14))
        XCTAssertEqual(parsed.metrics[.memory], .available(2))
        XCTAssertEqual(parsed.metrics[.videoEngine], .available(0))
        XCTAssertEqual(parsed.metrics[.videoDecode], .available(37))
        XCTAssertEqual(parsed.temperatureC, .available(58))

        XCTAssertEqual(MetricFormatter.formatPercentage(parsed.metrics[.gpuCore]!), "11%")
        XCTAssertEqual(MetricFormatter.formatTemperature(parsed.temperatureC), "58 °C")
        XCTAssertEqual(MetricFormatter.formatMenuBarTitle(parsed.metrics[.gpuCore]!), "GPU 11%")
    }

    func testMissingFieldsBecomeUnavailableNeverZero() {
        let partial: [String: Any] = [
            "Device Utilization %": 20
        ]

        let parsed = GPUPerformanceParser.parsePerformanceStatistics(partial)

        XCTAssertEqual(parsed.metrics[.gpuCore], .unavailable)
        XCTAssertEqual(parsed.metrics[.memory], .unavailable)
        XCTAssertEqual(parsed.metrics[.videoEngine], .unavailable)
        XCTAssertEqual(parsed.metrics[.videoDecode], .unavailable)
        XCTAssertEqual(parsed.temperatureC, .unavailable)
        XCTAssertEqual(parsed.metrics[.device], .available(20))

        XCTAssertEqual(MetricFormatter.formatPercentage(.unavailable), "Unavailable")
        XCTAssertEqual(MetricFormatter.formatTemperature(.unavailable), "Unavailable")
        XCTAssertEqual(MetricFormatter.formatMenuBarTitle(.unavailable), "GPU —")
    }

    func testNonNumericBooleanAndNonFiniteValuesBecomeUnavailable() {
        let invalid: [String: Any] = [
            "GPU Core Utilization %": "18",
            "Device Utilization %": true,
            "GPU Memory Utilization %": kCFBooleanFalse as Any,
            "GPU Video Engine Utilization %": Double.nan,
            "GPU Video Decode Utilization %": Double.infinity,
            "Temperature(C)": ["nested": 50]
        ]

        let parsed = GPUPerformanceParser.parsePerformanceStatistics(invalid)

        for kind in PercentageMetricKind.allCases {
            XCTAssertEqual(parsed.metrics[kind], .unavailable, "Expected \(kind) to be unavailable")
        }
        XCTAssertEqual(parsed.temperatureC, .unavailable)
    }

    func testBridgedNSNumberZeroAndOneAreValidWhileBooleansRemainUnavailable() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>GPU Core Utilization %</key>
            <integer>0</integer>
            <key>Device Utilization %</key>
            <integer>1</integer>
            <key>GPU Memory Utilization %</key>
            <true/>
            <key>GPU Video Engine Utilization %</key>
            <false/>
        </dict>
        </plist>
        """
        let dict = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any]
        )
        let parsed = GPUPerformanceParser.parsePerformanceStatistics(dict)

        XCTAssertEqual(parsed.metrics[.gpuCore], .available(0))
        XCTAssertEqual(parsed.metrics[.device], .available(1))
        XCTAssertEqual(parsed.metrics[.memory], .unavailable)
        XCTAssertEqual(parsed.metrics[.videoEngine], .unavailable)
        XCTAssertEqual(GPUPerformanceParser.parseNumericValue(NSNumber(value: 0)), .available(0))
        XCTAssertEqual(GPUPerformanceParser.parseNumericValue(NSNumber(value: 1)), .available(1))
        XCTAssertEqual(GPUPerformanceParser.parseNumericValue(NSNumber(value: true)), .unavailable)
        XCTAssertEqual(GPUPerformanceParser.parseNumericValue(NSNumber(value: false)), .unavailable)
    }

    func testOutOfRangeValuesKeepRawNumberAndClampOnlyVisualBar() {
        let dict: [String: Any] = [
            "GPU Core Utilization %": 135,
            "Device Utilization %": -5,
            "GPU Memory Utilization %": 100.002
        ]

        let parsed = GPUPerformanceParser.parsePerformanceStatistics(dict)

        let over = parsed.metrics[.gpuCore]!
        XCTAssertTrue(over.isOutOfPercentageRange)
        XCTAssertEqual(over.clampedPercentageFraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(MetricFormatter.formatPercentage(over), "135%")
        XCTAssertEqual(MetricFormatter.formatMenuBarTitle(over), "GPU 135% !")

        let negative = parsed.metrics[.device]!
        XCTAssertTrue(negative.isOutOfPercentageRange)
        XCTAssertEqual(negative.clampedPercentageFraction, 0.0, accuracy: 0.0001)
        XCTAssertEqual(MetricFormatter.formatPercentage(negative), "-5%")

        let slightlyOver = parsed.metrics[.memory]!
        XCTAssertTrue(slightlyOver.isOutOfPercentageRange)
        XCTAssertNotEqual(MetricFormatter.formatPercentage(slightlyOver), "100%")
    }

    func testMetricLabelsPreserveVideoEngineTerminology() {
        XCTAssertEqual(PercentageMetricKind.gpuCore.displayLabel, "GPU Core")
        XCTAssertEqual(PercentageMetricKind.device.displayLabel, "Device Utilization")
        XCTAssertEqual(PercentageMetricKind.memory.displayLabel, "Memory Utilization")
        XCTAssertEqual(PercentageMetricKind.videoEngine.displayLabel, "Video Engine")
        XCTAssertEqual(PercentageMetricKind.videoDecode.displayLabel, "Video Decode")
    }

    func testReliableModelNameAndFallbackWithoutInventingModel() {
        let nvidiaEntry = RawAcceleratorEntry(
            entryID: 0x100,
            entryName: "NVAccel",
            ioClass: "NVAccel",
            bundleIdentifier: "com.nullmoth.NVAccel",
            pciPrimaryMatch: "0x000010de&0x0000ffff",
            pciVendorID: 0x10de,
            pciDeviceID: 0x2520,
            pciModelName: "NVIDIA GeForce RTX 3060 Laptop GPU\0",
            acceleratorModelName: nil,
            performanceStatistics: [:]
        )
        let nvidiaDescriptor = nvidiaEntry.makeDescriptor()
        XCTAssertEqual(nvidiaDescriptor.displayName, "NVIDIA GeForce RTX 3060 Laptop GPU")
        XCTAssertTrue(nvidiaDescriptor.hasReliableModelName)
        XCTAssertEqual(nvidiaDescriptor.vendor, .nvidia)

        let unknownEntry = RawAcceleratorEntry(
            entryID: 0x200,
            entryName: "display",
            ioClass: "NVAccel",
            bundleIdentifier: "com.nullmoth.NVAccel",
            pciPrimaryMatch: "0x000010de&0x0000ffff",
            pciVendorID: 0x10de,
            pciDeviceID: 0x2520,
            pciModelName: "display",
            acceleratorModelName: nil,
            performanceStatistics: [:]
        )
        let unknownDescriptor = unknownEntry.makeDescriptor()
        XCTAssertEqual(unknownDescriptor.displayName, "Detected GPU")
        XCTAssertFalse(unknownDescriptor.hasReliableModelName)
    }

    func testMultipleAcceleratorsAutoSelectsNvidiaWithoutSumming() throws {
        let intel = RawAcceleratorEntry(
            entryID: 10,
            entryName: "IGPU",
            ioClass: "IntelAccelerator",
            bundleIdentifier: "com.apple.driver.AppleIntel",
            pciPrimaryMatch: "0x8086",
            pciVendorID: 0x8086,
            pciDeviceID: 0x9a49,
            pciModelName: "Intel UHD Graphics",
            acceleratorModelName: nil,
            performanceStatistics: ["GPU Core Utilization %": 30]
        )
        let nvidia = RawAcceleratorEntry(
            entryID: 20,
            entryName: "NVAccel",
            ioClass: "NVAccel",
            bundleIdentifier: "com.nullmoth.NVAccel",
            pciPrimaryMatch: "0x000010de&0x0000ffff",
            pciVendorID: 0x10de,
            pciDeviceID: 0x2520,
            pciModelName: "NVIDIA GeForce RTX 3060 Laptop GPU",
            acceleratorModelName: nil,
            performanceStatistics: ["GPU Core Utilization %": 12]
        )

        let result = try DeviceSelectionPolicy.selectDevice(from: [intel, nvidia], preferredDeviceID: nil)
        XCTAssertEqual(result.selectedDescriptor.id, 20)
        XCTAssertEqual(result.selectedDescriptor.vendor, .nvidia)
        XCTAssertFalse(result.isAmbiguous)
        XCTAssertEqual(result.reason, .autoSelectedNvidia(totalDevices: 2))
        XCTAssertEqual(result.allDescriptors.count, 2)
    }

    func testMultipleAcceleratorsWithoutNvidiaMarksAmbiguousAndNeverMislabels() throws {
        let first = RawAcceleratorEntry(
            entryID: 1,
            entryName: "AccelA",
            ioClass: "GenericAccelA",
            bundleIdentifier: "com.vendor.a",
            pciPrimaryMatch: nil,
            pciVendorID: 0x8086,
            pciDeviceID: 0x1234,
            pciModelName: "Intel Iris Graphics",
            acceleratorModelName: nil,
            performanceStatistics: ["GPU Core Utilization %": 10]
        )
        let second = RawAcceleratorEntry(
            entryID: 2,
            entryName: "AccelB",
            ioClass: "GenericAccelB",
            bundleIdentifier: "com.vendor.b",
            pciPrimaryMatch: nil,
            pciVendorID: 0x1002,
            pciDeviceID: 0x5678,
            pciModelName: nil,
            acceleratorModelName: nil,
            performanceStatistics: ["GPU Core Utilization %": 25]
        )

        let ambiguous = try DeviceSelectionPolicy.selectDevice(from: [second, first], preferredDeviceID: nil)
        XCTAssertTrue(ambiguous.isAmbiguous)
        XCTAssertEqual(ambiguous.selectedDescriptor.id, 1)
        XCTAssertNotEqual(ambiguous.selectedDescriptor.vendor, .nvidia)
        XCTAssertEqual(ambiguous.allDescriptors[1].displayName, "Detected GPU")

        let manual = try DeviceSelectionPolicy.selectDevice(from: [second, first], preferredDeviceID: 2)
        XCTAssertFalse(manual.isAmbiguous)
        XCTAssertEqual(manual.selectedDescriptor.id, 2)
        XCTAssertEqual(manual.reason, .userSelected(totalDevices: 2))
    }

    func testIORegFallbackPlistParsingIndependentOfKeyOrder() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>PerformanceStatistics</key>
                <dict>
                    <key>Temperature(C)</key>
                    <integer>61</integer>
                    <key>GPU Video Decode Utilization %</key>
                    <integer>19</integer>
                    <key>GPU Video Engine Utilization %</key>
                    <integer>4</integer>
                    <key>GPU Memory Utilization %</key>
                    <integer>7</integer>
                    <key>Device Utilization %</key>
                    <integer>22</integer>
                    <key>GPU Core Utilization %</key>
                    <integer>21</integer>
                </dict>
                <key>IOPCIPrimaryMatch</key>
                <string>0x000010de&amp;0x0000ffff</string>
                <key>CFBundleIdentifier</key>
                <string>com.nullmoth.NVAccel</string>
                <key>IOClass</key>
                <string>NVAccel</string>
                <key>IORegistryEntryID</key>
                <integer>4294968649</integer>
            </dict>
        </array>
        </plist>
        """
        let entries = try IORegFallbackCollector.parsePlistData(Data(xml.utf8))
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.entryID, 4294968649)
        XCTAssertEqual(entry.makeDescriptor().vendor, .nvidia)
        XCTAssertEqual(entry.makeDescriptor().displayName, "Detected GPU")

        let parsed = try XCTUnwrap(entry.parsedStatistics)
        XCTAssertEqual(parsed.metrics[.gpuCore], .available(21))
        XCTAssertEqual(parsed.metrics[.videoDecode], .available(19))
        XCTAssertEqual(parsed.metrics[.videoEngine], .available(4))
        XCTAssertEqual(parsed.temperatureC, .available(61))
    }

    func testCompositeCollectorUsesFallbackWhenPrimaryFails() throws {
        let fallbackSnapshot = GPUSnapshot(
            device: GPUDeviceDescriptor(
                id: 1,
                displayName: "Detected GPU",
                hasReliableModelName: false,
                vendor: .nvidia,
                vendorID: nil,
                deviceID: nil,
                ioClass: "NVAccel",
                bundleIdentifier: "com.nullmoth.NVAccel",
                entryName: "NVAccel"
            ),
            availableDevices: [],
            selectionReason: .singleDevice,
            isAmbiguousDeviceSelection: false,
            metrics: [.gpuCore: .available(42)],
            temperatureC: .available(55),
            source: .ioregFallback,
            timestamp: Date()
        )

        let composite = CompositeGPUCollector(
            primary: FailingStubCollector(error: GPUCollectionError.ioKitFailure(kernReturn: -536870212)),
            fallback: SuccessStubCollector(snapshot: fallbackSnapshot)
        )

        let snapshot = try composite.collectSnapshot(preferredDeviceID: nil)
        XCTAssertEqual(snapshot.source, .ioregFallback)
        XCTAssertEqual(snapshot.coreUtilization, .available(42))
    }

    @MainActor
    func testViewModelHandlesSuccessThenFailureWithoutShowingStaleNumbers() {
        let stub = MutableStubCollector()
        let firstTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        stub.result = .success(
            GPUSnapshot(
                device: GPUDeviceDescriptor(
                    id: 1,
                    displayName: "NVIDIA GeForce RTX 3060 Laptop GPU",
                    hasReliableModelName: true,
                    vendor: .nvidia,
                    vendorID: 0x10de,
                    deviceID: 0x2520,
                    ioClass: "NVAccel",
                    bundleIdentifier: "com.nullmoth.NVAccel",
                    entryName: "NVAccel"
                ),
                availableDevices: [],
                selectionReason: .singleDevice,
                isAmbiguousDeviceSelection: false,
                metrics: [
                    .gpuCore: .available(18),
                    .device: .available(20),
                    .memory: .available(5),
                    .videoEngine: .available(0),
                    .videoDecode: .available(12)
                ],
                temperatureC: .available(58),
                source: .ioKit,
                timestamp: firstTimestamp
            )
        )

        let vm = GPUMonitorViewModel(collector: stub, loginItemManager: StubLoginItemManager())
        vm.pollOnceSynchronously()

        XCTAssertEqual(vm.menuBarTitle, "GPU 18%")
        XCTAssertEqual(vm.gpuDisplayName, "NVIDIA GeForce RTX 3060 Laptop GPU")
        XCTAssertEqual(vm.lastSuccessfulReadAt, firstTimestamp)
        XCTAssertNil(vm.lastErrorMessage)
        XCTAssertEqual(vm.metricValue(for: .gpuCore), .available(18))

        stub.result = .failure(GPUCollectionError.performanceStatisticsUnavailable)
        vm.pollOnceSynchronously()

        XCTAssertNotNil(vm.lastErrorMessage)
        XCTAssertEqual(vm.lastSuccessfulReadAt, firstTimestamp)
        XCTAssertEqual(vm.menuBarTitle, "GPU —")
        XCTAssertEqual(vm.metricValue(for: .gpuCore), .unavailable)
        XCTAssertEqual(vm.temperatureValue, .unavailable)
    }

    @MainActor
    func testViewModelInitialFailureShowsNoneAndUnavailable() {
        let vm = GPUMonitorViewModel(
            collector: FailingStubCollector(error: GPUCollectionError.noAcceleratorFound),
            loginItemManager: StubLoginItemManager()
        )
        XCTAssertEqual(vm.lastSuccessfulReadFormatted, "Waiting…")

        vm.pollOnceSynchronously()
        XCTAssertNotNil(vm.lastErrorMessage)
        XCTAssertNil(vm.lastSuccessfulReadAt)
        XCTAssertEqual(vm.lastSuccessfulReadFormatted, "None")
        XCTAssertEqual(vm.menuBarTitle, "GPU —")
        XCTAssertEqual(vm.gpuDisplayName, "GPU unavailable")
        XCTAssertEqual(vm.metricValue(for: .gpuCore), .unavailable)
    }

    @MainActor
    func testLaunchAtLoginIsDisabledByDefaultAndHandlesUserToggleAndFailure() {
        let loginStub = StubLoginItemManager()
        let vm = GPUMonitorViewModel(
            collector: FailingStubCollector(error: GPUCollectionError.noAcceleratorFound),
            loginItemManager: loginStub
        )

        XCTAssertFalse(vm.isLaunchAtLoginEnabled)
        XCTAssertEqual(loginStub.setEnabledCalls, [])

        vm.setLaunchAtLogin(true)
        XCTAssertTrue(vm.isLaunchAtLoginEnabled)
        XCTAssertNil(vm.loginItemMessage)
        XCTAssertEqual(loginStub.setEnabledCalls, [true])

        vm.setLaunchAtLogin(false)
        XCTAssertFalse(vm.isLaunchAtLoginEnabled)
        XCTAssertEqual(loginStub.setEnabledCalls, [true, false])

        loginStub.shouldFail = true
        vm.setLaunchAtLogin(true)
        XCTAssertFalse(vm.isLaunchAtLoginEnabled)
        XCTAssertNotNil(vm.loginItemMessage)
    }

    func testMetricHistoryBufferPreservesUnavailableGapsClampsVisualPointsAndResetsOnDeviceChange() {
        var buffer = MetricHistoryBuffer(maxSamples: 5)
        let device1 = GPUDeviceDescriptor(
            id: 100,
            displayName: "NVIDIA GeForce RTX 3060 Laptop GPU",
            hasReliableModelName: true,
            vendor: .nvidia,
            vendorID: 0x10de,
            deviceID: 0x2520,
            ioClass: "NVAccel",
            bundleIdentifier: "com.nullmoth.NVAccel",
            entryName: "NVAccel"
        )
        let device2 = GPUDeviceDescriptor(
            id: 200,
            displayName: "Detected GPU",
            hasReliableModelName: false,
            vendor: .unknown,
            vendorID: nil,
            deviceID: nil,
            ioClass: "OtherAccel",
            bundleIdentifier: "com.other",
            entryName: "Other"
        )

        func makeSnapshot(device: GPUDeviceDescriptor, core: MetricValue, decode: MetricValue) -> GPUSnapshot {
            GPUSnapshot(
                device: device,
                availableDevices: [device],
                selectionReason: .singleDevice,
                isAmbiguousDeviceSelection: false,
                metrics: [
                    .gpuCore: core,
                    .device: .available(10),
                    .memory: .available(20),
                    .videoEngine: .available(0),
                    .videoDecode: decode
                ],
                temperatureC: .available(55),
                source: .ioKit,
                timestamp: Date()
            )
        }

        buffer.recordSnapshot(makeSnapshot(device: device1, core: .available(25), decode: .available(40)))
        buffer.recordSnapshot(makeSnapshot(device: device1, core: .available(140), decode: .unavailable))
        buffer.recordFailure()
        buffer.recordSnapshot(makeSnapshot(device: device1, core: .available(60), decode: .available(-10)))

        XCTAssertEqual(buffer.points(for: .gpuCore).count, 4)
        XCTAssertEqual(buffer.peakValue(for: .gpuCore), 140)

        // Two separate contiguous segments around the failure gap, right-aligned to slots [1, 2] and [4] out of 0..<5.
        let coreSegments = buffer.contiguousAvailableSegments(for: .gpuCore)
        XCTAssertEqual(coreSegments.count, 2)
        XCTAssertEqual(coreSegments[0], [
            PlottedHistoryPoint(slotIndex: 1, fraction: 0.25),
            PlottedHistoryPoint(slotIndex: 2, fraction: 1.0)
        ])
        XCTAssertEqual(coreSegments[1], [
            PlottedHistoryPoint(slotIndex: 4, fraction: 0.60)
        ])

        // Unavailable readings leave gaps instead of plotting 0%, and negative values clamp visually to 0.0.
        let decodeSegments = buffer.contiguousAvailableSegments(for: .videoDecode)
        XCTAssertEqual(decodeSegments.count, 2)
        XCTAssertEqual(decodeSegments[0], [PlottedHistoryPoint(slotIndex: 1, fraction: 0.40)])
        XCTAssertEqual(decodeSegments[1], [PlottedHistoryPoint(slotIndex: 4, fraction: 0.0)])

        // Switching to another GPU resets history so two devices are never mixed.
        buffer.recordSnapshot(makeSnapshot(device: device2, core: .available(5), decode: .available(5)))
        XCTAssertEqual(buffer.deviceID, 200)
        XCTAssertEqual(buffer.points(for: .gpuCore).count, 1)
    }

    @MainActor
    func testViewModelRecordsHistoryAcrossAllPercentagesAndSwitchesChartSelection() {
        let stub = MutableStubCollector()
        let device = GPUDeviceDescriptor(
            id: 1,
            displayName: "NVIDIA GeForce RTX 3060 Laptop GPU",
            hasReliableModelName: true,
            vendor: .nvidia,
            vendorID: 0x10de,
            deviceID: 0x2520,
            ioClass: "NVAccel",
            bundleIdentifier: "com.nullmoth.NVAccel",
            entryName: "NVAccel"
        )
        stub.result = .success(
            GPUSnapshot(
                device: device,
                availableDevices: [device],
                selectionReason: .singleDevice,
                isAmbiguousDeviceSelection: false,
                metrics: [
                    .gpuCore: .available(15),
                    .device: .available(20),
                    .memory: .available(30),
                    .videoEngine: .available(45),
                    .videoDecode: .available(50)
                ],
                temperatureC: .available(60),
                source: .ioKit,
                timestamp: Date()
            )
        )

        let vm = GPUMonitorViewModel(collector: stub, loginItemManager: StubLoginItemManager())
        XCTAssertEqual(vm.selectedHistoryMode, .metric(.gpuCore))

        vm.pollOnceSynchronously()
        for kind in PercentageMetricKind.allCases {
            XCTAssertEqual(vm.history.points(for: kind).count, 1)
        }
        XCTAssertEqual(vm.peakPercentageFormatted(for: .videoEngine), "45%")

        vm.selectHistoryMetric(.videoDecode)
        XCTAssertEqual(vm.selectedHistoryMode, .metric(.videoDecode))

        vm.selectedHistoryMode = .all
        XCTAssertEqual(vm.selectedHistoryMode.title, "All Percentages")
    }

    @MainActor
    func testHostAppRunsAsAccessoryWithStatusBarButton() {
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        let hasStatusButton = NSApp.windows.contains { window in
            guard let contentView = window.contentView else { return false }
            return containsStatusBarButton(in: contentView)
        }
        XCTAssertTrue(hasStatusButton)
    }

    private func containsStatusBarButton(in view: NSView) -> Bool {
        if view is NSStatusBarButton {
            return true
        }
        return view.subviews.contains { containsStatusBarButton(in: $0) }
    }
}

private final class StubLoginItemManager: LoginItemManaging, @unchecked Sendable {
    var state: LoginItemState = .disabled
    var shouldFail = false
    var setEnabledCalls: [Bool] = []

    func currentState() -> LoginItemState {
        state
    }

    func setEnabled(_ enabled: Bool) throws -> LoginItemState {
        setEnabledCalls.append(enabled)
        if shouldFail {
            throw NSError(domain: "StubLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated error"])
        }
        state = enabled ? .enabled : .disabled
        return state
    }
}

private struct FailingStubCollector: GPUCollecting {
    let error: Error
    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot {
        throw error
    }
}

private struct SuccessStubCollector: GPUCollecting {
    let snapshot: GPUSnapshot
    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot {
        snapshot
    }
}

private final class MutableStubCollector: GPUCollecting, @unchecked Sendable {
    var result: Result<GPUSnapshot, Error> = .failure(GPUCollectionError.noAcceleratorFound)
    func collectSnapshot(preferredDeviceID: UInt64?) throws -> GPUSnapshot {
        try result.get()
    }
}
