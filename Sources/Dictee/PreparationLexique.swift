import Foundation
import DicteeCore

/// Colle le lexique à la chaîne de dictée : le prompt de Whisper (mots choisis selon le contexte) et la correction « à l'oreille »
/// du texte reçu. Les deux se coupent d'un réglage (`Settings`) et ne font rien si lexique.json n'existe pas.
enum PreparationLexique {
    /// Le prompt d'un morceau : ancre de langue, le mot d'appel (premier morceau), mots.txt, mots du lexique les plus probables, fin du
    /// texte précédent.
    /// `champ` donne, au moment de l'envoi, ce que l'Accessibilité a lu (titre de la fenêtre, texte avant le curseur).
    static func promptPour(langue: String?, genre: AppKind, champ: @escaping @Sendable () -> ContexteChamp?, recents: [String]) -> @Sendable (String?) -> String {
        let motsChoisis = Dictionnaire.mots()
        let expressions = ExpressionsStore.partage.pourWhisper()
        return { texteDavant in
            let c = champ()
            let contexte = ContexteMots(genre: genre, titreFenetre: c?.titreFenetre, texteAutour: c?.precedent, recents: recents, dejaDicte: texteDavant)
            return ChoixMotsPrompt.prompt(motsChoisis: MotAppel.motsDuPrompt(motsChoisis, texteDavant: texteDavant), expressions: expressions, lexique: LexiqueStore.partage.entrees(), contexte: contexte,
                                          texteDavant: texteDavant, ancre: ChoixLangue.phraseAncre(langue: langue))
        }
    }

    /// La correction à l'oreille d'un morceau, journalisée. Le correcteur orthographique vit sur le fil principal.
    static func correcteur() -> @Sendable (String, Int) async -> String {
        return { texte, numero in
            guard let index = LexiqueStore.partage.index(motsChoisis: Dictionnaire.mots()) else { return texte }
            let resultat = await MainActor.run { CorrectionOreille.corriger(texte, index: index, estConnu: Orthographe.estConnu) }
            for c in resultat.corrections { Log.ecrire("morceau \(numero) : \(c.ligneDeJournal)") }
            return resultat.texte
        }
    }
}
