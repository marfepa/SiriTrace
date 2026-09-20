import Foundation
import OSLog
@preconcurrency import Combine

// MARK: - Log Stream Watcher

/// Polls `OSLogStore` for Siri / Apple Intelligence / Pegasus / Parsec subsystem entries.
/// Accurately differentiates between:
/// 1. Local on-device execution (ASR, App Intents, local model)
/// 2. Apple Cloud / Web Search (Pegasus, Parsec, Private Cloud Compute)
/// 3. Third-party external models (ChatGPT)
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
        "com.apple.generativeexperience",
        "com.apple.generativeexperiencesruntime",
        "com.apple.generativeassistanttools",
        "com.apple.pegasuskit",
        "com.apple.parsec",
        "com.apple.parsecd",
        "com.apple.searchtoold"
    ]

    /// How far back each poll window looks (seconds).
    private let lookbackInterval: TimeInterval = 2.0

    /// Seconds between consecutive polls.
    private let pollInterval: TimeInterval = 1.5

    /// Deduplicate: track the last N processed entry dates to avoid re-emitting.
    private var processedEntryDates = Set<Date>()
    private let maxTrackedDates = 300

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

        // Filter out background database indexing noise from intelligenceplatform
        if subsystem == "com.apple.intelligenceplatform" {
            if isIntelligencePlatformNoise(messageLower) {
                return nil
            }
        }

        // Skip low-value debug/internal noise
        guard isRelevantMessage(messageLower) else { return nil }

        let queryText = extractQueryText(from: message)

        // ── 1. Cloud & Web Search Subsystems (Pegasus, Parsec, PCC) ──
        if subsystem == "com.apple.PrivateCloudCompute" ||
           subsystem == "com.apple.pegasuskit" ||
           subsystem == "com.apple.parsec" ||
           subsystem == "com.apple.parsecd" ||
           subsystem == "com.apple.searchtoold" {
            return SiriLogEvent(
                isActive: true, isLocal: false, isPCC: true, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // ── 2. Cloud & Web Search Content Patterns ──
        if messageLower.contains("sam batch search") ||
           messageLower.contains("samintelligenceflow") ||
           messageLower.contains("parsecdconnection") ||
           messageLower.contains("parsec_warmup") ||
           messageLower.contains("parsec_connection") ||
           messageLower.contains("pccclient") ||
           messageLower.contains("privatecloudcompute") ||
           messageLower.contains("pcc enqueue") ||
           messageLower.contains("websearch") {
            return SiriLogEvent(
                isActive: true, isLocal: false, isPCC: true, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // ── 3. External AI (ChatGPT / third-party providers) ──
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

        // ── 4. Local Inference Indicators ──
        if messageLower.contains("localinference") ||
           messageLower.contains("ane_inference") ||
           messageLower.contains("uod:1") ||
           (messageLower.contains("on-device") && messageLower.contains("infer")) ||
           (messageLower.contains("neural") && messageLower.contains("engine") && messageLower.contains("execut")) {
            return SiriLogEvent(
                isActive: true, isLocal: true, isPCC: false, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        // ── 5. Generic Siri Activity ──
        if subsystem.hasPrefix("com.apple.siri") ||
           subsystem.hasPrefix("com.apple.assistant") ||
           subsystem.contains("generative") {
            return SiriLogEvent(
                isActive: true, isLocal: true, isPCC: false, isExternalService: false,
                rawMessage: message, queryText: queryText,
                subsystem: subsystem, timestamp: timestamp
            )
        }

        return nil
    }

    // MARK: Noise Filtering

    /// Filters out internal SQLite/Biome view updating logs that do not represent Siri requests.
    private func isIntelligencePlatformNoise(_ messageLower: String) -> Bool {
        let dbPatterns = [
            "viewupdate",
            "sourceupdater",
            "appsrecentlyfocused",
            "itddatestamp",
            "dropping notification",
            "using target provided",
            "beginning view update",
            "ending view update",
            "view was updated",
            "no update required",
            "finished update",
            "datastream"
        ]
        for pattern in dbPatterns {
            if messageLower.contains(pattern) { return true }
        }
        return false
    }

    /// Returns `false` for low-value internal system noise.
    private func isRelevantMessage(_ messageLower: String) -> Bool {
        if messageLower.count < 10 { return false }

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
    /// Returns `nil` if the message is purely technical or database-related.
    private func extractQueryText(from message: String) -> String? {
        // Reject ObjC selectors and internal method names
        if message.hasPrefix("*-[") || message.hasPrefix("-[") || message.hasPrefix("+[") {
            return nil
        }
        if message.contains("WithFinalOptions:") || message.contains("_start") && message.contains(":") {
            return nil
        }

        // Reject database/view update strings
        let technicalPrefixes = ["ViewUpdate:", "SourceUpdater:", "Using target", "App.InFocus", "SAM:", "proxyForSAM"]
        for prefix in technicalPrefixes {
            if message.contains(prefix) { return nil }
        }

        // Try to find text between quotes
        if let range = message.range(of: #""([^"]+)""#, options: .regularExpression) {
            let quoted = message[range].dropFirst().dropLast()
            if quoted.count >= 3 && !quoted.contains(":") && !quoted.contains(".") {
                return String(quoted.prefix(80))
            }
        }

        // Check if message looks like natural language (no brackets, colons, underscores)
        let suspicious: [Character] = ["[", "]", "_", "<", ">"]
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
