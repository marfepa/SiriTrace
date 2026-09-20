import Foundation
import Darwin
@preconcurrency import Combine

// MARK: - Network Process Watcher

/// Monitors network activity of Siri-related system processes via `proc_pidinfo`.
/// Emits `true` when outbound traffic from watched processes exceeds a threshold.
final class NetworkProcessWatcher: @unchecked Sendable {

    // MARK: Public

    let hasActiveTraffic = CurrentValueSubject<Bool, Never>(false)

    // MARK: Private

    private var isMonitoring = false
    private let queue = DispatchQueue(label: "com.siritrace.networkwatcher", qos: .utility)

    /// Process names associated with Siri and Apple Intelligence.
    private let targetProcessNames: Set<String> = [
        "assistantd",
        "siriknowledged",
        "siriactionsd",
        "sirittsd",
        "generativeexperienced",
        "intelligenceplatformd",
        "siri_suggestionsd",
        "apple_intelligenced",
        "siriinferenced"
    ]

    /// Delta threshold (messages sent between polls) to flag active cloud traffic.
    private let activityThreshold: Int32 = 5

    /// Polling interval in seconds.
    private let pollInterval: TimeInterval = 1.0

    /// Previous snapshot of messages-sent per PID.
    private var previousMessagesSent: [pid_t: Int32] = [:]

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
        let pids = findTargetPIDs()
        var totalDelta: Int32 = 0

        for pid in pids {
            let current = messagesSent(for: pid)
            if let previous = previousMessagesSent[pid], current > previous {
                totalDelta += (current - previous)
            }
            previousMessagesSent[pid] = current
        }

        // Clean stale PIDs
        let pidSet = Set(pids)
        previousMessagesSent = previousMessagesSent.filter { pidSet.contains($0.key) }

        hasActiveTraffic.send(totalDelta >= activityThreshold)
    }

    // MARK: PID Discovery

    private func findTargetPIDs() -> [pid_t] {
        // Allocate buffer for all PIDs
        let bufferSize = 4096
        var pids = [pid_t](repeating: 0, count: bufferSize)
        let bytesReturned = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * bufferSize))

        guard bytesReturned > 0 else { return [] }
        let pidCount = Int(bytesReturned) / MemoryLayout<pid_t>.size

        var matching: [pid_t] = []
        matching.reserveCapacity(targetProcessNames.count)

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            pathBuffer.withUnsafeMutableBufferPointer { buf in
                let len = proc_pidpath(pid, buf.baseAddress, UInt32(MAXPATHLEN))
                if len > 0 {
                    let path = String(cString: buf.baseAddress!)
                    let name = (path as NSString).lastPathComponent
                    if targetProcessNames.contains(name) {
                        matching.append(pid)
                    }
                }
            }
        }

        return matching
    }

    // MARK: Traffic Measurement

    private func messagesSent(for pid: pid_t) -> Int32 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)

        guard result == size else { return 0 }
        return info.pti_messages_sent
    }
}
