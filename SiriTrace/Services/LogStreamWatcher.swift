import Foundation
import OSLog
@preconcurrency import Combine

// MARK: - Log Stream Watcher

/// Polls `OSLogStore` for Siri / Apple Intelligence subsystem entries
/// and emits `SiriLogEvent` values via a Combine publisher.
final class LogStreamWatcher: @unchecked Sendable {

    // MARK: Public

    let eventPublisher = CurrentValueSubject<SiriLogEvent?, Never>(nil)

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
            // Attempt system-wide scope first; falls back to local process scope.
            let store: OSLogStore
            do {
                store = try OSLogStore(scope: .system)
            } catch {
                store = try OSLogStore(scope: .currentProcessIdentifier)
            }

            let position = store.position(date: Date().addingTimeInterval(-lookbackInterval))

            let predicateFormat = "subsystem IN %@"
            let predicate = NSPredicate(format: predicateFormat, subsystems)

            let entries = try store.getEntries(at: position, matching: predicate)

            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                if let event = parseLogEntry(logEntry) {
                    eventPublisher.send(event)
                }
            }
        } catch {
            // OSLogStore access may fail without proper entitlements; silently retry.
        }
    }

    // MARK: Parsing

    private func parseLogEntry(_ entry: OSLogEntryLog) -> SiriLogEvent? {
        let message = entry.composedMessage.lowercased()
        let timestamp = entry.date

        // Local inference indicators
        if message.contains("localinference") ||
           (message.contains("neural") && message.contains("execut")) ||
           (message.contains("on-device") && message.contains("start")) ||
           message.contains("ane_inference_begin") {
            return SiriLogEvent(
                isActive: true, isPCC: false, isExternalService: false,
                message: entry.composedMessage, timestamp: timestamp
            )
        }

        // Private Cloud Compute indicators
        if message.contains("privatecloudcompute") ||
           (message.contains("pcc") && message.contains("request")) ||
           (message.contains("cloud") && message.contains("enqueue")) ||
           message.contains("pccclient") {
            return SiriLogEvent(
                isActive: true, isPCC: true, isExternalService: false,
                message: entry.composedMessage, timestamp: timestamp
            )
        }

        // External AI (ChatGPT, third-party) indicators
        if message.contains("externalmodel") ||
           message.contains("thirdparty") ||
           message.contains("chatgpt") ||
           (message.contains("forwarding") && message.contains("external")) ||
           message.contains("externalprovider") {
            return SiriLogEvent(
                isActive: true, isPCC: false, isExternalService: true,
                message: entry.composedMessage, timestamp: timestamp
            )
        }

        return nil
    }
}
