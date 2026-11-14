import Foundation
import Combine

enum HistoryChartSelection: Equatable, Hashable, Sendable {
    case all
    case metric(PercentageMetricKind)

    var title: String {
        switch self {
        case .all:
            return "All Percentages"
        case .metric(let kind):
            return kind.displayLabel
        }
    }

    var shortLabel: String {
        switch self {
        case .all:
            return "All"
        case .metric(let kind):
            return kind.displayLabel
        }
    }
}

@MainActor
final class GPUMonitorViewModel: ObservableObject {
    @Published private(set) var currentSnapshot: GPUSnapshot?
    @Published private(set) var lastSuccessfulReadAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var launchAtLoginState: LoginItemState
    @Published private(set) var loginItemMessage: String?
    @Published private(set) var history = MetricHistoryBuffer(maxSamples: 60)
    @Published var selectedHistoryMode: HistoryChartSelection = .metric(.gpuCore)
    @Published var selectedDeviceID: UInt64?

    private let collector: any GPUCollecting
    private let loginItemManager: any LoginItemManaging
    private var pollingTask: Task<Void, Never>?
    private var isCollecting = false
    private let pollIntervalSeconds: TimeInterval

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    init(
        collector: any GPUCollecting = CompositeGPUCollector(),
        loginItemManager: any LoginItemManaging = MainAppLoginItemManager(),
        pollIntervalSeconds: TimeInterval = 1.0
    ) {
        self.collector = collector
        self.loginItemManager = loginItemManager
        self.pollIntervalSeconds = pollIntervalSeconds
        self.launchAtLoginState = loginItemManager.currentState()
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }

        let interval = pollIntervalSeconds
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performCollectionOnce()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func selectDevice(_ id: UInt64) {
        if selectedDeviceID != id {
            selectedDeviceID = id
            history.reset()
        }
        refreshNow()
    }

    func selectHistoryMetric(_ kind: PercentageMetricKind) {
        selectedHistoryMode = .metric(kind)
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.performCollectionOnce()
        }
    }

    func performCollectionOnce() async {
        guard !isCollecting else { return }
        isCollecting = true
        defer { isCollecting = false }

        let preferredID = selectedDeviceID
        let collector = self.collector
        let result: Result<GPUSnapshot, Error> = await Task.detached(priority: .utility) {
            Result { try collector.collectSnapshot(preferredDeviceID: preferredID) }
        }.value

        switch result {
        case .success(let snapshot):
            applySuccess(snapshot)
        case .failure(let error):
            applyFailure(error)
        }
    }

    /// Runs a single synchronous collection pass for unit tests.
    func pollOnceSynchronously() {
        let preferredID = selectedDeviceID
        do {
            let snapshot = try collector.collectSnapshot(preferredDeviceID: preferredID)
            applySuccess(snapshot)
        } catch {
            applyFailure(error)
        }
    }

    var menuBarTitle: String {
        guard lastErrorMessage == nil, let snapshot = currentSnapshot else {
            return "GPU —"
        }
        return MetricFormatter.formatMenuBarTitle(snapshot.coreUtilization)
    }

    var gpuDisplayName: String {
        if let snapshot = currentSnapshot {
            return snapshot.device.displayName
        }
        return lastErrorMessage == nil ? "Detected GPU" : "GPU unavailable"
    }

    var availableDevices: [GPUDeviceDescriptor] {
        currentSnapshot?.availableDevices ?? []
    }

    var hasMultipleDevices: Bool {
        availableDevices.count > 1
    }

    var effectiveSelectedDeviceID: UInt64 {
        selectedDeviceID ?? currentSnapshot?.device.id ?? 0
    }

    var lastSuccessfulReadFormatted: String {
        guard let lastSuccessfulReadAt else {
            return lastErrorMessage == nil ? "Waiting…" : "None"
        }
        return Self.timeFormatter.string(from: lastSuccessfulReadAt)
    }

    func metricValue(for kind: PercentageMetricKind) -> MetricValue {
        guard lastErrorMessage == nil, let snapshot = currentSnapshot else {
            return .unavailable
        }
        return snapshot.metrics[kind] ?? .unavailable
    }

    func peakPercentageFormatted(for kind: PercentageMetricKind) -> String {
        guard let peak = history.peakValue(for: kind) else {
            return MetricFormatter.formatPercentage(.unavailable)
        }
        return MetricFormatter.formatPercentage(.available(peak))
    }

    var temperatureValue: MetricValue {
        guard lastErrorMessage == nil, let snapshot = currentSnapshot else {
            return .unavailable
        }
        return snapshot.temperatureC
    }

    var selectionStatusBanner: String? {
        guard let snapshot = currentSnapshot else { return nil }
        switch snapshot.selectionReason {
        case .singleDevice:
            return nil
        case .autoSelectedNvidia(let total):
            return "Automatically selected NVIDIA among \(total) IOAccelerator devices."
        case .userSelected(let total):
            return "Showing selected device (\(total) IOAccelerator devices detected)."
        case .ambiguousFallbackToFirst(let total, let nvidiaCount):
            if nvidiaCount == 0 {
                return "Multiple IOAccelerator devices (\(total)) with no NVIDIA reliably identified. Showing: \(snapshot.device.displayName) (\(snapshot.device.shortHexID))."
            }
            return "Multiple NVIDIA IOAccelerator devices (\(nvidiaCount) of \(total)) detected. Choose the desired device."
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginState.isEnabled
    }

    func syncLoginItemState() {
        launchAtLoginState = loginItemManager.currentState()
        if launchAtLoginState == .requiresApproval {
            loginItemMessage = "Approval required in System Settings › General › Login Items."
        } else if launchAtLoginState == .enabled {
            loginItemMessage = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let newState = try loginItemManager.setEnabled(enabled)
            launchAtLoginState = newState
            if newState == .requiresApproval {
                loginItemMessage = "Approval required in System Settings › General › Login Items."
            } else {
                loginItemMessage = nil
            }
        } catch {
            launchAtLoginState = loginItemManager.currentState()
            loginItemMessage = "Unable to update launch at login (\(error.localizedDescription))."
        }
    }

    private func applySuccess(_ snapshot: GPUSnapshot) {
        currentSnapshot = snapshot
        lastSuccessfulReadAt = snapshot.timestamp
        lastErrorMessage = nil
        history.recordSnapshot(snapshot)
    }

    private func applyFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        history.recordFailure(at: Date())
    }
}
