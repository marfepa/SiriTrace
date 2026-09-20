import Foundation
import OSLog
@preconcurrency import Combine

// MARK: - Log Stream Watcher

/// Polls `OSLogStore` for Siri / Apple Intelligence subsystem entries.
/// Classifies events primarily by **subsystem** (not just message content)
/// and emits via a `PassthroughSubject` that does NOT retain stale values.
final class LogStreamWatcher: @unchecked Sendable {

    // MARK: Public

    /// Emits individual log events. PassthroughSubject so stale values
    /// are never retained — the ViewModel manages its own timeout.
    let eventPublisher = PassthroughSubject<SiriLogEvent, Never>()

    // MARK: Private

    private var isMonitoring = false
    private let queue = DispatchQueue(label: "com.siritrace.logwatcher", qos: .utility)

    /// Subsystems to filter in OSLog.
    private let subsystems: [String] = [
        "com.apple.siri",
        "com.apple.SiriIntelligence",
        "com.apple.intelligenceplatform",
        "com.apple.PrivateCloudCompute",
        "com.apple.assistant",
        "com.apple.AppleIntelligence",
        "com.apple.generativeexperience"
    ]

    /// How far back each poll window looks (seconds).
    private let lookbackInterval: TimeInterval = 2.0

    /// Seconds between consecutive polls.
    private let pollInterval: TimeInterval = 1.5

    /// Deduplicate: track the last N processed entry dates to avoid re-emitting.
    private var processedEntryDates = Set<Date>()
    private let maxTrackedDates = 200

    // MARK: Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        queue.async { [weak self] in
            self?.pollLoop()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
    }

    // MARK: Polling

    private func pollLoop() {
        while isMonitoring {
            autoreleasepool {
                pollOnce()
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private func pollOnce() {
        do {
            let store: OSLogStore
            do {
                store = try OSLogStore(scope: .system)
            } catch {
                store = try OSLogStore(scope: .currentProcessIdentifier)
            }

            let position = store.position(date: Date().addingTimeInterval(-lookbackInterval))
            let predicate = NSPredicate(format: "subsystem IN %@", subsystems)
            let entries = try store.getEntries(at: position, matching: predicate)

            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }

                // Deduplication: skip already-processed entries
                guard !processedEntryDates.contains(logEntry.date) else { continue }
                processedEntryDates.insert(logEntry.date)

                if let event = classifyEntry(logEntry) {
                    eventPublisher.send(event)
                }
            }

            // Prune dedup set
            if processedEntryDates.count > maxTrackedDates {
                processedEntryDates.removeAll()
            }

        } catch {
            // OSLogStore access may fail without proper entitlements; silently retry.
        }
    }

    // MARK: Classification (subsystem-first)

    private func classifyEntry(_ entry: OSLogEntryLog) -> SiriLogEvent? {
        let subsystem = entry.subsystem
        let message = entry.composedMessage
        let messageLower = message.lowercased()
        let timestamp = entry.date

        // Skip low-value debug/internal messages
        guard isRelevantMessage(messageLower) else { return nil }

        let queryText = extractQueryText(from: message)

        // ── Primary classification by subsystem ──

        // PCC subsystem → definitively Private Cloud Compute
        if subsystem == "com.apple.PrivateCloudCompute" {
            return SiriLogEvent(
                isActive: true, isLocal: false, isPCC: true, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // ── Secondary: message-content hints within Siri/Intelligence subsystems ──

        // External AI indicators (very specific patterns)
        if messageLower.contains("externalmodelprovider") ||
           messageLower.contains("thirdpartymodel") ||
           messageLower.contains("chatgpt") ||
           (messageLower.contains("external") && messageLower.contains("provider") && messageLower.contains("forward")) {
            return SiriLogEvent(
                isActive: true, isLocal: false, isPCC: false, isExternalService: true,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // PCC indicators within other subsystems
        if messageLower.contains("pccclient") ||
           messageLower.contains("privatecloudcompute") ||
           (messageLower.contains("pcc") && messageLower.contains("enqueue")) {
            return SiriLogEvent(
                isActive: true, isLocal: false, isPCC: true, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // Local inference indicators
        if messageLower.contains("localinference") ||
           messageLower.contains("ane_inference") ||
           (messageLower.contains("on-device") && messageLower.contains("infer")) ||
           (messageLower.contains("neural") && messageLower.contains("engine") && messageLower.contains("execut")) {
            return SiriLogEvent(
                isActive: true, isLocal: true, isPCC: false, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // Generic Siri activity (subsystem is Siri-related but no routing signal)
        // → default to local (most Siri actions are local)
        if subsystem.hasPrefix("com.apple.siri") ||
           subsystem.hasPrefix("com.apple.assistant") {
            return SiriLogEvent(
                isActive: true, isLocal: true, isPCC: false, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // Intelligence platform activity without specific routing → local default
        return SiriLogEvent(
            isActive: true, isLocal: true, isPCC: false, isExternalService: false,
            rawMessage: message, queryText: queryText,
            subsystem: subsystem, timestamp: timestamp
        )
    }

    // MARK: Filtering

    /// Returns `false` for low-value internal messages that shouldn't trigger state changes.
    private func isRelevantMessage(_ messageLower: String) -> Bool {
        // Skip very short messages
        if messageLower.count < 10 { return false }

        // Skip pure debug/lifecycle noise
        let noisePatterns = [
            "accessibility:",
            "vending elements",
            "elementwindow",
            "layout subviews",
            "is lower than shield",
            "connection invalidated",
            "xpc connection",
            "daemon started",
            "daemon stopped"
        ]
        for noise in noisePatterns {
            if messageLower.contains(noise) { return false }
        }

        return true
    }

    // MARK: Query Text Extraction

    /// Attempts to extract a user-facing query from the log message.
    /// Returns `nil` if the message is purely technical.
    private func extractQueryText(from message: String) -> String? {
        // Reject ObjC selectors and internal method names
        if message.hasPrefix("*-[") || message.hasPrefix("-[") || message.hasPrefix("+[") {
            return nil
        }
        if message.contains("WithFinalOptions:") || message.contains("_start") && message.contains(":") {
            return nil
        }

        // Try to find text between quotes
        if let range = message.range(of: #""([^"]+)""#, options: .regularExpression) {
            let quoted = message[range].dropFirst().dropLast()
            if quoted.count >= 3 {
                return String(quoted.prefix(80))
            }
        }

        // Check if message looks like natural language (no brackets, colons, underscores)
        let suspicious: [Character] = ["[", "]", "_"]
        let colonCount = message.filter({ $0 == ":" }).count
        let hasSuspiciousChars = message.contains(where: { suspicious.contains($0) })

        if !hasSuspiciousChars && colonCount <= 1 {
            let words = message.split(separator: " ")
            if words.count >= 3 {
                return String(message.prefix(80))
            }
        }

        return nil
    }
}
