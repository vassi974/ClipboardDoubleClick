import Foundation

/// Traductions de l'app — se cale automatiquement sur la langue système
/// (parmi celles disponibles : français, anglais, espagnol, allemand ;
/// l'anglais sert de repli si la langue système n'est pas gérée).
enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
