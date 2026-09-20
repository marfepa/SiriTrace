import SwiftUI

// MARK: - Siri Processing State

/// Represents the current routing destination of a Siri / Apple Intelligence request.
/// Uses a privacy-oriented traffic-light metaphor for non-technical users.
enum SiriProcessingState: String, Sendable, CaseIterable {
    case idle
    case local
    case privateCloud
    case externalAI

    // MARK: Icons

    var iconName: String {
        switch self {
        case .idle:         "moon.zzz.fill"
        case .local:        "lock.shield.fill"
        case .privateCloud: "cloud.fill"
        case .externalAI:   "exclamationmark.shield.fill"
        }
    }

    // MARK: Colors (privacy-oriented traffic light)

    var color: Color {
        switch self {
        case .idle:         .gray
        case .local:        .green
        case .privateCloud: .yellow
        case .externalAI:   .red
        }
    }

    // MARK: Short Labels (for menu bar and history)

    var shortLabel: String {
        switch self {
        case .idle:         "Espera"
        case .local:        "Privado"
        case .privateCloud: "Nube / Web"
        case .externalAI:   "Externo"
        }
    }

    // MARK: Friendly Labels (main UI, non-technical)

    var friendlyLabel: String {
        switch self {
        case .idle:         "Siri en espera"
        case .local:        "Privado — todo en tu Mac"
        case .privateCloud: "Nube de Apple y Búsqueda Web"
        case .externalAI:   "Servicio externo (p.ej. ChatGPT)"
        }
    }

    var friendlyDescription: String {
        switch self {
        case .idle:
            "Siri no está procesando nada ahora mismo."
        case .local:
            "Tu solicitud se procesa aquí, en tu Mac. Ningún dato sale de tu dispositivo."
        case .privateCloud:
            "Siri ha consultado internet o los servidores de Apple para responder a tu solicitud."
        case .externalAI:
            "Tu solicitud se ha reenviado a un servicio externo. Revisa la privacidad del proveedor."
        }
    }

    // MARK: Privacy Badge (traffic light)

    var privacyBadge: String {
        switch self {
        case .idle:         ""
        case .local:        "🟢 Privacidad alta"
        case .privateCloud: "🟡 Nube / Búsqueda web"
        case .externalAI:   "🔴 Revisar privacidad"
        }
    }

    /// Emoji indicator used in the history list.
    var emoji: String {
        switch self {
        case .idle:         "⚪"
        case .local:        "🟢"
        case .privateCloud: "🟡"
        case .externalAI:   "🔴"
        }
    }
}
