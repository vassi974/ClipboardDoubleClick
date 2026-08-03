import Foundation

/// Une entrée de l'historique presse-papiers.
/// Le contenu complet ("body") n'est PAS gardé en mémoire en permanence :
/// il est stocké dans un fichier séparé sur disque (voir ClipboardStore),
/// seul un aperçu tronqué (une ligne) reste en mémoire pour l'affichage.
struct ClipboardHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// Aperçu d'une ligne, pour l'affichage dans le Menu. Volontairement assez
    /// long (voir `makePreview`) : c'est le champ texte (largeur de la fenêtre)
    /// qui fait la troncature visuelle réelle, pas cette chaîne — ainsi,
    /// agrandir la fenêtre révèle vraiment plus de texte au lieu de laisser
    /// juste un aperçu figé entouré de vide.
    var preview: String
    /// Nombre de caractères du texte complet (utile pour l'UI / debug).
    var characterCount: Int
    /// true si le contenu a une version enrichie (RTF) stockée sur disque.
    var hasRichText: Bool
    var pinned: Bool

    static func makePreview(from text: String, limit: Int = 600) -> String {
        // \u{FFFC} = caractère de remplacement d'objet (une image incrustée dans du
        // texte enrichi le laisse souvent ici une fois converti en texte brut).
        // On le retire, sinon la "1re ligne" de contenu réel peut être vide ou
        // réduite à ce caractère invisible, et l'aperçu n'affiche plus que "…".
        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "")

        // On cherche la 1re ligne non vide (après trim), pas juste la ligne n°1 —
        // un copié-collé qui commence par une image / un saut de ligne vide sinon
        // donne un aperçu vide.
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false)
        let firstNonBlank = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let rawLine = firstNonBlank else {
            // Tout le contenu copié était une image / vide une fois le texte retiré.
            return "[Image ou contenu sans texte]"
        }

        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let hasMoreContent = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).count > line.count

        if line.count > limit {
            let idx = line.index(line.startIndex, offsetBy: limit)
            return String(line[..<idx]) + "…"
        }
        return hasMoreContent ? line + " …" : line
    }
}

/// Réglages persistés (Menu 2).
struct AppSettings: Codable {
    var maxItemsToKeep: Int = 50          // "Nombre copie a conserver"
    var maxDaysToKeep: Int = 30           // "Nombre de jours d'historique (max 30)"
    var clearHistoryOnQuit: Bool = false  // "effacer l'historique en sortie de cession"
    var forcePlainTextOnly: Bool = false  // "Tous convertir en texte brut"
    var keepRichText: Bool = true         // "Conserver le texte enrichis"
    var excludedBundleIdentifiers: [String] = [] // apps où le double clic droit est désactivé

    static let maxDaysHardLimit = 30

    mutating func clampDays() {
        if maxDaysToKeep > AppSettings.maxDaysHardLimit {
            maxDaysToKeep = AppSettings.maxDaysHardLimit
        }
        if maxDaysToKeep < 1 {
            maxDaysToKeep = 1
        }
    }
}
