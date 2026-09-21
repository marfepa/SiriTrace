import Foundation
import AppKit
import CoreGraphics
@preconcurrency import Combine

// MARK: - Siri App Focus Watcher

/// Monitors macOS in real time to detect when Siri or Apple Intelligence UI
/// (such as `com.apple.Siri` or `com.apple.campo`) is active in the foreground,
/// and when it gets dismissed, minimized, or loses focus.
@MainActor
final class SiriAppFocusWatcher {

    // MARK: Public

    /// Emits `true` when Siri / Apple Intelligence is frontmost or visible, and `false` otherwise.
    let isSiriFrontmost = CurrentValueSubject<Bool, Never>(false)

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false
    private var timer: Timer?

    /// Known bundle IDs for Siri UI on macOS Sonoma, Sequoia, and macOS 27.
    private let siriBundleIDs: Set<String> = [
        "com.apple.siri",
        "com.apple.campo",
        "com.apple.camporemoteservice",
        "com.apple.siri.launcher",
        "com.apple.siriuserservice",
        "com.apple.siri.directaccess"
    ]

    // MARK: Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Listen to NSWorkspace app activation/deactivation notifications
        let notifs: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]

        for notif in notifs {
            NotificationCenter.default.publisher(for: notif, object: nil)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.checkSiriPresence()
                }
                .store(in: &cancellables)
        }

        // 2. High-precision lightweight timer (120ms) for instantaneous detection of Siri overlay
        let timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.checkSiriPresence()
        }
        timer.tolerance = 0.03
        self.timer = timer

        // Immediate check
        checkSiriPresence()
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    // MARK: Evaluation

    private func checkSiriPresence() {
        let isPresent = isSiriFrontApp() || isSiriWindowVisible()

        if isPresent != isSiriFrontmost.value {
            isSiriFrontmost.send(isPresent)
        }
    }

    /// Checks if frontmost application belongs to Siri or Campo.
    private func isSiriFrontApp() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bid = (frontApp.bundleIdentifier ?? "").lowercased()
        let name = (frontApp.localizedName ?? "").lowercased()

        return siriBundleIDs.contains(bid) ||
               bid.contains(".siri") ||
               bid.contains(".campo") ||
               name == "siri" ||
               name.hasPrefix("siri ")
    }

    /// Checks if any on-screen window belongs to Siri (even as an auxiliary or overlay panel).
    private func isSiriWindowVisible() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in windowList {
            guard let ownerName = (info[kCGWindowOwnerName as String] as? String)?.lowercased() else { continue }
            if ownerName == "siri" || ownerName == "sirincservice" || ownerName.contains("campo") {
                if let bounds = info[kCGWindowBounds as String] as? [String: Any],
                   let width = bounds["Width"] as? CGFloat,
                   let height = bounds["Height"] as? CGFloat,
                   width > 60 && height > 60 {
                    return true
                }
            }
        }
        return false
    }
}

