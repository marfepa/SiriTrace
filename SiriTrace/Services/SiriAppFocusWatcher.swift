import Foundation
import AppKit
@preconcurrency import Combine

// MARK: - Siri App Focus Watcher

/// Monitors macOS in real time to detect when Siri or Apple Intelligence UI
/// (such as `com.apple.Siri` or `com.apple.campo`) is active in the foreground,
/// and when it gets dismissed, minimized, or loses focus.
@MainActor
final class SiriAppFocusWatcher {

    // MARK: Public

    /// Emits `true` when Siri / Apple Intelligence is frontmost, and `false` otherwise.
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
        "com.apple.siriuserservice"
    ]

    // MARK: Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Listen to NSWorkspace app activation/deactivation notifications
        NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFrontmostApp()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWorkspace.didDeactivateApplicationNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFrontmostApp()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWorkspace.didHideApplicationNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFrontmostApp()
            }
            .store(in: &cancellables)

        // 2. Scheduled timer on MainRunLoop for rapid tracking
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkFrontmostApp()
        }
        timer.tolerance = 0.1
        self.timer = timer

        // Immediate check
        checkFrontmostApp()
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    // MARK: Evaluation

    private func checkFrontmostApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            if isSiriFrontmost.value {
                isSiriFrontmost.send(false)
            }
            return
        }

        let bid = (frontApp.bundleIdentifier ?? "").lowercased()
        let name = (frontApp.localizedName ?? "").lowercased()

        let isSiri = siriBundleIDs.contains(bid) ||
                     bid.contains(".siri") ||
                     bid.contains(".campo") ||
                     name == "siri" ||
                     name.hasPrefix("siri ")

        if isSiri != isSiriFrontmost.value {
            isSiriFrontmost.send(isSiri)
        }
    }
}
