import Foundation
import IOKit
@preconcurrency import Combine

// MARK: - Neural Engine Monitor

/// Inspects IOKit for Apple Neural Engine (ANE) service activity.
/// Reports whether the ANE appears to be actively processing workloads.
final class NeuralEngineMonitor: @unchecked Sendable {

    // MARK: Public

    let aneActivity = CurrentValueSubject<Bool, Never>(false)

    // MARK: Private

    private var isMonitoring = false
    private let queue = DispatchQueue(label: "com.siritrace.anemonitor", qos: .utility)

    /// Polling interval in seconds.
    private let pollInterval: TimeInterval = 2.0

    /// IOKit matching names to try (varies by chip generation).
    private let serviceNames: [String] = [
        "AppleNeuralEngine",
        "AppleH13ANEInterface",
        "AppleH14ANEInterface",
        "AppleH15ANEInterface",
        "AppleH16ANEInterface",
        "AppleANEInterface"
    ]

    /// Baseline request count (captured on first successful read) to compute deltas.
    private var baselineRequestCount: Int?

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
                let isActive = checkANEActivity()
                aneActivity.send(isActive)
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    // MARK: IOKit Inspection

    private func checkANEActivity() -> Bool {
        for name in serviceNames {
            if let active = queryService(named: name) {
                return active
            }
        }
        return false
    }

    private func queryService(named name: String) -> Bool? {
        guard let matchingDict = IOServiceMatching(name) else { return nil }

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var cfProperties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service, &cfProperties, kCFAllocatorDefault, 0
            ) == KERN_SUCCESS else { continue }

            guard let dict = cfProperties?.takeRetainedValue() as? [String: Any] else { continue }

            // Strategy 1: Check PerformanceStatistics for request counts.
            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                if let total = perfStats["TotalRequestCount"] as? Int {
                    if let baseline = baselineRequestCount {
                        if total > baseline {
                            baselineRequestCount = total
                            return true
                        }
                    } else {
                        baselineRequestCount = total
                    }
                }
            }

            // Strategy 2: Check IOPowerManagement current power state.
            if let powerMgmt = dict["IOPowerManagement"] as? [String: Any],
               let currentState = powerMgmt["CurrentPowerState"] as? Int,
               currentState > 1 {
                return true
            }
        }

        return nil
    }
}
