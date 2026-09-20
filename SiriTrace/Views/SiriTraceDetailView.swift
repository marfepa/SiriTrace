import SwiftUI

// MARK: - SiriTrace Detail View (Popover)

/// Main popover displayed when clicking the menu-bar status item.
/// Designed for non-technical users with privacy-oriented traffic-light metaphor.
struct SiriTraceDetailView: View {
    var monitor: SiriEngineMonitor
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            privacyStatusSection
            Divider()
            lastRequestSection
            Divider()
            historySection
            Divider()
            footerSection
        }
        .frame(width: 400)
        .sheet(isPresented: $showSettings) {
            SettingsView(monitor: monitor)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Label("SiriTrace", systemImage: "waveform.circle.fill")
                .font(.headline)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Ajustes")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Privacy Status (main section)

    private var privacyStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Dónde se procesa tu solicitud?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Main status card
            HStack(spacing: 12) {
                statusIndicator
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.currentStatus.friendlyLabel)
                        .font(.body.weight(.semibold))

                    Text(monitor.currentStatus.friendlyDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(monitor.currentStatus.color.opacity(0.08))
            )

            // Privacy badge
            if !monitor.currentStatus.privacyBadge.isEmpty {
                Text(monitor.currentStatus.privacyBadge)
                    .font(.caption.weight(.medium))
            }

            // Technical details (collapsed by default feel — small text)
            Group {
                Label(monitor.chipInfo, systemImage: "cpu.fill")
                Label(monitor.networkInfo, systemImage: "network")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(monitor.currentStatus.color.opacity(0.2))
                .frame(width: 44, height: 44)

            Image(systemName: monitor.currentStatus.iconName)
                .font(.title2)
                .foregroundStyle(monitor.currentStatus.color)
                .symbolEffect(.pulse, isActive: monitor.currentStatus != .idle)
        }
    }

    // MARK: - Last Request

    private var lastRequestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Última solicitud")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(monitor.lastPrompt)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(
                    monitor.lastPrompt == "Esperando orden…"
                        ? .secondary
                        : .primary
                )

            if let ms = monitor.lastResponseTimeMs {
                Label(
                    "Tiempo: \(ms.humanReadableTime)",
                    systemImage: "timer"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actividad reciente")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let recent = monitor.recentHistory(minutes: 5)

            if recent.isEmpty {
                Text("Sin actividad en los últimos 5 minutos.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(recent.prefix(20)) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func historyRow(_ entry: SiriEventLog) -> some View {
        HStack(spacing: 6) {
            Text(entry.state.emoji)
                .font(.caption2)

            Text(entry.timestamp, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(entry.querySnippet)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(entry.state.shortLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(entry.state.color)
        }
        .help(entry.state.friendlyDescription)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                LogExporter.presentSavePanel(entries: monitor.history)
            } label: {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Button {
                monitor.toggleHUD()
            } label: {
                Label(
                    monitor.isHUDVisible ? "Ocultar HUD" : "Mostrar HUD",
                    systemImage: monitor.isHUDVisible
                        ? "rectangle.on.rectangle.slash"
                        : "rectangle.on.rectangle"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
