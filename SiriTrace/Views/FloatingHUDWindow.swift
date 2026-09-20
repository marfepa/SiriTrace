import AppKit
import SwiftUI

// MARK: - Floating HUD Window

/// A borderless, floating panel styled as a "Dynamic Island" that shows
/// the current Siri processing state at the top-center of the screen.
@MainActor
final class FloatingHUDWindow: NSPanel {

    init(monitor: SiriEngineMonitor) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 56),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let hostingView = NSHostingView(rootView: HUDContentView(monitor: monitor))
        contentView = hostingView

        // Position: top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 150
            let y = screenFrame.maxY - 70
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - HUD Content (SwiftUI)

/// SwiftUI content rendered inside the floating HUD panel.
private struct HUDContentView: View {
    var monitor: SiriEngineMonitor

    var body: some View {
        HStack(spacing: 12) {
            // Animated status icon
            ZStack {
                Circle()
                    .fill(monitor.currentStatus.color.opacity(0.25))
                    .frame(width: 32, height: 32)

                Image(systemName: monitor.currentStatus.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(monitor.currentStatus.color)
                    .symbolEffect(.pulse, isActive: monitor.currentStatus != .idle)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Siri — \(monitor.currentStatus.shortLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                Text(monitor.lastPrompt)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 300, height: 56)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .clipShape(Capsule())
    }
}
