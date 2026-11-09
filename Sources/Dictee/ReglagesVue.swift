import SwiftUI
import DicteeCore

/// Onglet Réglages : le strict nécessaire, en lignes de texte (planche 02).
struct ReglagesVue: View {
    @ObservedObject var r: ReglagesModele
    @ObservedObject var store: HistoriqueStore
    var surRevoirPriseEnMain: () -> Void = {}
    var surAutorisations: () -> Void = {}
    var surCle: () -> Void = {}
    var surDesinstaller: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                LigneReglage(libelle: "Dicter", note: nil) { HStack(spacing: 6) { Text("Maintenir"); ToucheFn() } }
                LigneReglage(libelle: "Mains libres", note: nil) { HStack(spacing: 6) { Text("Deux appuis"); ToucheFn() } }
                if r.globeAReglerEncore {
                    LigneReglage(libelle: "Touche 🌐", note: "\(ToucheGlobe.phrase(valeur: r.globeValeur)). Choisissez « Ne rien faire » dans le volet Clavier.") {
                        LienTexte(titre: "Ouvrir le volet Clavier", action: r.ouvrirVoletClavier)
                    }
                }
                LigneReglage(libelle: "Micro", note: "Automatique : le micro du Mac quand un casque Bluetooth est branché.") {
                    ChoixReglage(libelle: "Micro", valeur: $r.micro, options: r.micros.map { ($0.id, $0.nom) })
                }
                LigneReglage(libelle: "Langue", note: nil) {
                    ChoixReglage(libelle: "Langue", valeur: $r.langue, options: [("fr", "Français"), ("en", "Anglais"), ("auto", "Automatique")])
                }
                LigneReglage(libelle: "Remettre au propre", note: nil) { Interrupteur(actif: $r.remettreAuPropre, etiquette: "Remettre au propre") }
                LigneReglage(libelle: "Adapter le ton à l\u{2019}app", note: nil) { Interrupteur(actif: $r.adapterLeTon, etiquette: "Adapter le ton à l\u{2019}app") }
                LigneReglage(libelle: "Sons", note: "Un petit son au début, au texte collé et à l\u{2019}annulation.") { Interrupteur(actif: $r.sons, etiquette: "Sons") }
                LigneReglage(libelle: "Vibration", note: "Se sent seulement avec un doigt posé sur le trackpad.") { Interrupteur(actif: $r.vibration, etiquette: "Vibration") }
                LigneReglage(libelle: "Secours", note: r.phraseSecours) {
                    ChoixReglage(libelle: "Secours", valeur: $r.secoursApple, options: [(true, "Apple"), (false, "Aucun")])
                }
                LigneReglage(libelle: "Ouvrir au démarrage", note: r.avis) {
                    Interrupteur(actif: .constant(r.ouvrirAuDemarrage), etiquette: "Ouvrir au démarrage") { r.choisirOuvertureAuDemarrage($0) }
                }

                Rectangle().fill(Palette.filet).frame(height: 1).padding(.vertical, 10)

                LigneReglage(libelle: "Clé Groq", note: nil, hauteur: 34) {
                    HStack(spacing: 14) {
                        Text(r.cle == .absente ? "Manquante" : "Enregistrée")
                        LienTexte(titre: r.cle == .absente ? "Ajouter" : "Modifier", action: surCle)
                    }
                }
                LigneReglage(libelle: "Autorisations", note: nil, hauteur: 34) {
                    HStack(spacing: 14) {
                        Text(r.autorisationsCompletes ? "Accordées" : "À compléter")
                        LienTexte(titre: "Voir", action: surAutorisations)
                    }
                }
                LigneReglage(libelle: "Historique", note: nil, hauteur: 34) {
                    if r.confirmerEffacement {
                        HStack(spacing: 14) {
                            Text("Effacer les \(store.historique.entrees.count) dictées ?")
                            LienTexte(titre: "Effacer", fort: true) { store.effacer(); r.confirmerEffacement = false }
                            LienTexte(titre: "Garder") { r.confirmerEffacement = false }
                        }
                    } else {
                        HStack(spacing: 14) {
                            Text("\(store.historique.entrees.count) dictées")
                            LienTexte(titre: "Effacer…") { r.confirmerEffacement = true }
                                .opacity(store.historique.estVide ? 0.4 : 1).disabled(store.historique.estVide)
                        }
                    }
                }
                LigneReglage(libelle: "Prise en main", note: nil, hauteur: 34) { LienTexte(titre: "Revoir", action: surRevoirPriseEnMain) }
                LigneReglage(libelle: "Désinstaller", note: nil, hauteur: 34) { LienTexte(titre: "Désinstaller Verbe…", action: surDesinstaller) }
            }
            .padding(.vertical, 4)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in r.rafraichirGlobe() }
    }
}
