import SwiftUI

// MARK: - Siri Processing State

/// Represents the current routing destination of a Siri / Apple Intelligence request.
enum SiriProcessingState: String, Sendable, CaseIterable {
    case idle
    case local
    case privateCloud
    case externalAI

    // MARK: Visual Properties

    var iconName: String {
        switch self {
        case .idle:         "cpu"
        case .local:        "lock.shield.fill"
        case .privateCloud: "cloud.fill"
        case .externalAI:   "arrow.up.forward.app.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:         .gray
        case .local:        .green
        case .privateCloud: .blue
        case .externalAI:   .orange
        }
    }

    var shortLabel: String {
        switch self {
        case .idle:         "Siri"
        case .local:        "Local"
        case .privateCloud: "PCC"
        case .externalAI:   "Ext-AI"
        }
    }

    var detailLabel: String {
        switch self {
        case .idle:         "En reposo"
        case .local:        "Procesamiento 100 % Local"
        case .privateCloud: "Private Cloud Compute"
        case .externalAI:   "Modelo Externo (IA de terceros)"
        }
    }

    var detailDescription: String {
        switch self {
        case .idle:
            "Siri no está procesando ninguna solicitud."
        case .local:
            "La solicitud se procesa en el Neural Engine del dispositivo. Ningún dato sale del equipo."
        case .privateCloud:
            "La solicitud se envía a los servidores de Apple Private Cloud Compute con cifrado de extremo a extremo."
        case .externalAI:
            "La solicitud se reenvía a un proveedor externo de IA (p. ej., ChatGPT)."
        }
    }

    /// Emoji indicator used in the history list.
    var emoji: String {
        switch self {
        case .idle:         "⚪"
        case .local:        "🟢"
        case .privateCloud: "☁️"
        case .externalAI:   "🟧"
        }
    }
}
