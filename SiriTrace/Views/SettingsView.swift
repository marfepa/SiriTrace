import SwiftUI

// MARK: - Settings View

/// Settings panel accessible from the popover header.
struct SettingsView: View {
    var monitor: SiriEngineMonitor
    @Environment(\.dismiss) private var dismiss

    @AppStorage("pollingInterval") private var pollingInterval: Double = 1.5
    @AppStorage("showHUDOnStateChange") private var showHUDOnStateChange = true
    @AppStorage("historyRetentionMinutes") private var historyRetentionMinutes: Int = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(.secondary)
                Text("Ajustes de SiriTrace")
                    .font(.title2.weight(.bold))
            }

            // Monitor settings
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Intervalo de sondeo:")
                        Spacer()
                        Slider(value: $pollingInterval, in: 0.5...5.0, step: 0.5)
                            .frame(width: 160)
                        Text("\(pollingInterval, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack {
                        Text("Retención de historial:")
                        Spacer()
                        Picker("", selection: $historyRetentionMinutes) {
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("1 hora").tag(60)
                            Text("Sin límite").tag(0)
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
                .padding(4)
            } label: {
                Label("Monitor", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }

            // HUD settings
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Mostrar HUD automáticamente al cambiar estado",
                           isOn: $showHUDOnStateChange)

                    Button {
                        monitor.toggleHUD()
                    } label: {
                        Label("Mostrar / Ocultar HUD ahora", systemImage: "rectangle.on.rectangle")
                    }
                }
                .padding(4)
            } label: {
                Label("HUD Flotante", systemImage: "macwindow.on.rectangle")
            }

            // Data settings
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        LogExporter.presentSavePanel(entries: monitor.history)
                    } label: {
                        Label("Exportar historial como CSV", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        monitor.clearHistory()
                    } label: {
                        Label("Limpiar historial", systemImage: "trash")
                    }
                }
                .padding(4)
            } label: {
                Label("Datos", systemImage: "externaldrive.fill")
            }

            Spacer()

            // Close
            HStack {
                Text("SiriTrace v0.1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cerrar") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
        }
        .padding()
        .frame(width: 440, height: 420)
    }
}
