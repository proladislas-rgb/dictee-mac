import Foundation
import DicteeCore

/// L'app de bureau (maquette lucarne-app-final.html) : l'apparence et le bouton soleil/lune, les tuiles d'« Aujourd'hui » (anneau du
/// record, temps gagné, dernière note, prochain rendez-vous, rappels, étagère), le catalogue de « Découvrir », les calques des illustrations.
func controlesBureau() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    func date(_ j: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: j, hour: h, minute: m))! }
    let maintenant = date(12, 14, 32)   // jeudi 12 novembre, 14:32

    groupe("Bureau : l'apparence et le bouton soleil/lune")
    verifier(ApparenceBureau.depuis(nil) == .automatique && ApparenceBureau.depuis("n'importe quoi") == .automatique && ApparenceBureau.depuis("sombre") == .sombre,
             "absent ou illisible : la fenêtre suit le Mac")
    verifier(!ApparenceBureau.clair.sombre(systemeSombre: true) && ApparenceBureau.sombre.sombre(systemeSombre: false)
             && ApparenceBureau.automatique.sombre(systemeSombre: true) && !ApparenceBureau.automatique.sombre(systemeSombre: false),
             "clair et sombre s'imposent, automatique suit le Mac")
    verifier(ApparenceBureau.automatique.basculee(systemeSombre: false) == .sombre && ApparenceBureau.automatique.basculee(systemeSombre: true) == .clair,
             "le soleil/lune en automatique : l'inverse de ce qu'on voit")
    verifier(ApparenceBureau.clair.basculee(systemeSombre: true) == .sombre && ApparenceBureau.sombre.basculee(systemeSombre: false) == .clair,
             "deux clics reviennent au départ, quel que soit le Mac")

    groupe("Bureau : Aujourd'hui, les mots et l'anneau")
    func dictee(_ j: Int, _ h: Int, _ mots: Int, app: String = "Mail") -> EntreeHistorique {
        EntreeHistorique(date: date(j, h), appId: "id.\(app)", appNom: app, texte: Array(repeating: "mot", count: mots).joined(separator: " "), dureeParole: Double(mots) / 3)
    }
    let historique = [dictee(10, 10, 300), dictee(10, 11, 100, app: "Notes"),   // mardi : 400 (record)
                      dictee(11, 9, 200),                                       // mercredi : 200
                      dictee(12, 9, 150), dictee(12, 11, 90, app: "Notes"), dictee(12, 14, 40, app: "Messages")]   // aujourd'hui : 280
    let t = Aujourdhui.calculer(entrees: historique, reunions: [], evenements: [], rappels: [], etagere: [], maintenant: maintenant, calendrier: cal)
    verifier(t.date == "Jeudi 12 novembre", "la date en toutes lettres, majuscule au jour (\(t.date))")
    verifier(t.mots.mots == 280 && t.mots.dictees == 3 && t.mots.apps == 3, "280 mots, 3 dictées, 3 apps aujourd'hui")
    verifier(t.mots.record?.mots == 400 && t.mots.moyenne == 300, "le record (mardi, 400) et la moyenne d'avant (300) ne comptent pas aujourd'hui")
    verifier(abs(t.mots.remplissage - 0.7) < 1e-9 && t.mots.pourcent == "70\u{00A0}%" && t.mots.sousAnneau == "de ton record", "l'anneau : 70 % du record")
    let battu = TuileMots(mots: 512, dictees: 9, apps: 2, record: (date(10, 0), 400), moyenne: 300)
    verifier(battu.remplissage == 1 && battu.pourcent == "Record" && battu.sousAnneau.contains("battu"), "record battu : l'anneau est plein et le dit")
    let premier = TuileMots(mots: 40, dictees: 1, apps: 1, record: nil, moyenne: nil)
    verifier(premier.remplissage == 0 && premier.pourcent == nil && premier.sousAnneau == "premier jour", "premier jour : pas de pourcentage inventé")
    let tropPres = TuileMots(mots: 399, dictees: 1, apps: 1, record: (date(10, 0), 400), moyenne: nil)
    verifier(tropPres.pourcent == "99\u{00A0}%", "399 sur 400 : 99 %, jamais arrondi à 100 % avant d'y être")

    groupe("Bureau : Aujourd'hui, le temps gagné et la semaine")
    verifier(t.temps.barres.count == 7 && t.temps.barres.last == 0.7 && t.temps.barres[4] == 1 && t.temps.barres[0] == 0,
             "7 barres, aujourd'hui en dernier, proportionnelles au plus grand jour (\(t.temps.barres))")
    verifier(Aujourdhui.barres([1000, 1, 0]) == [1, 0.12, 0] && Aujourdhui.barres([0, 0]) == [0, 0], "un jour actif reste visible (12 %), un jour vide est à 0")
    verifier(TuileTemps(secondes: 52 * 60, barres: []).chiffre == ("52", "min") && TuileTemps(secondes: 75 * 60, barres: []).chiffre.nombre == "1\u{00A0}h\u{00A0}15",
             "« 52 min », « 1 h 15 »")

    groupe("Bureau : Aujourd'hui, la dernière note et le prochain rendez-vous")
    var prete = Reunion(debut: date(12, 14, 2), duree: 29 * 60, titre: "Lancement de la boutique", dit: ["Le site sort le 2 décembre."], etat: .prete,
                        enBref: "La page d\u{2019}accueil est validée.")
    let enCours = Reunion(debut: date(12, 15), duree: 60, titre: "En cours", etat: .enregistrement)
    let ancienne = Reunion(debut: date(9, 10), duree: 18 * 60, titre: "Fournisseurs", dit: ["Point sur les emballages."], etat: .prete)
    let n = Aujourdhui.derniereNote([ancienne, prete, enCours], maintenant: maintenant, calendrier: cal)
    verifier(n?.id == prete.id && n?.extrait == "La page d\u{2019}accueil est validée." && n?.meta == "Réunion \u{00B7} 14:02 \u{00B7} 29 min",
             "la plus récente note ÉCRITE (pas celle en cours), « En bref » d'abord (\(n?.meta ?? "rien"))")
    prete.enBref = nil
    verifier(Aujourdhui.derniereNote([prete], maintenant: maintenant, calendrier: cal)?.extrait == "Le site sort le 2 décembre.", "sans « En bref » : le premier point dit")
    verifier(Aujourdhui.derniereNote([ancienne], maintenant: maintenant, calendrier: cal)?.meta.hasPrefix("9 nov") == true, "une note d'un autre jour porte sa date")
    verifier(Aujourdhui.derniereNote([enCours], maintenant: maintenant, calendrier: cal) == nil, "aucune note écrite : pas de tuile inventée")
    func rdv(_ titre: String, _ debut: Date, minutes: Double = 30, jour: Bool = false) -> EvenementAgenda {
        EvenementAgenda(id: titre, titre: titre, debut: debut, fin: debut.addingTimeInterval(minutes * 60), toutelaJournee: jour)
    }
    let r = Aujourdhui.prochainRendezVous([rdv("Journée", date(12, 0), minutes: 1440, jour: true), rdv("Plus tard", date(12, 17)), rdv("Point fournisseurs", date(12, 15))],
                                          maintenant: maintenant, calendrier: cal)
    verifier(r == TuileRendezVous(heure: "15:00", titre: "Point fournisseurs", quand: "dans 28\u{00A0}min"), "le plus proche, pas la journée entière (\(String(describing: r)))")
    verifier(Aujourdhui.prochainRendezVous([rdv("Commencé", date(12, 14, 20))], maintenant: maintenant, calendrier: cal)?.quand == "en cours", "déjà commencé : « en cours »")
    verifier(Aujourdhui.prochainRendezVous([rdv("Fini", date(12, 13), minutes: 30), rdv("Demain soir", date(13, 9))], maintenant: maintenant, calendrier: cal) == nil,
             "fini, ou à plus de 12 h : rien")
    verifier(Aujourdhui.dans(maintenant.addingTimeInterval(20), maintenant: maintenant) == "maintenant" && Aujourdhui.dans(maintenant.addingTimeInterval(3900), maintenant: maintenant) == "dans 1\u{00A0}h\u{00A0}05"
             && Aujourdhui.dans(maintenant.addingTimeInterval(7200), maintenant: maintenant) == "dans 2\u{00A0}h", "« maintenant », « dans 1 h 05 », « dans 2 h »")

    groupe("Bureau : Aujourd'hui, les rappels et l'étagère")
    let rappels = [Rappel(texte: "Sonné", echeance: date(12, 16), sonneLe: date(12, 14), cree: date(12, 9)),
                   Rappel(texte: "Passé", echeance: date(12, 10), cree: date(12, 9)),
                   Rappel(texte: "Demain", echeance: date(13, 9), cree: date(12, 9)),
                   Rappel(texte: "Appeler le garage", echeance: date(12, 17), cree: date(12, 9)),
                   Rappel(texte: "Lundi", echeance: date(16, 9, 30), cree: date(12, 9))]
    let p = Aujourdhui.rappelsAVenir(rappels, maintenant: maintenant, calendrier: cal)
    verifier(p.map(\.texte) == ["Appeler le garage", "Demain", "Lundi"] && p.map(\.valeur) == ["17:00", "demain 09:00", "lun. 09:30"],
             "à venir seulement, du plus proche au plus lointain, l'heure lisible (\(p.map(\.valeur)))")
    let tout = Aujourdhui.calculer(entrees: [], reunions: [], evenements: [], rappels: rappels,
                                   etagere: [ElementEtagere(chemin: "/tmp/Devis.pdf", signet: Data(), ajout: date(11, 9)),
                                             ElementEtagere(chemin: "/tmp/Atelier.jpg", signet: Data(), ajout: date(12, 9))],
                                   maintenant: maintenant, calendrier: cal)
    verifier(tout.puces.count == Aujourdhui.pucesMax && tout.etagere == ["Atelier.jpg", "Devis.pdf"], "deux pastilles au plus ; l'étagère, le plus récent d'abord")
    verifier(tout.mots.mots == 0 && tout.temps.barres == Array(repeating: 0, count: 7) && tout.note == nil && tout.rendezVous == nil, "journée vide : des zéros, rien d'inventé")

    groupe("Bureau : Découvrir et les illustrations")
    verifier(Decouverte.allCases.count == 7 && Decouverte.allCases.filter(\.grande) == [.centre], "sept choses, une seule grande tuile (le Centre)")
    verifier(Decouverte.allCases.allSatisfy { !$0.titre.isEmpty && $0.phrase.count <= 60 }, "chaque tuile a un titre et une phrase courte (≤ 60 signes)")
    verifier(IllustrationsAccueil.noms.count == 11 && Set(IllustrationsAccueil.noms).count == 11, "11 pièces, chacune une fois")
    verifier((1...5).flatMap { IllustrationsAccueil.calques(carte: $0) } == IllustrationsAccueil.noms, "les calques des 5 cartes couvrent toute la série, dans l'ordre")
    verifier(IllustrationsAccueil.calques(carte: 1) == ["1a", "1b", "1c"] && IllustrationsAccueil.calques(carte: 4) == ["4a", "4b", "4c"] && IllustrationsAccueil.calques(carte: 5) == ["5a"],
             "fn : clavier, touche enfoncée, index ; clé : clé, champ, pastille ; essai : l'onde seule")
    verifier(IllustrationsAccueil.rapport(carte: 5) == 3 && IllustrationsAccueil.rapport(carte: 1) == 1.5, "toiles 1536 × 1024, l'onde 1536 × 512")
    verifier(IllustrationsAccueil.noms.allSatisfy { IllustrationsAccueil.sujet($0) != $0 }, "chaque pièce dit ce qu'elle montre")

    groupe("Bureau : le mouvement des cartes d'accueil")
    verifier(Ressort.valeur(-1) == 0 && Ressort.valeur(0) == 0, "avant le départ : immobile")
    verifier(abs(Ressort.valeur(3, duree: 0.5) - 1) < 1e-4 && abs(Ressort.valeur(3, duree: 0.5, rebond: 0.4) - 1) < 1e-3, "posé à l'arrivée, avec ou sans rebond")
    let sansRebond = stride(from: 0.0, through: 2, by: 0.01).map { Ressort.valeur($0, duree: 0.5) }
    let avecRebond = stride(from: 0.0, through: 2, by: 0.01).map { Ressort.valeur($0, duree: 0.5, rebond: 0.4) }
    verifier(sansRebond.allSatisfy { $0 <= 1 + 1e-9 } && zip(sansRebond, sansRebond.dropFirst()).allSatisfy { $1 >= $0 - 1e-12 }, "sans rebond : monte sans jamais dépasser")
    verifier((avecRebond.max() ?? 0) > 1.05, "avec rebond : dépasse puis revient (\(String(format: "%.3f", avecRebond.max() ?? 0)))")
    verifier(Ressort.valeur(0.05, duree: 0.5) < 0.2, "il accélère : rien de linéaire au départ")
    let ar = Ressort.allerRetour(0, 10, t: 4, aller: 0, retour: 1, duree: 0.4)
    verifier(abs(ar) < 0.01 && Ressort.allerRetour(0, 10, t: 0.99, aller: 0, retour: 1, duree: 0.4) > 9.9, "aller-retour : arrivé avant le retour, revenu ensuite")
    let b = IllustrationsAccueil.barres(colonnes: [0, 2, 3, 0, 0, 5, 0, 1])
    verifier(b.count == 3 && b[0].debut == 1.0 / 8 && b[0].fin == 3.0 / 8 && b[2].fin == 1, "les barres de l'onde : séparées par les colonnes vides, la dernière jusqu'au bord")
}
