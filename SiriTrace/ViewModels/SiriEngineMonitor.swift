import Foundation
import Observation
@preconcurrency import Combine

// MARK: - Siri Engine Monitor (ViewModel)

/// Central coordinator that fuses signals from `LogStreamWatcher`,
/// `NetworkProcessWatcher` and `NeuralEngineMonitor` into a single
/// observable processing state for the UI layer.
///
/// v0.2 changes:
/// - **Idle timeout**: automatically returns to idle after N seconds of no new events.
/// - **Subsystem-first classification**: log subsystem is the primary signal; network confirms.
/// - **No stale state**: PassthroughSubject + timeout prevent state from getting "stuck".
/// - **Clean query display**: filters out ObjC selectors and internal messages.
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
    var networkInfo: String = "Sin conexión saliente"

    // MARK: Configuration

    /// Seconds of inactivity before returning to idle. Configurable from Settings.
    var idleTimeoutSeconds: TimeInterval = 15.0

    // MARK: Private

    @ObservationIgnored private let logWatcher = LogStreamWatcher()
    @ObservationIgnored private let networkWatcher = NetworkProcessWatcher()
    @ObservationIgnored private let aneMonitor = NeuralEngineMonitor()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    /// Most recent signals from each subsystem (read at evaluation time).
    @ObservationIgnored private var lastNetworkStatus: NetworkDestination = .none
    @ObservationIgnored private var lastANEActive: Bool = false

    /// Timestamp of the current request start (for response time calculation).
    @ObservationIgnored private var requestStartDate: Date?

    /// Task for the idle timeout.
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    private let maxHistoryItems = 100

    // MARK: Init

    init() {
        setupSubscriptions()
        startMonitoring()
    }

    // MARK: Subscriptions

    private func setupSubscriptions() {
        // ── Log events (primary signal) ──
        // PassthroughSubject: only fires on new events, no stale retention.
        logWatcher.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logEvent in
                MainActor.assumeIsolated {
                    self?.handleLogEvent(logEvent)
                }
            }
            .store(in: &cancellables)

        // ── Network status (secondary / confirmatory signal) ──
        networkWatcher.networkStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    self?.lastNetworkStatus = status
                }
            }
            .store(in: &cancellables)

        // ── ANE activity (supplementary signal) ──
        aneMonitor.aneActivity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                MainActor.assumeIsolated {
                    self?.lastANEActive = isActive
                }
            }
            .store(in: &cancellables)
    }

    private func startMonitoring() {
        logWatcher.startMonitoring()
        networkWatcher.startMonitoring()
        aneMonitor.startMonitoring()
    }

    // MARK: Event Handling

    private func handleLogEvent(_ event: SiriLogEvent) {
        // Start response timer on first event of a session
        if requestStartDate == nil {
            requestStartDate = event.timestamp
        }

        // Compute response time from request start
        let elapsed = Date().timeIntervalSince(requestStartDate ?? Date())
        lastResponseTimeMs = max(1, Int(elapsed * 1000))

        // Update display prompt (prefer extracted query text over raw message)
        lastPrompt = displayableQuery(from: event)

        // ── Evaluate state using log (primary) + network (secondary) ──
        evaluateState(logEvent: event)

        // Record history
        recordHistory(event: event)

        // Reset idle timer — state will return to idle after timeout
        resetIdleTimer()
    }

    // MARK: State Evaluation

    private func evaluateState(logEvent event: SiriLogEvent) {
        // Priority 1: Log says external OR network detected third-party connections
        if event.isExternalService || lastNetworkStatus == .thirdParty {
            currentStatus = .externalAI
            chipInfo = "Apple Neural Engine"
            networkInfo = "Tráfico saliente detectado: servicio externo"
            return
        }

        // Priority 2: Log says PCC OR network detected Apple cloud connections
        if event.isPCC || lastNetworkStatus == .appleCloud {
            currentStatus = .privateCloud
            chipInfo = "Apple Neural Engine"
            networkInfo = "Tráfico saliente: nube segura de Apple (cifrado E2E)"
            return
        }

        // Priority 3: Local processing (default for Siri activity)
        currentStatus = .local
        chipInfo = lastANEActive
            ? "Apple Neural Engine (activo)"
            : "Apple Neural Engine"
        networkInfo = "Sin conexión saliente — todo en tu Mac"
    }

    // MARK: Idle Timeout

    private func resetIdleTimer() {
        idleTask?.cancel()
        let timeout = idleTimeoutSeconds
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.transitionToIdle()
        }
    }

    private func transitionToIdle() {
        currentStatus = .idle
        requestStartDate = nil
        lastResponseTimeMs = nil
        chipInfo = "Apple Neural Engine"
        networkInfo = "Sin conexión saliente"
        lastPrompt = "Esperando orden…"
    }

    // MARK: History

    private func recordHistory(event: SiriLogEvent) {
        let entry = SiriEventLog(
            timestamp: event.timestamp,
            state: currentStatus,
            querySnippet: displayableQuery(from: event),
            responseTimeMs: lastResponseTimeMs
        )

        // Avoid duplicate consecutive entries with the same state and query
        if let last = history.first,
           last.state == entry.state,
           last.querySnippet == entry.querySnippet,
           abs(last.timestamp.timeIntervalSince(entry.timestamp)) < 2.0 {
            return
        }

        history.insert(entry, at: 0)
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
    }

    // MARK: Display Helpers

    /// Returns a user-friendly query string, filtering out internal messages.
    private func displayableQuery(from event: SiriLogEvent) -> String {
        // Prefer extracted query text
        if let query = event.queryText {
            return query
        }

        // Fallback: return a generic message (never show raw ObjC selectors)
        return "Procesando solicitud…"
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
        guard minutes > 0 else { return history }
        let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
        return history.filter { $0.timestamp >= cutoff }
    }
}
