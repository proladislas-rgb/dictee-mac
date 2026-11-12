import AppKit
import SwiftUI

/// Ce que le champ transmet à la liste au lieu de le traiter lui-même.
enum CommandeChamp: Equatable {
    case haut, bas, entree, echap
    case ouvrirFenetre      // ⌘,
    case copier             // ⌘C quand rien n'est sélectionné dans le champ
    case voirTout           // ⌘E
    case focus              // ⌘K
}

final class ChampNS: NSTextField {
    var surRaccourci: ((NSEvent) -> Bool)?
    var prendreLeFocusAuMontage = true
    var surFocus: ((Bool) -> Void)?
    /// Barre d'espace pressée dans un champ vide (déplier la dictée choisie) ; `true` = traitée, rien n'est tapé.
    var surEspace: (() -> Bool)?
    private var moniteurEspace: Any?

    private func retirerMoniteur() {
        if let moniteurEspace { NSEvent.removeMonitor(moniteurEspace) }
        moniteurEspace = nil
    }

    deinit { if let moniteurEspace { NSEvent.removeMonitor(moniteurEspace) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        retirerMoniteur()
        if window != nil, surEspace != nil {
            moniteurEspace = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 49,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let editeur = self.currentEditor() as? NSText, self.window?.firstResponder === editeur,
                      editeur.string.isEmpty, self.surEspace?() == true else { return event }
                return nil
            }
        }
        guard window != nil, prendreLeFocusAuMontage else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let fenetre = self.window, fenetre.isKeyWindow || fenetre is NSPanel else { return }
            fenetre.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { surFocus?(true) }
        // Curseur ambre, sélection ambre : la signature visuelle du design.
        if let editeur = currentEditor() as? NSTextView {
            editeur.insertionPointColor = Palette.nsAccent
            editeur.selectedTextAttributes = [.backgroundColor: Palette.nsAccent.withAlphaComponent(0.34), .foregroundColor: NSColor.white]
        }
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if surRaccourci?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Champ de recherche sans cadre : texte SF Pro 13, curseur ambre, ↑ ↓ Entrée Échap transmis à la liste.
struct ChampRecherche: NSViewRepresentable {
    @Binding var texte: String
    var invite: String
    var taille: CGFloat = 13
    /// Change de valeur pour redonner le focus au champ (ouverture du panneau, ⌘K).
    var jetonFocus: Int = 0
    var surCommande: (CommandeChamp) -> Bool
    /// La barre d'espace, dans un champ vide, déplie la ligne choisie (fenêtre des dictées).
    var espaceDeplie = false
    /// Le champ prend le clavier dès qu'il apparaît (faux pour un second champ de la même page : « Demander »).
    var focusAuMontage = true
    /// Le champ prend ou rend le clavier (anneau de mise en avant).
    var surFocus: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinateur { Coordinateur(self) }

    func makeNSView(context: Context) -> ChampNS {
        let champ = ChampNS()
        champ.isBordered = false
        champ.drawsBackground = false
        champ.focusRingType = .none
        champ.isBezeled = false
        champ.font = .systemFont(ofSize: taille)
        champ.textColor = Palette.nsTexte
        champ.placeholderAttributedString = NSAttributedString(string: invite, attributes: [.foregroundColor: Palette.nsTexte3, .font: NSFont.systemFont(ofSize: taille)])
        champ.cell?.usesSingleLineMode = true
        champ.cell?.isScrollable = true
        champ.delegate = context.coordinator
        champ.surRaccourci = { [weak coord = context.coordinator] event in coord?.raccourci(event) ?? false }
        champ.prendreLeFocusAuMontage = focusAuMontage
        champ.surFocus = { [weak coord = context.coordinator] f in coord?.parent.surFocus?(f) }
        if espaceDeplie { champ.surEspace = { [weak coord = context.coordinator] in coord?.parent.surCommande(.voirTout) ?? false } }
        context.coordinator.champ = champ
        context.coordinator.dernierJeton = jetonFocus
        return champ
    }

    func updateNSView(_ champ: ChampNS, context: Context) {
        context.coordinator.parent = self
        if champ.stringValue != texte { champ.stringValue = texte }
        if context.coordinator.dernierJeton != jetonFocus {
            context.coordinator.dernierJeton = jetonFocus
            DispatchQueue.main.async { champ.window?.makeFirstResponder(champ) }
        }
    }

    @MainActor
    final class Coordinateur: NSObject, NSTextFieldDelegate {
        var parent: ChampRecherche
        weak var champ: ChampNS?
        var dernierJeton = 0
        init(_ parent: ChampRecherche) { self.parent = parent }

        func controlTextDidEndEditing(_ obj: Notification) { parent.surFocus?(false) }

        func controlTextDidChange(_ notification: Notification) {
            guard let champ else { return }
            if parent.texte != champ.stringValue { parent.texte = champ.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): return parent.surCommande(.haut)
            case #selector(NSResponder.moveDown(_:)): return parent.surCommande(.bas)
            case #selector(NSResponder.insertNewline(_:)): return parent.surCommande(.entree)
            case #selector(NSResponder.cancelOperation(_:)): return parent.surCommande(.echap)
            default: return false
            }
        }

        func raccourci(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown else { return false }
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard mods == .command, let touche = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch touche {
            case ",": return parent.surCommande(.ouvrirFenetre)
            case "e": return parent.surCommande(.voirTout)
            case "k": return parent.surCommande(.focus)
            case "c":
                // Dans le champ, ⌘C garde son sens habituel s'il y a du texte sélectionné ; sinon il copie la dictée choisie.
                if let editeur = champ?.currentEditor(), editeur.selectedRange.length > 0 { return false }
                return parent.surCommande(.copier)
            default: return false
            }
        }
    }
}
