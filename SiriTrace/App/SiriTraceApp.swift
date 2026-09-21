import SwiftUI

// MARK: - SiriTrace App

@main
struct SiriTraceApp: App {
    @State private var monitor = SiriEngineMonitor()
    @NSApplicationDelegateAdaptor(SiriTraceAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SiriTraceDetailView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: monitor.currentStatus.iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(monitor.currentStatus.color)
                Text(monitor.currentStatus.shortLabel)
                    .font(.caption.monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: monitor.isHUDVisible) { _, isVisible in
            if isVisible {
                appDelegate.showHUD(monitor: monitor)
            } else {
                appDelegate.hideHUD()
            }
        }
    }
}

// MARK: - App Delegate

/// Manages the Dynamic Island HUD window lifecycle.
@MainActor
final class SiriTraceAppDelegate: NSObject, NSApplicationDelegate {
    private var hudWindow: FloatingHUDWindow?

    func showHUD(monitor: SiriEngineMonitor) {
        if hudWindow == nil {
            hudWindow = FloatingHUDWindow(monitor: monitor)
        }
        hudWindow?.showIsland()
    }

    func hideHUD() {
        hudWindow?.hideIsland { [weak self] in
            self?.hudWindow = nil
        }
    }
}
