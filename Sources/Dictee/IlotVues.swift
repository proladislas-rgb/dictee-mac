import AppKit
import SwiftUI
import DicteeCore

// Les écrans de l'îlot, un par `VueIlot`, dessinés à partir des mesures de la maquette (coordonnées depuis le centre de l'encoche et le haut
// de l'écran). Les éléments qui touchent la barre des menus (« ailes ») suivent la vraie caméra ; ceux du corps suivent la vraie barre.

struct Cx {
    var cx: CGFloat
    var dy: CGFloat
    var dAile: CGFloat
    var dyA: CGFloat { dy / 2 }
}
enum ZoneIlot { case corps, gauche, droite }

extension View {
    /// Pose la vue à la place de la maquette : x depuis le centre, y depuis le haut.
    func place(_ c: Cx, _ z: ZoneIlot = .corps, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, _ al: Alignment = .leading) -> some View {
        frame(width: w, height: h, alignment: al)
            .offset(x: c.cx + x + (z == .gauche ? -c.dAile : (z == .droite ? c.dAile : 0)), y: y + (z == .corps ? c.dy : c.dyA))
    }
}

private func t1(_ s: String) -> some View {
    Text(s).font(.system(size: 18, weight: .semibold)).tracking(-0.2).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
}
private func t15(_ s: String) -> some View {
    Text(s).font(.system(size: 15, weight: .semibold)).tracking(-0.12).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
}
private func t2(_ s: String) -> some View {
    Text(s).font(.system(size: 13)).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
}
private func nombre(_ s: String, _ c: Color = .white) -> some View {
    Text(s).font(.system(size: 14, weight: .semibold).monospacedDigit()).tracking(-0.1).foregroundStyle(c).lineLimit(1)
}

/// Tous les écrans, posés les uns sur les autres : chacun a un poids (0…1) qui monte ou descend par ressort ; la forme noire les rogne.
struct IlotCalques: View {
    @ObservedObject var m: IlotMoteur
    var cx: Cx

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(VueIlot.allCases, id: \.self) { v in
                let p = CGFloat(m.poids[v]?.x ?? 0)
                let op = lisseIlot((p - 0.5) / 0.42)
                if p > 0.01 {
                    calque(v)
                        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
                        .scaleEffect(0.955 + 0.045 * op, anchor: .top)
                        .blur(radius: (1 - op) * 8)
                        .opacity(Double(op))
                        .allowsHitTesting(op > 0.6)
                }
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    @ViewBuilder private func calque(_ v: VueIlot) -> some View {
        ZStack(alignment: .topLeading) {
            switch v {
            case .repos: Color.clear
            case .minuteurMinimal, .minuteurCompact, .minuteurEtendu, .minuteurLance, .minuteurFini: calqueMinuteur(v)
            case .lectureCompact, .lectureEtendu: calqueLecture(v)
            case .rappelEtendu, .rappelCompact, .rappelAjoute, .rappelFait, .rappelReporte, .rappelListe: calqueRappel(v)
            case .agendaAvant, .agendaCompact, .agendaEtendu, .agendaDebut: calqueAgenda(v)
            case .notification, .notifications: calqueNotification(v)
            case .accueil: calqueAccueil()
            }
        }
    }

    // MARK: étiquettes et bandeaux

    private func etiquetteGauche(_ texte: String, _ couleur: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(couleur).frame(width: 6, height: 6).shadow(color: couleur, radius: 4)
            Text(texte).font(.system(size: 11.5)).foregroundStyle(CouleursIlot.encre2).lineLimit(1).minimumScaleFactor(0.8)
        }.place(cx, .gauche, x: -160, y: 0, w: 66, h: 38)
    }
    private func etiquetteDroite(_ texte: String) -> some View {
        Text(texte).font(.system(size: 11.5)).foregroundStyle(CouleursIlot.encre2).lineLimit(1).minimumScaleFactor(0.8)
            .place(cx, .droite, x: 94, y: 0, w: 66, h: 38, .trailing)
    }

