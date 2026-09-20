import Foundation
import Observation
@preconcurrency import Combine

// MARK: - Siri Engine Monitor (ViewModel)

/// Central coordinator that fuses signals from `LogStreamWatcher`,
/// `NetworkProcessWatcher` and `NeuralEngineMonitor` into a single
/// observable processing state for the UI layer.
@MainActor
@Observable
final class SiriEngineMonitor {

    // MARK: Observable State

    var currentStatus: SiriProcessingState = .idle
    var lastPrompt: String = "Esperando orden…"
    var lastResponseTimeMs: Int? = nil
    var history: [SiriEventLog] = []
    var isHUDVisible: Bool = false
    var chipInfo: String = "Apple Neural Engine"
    var networkInfo: String = "Sin conexión saliente (0 B/s)"

    // MARK: Private

    @ObservationIgnored private let logWatcher = LogStreamWatcher()
    @ObservationIgnored private let networkWatcher = NetworkProcessWatcher()
    @ObservationIgnored private let aneMonitor = NeuralEngineMonitor()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var requestStartDate: Date?

    private let maxHistoryItems = 100

    // MARK: Init

    init() {
        setupSubscriptions()
        startMonitoring()
    }

    // MARK: Subscriptions

    private func setupSubscriptions() {
        Publishers.CombineLatest3(
            logWatcher.eventPublisher,
            networkWatcher.hasActiveTraffic,
            aneMonitor.aneActivity
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] logEvent, hasNetworkTraffic, hasANEActivity in
            MainActor.assumeIsolated {
                self?.evaluateState(
                    logEvent: logEvent,
                    isCloudActive: hasNetworkTraffic,
                    isANEActive: hasANEActivity
                )
            }
        }
        .store(in: &cancellables)
    }

    private func startMonitoring() {
        logWatcher.startMonitoring()
        networkWatcher.startMonitoring()
        aneMonitor.startMonitoring()
    }

    // MARK: State Evaluation

    private func evaluateState(
        logEvent: SiriLogEvent?,
        isCloudActive: Bool,
        isANEActive: Bool
    ) {
        // No active Siri event
        guard let event = logEvent, event.isActive else {
            if isANEActive {
                currentStatus = .local
                chipInfo = "Apple Neural Engine (activo)"
                networkInfo = "Sin conexión saliente (0 B/s)"
            } else {
                currentStatus = .idle
                chipInfo = "Apple Neural Engine"
                networkInfo = "Sin conexión saliente (0 B/s)"
            }
            return
        }

        let previousStatus = currentStatus

        // Determine new state
        if event.isExternalService {
            currentStatus = .externalAI
            networkInfo = "Tráfico saliente: proveedor externo"
        } else if isCloudActive || event.isPCC {
            currentStatus = .privateCloud
            networkInfo = "Tráfico saliente: Apple PCC (cifrado E2E)"
        } else {
            currentStatus = .local
            chipInfo = "Apple Neural Engine (activo)"
            networkInfo = "Ninguna conexión saliente (0 B/s)"
        }

        // Compute response time
        if requestStartDate == nil {
            requestStartDate = event.timestamp
        }
        let elapsed = Date().timeIntervalSince(requestStartDate ?? Date())
        lastResponseTimeMs = Int(elapsed * 1000)

        // Update prompt
        lastPrompt = extractQuerySnippet(from: event.message)

        // Record history entry on state change or new activity
        if previousStatus != currentStatus || currentStatus != .idle {
            let entry = SiriEventLog(
                timestamp: event.timestamp,
                state: currentStatus,
                querySnippet: lastPrompt,
                responseTimeMs: lastResponseTimeMs
            )
            history.insert(entry, at: 0)
            if history.count > maxHistoryItems {
                history = Array(history.prefix(maxHistoryItems))
            }
        }

        // Reset request timer when going idle
        if currentStatus == .idle {
            requestStartDate = nil
        }
    }

    // MARK: Helpers

    private func extractQuerySnippet(from message: String) -> String {
        let maxLength = 80
        let cleaned = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(cleaned.prefix(maxLength))
        return snippet.isEmpty ? "Solicitud detectada" : snippet
    }

    // MARK: Public Actions

    func clearHistory() {
        history.removeAll()
    }

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    /// Returns history entries within the last N minutes.
    func recentHistory(minutes: Int) -> [SiriEventLog] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
        return history.filter { $0.timestamp >= cutoff }
    }
}
