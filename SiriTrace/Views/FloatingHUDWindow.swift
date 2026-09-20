import AppKit
import SwiftUI

// MARK: - Notch Geometry Helper

struct NotchGeometry {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static func current(for screen: NSScreen) -> NotchGeometry {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            let height = max(32, screen.frame.maxY - screen.visibleFrame.maxY)
            if width > 50 {
                return NotchGeometry(hasNotch: true, notchWidth: width, notchHeight: height)
            }
        }
        return NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
    }
}

// MARK: - Floating HUD Window (Mac Dynamic Island)

/// Borderless, non-activating panel that docks directly into the hardware MacBook Notch,
/// expanding smoothly downwards when Siri is active, and retracting when dismissed.
@MainActor
final class FloatingHUDWindow: NSPanel {

    private let notchGeo: NotchGeometry

    init(monitor: SiriEngineMonitor) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let geo = NotchGeometry.current(for: screen)
        self.notchGeo = geo

        // Dynamic Island dimensions
        let islandWidth: CGFloat = geo.hasNotch ? max(geo.notchWidth + 110, 310) : 310
        let islandHeight: CGFloat = geo.hasNotch ? (geo.notchHeight + 42) : 58

        let x = screen.frame.midX - (islandWidth / 2)
        let y = geo.hasNotch
            ? (screen.frame.maxY - islandHeight)
            : (screen.visibleFrame.maxY - islandHeight - 8)

        super.init(
            contentRect: NSRect(x: x, y: y, width: islandWidth, height: islandHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver // High floating level to stay on top of fullscreen windows & menubar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = !geo.hasNotch // Hardware notch creates its own optical silhouette
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let hostingView = NSHostingView(
            rootView: DynamicIslandContentView(monitor: monitor, hasNotch: geo.hasNotch, notchHeight: geo.notchHeight)
        )
        contentView = hostingView
    }

    /// Shows the Dynamic Island with an expansion animation
    func showIsland() {
        alphaValue = 0.0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }
    }

    /// Retracts and hides the Dynamic Island
    func hideIsland(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}

// MARK: - Dynamic Island Shape

/// Custom shape that seamlessly attaches to the top notch with rounded bottom corners.
struct NotchConnectedShape: Shape {
    var cornerRadius: CGFloat = 20
    var hasNotch: Bool

    func path(in rect: CGRect) -> Path {
        if hasNotch {
            var path = Path()
            // Top-left at the very top edge of the screen
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            // Top edge touching hardware bezel
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            // Down to bottom-right corner
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            // Rounded bottom-right
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            // Bottom edge
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            // Rounded bottom-left
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            // Back up to top-left
            path.closeSubpath()
            return path
        } else {
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        }
    }
}

// MARK: - Dynamic Island Content View (SwiftUI)

private struct DynamicIslandContentView: View {
    var monitor: SiriEngineMonitor
    var hasNotch: Bool
    var notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Padding offset if hugging physical notch
            if hasNotch {
                Spacer().frame(height: max(0, notchHeight - 6))
            }

            HStack(spacing: 12) {
                // Left Wing: Animated Status Orb
                statusOrb

                // Center Island: Title & Telemetry
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(islandTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)

                        if !monitor.currentStatus.privacyBadge.isEmpty && monitor.currentStatus != .idle {
                            Text(monitor.currentStatus.emoji)
                                .font(.system(size: 10))
                        }
                    }

                    Text(islandSubtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                // Right Wing: Response time badge or mode indicator
                if let ms = monitor.lastResponseTimeMs, monitor.currentStatus != .idle {
                    Text(ms.humanReadableTime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                } else if monitor.currentStatus == .idle {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, hasNotch ? 8 : 10)
            .padding(.top, hasNotch ? 2 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            NotchConnectedShape(cornerRadius: 18, hasNotch: hasNotch)
                .fill(Color.black)
                .overlay(
                    NotchConnectedShape(cornerRadius: 18, hasNotch: hasNotch)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }

    private var statusOrb: some View {
        ZStack {
            Circle()
                .fill(monitor.currentStatus.color.opacity(0.3))
                .frame(width: 28, height: 28)

            Image(systemName: monitor.currentStatus.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(monitor.currentStatus.color)
                .symbolEffect(.pulse, isActive: monitor.currentStatus != .idle)
        }
    }

    private var islandTitle: String {
        if monitor.currentStatus == .idle {
            return "Siri listo"
        }
        return monitor.currentStatus.friendlyLabel
    }

    private var islandSubtitle: String {
        if monitor.currentStatus == .idle {
            return "Escuchando orden…"
        }
        return monitor.lastPrompt
    }
}