    @ViewBuilder private func bandeau<I: View, M: View, P: View>(icone: I, meta: M, l1: String, l2: String, pilule: P?, largeur: CGFloat? = nil) -> some View {
        let avecPilule = pilule != nil
        icone.place(cx, .gauche, x: -157, y: 5, w: 28, h: 28, .center)
        meta.place(cx, .droite, x: 94, y: 0, w: 64, h: 38, .trailing)
        t15(l1).place(cx, x: -196, y: 37, w: avecPilule ? 290 : 392, h: 20)
        t2(l2).place(cx, x: -196, y: 57, w: avecPilule ? 290 : 392, h: 18)
        if let pilule { pilule.place(cx, x: 98, y: 41, w: 98, h: 32, .trailing) }
    }
    private func metaTexte(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.encre2).lineLimit(1)
    }

    // MARK: minuteur

    private var mn: MinuteurIlot { m.minuteur ?? m.dernierMinuteur }

    /// Un texte qui se met à jour à chaque seconde du minuteur (une fois par seconde, jamais plus).
    private func tic<Contenu: View>(@ViewBuilder _ contenu: @escaping (Date) -> Contenu) -> some View {
        TimelineView(.periodic(from: m.minuteur?.echeance ?? Date(timeIntervalSinceReferenceDate: 0), by: 1)) { ctx in contenu(ctx.date) }
    }
    private func tempsRestant(_ d: Date) -> String {
        FormatIlot.duree(m.minuteur == nil ? mn.restant(a: d) : mn.restant(a: m.maintenant()))
    }

    @ViewBuilder private func calqueMinuteur(_ v: VueIlot) -> some View {
        switch v {
        case .minuteurMinimal:
            tic { d in AnneauIlot(taille: 22, trait: 3, couleur: CouleursIlot.ambre, fraction: mn.fraction(a: m.maintenant()), enPause: mn.enPause) {} }
                .place(cx, .gauche, x: -133, y: 8, w: 22, h: 22, .center)
        case .minuteurCompact:
            tic { _ in AnneauIlot(taille: 22, trait: 3, couleur: CouleursIlot.ambre, fraction: mn.fraction(a: m.maintenant()), enPause: mn.enPause) {} }
                .place(cx, .gauche, x: -154, y: 8, w: 22, h: 22, .center)
            tic { d in nombre(tempsRestant(d), CouleursIlot.ambre) }.place(cx, .droite, x: 94, y: 9, w: 60, h: 20, .trailing)
        case .minuteurEtendu:
            etiquetteGauche("Minuteur", CouleursIlot.ambre)
            etiquetteDroite(FormatIlot.minutes(mn.total))
            tic { d in
                AnneauIlot(taille: 96, trait: 6, couleur: CouleursIlot.ambre, fraction: mn.fraction(a: m.maintenant()), enPause: mn.enPause) {
                    Text(tempsRestant(d)).font(.system(size: 26, weight: .semibold).monospacedDigit()).tracking(-0.5).foregroundStyle(.white)
                }
            }.place(cx, x: -208, y: 50, w: 96, h: 96)
            tic { _ in t1("Fin à " + FormatIlot.heure(mn.heureDeFin(a: m.maintenant()))) }.place(cx, x: -96, y: 50, w: 300, h: 24)
            t2(mn.enPause ? "En pause" : "Compte à rebours").place(cx, x: -96, y: 76, w: 300, h: 18)
            HStack(spacing: 12) {
                RondIlot(symbole: mn.enPause ? "play.fill" : "pause.fill", diametre: 46, etiquette: mn.enPause ? "Reprendre" : "Pause") { m.surAction(.minuteurBasculer) }
                PiluleIlot(titre: "1 min", icone: "plus", hauteur: 46, largeur: 130) { m.surAction(.minuteurPlusUneMinute) }
                RondIlot(symbole: "stop.fill", diametre: 46, rouge: true, etiquette: "Arrêter") { m.surAction(.minuteurArreter) }
            }.place(cx, x: -96, y: 102, w: 300, h: 46)
        case .minuteurLance:
            let b = m.bandeauVu
            bandeau(icone: TuileIlot(genre: .minuteur, taille: 28),
                    meta: tic { d in metaTexte(tempsRestant(d)) }, l1: b?.ligne1 ?? "Minuteur lancé", l2: b?.ligne2 ?? "", pilule: Optional<EmptyView>.none)
        case .minuteurFini:
            alerteMinuteur
        default: EmptyView()
        }
    }

    private var alerteMinuteur: some View {
        Group {
            PulsationIlot(couleur: CouleursIlot.ambre, rond: true).place(cx, x: -206, y: 46, w: 52, h: 52, .center)
            Image(systemName: "timer").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 52, height: 52).background(Circle().fill(CouleursIlot.ambre)).place(cx, x: -206, y: 46, w: 52, h: 52, .center)
            t1("Minuteur terminé").place(cx, x: -136, y: 46, w: 300, h: 24)
            t2((m.alerteVu?.libelle ?? "") + " \u{00B7} il est " + FormatIlot.heure(m.maintenant())).place(cx, x: -136, y: 72, w: 300, h: 18)
            PiluleIlot(titre: "Encore 5 min", largeur: 205) { m.surAction(.minuteurRecommencer(minutes: 5)) }.place(cx, x: -210, y: 106, w: 205, h: 42)
            PiluleIlot(titre: "OK", style: .blanc, largeur: 205) { m.surAction(.alerteOK) }.place(cx, x: 5, y: 106, w: 205, h: 42)
        }
    }

    // MARK: lecture

    @ViewBuilder private func calqueLecture(_ v: VueIlot) -> some View {
        let t = m.lecture.teinte
        if v == .lectureCompact {
            PochetteLecture(m: m.lecture).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .place(cx, .gauche, x: -154, y: 4, w: 30, h: 30, .center)
            Group {
                if m.statique { OndeFixe(teinte: t.clair, joue: m.lecture.joue) }
                else { OndeLecture(teinte: t.clair, joue: m.lecture.joue, animer: !m.reduire) }
            }.place(cx, .droite, x: 104, y: 7, w: 50, h: 24, .center)
        } else {
            LectureEtendueVue(m: m, cx: cx, etiquetteG: AnyView(etiquetteGauche(m.lecture.joue ? "En lecture" : "En pause", teinteIlot(t.clair))),
                              etiquetteD: AnyView(etiquetteDroite(m.lecture.genre == .musique ? "Musique" : (m.lecture.site ?? "Vidéo"))))
        }
    }

    // MARK: rappels

    private var rappelVu: Rappel? { m.alerteVu?.rappel ?? m.rappelsSonnes.first ?? m.dernierRappel }

    @ViewBuilder private func calqueRappel(_ v: VueIlot) -> some View {
        let r = rappelVu
        switch v {
        case .rappelEtendu:
            PulsationIlot(couleur: CouleursIlot.corail, rond: false).place(cx, x: -206, y: 44, w: 56, h: 56, .center)
            CloucheSecouee().place(cx, x: -206, y: 44, w: 56, h: 56, .center)
            t1(r?.texte ?? "").place(cx, x: -136, y: 46, w: 300, h: 24)
            (Text("Rappel \u{00B7} ").foregroundColor(CouleursIlot.encre2) + Text(FormatIlot.heure(r?.echeance ?? m.maintenant())).bold().foregroundColor(.white)
                + Text(" \u{00B7} " + ListeRappels.retard(de: r?.echeance ?? m.maintenant(), maintenant: m.maintenant())).foregroundColor(CouleursIlot.encre2))
                .font(.system(size: 13)).lineLimit(1).place(cx, x: -136, y: 72, w: 300, h: 18)
            PiluleIlot(titre: "Plus tard (10 min)", largeur: 205) { if let r { m.surAction(.rappelPlusTard(r.id)) } }.place(cx, x: -210, y: 106, w: 205, h: 42)
            PiluleIlot(titre: "Fait", style: .blanc, largeur: 205) { if let r { m.surAction(.rappelFait(r.id)) } }.place(cx, x: 5, y: 106, w: 205, h: 42)
        case .rappelCompact:
            TuileIlot(genre: .rappel, taille: 24).place(cx, .gauche, x: -154, y: 7, w: 24, h: 24, .center)
            nombre(FormatIlot.heure(r?.echeance ?? m.maintenant()), CouleursIlot.corail).place(cx, .droite, x: 94, y: 9, w: 60, h: 20, .trailing)
        case .rappelAjoute:
            let b = m.bandeauVu
            bandeau(icone: TuileIlot(genre: .rappel, taille: 28), meta: metaTexte(b?.meta ?? ""), l1: b?.ligne1 ?? "Rappel ajouté", l2: b?.ligne2 ?? "",
                    pilule: PiluleIlot(titre: "Annuler", hauteur: 32, largeur: 98) { if let id = b?.rappelId { m.surAction(.rappelAnnuler(id)) } })
        case .rappelFait:
            let b = m.bandeauVu
            bandeau(icone: TuileIlot(genre: .fait, taille: 28), meta: EmptyView(), l1: b?.ligne1 ?? "Fait", l2: b?.ligne2 ?? "", pilule: Optional<EmptyView>.none)
        case .rappelReporte:
            let b = m.bandeauVu
            bandeau(icone: TuileIlot(genre: .horloge, taille: 28), meta: metaTexte(b?.meta ?? ""), l1: b?.ligne1 ?? "", l2: b?.ligne2 ?? "", pilule: Optional<EmptyView>.none)
        case .rappelListe:
            etiquetteGauche("Rappels", CouleursIlot.corail)
            VStack(spacing: 0) {
                ForEach(Array(m.rappelsAVenir.prefix(2))) { r in
                    LigneRappel(rappel: r) { m.surAction(.rappelFait(r.id)) }
                }
                if m.rappelsAVenir.isEmpty {
                    Text("Aucun rappel pour l\u{2019}instant.").font(.system(size: 13)).foregroundStyle(CouleursIlot.encre3).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).padding(.leading, 4)
                }
            }.place(cx, x: -214, y: 40, w: 428, h: 72, .topLeading)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Dis \u{00AB} appeler Paul \u{00E0} 15 h \u{00BB} (fn)").font(.system(size: 14)).foregroundStyle(CouleursIlot.encre3).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "mic").font(.system(size: 15, weight: .semibold)).foregroundStyle(CouleursIlot.encre2)
                }.padding(.leading, 16).padding(.trailing, 12).frame(height: 40).background(Capsule().fill(Color.white.opacity(0.1)))
            }.place(cx, x: -214, y: 124, w: 428, h: 40)
        default: EmptyView()
        }
    }

    // MARK: agenda

    private var rdvVu: EvenementAgenda? { m.alerteVu?.evenement ?? m.rendezVous ?? m.dernierRendezVous }

    @ViewBuilder private func calqueAgenda(_ v: VueIlot) -> some View {
        let e = rdvVu
        let visio = e?.lien != nil
        switch v {
        case .agendaAvant:
            let b = m.bandeauVu
            bandeau(icone: TuileIlot(genre: .calendrier, taille: 28), meta: metaTexte(e.map { FormatIlot.heure($0.debut) } ?? ""),
                    l1: b?.ligne1 ?? e?.titre ?? "", l2: b?.ligne2 ?? "", pilule: Optional<EmptyView>.none)
        case .agendaCompact:
            TuileIlot(genre: .calendrier, taille: 24).place(cx, .gauche, x: -154, y: 7, w: 24, h: 24, .center)
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 15)) { _ in
                nombre(e.map { PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())).replacingOccurrences(of: "dans ", with: "") } ?? "").foregroundStyle(.white)
            }.place(cx, .droite, x: 94, y: 9, w: 60, h: 20, .trailing)
        case .agendaEtendu:
            etiquetteGauche("Agenda", CouleursIlot.vert)
            etiquetteDroite(e.map { PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())) } ?? "")
            TuileIlot(genre: .calendrier, taille: 56).place(cx, x: -208, y: 46, w: 56, h: 56)
            t1(e?.titre ?? "").place(cx, x: -136, y: 46, w: 300, h: 24)
            t2(e.map { PlanAgenda.plage($0) } ?? "").place(cx, x: -136, y: 72, w: 300, h: 18)
            HStack(spacing: 7) {
                Image(systemName: visio ? "video" : "mappin.and.ellipse").font(.system(size: 13, weight: .semibold))
                Text(e.flatMap { $0.lien.map(adresseCourte) ?? $0.lieu } ?? "").font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            }.foregroundStyle(CouleursIlot.encre2).place(cx, x: -136, y: 92, w: 300, h: 18)
            if let e {
                if visio { PiluleIlot(titre: "Rejoindre", icone: "video", style: .vert, largeur: 205) { m.surAction(.rendezVousRejoindre(e)) }.place(cx, x: -210, y: 124, w: 205, h: 42) }
                PiluleIlot(titre: "Noter la réunion", icone: "note.text", largeur: visio ? 205 : 420) { m.surAction(.rendezVousNoter(e)) }
                    .place(cx, x: visio ? 5 : -210, y: 124, w: visio ? 205 : 420, h: 42)
            }
        case .agendaDebut:
            let b = rdvVu
            let visioDebut = b?.lien != nil
            bandeau(icone: TuileIlot(genre: .calendrier, taille: 28),
                    meta: HStack(spacing: 6) { PointPulsant(couleur: CouleursIlot.vert); metaTexte(b.map { FormatIlot.heure($0.debut) } ?? "") },
                    l1: (b?.titre ?? "") + " commence", l2: "Maintenant" + (visioDebut ? " \u{00B7} Visio" : ""),
                    pilule: visioDebut ? PiluleIlot(titre: "Rejoindre", style: .vert, hauteur: 32, largeur: 98) { if let b { m.surAction(.rendezVousRejoindre(b)) } } : nil)
        default: EmptyView()
        }
    }
    private func adresseCourte(_ u: URL) -> String { (u.host ?? "") + u.path }

    // MARK: notifications

    @ViewBuilder private func calqueNotification(_ v: VueIlot) -> some View {
        let n = m.notifications
        if v == .notification, let x = n.last {
            bandeau(icone: TuileIlot(genre: .messages, taille: 28), meta: metaTexte("maintenant"), l1: x.titre.isEmpty ? x.app : x.titre, l2: x.corps.isEmpty ? x.app : x.corps, pilule: Optional<EmptyView>.none)
        } else if v == .notifications {
            ZStack(alignment: .topLeading) {
                TuileIlot(genre: .messages, taille: 24)
                TuileIlot(genre: .notes, taille: 24).overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.black, lineWidth: 2)).offset(x: 16)
            }.place(cx, .gauche, x: -158, y: 7, w: 40, h: 24)
            nombre("\(max(2, n.count))", CouleursIlot.encre2).place(cx, .droite, x: 94, y: 9, w: 64, h: 20, .trailing)
            t15(LectureNotifications.titreDeGroupe(max(2, n.count))).place(cx, x: -196, y: 37, w: 392, h: 20)
            t2(LectureNotifications.ligneDeGroupe(n)).place(cx, x: -196, y: 57, w: 392, h: 18)
        }
    }

    // MARK: accueil

    @ViewBuilder private func calqueAccueil() -> some View {
        etiquetteGauche("Verbe", .white)
        etiquetteDroite(m.horloge)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                CarteIlot(titre: "Minuteur", tuile: .minuteur) {
                    HStack(spacing: 6) {
                        ForEach([5, 10, 25], id: \.self) { n in
                            CourtBouton(titre: "\(n) min") { m.surAction(.minuteurLancer(minutes: Double(n))) }
                        }
                    }
                }
                CarteIlot(titre: "Rappel", tuile: .rappel, action: { m.surAction(.rappelFormulaire) }) {
                    HStack(spacing: 7) {
                        Image(systemName: "mic").font(.system(size: 13, weight: .semibold))
                        Text("Dire (fn)\u{2026}").lineLimit(1)
                    }.font(.system(size: 12.5)).foregroundStyle(CouleursIlot.encre2).padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.09)))
                }
            }
            HStack(spacing: 10) {
                let e = m.rendezVousSuivant
                CarteIlot(titre: "Rendez-vous", tuile: .calendrier, droite: e.map { FormatIlot.heure($0.debut) }) {
                    HStack(spacing: 6) {
                        Text(e?.titre ?? (m.calendrierActif ? "Rien de prévu" : "Calendrier éteint")).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let e, e.lien != nil { PiluleIlot(titre: "Rejoindre", style: .vert, hauteur: 26) { m.surAction(.rendezVousRejoindre(e)) } }
                    }
                }
                let d = m.derniereDictee
                CarteIlot(titre: "Dernière dictée", tuile: .dictee, droite: d?.age, action: d == nil ? nil : { m.surAction(.collerLaDerniereDictee) }) {
                    HStack(spacing: 6) {
                        Text(d?.texte ?? "Rien pour l\u{2019}instant").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xDEDAD3)).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if d != nil { PiluleIlot(titre: "Coller", hauteur: 26) { m.surAction(.collerLaDerniereDictee) } }
                    }
                }
            }
        }.place(cx, x: -214, y: 42, w: 428, h: 162, .topLeading)
    }
}

