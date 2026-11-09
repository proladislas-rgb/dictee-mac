import Foundation

/// Filet de sécurité de l'écriture : après le ⌘V simulé, l'Accessibilité relit ce qu'il y a juste avant le curseur de l'app cible.
/// Cette logique pure décide si le texte est bien arrivé. Règle d'or : ne jamais conclure à un échec quand on ne peut simplement
/// pas lire (Terminal, apps sans Accessibilité) ; un échec n'est annoncé que sur une preuve.
public enum FocusObserve: Equatable, Sendable {
    /// L'app répond mais aucun élément n'a le focus (ou l'Accessibilité ne trouve aucun élément focalisé alors qu'une fenêtre existe).
    case aucun
    /// Un élément a le focus ; `role` est son rôle d'Accessibilité (AXTextField, AXButton…).
    case element(role: String?)
    /// Impossible de savoir (pas de réponse, app sans Accessibilité).
    case inconnu
}

public struct ObservationChamp: Equatable, Sendable {
    public var focus: FocusObserve
    /// Les derniers caractères lus juste avant le curseur, ou `nil` si l'app ne les expose pas.
    public var avantLeCurseur: String?
    public init(focus: FocusObserve, avantLeCurseur: String? = nil) { self.focus = focus; self.avantLeCurseur = avantLeCurseur }
}

public enum VerdictInsertion: Equatable, Sendable {
    case inseree
    case nonInseree(raison: String)
    /// On ne peut pas savoir : aucun widget.
    case indetermine

    public var estEchec: Bool { if case .nonInseree = self { return true } else { return false } }
}

public enum VerificationInsertion {
    /// Rôles qui ne peuvent jamais recevoir du texte : si le texte n'est pas relisible et que le focus est là, c'est un échec.
    public static let rolesSansTexte: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXImage", "AXStaticText", "AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem",
        "AXOutline", "AXTable", "AXRow", "AXColumn", "AXList", "AXToolbar", "AXScrollBar", "AXPopUpButton", "AXMenuButton",
        "AXTabGroup", "AXSlider", "AXProgressIndicator", "AXDisclosureTriangle", "AXSplitter", "AXWindow", "AXApplication", "AXDock", "AXDockItem",
    ]

    /// Combien de caractères de la fin du texte on cherche devant le curseur.
    public static let tailleQueue = 24

    /// Texte comparable : espaces de toute sorte réduites à une, bouts retirés, Unicode composé.
    public static func normaliser(_ s: String) -> String {
        let remplace = s.unicodeScalars.map { u -> Character in
            switch u.value {
            case 0x00A0, 0x202F, 0x2009, 0x2007, 0x2028, 0x2029, 0x09, 0x0A, 0x0D, 0xFFFC, 0x200B: return " "
            default: return Character(u)
            }
        }
        let collapse = String(remplace).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapse.precomposedStringWithCanonicalMapping
    }

    /// La fin (normalisée) du texte écrit : c'est ce qui doit se trouver juste avant le curseur.
    public static func queueAttendue(_ texte: String) -> String {
        String(normaliser(texte).suffix(tailleQueue))
    }

    /// Nombre d'unités UTF-16 à lire avant le curseur (la queue plus une marge pour les espaces et retours à la ligne).
    public static func longueurALire(_ texte: String) -> Int { queueAttendue(texte).utf16.count + 24 }

    public static func evaluer(texte: String, observation: ObservationChamp?, genre: AppKind) -> VerdictInsertion {
        guard let o = observation else { return .indetermine }
        switch o.focus {
        case .inconnu:
            return .indetermine
        case .aucun:
            return .nonInseree(raison: "aucun champ de texte actif")
        case .element(let role):
            // Terminal : la position du curseur n'est pas exposée de façon fiable, on ne conclut jamais.
            if genre == .terminal { return .indetermine }
            if let lu = o.avantLeCurseur {
                return normaliser(lu).hasSuffix(queueAttendue(texte)) ? .inseree : .nonInseree(raison: "le texte n\u{2019}apparaît pas dans le champ")
            }
            if let role, rolesSansTexte.contains(role) { return .nonInseree(raison: "le curseur n\u{2019}est pas dans un champ de texte") }
            return .indetermine
        }
    }

    /// Plusieurs lectures successives (250, 400, 650 ms…) : une seule preuve d'écriture suffit ; sinon la dernière lecture décide.
    public static func conclure(_ verdicts: [VerdictInsertion]) -> VerdictInsertion {
        if verdicts.contains(.inseree) { return .inseree }
        return verdicts.last ?? .indetermine
    }

    /// Délais (en ms après le ⌘V) des relectures.
    public static let delaisDeRelecture: [Int] = [250, 150, 250]
}
