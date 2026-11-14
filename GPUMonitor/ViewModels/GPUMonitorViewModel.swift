import Foundation
import Combine

@MainActor
final class GPUMonitorViewModel: ObservableObject {
    @Published private(set) var currentSnapshot: GPUSnapshot?
    @Published private(set) var lastSuccessfulReadAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published var selectedDeviceID: UInt64?

    private let collector: any GPUCollecting
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
        pollIntervalSeconds: TimeInterval = 1.0
    ) {
        self.collector = collector
        self.pollIntervalSeconds = pollIntervalSeconds
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
        selectedDeviceID = id
        refreshNow()
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

    /// Executa uma coleta síncrona em testes unitários.
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
        return lastErrorMessage == nil ? "GPU detectada" : "GPU indisponível"
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
            return lastErrorMessage == nil ? "Aguardando…" : "Nenhuma"
        }
        return Self.timeFormatter.string(from: lastSuccessfulReadAt)
    }

    func metricValue(for kind: PercentageMetricKind) -> MetricValue {
        guard lastErrorMessage == nil, let snapshot = currentSnapshot else {
            return .unavailable
        }
        return snapshot.metrics[kind] ?? .unavailable
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
            return "NVIDIA selecionada automaticamente entre \(total) dispositivos IOAccelerator."
        case .userSelected(let total):
            return "Exibindo dispositivo selecionado (\(total) dispositivos IOAccelerator detectados)."
        case .ambiguousFallbackToFirst(let total, let nvidiaCount):
            if nvidiaCount == 0 {
                return "Múltiplos IOAccelerator (\(total)) sem NVIDIA identificada com segurança. Exibindo: \(snapshot.device.displayName) (\(snapshot.device.shortHexID))."
            }
            return "Múltiplos IOAccelerator NVIDIA (\(nvidiaCount) de \(total)) detectados. Selecione o dispositivo desejado."
        }
    }

    private func applySuccess(_ snapshot: GPUSnapshot) {
        currentSnapshot = snapshot
        lastSuccessfulReadAt = snapshot.timestamp
        lastErrorMessage = nil
    }

    private func applyFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}