// MARK: pièces des écrans

struct CarteIlot<Contenu: View>: View {
    var titre: String
    var tuile: TuileIlot.Genre
    var droite: String?
    var action: (() -> Void)?
    @ViewBuilder var contenu: () -> Contenu
    @State private var survol = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TuileIlot(genre: tuile, taille: 20)
                Text(titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
                if let droite { Text(droite).font(.system(size: 12)).foregroundStyle(CouleursIlot.encre3).lineLimit(1) }
            }
            Spacer(minLength: 0)
            contenu().foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(action != nil && survol ? 0.12 : 0.075)))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover { survol = $0 }
        .onTapGesture { action?() }
        .animation(.easeOut(duration: 0.15), value: survol)
    }
}

struct CourtBouton: View {
    var titre: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(survol ? Color(hex: 0x1B1103) : .white)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(Capsule().fill(survol ? CouleursIlot.ambre : Color.white.opacity(0.11)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
    }
}

struct LigneRappel: View {
    var rappel: Rappel
    var fait: () -> Void
    @State private var survol = false
    var body: some View {
        HStack(spacing: 12) {
            Button(action: fait) {
                Circle().strokeBorder(Color.white.opacity(survol ? 0.8 : 0.4), lineWidth: 1.6).frame(width: 18, height: 18)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).opacity(survol ? 1 : 0))
            }.buttonStyle(.plain).onHover { survol = $0 }.accessibilityLabel("Fait")
            Text(rappel.texte).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Text(FormatIlot.heure(rappel.echeance)).font(.system(size: 13).monospacedDigit()).foregroundStyle(CouleursIlot.encre3)
        }
        .padding(.horizontal, 4).frame(height: 36)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}

