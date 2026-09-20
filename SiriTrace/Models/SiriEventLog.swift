import Foundation

// MARK: - Siri Event Log Entry

/// A single recorded event in the SiriTrace history timeline.
struct SiriEventLog: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let state: SiriProcessingState
    let querySnippet: String
    let responseTimeMs: Int?

    init(
        timestamp: Date = .now,
        state: SiriProcessingState,
        querySnippet: String,
        responseTimeMs: Int? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.state = state
        self.querySnippet = querySnippet
        self.responseTimeMs = responseTimeMs
    }
}

// MARK: - Raw Log Event (internal)

/// Lightweight value emitted by `LogStreamWatcher` before state evaluation.
struct SiriLogEvent: Sendable {
    let isActive: Bool
    let isPCC: Bool
    let isExternalService: Bool
    let message: String
    let timestamp: Date
}
