import AppKit
import SwiftUI
import DicteeCore

// MARK: - pièces des réglages

/// Un groupe de réglages (maquette, étape 11) : son nom en gris, puis ses lignes dans une carte arrondie.
struct GroupeReglages<Contenu: View>: View {
    var titre: String
    @ViewBuilder var contenu: Contenu
    @Environment(\.colorScheme) private var schema
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(TonsBureau.encre3).padding(.leading, 12)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { contenu }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TonsBureau.carte))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(schema == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: Color(red: 70/255, green: 45/255, blue: 20/255).opacity(schema == .dark ? 0 : 0.08), radius: 8, y: 4)
        }
    }
}

/// Une ligne de groupe : le libellé (et un détail gris après « · »), une phrase dessous si besoin, le contrôle ou l'état à droite.
/// Avec `action`, toute la ligne s'ouvre d'un clic et finit par un chevron. Un filet fin la sépare de la précédente.
struct LigneGroupe<Valeur: View>: View {
    var libelle: String
    var detail: String? = nil
    var note: String? = nil
    var premiere = false
    var action: (() -> Void)? = nil
    @ViewBuilder var valeur: Valeur

    var body: some View {
        Group {
            if let action {
                Button(action: action) { contenu(chevron: true).contentShape(Rectangle()) }.buttonStyle(.plain)
            } else {
                contenu(chevron: false)
            }
        }
        .overlay(alignment: .top) { if !premiere { Rectangle().fill(TonsBureau.filet).frame(height: 1).padding(.leading, 14) } }
    }

    private func contenu(chevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(libelle).foregroundStyle(TonsBureau.encre))\(Text(detail.map { " \u{00B7} \($0)" } ?? "").font(.system(size: 12)).foregroundStyle(TonsBureau.encre3))")
                    .font(.system(size: 13.5))
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note).font(.system(size: 12)).foregroundStyle(TonsBureau.encre2).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                valeur
                if chevron { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(TonsBureau.encre3) }
            }
            .font(.system(size: 13)).foregroundStyle(TonsBureau.encre2)
            .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, note == nil ? 9 : 10)
        .frame(minHeight: 40)
    }
}
extension LigneGroupe where Valeur == EmptyView {
    init(libelle: String, detail: String? = nil, note: String? = nil, premiere: Bool = false, action: (() -> Void)? = nil) {
        self.init(libelle: libelle, detail: detail, note: note, premiere: premiere, action: action) { EmptyView() }
    }
}

/// « ✓ Enregistrée » en vert : un état bon, dit en clair.
struct EtatVert: View {
    var texte: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
            Text(texte).fontWeight(.semibold)
        }
        .foregroundStyle(TonsBureau.vert)
        .accessibilityElement(children: .combine)
    }
}