/// Deux anneaux qui s'étendent derrière l'icône d'une alerte (1,9 s, le second décalé de 0,95 s).
struct PulsationIlot: View {
    var couleur: Color
    var rond: Bool
    @State private var t = false
    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let forme = RoundedRectangle(cornerRadius: rond ? 26 : 17, style: .continuous)
                forme.stroke(couleur, lineWidth: 2).scaleEffect(t ? 1.9 : 1).opacity(t ? 0 : 0.55)
                    .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false).delay(Double(i) * 0.95), value: t)
            }
        }.onAppear { t = true }.allowsHitTesting(false)
    }
}

struct PointPulsant: View {
    var couleur: Color
    @State private var t = false
    var body: some View {
        Circle().fill(couleur).frame(width: 6, height: 6).shadow(color: couleur, radius: 4).opacity(t ? 0.35 : 1)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: t).onAppear { t = true }
    }
}

/// La cloche du rappel qui sonne : elle se secoue (14°, −12°, 9°, −6°, 3°) puis se repose, toutes les 1,2 s.
struct CloucheSecouee: View {
    private static func angle(_ phase: Double) -> Double {
        let k: [(Double, Double)] = [(0, 0), (0.06, 14), (0.12, -12), (0.18, 9), (0.24, -6), (0.30, 3), (0.38, 0), (1, 0)]
        for i in 1..<k.count where phase <= k[i].0 {
            let (a, b) = (k[i - 1], k[i]); let f = (phase - a.0) / (b.0 - a.0); return a.1 + (b.1 - a.1) * f
        }
        return 0
    }
    var body: some View {
        TimelineView(.animation) { ctx in
            let phase = (ctx.date.timeIntervalSinceReferenceDate / 1.2).truncatingRemainder(dividingBy: 1)
            ZStack {
                CouleursIlot.corail
                Image(systemName: "bell.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    .rotationEffect(.degrees(Self.angle(phase)), anchor: UnitPoint(x: 0.5, y: 0.12))
            }
        }
        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

/// L'onde de la lecture, immobile (rendus PNG).
struct OndeFixe: View {
    var teinte: CouleurRVB
    var joue: Bool
    var body: some View {
        Path { p in
            let k: CGFloat = 50.0 / 30.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y) }
            p.move(to: pt(0, 12))
            p.addCurve(to: pt(15, 12), control1: pt(3.75, -2), control2: pt(11.25, -2))
            p.addCurve(to: pt(30, 12), control1: pt(18.75, 26), control2: pt(26.25, 26))
            p.addCurve(to: pt(45, 12), control1: pt(33.75, -2), control2: pt(41.25, -2))
        }
        .stroke(teinteIlot(teinte), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        .frame(width: 50, height: 24).clipped()
        .shadow(color: teinteIlot(teinte).opacity(0.7), radius: 4)
        .opacity(joue ? 1 : 0.45)
    }
}

// MARK: lecture étendue

struct LectureEtendueVue: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var lecture: LectureModele
    var cx: Cx
    var etiquetteG: AnyView
    var etiquetteD: AnyView
    @State private var survolBarre = false

    init(m: IlotMoteur, cx: Cx, etiquetteG: AnyView, etiquetteD: AnyView) {
        self.m = m; self.lecture = m.lecture; self.cx = cx; self.etiquetteG = etiquetteG; self.etiquetteD = etiquetteD
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            etiquetteG
            etiquetteD
            PochetteLecture(m: lecture).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .place(cx, x: -208, y: 50, w: 108, h: 108)
            Text(lecture.morceau?.titre ?? "").font(.system(size: 18, weight: .semibold)).tracking(-0.2).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                .place(cx, x: -80, y: 40, w: 290, h: 24)
            barreEtTemps
            commandes.place(cx, x: -80, y: 122, w: 290, h: 48, .center)
        }
    }

