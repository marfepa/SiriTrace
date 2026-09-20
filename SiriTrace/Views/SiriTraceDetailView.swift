import SwiftUI

// MARK: - SiriTrace Detail View (Popover)

/// Main popover displayed when clicking the menu-bar status item.
struct SiriTraceDetailView: View {
    var monitor: SiriEngineMonitor
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            statusSection
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

    // MARK: - Real-Time Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ESTADO EN TIEMPO REAL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                statusIndicator
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.currentStatus.detailLabel)
                        .font(.body.weight(.medium))
                    Text(monitor.currentStatus.detailDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                Label(monitor.chipInfo, systemImage: "cpu.fill")
                Label(monitor.networkInfo, systemImage: "network")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(monitor.currentStatus.color.opacity(0.2))
                .frame(width: 40, height: 40)

            Image(systemName: monitor.currentStatus.iconName)
                .font(.title3)
                .foregroundStyle(monitor.currentStatus.color)
                .symbolEffect(.pulse, isActive: monitor.currentStatus != .idle)
        }
    }

    // MARK: - Last Request

    private var lastRequestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ÚLTIMA SOLICITUD")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\u{201C}\(monitor.lastPrompt)\u{201D}")
                .font(.callout)
                .lineLimit(2)

            if let ms = monitor.lastResponseTimeMs {
                Label("Tiempo de respuesta: \(ms) ms", systemImage: "timer")
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
            Text("HISTORIAL RECIENTE")
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
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(recent.prefix(20)) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func historyRow(_ entry: SiriEventLog) -> some View {
        HStack(spacing: 6) {
            Text(entry.state.emoji)
                .font(.caption)

            Text(entry.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("\u{201C}\(entry.querySnippet)\u{201D}")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text("→ \(entry.state.shortLabel)")
                .font(.caption.weight(.medium))
                .foregroundStyle(entry.state.color)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                LogExporter.presentSavePanel(entries: monitor.history)
            } label: {
                Label("Exportar Log", systemImage: "square.and.arrow.up")
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
