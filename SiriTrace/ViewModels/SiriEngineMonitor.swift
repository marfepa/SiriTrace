import Foundation
import Observation
@preconcurrency import Combine

// MARK: - Siri Engine Monitor (ViewModel)

/// Central coordinator that fuses signals from `LogStreamWatcher`,
/// `NetworkProcessWatcher`, `NeuralEngineMonitor`, and `SiriAppFocusWatcher`
/// into a single observable state for the UI layer and Dynamic Island HUD.
@MainActor
@Observable
final class SiriEngineMonitor {

    // MARK: Observable State

    var currentStatus: SiriProcessingState = .idle
    var lastPrompt: String = "Esperando orden…"
    var lastResponseTimeMs: Int? = nil
    var history: [SiriEventLog] = []
    var isHUDVisible: Bool = false
    var isSiriFrontmost: Bool = false
    var chipInfo: String = "Apple Neural Engine"
    var networkInfo: String = "Sin conexión saliente"

    // MARK: Configuration

    /// Seconds of inactivity before returning to idle. Configurable from Settings.
    var idleTimeoutSeconds: TimeInterval = 15.0

    /// Automatically display the Dynamic Island when Siri is active or in the foreground.
    var autoShowDynamicIsland: Bool = true

    // MARK: Export Notification

    var lastExportNotification: String? = nil

    // MARK: Private

    @ObservationIgnored private let logWatcher = LogStreamWatcher()
    @ObservationIgnored private let networkWatcher = NetworkProcessWatcher()
    @ObservationIgnored private let aneMonitor = NeuralEngineMonitor()
    @ObservationIgnored private let focusWatcher = SiriAppFocusWatcher()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    /// Most recent signals from each subsystem (read at evaluation time).
    @ObservationIgnored private var lastNetworkStatus: NetworkDestination = .none
    @ObservationIgnored private var lastANEActive: Bool = false

    /// Timestamp of the current request start (for response time calculation).
    @ObservationIgnored private var requestStartDate: Date?

    /// Task for the idle timeout.
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    private let maxHistoryItems = 500

    // MARK: Init

    init() {
        setupSubscriptions()
        startMonitoring()
    }

    // MARK: Subscriptions

    private func setupSubscriptions() {
        // ── 1. Log events (primary signal) ──
        logWatcher.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logEvent in
                MainActor.assumeIsolated {
                    self?.handleLogEvent(logEvent)
                }
            }
            .store(in: &cancellables)

        // ── 2. Network status (secondary / confirmatory signal) ──
        networkWatcher.networkStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    self?.lastNetworkStatus = status
                }
            }
            .store(in: &cancellables)

        // ── 3. ANE activity (supplementary signal) ──
        aneMonitor.aneActivity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                MainActor.assumeIsolated {
                    self?.lastANEActive = isActive
                }
            }
            .store(in: &cancellables)

        // ── 4. Siri App Focus (Dynamic Island auto-visibility) ──
        focusWatcher.isSiriFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFrontmost in
                MainActor.assumeIsolated {
                    self?.isSiriFrontmost = isFrontmost
                    self?.updateHUDVisibility()
                }
            }
            .store(in: &cancellables)
    }

    private func startMonitoring() {
        logWatcher.startMonitoring()
        networkWatcher.startMonitoring()
        aneMonitor.startMonitoring()
        focusWatcher.startMonitoring()
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

        // Record history with full technical telemetry
        recordHistory(event: event)

        // Update Dynamic Island visibility
        updateHUDVisibility()

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
            if event.subsystem.contains("pegasus") || event.subsystem.contains("parsec") {
                networkInfo = "Conexión saliente: Búsqueda Web de Apple (Pegasus / Parsec)"
            } else {
                networkInfo = "Conexión saliente: Nube de Apple (Private Cloud Compute)"
            }
            return
        }

        // Priority 3: Local processing (default for Siri activity)
        currentStatus = .local
        chipInfo = lastANEActive
            ? "Apple Neural Engine (activo)"
            : "Apple Neural Engine"
        networkInfo = "Sin conexión saliente — todo en tu Mac"
    }

    // MARK: Dynamic Island Visibility

    func updateHUDVisibility() {
        guard autoShowDynamicIsland else { return }

        // Island appears if Siri app is in the foreground OR if request is actively processing
        let shouldShow = isSiriFrontmost || currentStatus != .idle
        if isHUDVisible != shouldShow {
            isHUDVisible = shouldShow
        }
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
        updateHUDVisibility()
    }

    // MARK: History

    private func recordHistory(event: SiriLogEvent) {
        let entry = SiriEventLog(
            timestamp: event.timestamp,
            state: currentStatus,
            querySnippet: displayableQuery(from: event),
            responseTimeMs: lastResponseTimeMs,
            subsystem: event.subsystem,
            rawMessage: event.rawMessage,
            networkDestination: lastNetworkStatus.description,
            aneActive: lastANEActive
        )

        // Avoid duplicate consecutive entries with identical raw message within 1s
        if let last = history.first,
           last.rawMessage == entry.rawMessage,
           abs(last.timestamp.timeIntervalSince(entry.timestamp)) < 1.0 {
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

        // If we already have a clean query from an earlier event in the current request, keep it
        if lastPrompt != "Esperando orden…" && lastPrompt != "Procesando solicitud…" && !lastPrompt.isEmpty {
            return lastPrompt
        }

        // Fallback: return a generic message (never show raw ObjC selectors)
        return "Procesando solicitud…"
    }

    // MARK: Public Actions

    func clearHistory() {
        history.removeAll()
        lastExportNotification = nil
    }

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    /// Exports directly to Downloads and reveals in Finder
    func exportToDownloads() {
        if let url = LogExporter.exportToDownloads(entries: history) {
            lastExportNotification = "Guardado en Descargas: \(url.lastPathComponent)"
        } else {
            lastExportNotification = "Error al exportar archivo"
        }
    }

    /// Prompts Save Panel to save at custom location
    func exportViaSavePanel() {
        LogExporter.presentSavePanel(entries: history) { [weak self] url in
            Task { @MainActor [weak self] in
                if let url {
                    self?.lastExportNotification = "Guardado: \(url.lastPathComponent)"
                }
            }
        }
    }

    func clearExportNotification() {
        lastExportNotification = nil
    }

    /// Returns history entries within the last N minutes.
    func recentHistory(minutes: Int) -> [SiriEventLog] {
        guard minutes > 0 else { return history }
        let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
        return history.filter { $0.timestamp >= cutoff }
    }
}