/// Un lien bleu dans une ligne (« Modifier », « Voir », « Ouvrir le volet Clavier »).
struct LienBleu: View {
    var titre: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(titre).font(.system(size: 13, weight: .medium)).foregroundStyle(TonsBureau.bleu).contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

/// « fn », en touche du clavier.
struct ToucheBureau: View {
    var texte = "fn"
    var body: some View {
        Text(texte).font(.system(size: 10.5, weight: .bold)).foregroundStyle(TonsBureau.encre)
            .padding(.horizontal, 5).frame(minWidth: 22, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(TonsBureau.carte).shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

// MARK: - la page

/// Réglages (maquette, étape 11) : cinq groupes, grands et lisibles. Ce qui demande plus de place s'ouvre dans une sous-page
/// (Dictée, Mots, Ce qu'elle montre, Confidentialité), d'un clic sur sa ligne.
struct ReglagesBureauVue: View {
    @ObservedObject var r: ReglagesModele
    @ObservedObject var store: HistoriqueStore
    @ObservedObject var mots: MotsModele
    @ObservedObject var apparence: ApparenceFenetre
    var actions: ActionsBureau
    var ouvrir: (SousPageBureau) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EntetePage(petit: "Peu de réglages, chacun dit ce qu\u{2019}il fait", titre: "Réglages") { aPropos }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) { dictee; lucarne }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 14) { apparenceGroupe; confidentialite; compte }.frame(maxWidth: .infinity)
                    }
                    liens
                }
                .padding(.bottom, TonsBureau.margeBas)
            }
        }
        .padding(.horizontal, TonsBureau.margeH)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in r.rafraichirGlobe() }
    }

    private var aPropos: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconeApp.image()).resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Verbe \(r.maj.versionActuelle)").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(TonsBureau.encre)
                Text(r.maj.disponible == nil ? "Tout reste sur ce Mac" : "Une mise à jour est prête").font(.system(size: 12)).foregroundStyle(TonsBureau.encre3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dictee: some View {
        GroupeReglages(titre: "Dictée") {
            LigneGroupe(libelle: "Dicter", premiere: true) { Text("Tenir"); ToucheBureau() }
            LigneGroupe(libelle: "Mains libres", detail: "un appui l\u{2019}arrête") { Text("Deux appuis"); ToucheBureau() }
            LigneGroupe(libelle: "Remettre au propre", detail: "ponctuation, «\u{202F}euh\u{202F}»") { Interrupteur(actif: $r.remettreAuPropre, etiquette: "Remettre au propre") }
            if r.globeAReglerEncore {
                LigneGroupe(libelle: "Touche 🌐", note: "\(ToucheGlobe.phrase(valeur: r.globeValeur)). Choisis «\u{202F}Ne rien faire\u{202F}».") {
                    LienBleu(titre: "Ouvrir le volet Clavier", action: r.ouvrirVoletClavier)
                }
            }
            LigneGroupe(libelle: "Micro, langue, vitesse", action: { ouvrir(.dictee) }) { Text(r.micros.first { $0.id == r.micro }?.nom ?? "Automatique").lineLimit(1) }
            LigneGroupe(libelle: "Mots et raccourcis", action: { ouvrir(.mots) }) {
                if mots.propositions.enAttente.count > 0 {
                    Text("\(mots.propositions.enAttente.count) à valider").foregroundStyle(TonsBureau.orange)
                } else {
                    Text("\(mots.mots.count + mots.raccourcis.count)")
                }
            }
        }
    }

    private var lucarne: some View {
        let interrupteurs = [r.afficherLaLecture, r.ilotMinuteur, r.ilotRappels, r.ilotCalendrier, r.ilotEnergie, r.ilotTelechargements,
                             r.ilotEtagere, r.ilotMicro, r.ilotNiveaux, r.ilotClaude, r.ilotNotifications]
        return GroupeReglages(titre: "L\u{2019}encoche") {
            LigneGroupe(libelle: "Ce qu\u{2019}elle montre", premiere: true, action: { ouvrir(.lucarne) }) { Text("\(interrupteurs.filter { $0 }.count) sur \(interrupteurs.count)") }
            LigneGroupe(libelle: "Claude Code", detail: r.claudeBranche ? "branché" : nil) {
                if r.claudeBranche { EtatVert(texte: "Branché") }
                else { LienBleu(titre: "Brancher", action: r.brancherClaude).opacity(r.ilotClaude ? 1 : 0.4).disabled(!r.ilotClaude) }
            }
            LigneGroupe(libelle: "Son de fin du minuteur") {
                ChoixMenu(libelle: "Son de fin du minuteur", valeur: $r.sonFinMinuteur, options: Settings.sonsDisponibles.map { ($0, $0) })
                LienBleu(titre: "Écouter") { Retours.sonIlot(r.sonFinMinuteur) }
            }
        }
    }

    private var apparenceGroupe: some View {
        GroupeReglages(titre: "Apparence") {
            HStack(spacing: 14) {
                ForEach(ApparenceBureau.allCases, id: \.self) { a in
                    Button { withAnimation(.easeInOut(duration: 0.3)) { apparence.choix = a } } label: {
                        VStack(spacing: 6) {
                            VignetteApparence(apparence: a)
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(apparence.choix == a ? TonsBureau.bleu : Color.primary.opacity(0.15),
                                                                                                          lineWidth: apparence.choix == a ? 2.5 : 0.5).padding(apparence.choix == a ? -2 : 0))
                            Text(a.libelle).font(.system(size: 12.5, weight: apparence.choix == a ? .semibold : .medium))
                                .foregroundStyle(apparence.choix == a ? TonsBureau.encre : TonsBureau.encre2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apparence \(a.libelle)")
                    .accessibilityAddTraits(apparence.choix == a ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }

    private var confidentialite: some View {
        GroupeReglages(titre: "Confidentialité") {
            LigneGroupe(libelle: "Tout reste sur ce Mac, sauf ta voix, envoyée à Groq quand tu tiens fn", premiere: true, action: { ouvrir(.confidentialite) })
        }
    }

    private var compte: some View {
        GroupeReglages(titre: "Compte") {
            LigneGroupe(libelle: "Clé Groq", premiere: true) {
                if r.cle == .absente { Text("Manquante").foregroundStyle(TonsBureau.orange); LienBleu(titre: "Ajouter", action: actions.cle) }
                else { EtatVert(texte: "Enregistrée"); LienBleu(titre: "Modifier", action: actions.cle) }
            }
            LigneGroupe(libelle: r.ligneGroq, note: r.noteGroq) {
                if let g = r.groq, g.niveau != .ok {
                    Image(systemName: g.niveau == .epuise ? "pause.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(TonsBureau.orange)
                        .accessibilityLabel(g.niveau == .epuise ? "En pause" : "Bientôt à la limite")
                }
            }
            LigneGroupe(libelle: "Autorisations", detail: "micro, accessibilité, clavier") {
                if r.autorisationsAccordees == 3 { EtatVert(texte: "3 sur 3") } else { Text("\(r.autorisationsAccordees) sur 3").foregroundStyle(TonsBureau.orange) }
                LienBleu(titre: "Voir", action: actions.autorisations)
            }
            LigneGroupe(libelle: "Ouvrir au démarrage", note: r.avis) {
                Interrupteur(actif: .constant(r.ouvrirAuDemarrage), etiquette: "Ouvrir au démarrage") { r.choisirOuvertureAuDemarrage($0) }
            }
            LignesMiseAJour(m: r.maj)
        }
    }

    private var liens: some View {
        HStack(spacing: 22) {
            LienBleu(titre: "Revoir la prise en main", action: actions.revoirPriseEnMain)
            LienBleu(titre: "Ouvrir le journal") { r.ouvrirJournal() }
            Spacer()
            LienBleu(titre: "Désinstaller Verbe", action: actions.desinstaller)
            LienBleu(titre: "Quitter Verbe") { r.quitter() }
        }
        .padding(.horizontal, 12)
    }
}

/// La petite fenêtre dessinée de chaque apparence (claire, sombre, moitié-moitié).
struct VignetteApparence: View {
    var apparence: ApparenceBureau
    var body: some View {
        ZStack {
            switch apparence {
            case .clair: fenetre(sombre: false)
            case .sombre: fenetre(sombre: true)
            case .automatique:
                fenetre(sombre: false)
                fenetre(sombre: true).mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
        .frame(width: 76, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
    private func fenetre(sombre: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color(hex: sombre ? 0x1C1C1E : 0xF8F5F0)
            Capsule().fill(Color(hex: sombre ? 0x3A3A3D : 0xFFFFFF)).frame(height: 6).padding(.horizontal, 8).padding(.top, 9)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: sombre ? 0x2C2C2E : 0xFFFFFF)).frame(width: 26)
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: sombre ? 0x2C2C2E : 0xFFFFFF))
            }
            .frame(height: 18).padding(.horizontal, 8).padding(.top, 20)
        }
    }
}

/// Un choix dans un vrai menu du système (« Glass ⌄ »), en texte bleu discret.
struct ChoixMenu<V: Hashable>: View {
    var libelle: String
    @Binding var valeur: V
    var options: [(V, String)]
    var body: some View {
        Picker(libelle, selection: $valeur) {
            ForEach(options, id: \.0) { o in Text(o.1).tag(o.0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

// MARK: - les sous-pages

/// Les réglages détaillés : Dictée (micro, langue, vitesse, retours), Ce qu'elle montre (l'encoche, fonction par fonction),
/// Confidentialité (ce qui reste sur le Mac, ce qui part, l'historique). Deux colonnes, une phrase sous chaque réglage.
struct ReglagesDetailVue: View {
    var sous: SousPageBureau
    @ObservedObject var r: ReglagesModele
    @ObservedObject var store: HistoriqueStore
    var actions: ActionsBureau

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                switch sous {
                case .dictee:
                    VStack(spacing: 14) { voix }.frame(maxWidth: .infinity)
                    VStack(spacing: 14) { ecriture; retours }.frame(maxWidth: .infinity)
                case .lucarne:
                    VStack(spacing: 14) { activites; lecture }.frame(maxWidth: .infinity)
                    VStack(spacing: 14) { fichiers; barre }.frame(maxWidth: .infinity)
                default:
                    VStack(spacing: 14) { ceQuiPart; reunions }.frame(maxWidth: .infinity)
                    VStack(spacing: 14) { historique }.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, TonsBureau.margeH).padding(.bottom, TonsBureau.margeBas)
        }
    }

    // Dictée
    private var voix: some View {
        GroupeReglages(titre: "Voix") {
            LigneGroupe(libelle: "Micro", note: "Automatique : le micro du Mac quand un casque Bluetooth est branché.", premiere: true) {
                ChoixMenu(libelle: "Micro", valeur: $r.micro, options: r.micros.map { ($0.id, $0.nom) })
            }
            LigneGroupe(libelle: "Langue", note: "La langue que tu parles pendant la dictée.") {
                ChoixMenu(libelle: "Langue", valeur: $r.langue, options: [("fr", "Français"), ("en", "Anglais"), ("auto", "Automatique")])
            }
            LigneGroupe(libelle: "Vitesse", note: r.phraseVitesse.isEmpty ? "Rapide : le plus rapide. Précis : un peu plus lent, plus juste." : r.phraseVitesse) {
                ChoixMenu(libelle: "Vitesse de transcription", valeur: $r.modeleWhisper, options: ModeleWhisper.allCases.map { ($0, $0.libelle) })
            }
            LigneGroupe(libelle: "Secours", note: r.phraseSecours) {
                ChoixMenu(libelle: "Secours", valeur: $r.secoursApple, options: [(true, "Apple"), (false, "Aucun")])
            }
        }
    }
    private var ecriture: some View {
        GroupeReglages(titre: "Écriture") {
            LigneGroupe(libelle: "Remettre au propre", note: "Ajoute la ponctuation et retire les «\u{202F}euh\u{202F}».", premiere: true) {
                Interrupteur(actif: $r.remettreAuPropre, etiquette: "Remettre au propre")
            }
            LigneGroupe(libelle: "Adapter le ton à l\u{2019}app", note: "Plus soigné dans Mail, plus court dans WhatsApp.") {
                Interrupteur(actif: $r.adapterLeTon, etiquette: "Adapter le ton à l\u{2019}app")
            }
        }
    }
    private var retours: some View {
        GroupeReglages(titre: "Ce que tu sens et entends") {
            LigneGroupe(libelle: "Sons", note: "Un petit son au début, au texte collé et à l\u{2019}annulation.", premiere: true) { Interrupteur(actif: $r.sons, etiquette: "Sons") }
            LigneGroupe(libelle: "Vibration", note: "Se sent seulement avec un doigt posé sur le trackpad.") { Interrupteur(actif: $r.vibration, etiquette: "Vibration") }
        }
    }

    // Ce qu'elle montre
    private var activites: some View {
        GroupeReglages(titre: "Activités") {
            LigneGroupe(libelle: "Minuteur et réveil", note: "Depuis le Centre, ou en disant «\u{202F}réveille-moi à 9 h\u{202F}». Si le Mac dort à l\u{2019}heure du réveil, il sonne dès qu\u{2019}il se réveille.", premiere: true) {
                Interrupteur(actif: $r.ilotMinuteur, etiquette: "Minuteur et réveil")
            }
            LigneGroupe(libelle: "Rappels", note: "Gardés sur ce Mac seulement. Ils reviennent après un redémarrage.") { Interrupteur(actif: $r.ilotRappels, etiquette: "Rappels") }
            LigneGroupe(libelle: "Calendrier", note: r.phraseCalendrier) { Interrupteur(actif: $r.ilotCalendrier, etiquette: "Calendrier") }
            LigneGroupe(libelle: "Claude au travail", note: r.phraseClaude) {
                LienBleu(titre: r.claudeBranche ? "Débrancher" : "Brancher") { if r.claudeBranche { r.debrancherClaude() } else { r.brancherClaude() } }
                    .opacity(r.ilotClaude || r.claudeBranche ? 1 : 0.4).disabled(!r.ilotClaude && !r.claudeBranche)
                Interrupteur(actif: $r.ilotClaude, etiquette: "Claude au travail")
            }
            LigneGroupe(libelle: "Notifications", detail: "expérimental", note: "Les notifications des autres apps, lues avec l\u{2019}Accessibilité déjà accordée. Peut cesser de marcher avec une mise à jour de macOS.") {
                Interrupteur(actif: $r.ilotNotifications, etiquette: "Notifications")
            }
        }
    }
    private var lecture: some View {
        GroupeReglages(titre: "Lecture en cours") {
            LigneGroupe(libelle: "Afficher la lecture", note: "Musique et vidéos : pochette, titre, commandes.", premiere: true) {
                Interrupteur(actif: $r.afficherLaLecture, etiquette: "Afficher la lecture en cours")
            }
            LigneGroupe(libelle: "Pause pendant la dictée", note: r.afficherLaLecture ? "Elle reprend à la fin, seulement si Verbe l\u{2019}a mise en pause." : "Demande d\u{2019}afficher la lecture.") {
                Interrupteur(actif: $r.pauseLecturePendantDictee, etiquette: "Mettre en pause pendant la dictée").disabled(!r.afficherLaLecture)
            }
            .opacity(r.afficherLaLecture ? 1 : 0.5)
        }
    }
    private var fichiers: some View {
        GroupeReglages(titre: "Fichiers et appareils") {
            LigneGroupe(libelle: "Étagère", note: "Glisse des fichiers sur l\u{2019}encoche : ils y restent. Verbe garde un lien vers chaque fichier, jamais une copie.", premiere: true) {
                Interrupteur(actif: $r.ilotEtagere, etiquette: "Étagère")
            }
            LigneGroupe(libelle: "Téléchargements", note: "Un fichier qui arrive, AirDrop compris, avec «\u{202F}Ouvrir\u{202F}». macOS demande l\u{2019}accès au dossier en l\u{2019}allumant.") {
                Interrupteur(actif: $r.ilotTelechargements, etiquette: "Téléchargements")
            }
            LigneGroupe(libelle: "Batterie et appareils", note: "La batterie du Mac et de tes AirPods, le chargeur branché. macOS demande une fois l\u{2019}accès au Bluetooth.") {
                Interrupteur(actif: $r.ilotEnergie, etiquette: "Batterie et appareils")
            }
            LigneGroupe(libelle: "Micro coupé", note: "Le bouton Micro du Centre coupe le micro du Mac et le rouvre. Coupé, fn ne dicte pas.") {
                Interrupteur(actif: $r.ilotMicro, etiquette: "Micro coupé")
            }
            LigneGroupe(libelle: "Volume et luminosité", note: "Les touches du volume et de la luminosité s\u{2019}affichent dans l\u{2019}encoche.") {
                Interrupteur(actif: $r.ilotNiveaux, etiquette: "Volume et luminosité dans l\u{2019}encoche")
            }
        }
    }
    private var barre: some View {
        GroupeReglages(titre: "Barre des menus") {
            LigneGroupe(libelle: "Icône dans la barre des menus",
                        note: r.iconeToujours ? "Toujours là sans encoche : c\u{2019}est le chemin vers Verbe sur cet écran."
                                              : "Éteinte, tout se fait depuis l\u{2019}encoche. Sans encoche (écran externe), l\u{2019}icône reste.",
                        premiere: true) {
                if r.iconeToujours {
                    Interrupteur(actif: .constant(true), etiquette: "Icône dans la barre des menus, toujours là sans encoche") { _ in }.disabled(true)
                } else {
                    Interrupteur(actif: $r.iconeBarre, etiquette: "Icône dans la barre des menus")
                }
            }
        }
    }

    // Confidentialité
    private var ceQuiPart: some View {
        GroupeReglages(titre: "Ce qui part, ce qui reste") {
            LigneGroupe(libelle: "Ta voix", note: "Envoyée à Groq seulement quand tu tiens fn (ou pendant une réunion que tu notes), pour l\u{2019}écrire. Rien d\u{2019}autre ne quitte le Mac.", premiere: true)
            LigneGroupe(libelle: "Tes dictées, tes notes, tes mots", note: "Gardés sur ce Mac, dans ton dossier. Jamais envoyés ailleurs.")
            LigneGroupe(libelle: "Le journal", note: "30 caractères au plus de chaque dictée, pour comprendre une panne.") { LienBleu(titre: "Ouvrir") { r.ouvrirJournal() } }
        }
    }
    private var reunions: some View {
        GroupeReglages(titre: "Réunions") {
            LigneGroupe(libelle: "Proposer de noter les appels", note: "Quand Zoom, Teams, FaceTime… utilise le micro. Rien ne s\u{2019}enregistre sans ton clic.", premiere: true) {
                Interrupteur(actif: $r.proposerLesAppels, etiquette: "Proposer de noter les appels")
            }
            LigneGroupe(libelle: "Garder le son des réunions", note: r.garderSonReunions ? "Le son est gardé à côté de la note, sur ce Mac." : "Le son est effacé dès que la note est prête.") {
                Interrupteur(actif: $r.garderSonReunions, etiquette: "Garder le son des réunions")
            }
        }
    }
    private var historique: some View {
        let n = store.historique.entrees.count
        return GroupeReglages(titre: "Historique") {
            if r.confirmerEffacement {
                LigneGroupe(libelle: "Effacer les \(n) dictées\u{202F}?", note: "Cela ne se récupère pas.", premiere: true) {
                    LienBleu(titre: "Garder") { r.confirmerEffacement = false }
                    Button("Effacer", role: .destructive) { store.effacer(); r.confirmerEffacement = false }
                }
            } else {
                LigneGroupe(libelle: "Dictées gardées", note: n == 0 ? "Aucune dictée gardée sur ce Mac." : "\(n) dictée\(n > 1 ? "s" : "") sur ce Mac.", premiere: true) {
                    LienBleu(titre: "Effacer…") { r.confirmerEffacement = true }.opacity(n == 0 ? 0.4 : 1).disabled(n == 0)
                }
            }
            LigneGroupe(libelle: "Test de précision", note: r.testPrecision
                        ? "\(r.testPrecisionRestant) dictée\(r.testPrecisionRestant > 1 ? "s" : "") encore gardée\(r.testPrecisionRestant > 1 ? "s" : ""), sur ce Mac seulement. Ça s\u{2019}arrête tout seul."
                        : "Garde le son des \(TestPrecision.nombreDeDictees) prochaines dictées sur ce Mac, pour comparer les modèles.") {
                Interrupteur(actif: $r.testPrecision, etiquette: "Test de précision")
            }
        }
    }
}
