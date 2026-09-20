import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Log Exporter

/// Exports `SiriEventLog` history entries to CSV format.
enum LogExporter {

    /// Generates a CSV file in a temporary location and returns its URL.
    static func exportToCSV(entries: [SiriEventLog]) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var csv = "Timestamp,Estado,Consulta,TiempoRespuestaMs\n"

        for entry in entries {
            let ts = formatter.string(from: entry.timestamp)
            let state = entry.state.shortLabel
            let query = entry.querySnippet
                .replacingOccurrences(of: "\"", with: "\"\"")  // escape quotes
                .replacingOccurrences(of: "\n", with: " ")
            let rt = entry.responseTimeMs.map(String.init) ?? "N/A"

            csv += "\(ts),\(state),\"\(query)\",\(rt)\n"
        }

        let fileName = "SiriTrace_Log_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Presents an NSSavePanel and writes the CSV to the chosen location.
    @MainActor
    static func presentSavePanel(entries: [SiriEventLog]) {
        guard let sourceURL = exportToCSV(entries: entries) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "SiriTrace_Log.csv"
        panel.title = "Exportar Log de SiriTrace"
        panel.prompt = "Guardar"

        panel.begin { response in
            defer { try? FileManager.default.removeItem(at: sourceURL) }
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.copyItem(at: sourceURL, to: destination)
        }
    }
}
