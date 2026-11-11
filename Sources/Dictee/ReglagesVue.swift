import SwiftUI
import DicteeCore

/// Onglet Réglages : quatre sections titrées (Dictée, Écriture, Retours, Compte & données), une phrase sous chaque réglage.
/// Deux colonnes quand la fenêtre est assez large, une seule sinon.
struct ReglagesVue: View {
    @ObservedObject var r: ReglagesModele
    @ObservedObject var store: HistoriqueStore
    var surRevoirPriseEnMain: () -> Void = {}
    var surAutorisations: () -> Void = {}
    var surCle: () -> Void = {}
    var surDesinstaller: () -> Void = {}
    /// En dessous de cette largeur de contenu, les deux colonnes passent en une.
    static let largeurDeuxColonnes: CGFloat = 780

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if g.size.width >= Self.largeurDeuxColonnes {
                        HStack(alignment: .top, spacing: 56) {
                            VStack(alignment: .leading, spacing: 28) { dictee; ecriture; lecture; ilot }.frame(maxWidth: .infinity, alignment: .top)
                            VStack(alignment: .leading, spacing: 28) { retours; reunions; compte }.frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 28) { dictee; ecriture; lecture; ilot; retours; reunions; compte }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in r.rafraichirGlobe() }
    }

    // MARK: sections

    private var dictee: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Dictée", phrase: "Comment tu lances la dictée.", compte: nil)
            LigneReglage(libelle: "Dicter", note: "Maintiens fn, parle, relâche : le texte s\u{2019}écrit au curseur.", premiere: true) {
                Text("Maintenir"); ToucheFn()
            }
            LigneReglage(libelle: "Mains libres", note: "Deux appuis lancent la dictée, un appui la termine.") {
                Text("Deux appuis"); ToucheFn()
            }
            if r.globeAReglerEncore {
                LigneReglage(libelle: "Touche 🌐", note: "\(ToucheGlobe.phrase(valeur: r.globeValeur)). Choisissez « Ne rien faire » dans le volet Clavier.") {
                    BoutonCadre("Ouvrir le volet Clavier", action: r.ouvrirVoletClavier)
                }
            }
            LigneReglage(libelle: "Micro", note: "Automatique : le micro du Mac quand un casque Bluetooth est branché.") {
                ChoixReglage(libelle: "Micro", valeur: $r.micro, options: r.micros.map { ($0.id, $0.nom) })
            }
            LigneReglage(libelle: "Langue", note: "La langue que tu parles pendant la dictée.") {
                ChoixReglage(libelle: "Langue", valeur: $r.langue, options: [("fr", "Français"), ("en", "Anglais"), ("auto", "Automatique")])
            }
        }
    }

    private var ecriture: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Écriture", phrase: "Ce que Verbe fait du texte avant de l\u{2019}écrire.", compte: nil)
            LigneReglage(libelle: "Vitesse de transcription", note: r.phraseVitesse.isEmpty ? "Rapide : le plus rapide.\nPrécis : un peu plus lent, plus juste." : r.phraseVitesse, premiere: true) {
                ChoixReglage(libelle: "Vitesse de transcription", valeur: $r.modeleWhisper, options: ModeleWhisper.allCases.map { ($0, $0.libelle) })
            }
            LigneReglage(libelle: "Remettre au propre", note: "Ajoute la ponctuation et retire les « euh ».") {
                Interrupteur(actif: $r.remettreAuPropre, etiquette: "Remettre au propre")
            }
            LigneReglage(libelle: "Adapter le ton à l\u{2019}app", note: "Plus soigné dans Mail, plus court dans WhatsApp.") {
                Interrupteur(actif: $r.adapterLeTon, etiquette: "Adapter le ton à l\u{2019}app")
            }
            LigneReglage(libelle: "Secours", note: r.phraseSecours) {
                ChoixReglage(libelle: "Secours", valeur: $r.secoursApple, options: [(true, "Apple"), (false, "Aucun")])
            }
        }
    }

    private var lecture: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Lecture en cours", phrase: "Ce qui joue sur le Mac, dans l\u{2019}encoche.", compte: nil)
            LigneReglage(libelle: "Afficher la lecture en cours", note: "Musique et vidéos : pochette, titre, commandes. Survole l\u{2019}encoche pour la déplier.", premiere: true) {
                Interrupteur(actif: $r.afficherLaLecture, etiquette: "Afficher la lecture en cours")
            }
            LigneReglage(libelle: "Mettre en pause pendant la dictée", note: r.afficherLaLecture ? "La lecture reprend à la fin, seulement si Verbe l\u{2019}a mise en pause." : "Demande d\u{2019}afficher la lecture en cours.") {
                Interrupteur(actif: $r.pauseLecturePendantDictee, etiquette: "Mettre en pause pendant la dictée")
            }
            .opacity(r.afficherLaLecture ? 1 : 0.45)
            .disabled(!r.afficherLaLecture)
        }
    }

    private var ilot: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Îlot", phrase: "Le minuteur, les rappels et les rendez-vous dans l\u{2019}encoche.", compte: nil)
            LigneReglage(libelle: "Minuteur", note: "Depuis l\u{2019}accueil de l\u{2019}îlot (clic sur l\u{2019}encoche vide), ou en dictant « minuteur 10 minutes » quand l\u{2019}accueil est ouvert.", premiere: true) {
                Interrupteur(actif: $r.ilotMinuteur, etiquette: "Minuteur")
            }
            LigneReglage(libelle: "Son de fin du minuteur", note: "Joué quand un minuteur ou un rappel sonne ; le volume du Mac le coupe.") {
                ChoixReglage(libelle: "Son de fin du minuteur", valeur: $r.sonFinMinuteur, options: Settings.sonsDisponibles.map { ($0, $0) })
                BoutonCadre("Écouter") { Retours.sonIlot(r.sonFinMinuteur) }
            }
            LigneReglage(libelle: "Rappels", note: "Gardés sur ce Mac seulement. Ils reviennent après un redémarrage.") {
                Interrupteur(actif: $r.ilotRappels, etiquette: "Rappels")
            }
            LigneReglage(libelle: "Batterie et appareils", note: "La batterie du Mac et de tes AirPods quand l\u{2019}îlot s\u{2019}ouvre, le chargeur branché, la batterie faible, les écouteurs qui se connectent. macOS demande une fois l\u{2019}accès au Bluetooth.") {
                Interrupteur(actif: $r.ilotEnergie, etiquette: "Batterie et appareils")
            }
            LigneReglage(libelle: "Téléchargements", note: "Un fichier qui arrive dans Téléchargements, AirDrop compris : son nom, sa taille et « Ouvrir ». macOS demande une fois l\u{2019}accès au dossier.") {
                Interrupteur(actif: $r.ilotTelechargements, etiquette: "Téléchargements")
            }
            LigneReglage(libelle: "Micro coupé", note: "Le raccourci coupe le micro du Mac et le rouvre, pendant un appel par exemple. La dictée le rouvre le temps de dicter.") {
                EnregistreurRaccourci(raccourci: $r.raccourciMicro, etiquette: "Raccourci du micro coupé")
                    .opacity(r.ilotMicro ? 1 : 0.45)
                    .disabled(!r.ilotMicro)
                Interrupteur(actif: $r.ilotMicro, etiquette: "Micro coupé")
            }
            LigneReglage(libelle: "Calendrier", note: r.phraseCalendrier) {
                Interrupteur(actif: $r.ilotCalendrier, etiquette: "Calendrier")
            }
            LigneReglage(libelle: "Notifications (expérimental)", note: "Montre dans l\u{2019}encoche les notifications des autres apps, en lisant le Centre de notifications avec l\u{2019}Accessibilité déjà accordée. Peut cesser de marcher avec une mise à jour de macOS.") {
                Interrupteur(actif: $r.ilotNotifications, etiquette: "Notifications")
            }
        }
    }

    private var retours: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Retours", phrase: "Ce que tu sens et entends.", compte: nil)
            LigneReglage(libelle: "Sons", note: "Un petit son au début, au texte collé et à l\u{2019}annulation.", premiere: true) {
                Interrupteur(actif: $r.sons, etiquette: "Sons")
            }
            LigneReglage(libelle: "Vibration", note: "Se sent seulement avec un doigt posé sur le trackpad.") {
                Interrupteur(actif: $r.vibration, etiquette: "Vibration")
            }
        }
    }

    private var reunions: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Réunions", phrase: "Noter une réunion ou un appel : \u{2325}\u{2318}N.", compte: nil)
            LigneReglage(libelle: "Proposer de noter les appels", note: "Quand Zoom, Teams, FaceTime… utilise le micro. Rien ne s\u{2019}enregistre sans ton clic.", premiere: true) {
                Interrupteur(actif: $r.proposerLesAppels, etiquette: "Proposer de noter les appels")
            }
            LigneReglage(libelle: "Garder le son des réunions", note: r.garderSonReunions ? "Le son est gardé à côté de la note, sur ce Mac." : "Le son est effacé dès que la note est prête.") {
                Interrupteur(actif: $r.garderSonReunions, etiquette: "Garder le son des réunions")
            }
        }
    }

    private var compte: some View {
        let n = store.historique.entrees.count
        return VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Compte & données", phrase: "État de la connexion et de ce Mac.", compte: nil)
            LigneReglage(libelle: "Clé Groq", note: "Sert à transcrire ta voix.", premiere: true) {
                if r.cle == .absente {
                    Text("Manquante")
                    BoutonCadre("Ajouter", action: surCle)
                } else {
                    Etat(texte: "Enregistrée")
                    BoutonCadre("Modifier", action: surCle)
                }
            }
            LigneReglage(libelle: "Autorisations", note: "Micro, accessibilité, saisie au clavier.") {
                if r.autorisationsAccordees == 3 { Etat(texte: "3 sur 3") } else { Text("\(r.autorisationsAccordees) sur 3") }
                BoutonCadre("Voir", action: surAutorisations)
            }
            LigneReglage(libelle: "Ouvrir au démarrage", note: r.avis ?? "Verbe est prêt dès que le Mac s\u{2019}allume.") {
                Interrupteur(actif: .constant(r.ouvrirAuDemarrage), etiquette: "Ouvrir au démarrage") { r.choisirOuvertureAuDemarrage($0) }
            }
            LignesMiseAJour(m: r.maj)
            if r.confirmerEffacement {
                LigneReglage(libelle: "Historique", note: "Effacer les \(n) dictées ? Cela ne se récupère pas.") {
                    BoutonCadre("Effacer") { store.effacer(); r.confirmerEffacement = false }
                    BoutonCadre("Garder") { r.confirmerEffacement = false }
                }
            } else {
                LigneReglage(libelle: "Historique", note: n == 0 ? "Aucune dictée gardée sur ce Mac." : "\(n) dictée\(n > 1 ? "s" : "") gardée\(n > 1 ? "s" : "") sur ce Mac.") {
                    BoutonCadre("Effacer…") { r.confirmerEffacement = true }
                        .opacity(store.historique.estVide ? 0.4 : 1).disabled(store.historique.estVide)
                }
            }
            LigneReglage(libelle: "Garder le son des \(TestPrecision.nombreDeDictees) prochaines dictées pour un test de précision",
                         note: r.testPrecision ? "\(r.testPrecisionRestant) dictée\(r.testPrecisionRestant > 1 ? "s" : "") encore gardée\(r.testPrecisionRestant > 1 ? "s" : ""), sur ce Mac seulement. Ça s\u{2019}arrête tout seul."
                                               : "Le son reste sur ce Mac (dossier test-precision), pour comparer les modèles plus tard. Désactivé par défaut.") {
                Interrupteur(actif: $r.testPrecision, etiquette: "Test de précision")
            }
            HStack(spacing: 24) {
                LienDiscret(titre: "Revoir la prise en main", action: surRevoirPriseEnMain)
                LienDiscret(titre: "Désinstaller Verbe", action: surDesinstaller)
            }
            .padding(.top, 16)
        }
    }
}

/// « ✓ Enregistrée » : une coche et le mot, en clair.
struct Etat: View {
    var texte: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
            Text(texte)
        }
        .foregroundStyle(Palette.texte)
        .accessibilityElement(children: .combine)
    }
}

/// Lien discret en bas de colonne (texte seul, 14 pt).
struct LienDiscret: View {
    var titre: String
    var action: () -> Void
    @State private var survol = false
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: action) {
            Text(titre).font(Polices.commande(14)).foregroundStyle(survol ? Palette.texte : Palette.texte2).underline(survol, color: Palette.texte3).lineLimit(1)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
        .onHover { survol = $0 }
    }
}