    private var commandes: some View {
        HStack(spacing: 12) {
            if lecture.genre == .musique {
                BoutonLecture(symbole: "backward.fill", diametre: 42, taillePictogramme: 18, etiquette: "Précédent") { lecture.surPrecedent() }
                BoutonLecture(symbole: lecture.joue ? "pause.fill" : "play.fill", diametre: 48, taillePictogramme: 21, plein: true, etiquette: lecture.joue ? "Pause" : "Lecture") { lecture.surBascule() }
                BoutonLecture(symbole: "forward.fill", diametre: 42, taillePictogramme: 18, etiquette: "Suivant") { lecture.surSuivant() }
            } else {
                BoutonLecture(symbole: "gobackward.10", diametre: 42, taillePictogramme: 18, etiquette: "Reculer de 10 secondes") { lecture.surSaut(-10) }
                BoutonLecture(symbole: lecture.joue ? "pause.fill" : "play.fill", diametre: 48, taillePictogramme: 21, plein: true, etiquette: lecture.joue ? "Pause" : "Lecture") { lecture.surBascule() }
                BoutonLecture(symbole: "goforward.10", diametre: 42, taillePictogramme: 18, etiquette: "Avancer de 10 secondes") { lecture.surSaut(10) }
                BoutonLecture(symbole: "forward.end.fill", diametre: 42, taillePictogramme: 16, etiquette: "Suivant") { lecture.surSuivant() }
            }
        }
    }

