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

/// Lightweight value emitted by `LogStreamWatcher` after parsing an OSLog entry.
/// Includes subsystem-based classification and optional extracted query text.
struct SiriLogEvent: Sendable {
    let isActive: Bool
    let isLocal: Bool
    let isPCC: Bool
    let isExternalService: Bool
    let rawMessage: String
    let queryText: String?
    let subsystem: String
    let timestamp: Date
}

// MARK: - Network Destination

/// Classification of network destinations detected by `NetworkProcessWatcher`.
enum NetworkDestination: Sendable {
    /// No active TCP connections from Siri processes.
    case none
    /// Connections to Apple IP ranges (17.0.0.0/8).
    case appleCloud
    /// Connections to non-Apple, non-local IPs.
    case thirdParty
    /// Sockets detected but unable to determine destination (SIP, permissions).
    case unknown
}

// MARK: - Human-Readable Time

extension Int {
    /// Formats milliseconds into a user-friendly string.
    var humanReadableTime: String {
        if self < 1000 {
            return "< 1 s"
        } else if self < 10_000 {
            let seconds = Double(self) / 1000.0
            return String(format: "%.1f s", seconds)
        } else {
            let seconds = self / 1000
            return "\(seconds) s"
        }
    }
}
