import SwiftUI

// MARK: - Settings View

/// Settings panel accessible from the popover header.
struct SettingsView: View {
    var monitor: SiriEngineMonitor
    @Environment(\.dismiss) private var dismiss

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
                        Text("Volver a reposo tras:")
                            .help("Segundos de inactividad antes de que el estado vuelva a 'En espera'.")
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { monitor.idleTimeoutSeconds },
                                set: { monitor.idleTimeoutSeconds = $0 }
                            ),
                            in: 5...60,
                            step: 5
                        )
                        .frame(width: 150)
                        Text("\(Int(monitor.idleTimeoutSeconds)) s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }

                    HStack {
                        Text("Conservar historial:")
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

            // HUD / Dynamic Island settings
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Desplegar Dynamic Island automáticamente con Siri",
                        isOn: Binding(
                            get: { monitor.autoShowDynamicIsland },
                            set: {
                                monitor.autoShowDynamicIsland = $0
                                monitor.updateHUDVisibility()
                            }
                        )
                    )
                    .help("Muestra la Dynamic Island en el Notch cuando la ventana de Siri esté activa o procesando una solicitud.")

                    Button {
                        monitor.toggleHUD()
                    } label: {
                        Label(
                            monitor.isHUDVisible ? "Ocultar Dynamic Island ahora" : "Mostrar Dynamic Island ahora",
                            systemImage: "macwindow.on.rectangle"
                        )
                    }
                }
                .padding(4)
            } label: {
                Label("Dynamic Island (Notch de Mac)", systemImage: "macwindow.badge.plus")
            }

            // Data settings
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if let note = monitor.lastExportNotification {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(note)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }

                    Button {
                        monitor.exportToDownloads()
                    } label: {
                        Label("Exportar a Descargas y abrir Finder", systemImage: "arrow.down.circle.fill")
                    }

                    Button {
                        monitor.exportViaSavePanel()
                    } label: {
                        Label("Elegir ubicación para guardar (CSV)...", systemImage: "folder.fill")
                    }

                    Button(role: .destructive) {
                        monitor.clearHistory()
                    } label: {
                        Label("Limpiar historial", systemImage: "trash")
                    }
                }
                .padding(4)
            } label: {
                Label("Auditoría y datos", systemImage: "externaldrive.fill")
            }

            // Privacy legend
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    legendRow(emoji: "🟢", label: "Privado", desc: "Todo se procesa en tu Mac")
                    legendRow(emoji: "🟡", label: "Nube Apple", desc: "Nube segura con cifrado E2E")
                    legendRow(emoji: "🔴", label: "Externo", desc: "Servicio de terceros (ej. ChatGPT)")
                }
                .padding(4)
            } label: {
                Label("Significado de los colores", systemImage: "circle.lefthalf.filled")
            }

            Spacer()

            // Close
            HStack {
                Text("SiriTrace v0.2.0")
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
        .frame(width: 460, height: 520)
    }

    private func legendRow(emoji: String, label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
                .font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.medium))
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