    @ViewBuilder private var barreEtTemps: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let duree = lecture.morceau?.duree
            let position = lecture.positionAffichee(a: ctx.date)
            let fraction = (position != nil && duree != nil) ? TempsLecture.fraction(position: position!, duree: duree!) : 0
            ZStack(alignment: .topLeading) {
                if lecture.morceau?.positionnable == true, let duree {
                    TraceIlotVue(fraction: fraction, teinte: lecture.teinte, actif: survolBarre || lecture.fractionGlissee != nil)
                        .frame(width: 290, height: 28)
                        .scaleEffect(x: 1, y: lecture.fractionGlissee != nil ? 1.12 : 1)
                        .animation(.spring(duration: 0.2, bounce: 0.2), value: lecture.fractionGlissee != nil)
                        .contentShape(Rectangle())
                        .onHover { survolBarre = $0 }
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { v in lecture.fractionGlissee = TempsLecture.fractionSousSouris(x: v.location.x, largeur: 290) }
                            .onEnded { v in
                                let f = TempsLecture.fractionSousSouris(x: v.location.x, largeur: 290)
                                lecture.fractionGlissee = nil
                                lecture.surPosition(TempsLecture.position(fraction: f, duree: duree))
                                lecture.surFinGlissement()
                            })
                        .accessibilityElement()
                        .accessibilityLabel("Position")
                        .accessibilityValue("\(TempsLecture.format(position ?? 0)) sur \(TempsLecture.format(duree))")
                    HStack {
                        Text(TempsLecture.format(position ?? 0))
                        Spacer(minLength: 0)
                        Text(TempsLecture.restant(position: position ?? 0, duree: duree))
                    }
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(CouleursIlot.encre3)
                    .frame(width: 290).offset(y: 30)
                } else {
                    Text(lecture.morceau?.joue == true ? "En direct" : "Durée inconnue").font(.system(size: 12)).foregroundStyle(CouleursIlot.encre3)
                        .frame(width: 290, height: 28, alignment: .leading)
                }
            }.frame(width: 290, height: 48, alignment: .topLeading)
        }
        .place(cx, x: -80, y: 70, w: 290, h: 48, .topLeading)
    }
}

