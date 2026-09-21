import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Log Exporter

/// Exports `SiriEventLog` history entries to CSV format for technical auditing.
enum LogExporter {

    /// Generates a CSV file with full audit telemetry in a temporary location.
    static func exportToCSV(entries: [SiriEventLog]) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var csv = "Timestamp,EstadoClasificado,Subsistema,DestinoRed,NeuralEngineActivo,TiempoRespuestaMs,Consulta,MensajeSistemaCrudo\n"

        if entries.isEmpty {
            let nowStr = formatter.string(from: Date())
            csv += "\(nowStr),En espera,com.siritrace.monitor,Ninguna,false,0,\"Sin registros de actividad capturados aún\",\"Inicie una consulta a Siri para generar registros\"\n"
        } else {
            for entry in entries {
                let ts = formatter.string(from: entry.timestamp)
                let state = entry.state.friendlyLabel
                    .replacingOccurrences(of: "\"", with: "\"\"")
                let subsystem = entry.subsystem
                    .replacingOccurrences(of: "\"", with: "\"\"")
                let network = entry.networkDestination
                    .replacingOccurrences(of: "\"", with: "\"\"")
                let ane = entry.aneActive ? "true" : "false"
                let rt = entry.responseTimeMs.map(String.init) ?? "N/A"
                let query = entry.querySnippet
                    .replacingOccurrences(of: "\"", with: "\"\"")
                    .replacingOccurrences(of: "\n", with: " ")
                let raw = entry.rawMessage
                    .replacingOccurrences(of: "\"", with: "\"\"")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: "")

                csv += "\(ts),\"\(state)\",\"\(subsystem)\",\"\(network)\",\(ane),\(rt),\"\(query)\",\"\(raw)\"\n"
            }
        }

        let fileName = "SiriTrace_Auditoria_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Exports directly to the user's Downloads folder and reveals the file in Finder.
    @MainActor
    @discardableResult
    static func exportToDownloads(entries: [SiriEventLog]) -> URL? {
        guard let tempURL = exportToCSV(entries: entries) else { return nil }

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let destName = "SiriTrace_Auditoria_\(formatter.string(from: Date())).csv"
        let destURL = downloadsURL.appendingPathComponent(destName)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destURL)
            try? FileManager.default.removeItem(at: tempURL)

            // Reveal file in Finder
            NSWorkspace.shared.activateFileViewerSelecting([destURL])
            return destURL
        } catch {
            return nil
        }
    }

    /// Presents an NSSavePanel in front of all windows to let the user choose the destination.
    @MainActor
    static func presentSavePanel(entries: [SiriEventLog], onComplete: (@Sendable (URL?) -> Void)? = nil) {
        guard let sourceURL = exportToCSV(entries: entries) else {
            onComplete?(nil)
            return
        }

        // Activate app to bring panel to the front in LSUIElement menubar apps
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "SiriTrace_Auditoria_\(formatter.string(from: Date())).csv"
        panel.title = "Guardar Log de Auditoría SiriTrace"
        panel.prompt = "Guardar"
        panel.level = .modalPanel
        panel.canCreateDirectories = true

        let response = panel.runModal()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        if response == .OK, let destination = panel.url {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                // Optionally reveal in Finder
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                onComplete?(destination)
            } catch {
                onComplete?(nil)
            }
        } else {
            onComplete?(nil)
        }
    }
}
