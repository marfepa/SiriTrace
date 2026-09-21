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

// MARK: - Animation State Bridge

@MainActor
@Observable
final class HUDAnimationState {
    var isExpanded: Bool = false
}

// MARK: - Floating HUD Window (Mac Dynamic Island)

/// Borderless, non-activating panel that docks directly into the hardware MacBook Notch,
/// expanding smoothly downwards with fluid spring physics when Siri is active,
/// and retracting cleanly back into the notch when dismissed.
@MainActor
final class FloatingHUDWindow: NSPanel {

    private let notchGeo: NotchGeometry
    private let animState = HUDAnimationState()

    init(monitor: SiriEngineMonitor) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let geo = NotchGeometry.current(for: screen)
        self.notchGeo = geo

        // Dynamic Island dimensions (ample width to prevent text truncation)
        let islandWidth: CGFloat = geo.hasNotch ? max(geo.notchWidth + 170, 390) : 380
        let islandHeight: CGFloat = geo.hasNotch ? (geo.notchHeight + 48) : 60

        let x = screen.frame.midX - (islandWidth / 2)
        let y = geo.hasNotch
            ? (screen.frame.maxY - islandHeight)
            : (screen.visibleFrame.maxY - islandHeight - 6)

        super.init(
            contentRect: NSRect(x: x, y: y, width: islandWidth, height: islandHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver // High floating level to stay on top of fullscreen windows & menubar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // Shadow rendered via SwiftUI shape for seamless notch integration
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let hostingView = NSHostingView(
            rootView: DynamicIslandContentView(
                monitor: monitor,
                animState: animState,
                hasNotch: geo.hasNotch,
                notchHeight: geo.notchHeight
            )
        )
        contentView = hostingView
    }

    /// Shows the Dynamic Island with an expansion spring animation from the notch
    func showIsland() {
        alphaValue = 1.0
        orderFront(nil)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.72, blendDuration: 0)) {
            animState.isExpanded = true
        }
    }

    /// Retracts and hides the Dynamic Island into the notch
    func hideIsland(completion: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0)) {
            animState.isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.orderOut(nil)
            completion?()
        }
    }
}

// MARK: - Dynamic Island Content View (SwiftUI)

private struct DynamicIslandContentView: View {
    var monitor: SiriEngineMonitor
    var animState: HUDAnimationState
    var hasNotch: Bool
    var notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Padding offset beneath physical hardware notch
            if hasNotch {
                Spacer().frame(height: max(0, notchHeight - 4))
            }

            HStack(spacing: 12) {
                // Left Wing: Animated Status Orb
                statusOrb

                // Center Column: Concise Title & Telemetry/Query
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(monitor.currentStatus.hudTitle)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        if let badge = monitor.currentStatus.hudBadge, monitor.currentStatus != .idle {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(monitor.currentStatus.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule()
                                        .fill(monitor.currentStatus.color.opacity(0.2))
                                )
                        }
                    }

                    Text(subtitleText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                // Right Wing: Latency badge or processing waveform
                rightWing
            }
            .padding(.horizontal, 16)
            .padding(.bottom, hasNotch ? 10 : 12)
            .padding(.top, hasNotch ? 4 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: hasNotch ? 0 : 20,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: hasNotch ? 0 : 20,
                style: .continuous
            )
            .fill(Color.black)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: hasNotch ? 0 : 20,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: hasNotch ? 0 : 20,
                    style: .continuous
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            )
            .shadow(
                color: .black.opacity(hasNotch ? 0.45 : 0.35),
                radius: hasNotch ? 12 : 16,
                x: 0,
                y: hasNotch ? 4 : 6
            )
        )
        // Spring Morphing animation rooted at the screen notch
        .scaleEffect(
            x: animState.isExpanded ? 1.0 : (hasNotch ? 0.75 : 0.6),
            y: animState.isExpanded ? 1.0 : 0.1,
            anchor: .top
        )
        .opacity(animState.isExpanded ? 1.0 : 0.0)
        .offset(y: animState.isExpanded ? 0 : (hasNotch ? -8 : -14))
    }

    // MARK: Subviews

    private var statusOrb: some View {
        ZStack {
            Circle()
                .fill(monitor.currentStatus.color.opacity(0.22))
                .frame(width: 28, height: 28)

            Circle()
                .strokeBorder(monitor.currentStatus.color.opacity(0.4), lineWidth: 1)
                .frame(width: 28, height: 28)

            Image(systemName: monitor.currentStatus.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(monitor.currentStatus.color)
                .symbolEffect(.pulse, isActive: monitor.currentStatus != .idle)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if let ms = monitor.lastResponseTimeMs, monitor.currentStatus != .idle {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(monitor.currentStatus.color)
                Text("\(ms) ms")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )
        } else if monitor.currentStatus != .idle {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(monitor.currentStatus.color)
                .symbolEffect(.variableColor.iterative, isActive: true)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var subtitleText: String {
        if monitor.currentStatus == .idle {
            return "Escuchando orden…"
        }
        return monitor.lastPrompt
    }
}