// MARK: pastille

struct PastilleVue: View {
    @ObservedObject var m: IlotMoteur
    var cx: Cx

    var body: some View {
        let vv = CGFloat(m.pastilleVisible.x), bp = CGFloat(min(1.05, max(0, m.pastilleOuverte.x)))
        if let a = m.pastille, vv > 0.01 {
            let pw = m.largeurPastille(a)
            let largeur = 34 + (pw - 34) * bp
            HStack(spacing: 0) {
                glyphe(a).frame(width: 34, height: 34)
                Text(texte(a)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(a == .minuteur ? CouleursIlot.ambre : .white)
                    .lineLimit(1).padding(.leading, 2).padding(.trailing, 12).opacity(Double(lisseIlot((bp - 0.35) / 0.5)))
            }
            .frame(width: largeur, height: 34, alignment: .leading)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(0.45 + 0.55 * vv, anchor: .leading)
            .opacity(Double(lisseIlot(vv * 1.5)))
            .offset(x: cx.cx + m.demiCamera + CGFloat(m.geo[3].cible) + 8 - (1 - vv) * 30, y: 41 + cx.dy - (1 - vv) * 24)
            .onTapGesture { m.cliquerPastille() }
            .accessibilityLabel("Autre activité")
        }
    }

    @ViewBuilder private func glyphe(_ a: ActiviteIlot) -> some View {
        switch a {
        case .lecture:
            PochetteLecture(m: m.lecture).clipShape(Circle()).frame(width: 26, height: 26)
        case .minuteur:
            AnneauIlot(taille: 26, trait: 3, couleur: CouleursIlot.ambre, fraction: (m.minuteur ?? m.dernierMinuteur).fraction(a: m.maintenant())) {}
        case .rendezVous: TuileIlot(genre: .calendrier, taille: 24)
        case .rappel: TuileIlot(genre: .rappel, taille: 24)
        case .alerte: TuileIlot(genre: .rappel, taille: 24)
        }
    }
    private func texte(_ a: ActiviteIlot) -> String {
        switch a {
        case .lecture: return m.lecture.morceau?.titre ?? ""
        case .minuteur:
            let mn = m.minuteur ?? m.dernierMinuteur
            return FormatIlot.duree(mn.restant(a: m.maintenant()))
        case .rendezVous: return (m.rendezVous ?? m.dernierRendezVous).map { PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())) } ?? ""
        case .rappel: return (m.rappelsSonnes.first ?? m.dernierRappel)?.texte ?? ""
        case .alerte: return ""
        }
    }
}

// MARK: racine

/// Le contenu de la fenêtre de l'îlot : la forme noire, ses écrans rognés à la forme, la pastille.
struct IlotVue: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let _ = m.rev
        let g = m.geometrie
        let cx = Cx(cx: IlotMoteur.largeur / 2, dy: m.dy, dAile: m.dAile)
        let points = m.trace
        let forme = FormeNoire(points: points)
        let hauteur = CGFloat(m.geo[4].x)
        let ombre = Double(min(1, max(0, (hauteur - g.hauteur) / 40)))
        ZStack(alignment: .topLeading) {
            forme.fill(Color.black)
                .overlay(forme.stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5 * ombre), radius: 14, x: 0, y: 10)
            IlotCalques(m: m, cx: cx)
                .clipShape(forme)
                .contentShape(forme)
                .onTapGesture { m.clicForme() }
            PastilleVue(m: m, cx: cx)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .offset(x: CGFloat(m.secousse.x))
        .opacity(m.cache && m.poids[VueIlot.repos]!.fini ? 0 : 1)
    }
}
