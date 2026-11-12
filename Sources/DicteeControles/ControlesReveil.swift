import Foundation
import DicteeCore

/// Le Réveil et le Calendrier (maquette ilot-bibliotheque.html, étapes 7 à 13) : la commande dictée (stricte), la prochaine sonnerie (jour
/// même, lendemain, changement d'heure), « Encore 10 min », « Autre… » (− et +), le fichier, ce que l'îlot écrit ; les vues (≤ 66 pt dans
/// la barre), la priorité, le 6e rond Calendrier (une fois dans un Centre déjà rangé), les noms des services de visio.
func controlesReveil() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    func date(_ j: Int, _ h: Int, _ m: Int = 0, mois: Int = 11) -> Date { cal.date(from: DateComponents(year: 2026, month: mois, day: j, hour: h, minute: m))! }

    groupe("Réveil : la commande dictée")
    typealias A = AnalyseCommandeIlot
    func r(_ t: String) -> String { A.reveil(t).map { ReveilIlot.texte($0.heure, $0.minute) } ?? "rien" }
    verifier(r("réveille-moi à 9 h") == "9:00" && r("Réveille-moi à 9 h.") == "9:00" && r("réveille-moi à 9h") == "9:00", "« réveille-moi à 9 h » (maquette, étape 8), avec majuscule et point")
    verifier(r("réveil à 7 h 30") == "7:30" && r("Réveil à 7h30") == "7:30" && r("réveil à 7:30") == "7:30" && r("réveil 6 h 45") == "6:45", "« réveil à 7 h 30 », « 7h30 », « 7:30 », sans « à »")
    verifier(r("Réveille-moi demain à 7 h 30.") == "7:30" && r("réveille-moi à 8 h demain") == "8:00" && r("réveille-moi à 8 h du matin") == "8:00",
             "« demain » avant ou après, « du matin »")
    verifier(r("Mets un réveil à 8 heures") == "8:00" && r("mets un réveil pour 6 h 15") == "6:15" && r("réveillez-moi à 10 heures 30") == "10:30",
             "« mets un réveil à 8 heures », « pour 6 h 15 », « réveillez-moi »")
    verifier(r("réveille-moi à sept heures et demie") == "7:30" && r("réveille-moi à huit heures") == "8:00" && r("réveil à six heures et quart") == "6:15"
             && r("réveille-moi à neuf heures quinze") == "9:15", "en toutes lettres : « sept heures et demie », « huit heures », « six heures et quart », « neuf heures quinze »")
    verifier(r("reveille-moi a 9 h") == "9:00" && r("réveille-moi à midi") == "12:00", "sans accents (« reveille-moi a 9 h »), « midi »")
    verifier(r("Dis-lui de me réveiller à 9 h") == "rien" && r("réveille-moi à 9 h pour le train") == "rien" && r("réveiller les enfants à 7 h") == "rien"
             && r("Réveil difficile ce matin") == "rien" && r("réveille-moi") == "rien" && r("réveille-moi à 25 h") == "rien" && r("Le réveil sonne à 7 h, puis on part") == "rien",
             "strict : une phrase qui contient un réveil sans l'être est collée normalement (rien avant, rien après, heure valide)")
    func o(_ t: String) -> String { A.reveil(t, ordre: true).map { ReveilIlot.texte($0.heure, $0.minute) } ?? "rien" }
    verifier(o("Réveille-moi à 9 h.") == "9:00" && o("Mets un réveil à 8 heures") == "8:00" && o("réveillez-moi à 10 heures 30") == "10:30"
             && o("Programme un réveil pour 6 h 15") == "6:15" && o("règle un réveil à 7 h") == "7:00" && o("Mets une alarme à 7 h") == "7:00",
             "îlot fermé : les ORDRES (« réveille-moi », « mets / règle / programme un réveil », « mets une alarme »)")
    verifier(o("Le réveil à 7 h.") == "rien" && o("Réveil à 7 h demain.") == "rien" && o("Un réveil à 7 h") == "rien" && o("réveil 6 h 45") == "rien"
             && o("Une alarme à 7 h") == "rien" && o("Alarme à 7 h") == "rien" && o("Le réveil à 7 h 30") == "rien",
             "îlot fermé : un début qui DÉCRIT (« Le réveil à 7 h. », écrit à quelqu'un) est collé normalement")
    verifier(r("Le réveil à 7 h") == "7:00" && r("Réveil à 7 h 30") == "7:30", "l'accueil ouvert (dictée armée) : la liste large reste")
    verifier(A.analyser("Réveille-moi à 9 h.", maintenant: date(11, 23, 12), calendrier: cal) == .reveil(heure: 9, minute: 0)
             && A.analyser("minuteur 10 minutes", maintenant: date(11, 23), calendrier: cal) == .minuteur(secondes: 600)
             && A.analyser("rappelle-moi d'appeler Paul à 15 h", maintenant: date(11, 10), calendrier: cal) == .rappel(texte: "Appeler Paul", quand: date(11, 15)),
             "dans l'accueil ouvert : réveil, minuteur et rappel se distinguent")

    groupe("Réveil : la sonnerie")
    let soir = date(11, 23, 12)   // mercredi 11 novembre, 23:12 (maquette)
    var rv = ReveilIlot(heure: 9, minute: 0, apres: soir, calendrier: cal)
    verifier(rv.sonnerie == date(12, 9) && rv.libelle(calendrier: cal) == "9:00", "réglé à 23:12 pour 9:00 : demain jeudi 12, 9:00")
    verifier(ReveilIlot(heure: 23, minute: 30, apres: soir, calendrier: cal).sonnerie == date(11, 23, 30), "23:30 réglé à 23:12 : le jour même")
    verifier(ReveilIlot(heure: 23, minute: 12, apres: soir, calendrier: cal).sonnerie == date(12, 23, 12), "l'heure qu'il est exactement : le lendemain (jamais tout de suite)")
    let avantChangement = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 22))!   // la nuit du passage à l'heure d'hiver
    let apresChangement = ReveilIlot(heure: 7, minute: 0, apres: avantChangement, calendrier: cal).sonnerie
    verifier(cal.component(.hour, from: apresChangement) == 7 && cal.component(.day, from: apresChangement) == 25 && apresChangement.timeIntervalSince(avantChangement) == 10 * 3600,
             "changement d'heure (25 octobre) : 7:00 à l'heure locale, 10 h après 22:00 (et non 9)")
    verifier(!rv.du(a: date(12, 8, 59)) && rv.du(a: date(12, 9)) && rv.du(a: date(12, 9, 30)) && !rv.perime(a: date(12, 10, 59)) && rv.perime(a: date(12, 11, 1)),
             "il sonne à 9:00 (et jusqu'à 2 h de retard, Mac endormi) ; au-delà, oublié")
    rv.repousser(a: date(12, 9))
    verifier(rv.sonnerie == date(12, 9, 10) && rv.repousse && rv.libelle(calendrier: cal) == "9:10" && rv.heure == 9, "« Encore 10 min » : 9:10, l'aile montre 9:10")
    let d1 = ReveilIlot.decaler(heure: 7, minute: 30, de: 1), d2 = ReveilIlot.decaler(heure: 7, minute: 30, de: -1)
    let d3 = ReveilIlot.decaler(heure: 23, minute: 45, de: 1), d4 = ReveilIlot.decaler(heure: 0, minute: 0, de: -1), d5 = ReveilIlot.decaler(heure: 6, minute: 50, de: 1)
    let d6 = ReveilIlot.decaler(heure: 6, minute: 50, de: -1)
    verifier(d1 == (7, 45) && d2 == (7, 15) && d3 == (0, 0) && d4 == (23, 45) && d5 == (7, 0) && d6 == (6, 45),
             "« Autre… » : − et + par 15 min, autour de minuit, recalé sur le quart d'heure (6:50 → 7:00 ou 6:45)")
    verifier(ReveilIlot.jour(date(12, 9), maintenant: soir, calendrier: cal) == "demain" && ReveilIlot.jour(date(11, 23, 30), maintenant: soir, calendrier: cal) == "aujourd\u{2019}hui"
             && ReveilIlot.jour(date(14, 9), maintenant: soir, calendrier: cal) == "samedi", "« demain », « aujourd'hui », puis le jour")
    let reglé = ReveilIlot(heure: 9, minute: 0, apres: soir, calendrier: cal)
    verifier(reglé.ligneReglee(maintenant: soir, calendrier: cal) == "Demain, jeudi \u{00B7} rien n\u{2019}a été collé", "bandeau : « Demain, jeudi · rien n'a été collé » (maquette)")
    verifier(ReveilIlot.salut(date(12, 9), calendrier: cal) == "Bonjour \u{00B7} jeudi 12 novembre" && ReveilIlot.salut(date(12, 19), calendrier: cal).hasPrefix("Bonsoir"),
             "alerte : « Bonjour · jeudi 12 novembre » (« Bonsoir » le soir)")
    let fichier = reglé.donnees()
    verifier(fichier.flatMap(ReveilIlot.depuis) == reglé && ReveilIlot.depuis(Data("{}".utf8)) == nil && ReveilIlot.depuis(Data("abîmé".utf8)) == nil
             && ReveilIlot.depuis(Data(#"{"heure":31,"minute":0,"sonnerie":"2026-11-12T08:00:00Z","repousse":false}"#.utf8)) == nil,
             "fichier : aller-retour ; abîmé ou heure impossible : rien (pas de plantage)")
    verifier(fichier.map { String(decoding: $0, as: UTF8.self) }.map { !$0.contains("/Users") } ?? false, "le fichier ne garde que l'heure (aucun chemin, aucun texte dicté)")

    groupe("Réveil : dans l'îlot")
    for (cam, barre) in [(179.0, 33.0), (185.0, 32.0), (200.0, 32.0)] {
        let p = TraceIlot.calculer(GeoIlot.valeurs(.reveilCompact, hauteurBarre: barre, demiCamera: cam / 2), demiCamera: cam / 2, barre: barre)
        verifier(p.bande - cam / 2 <= GeoIlot.aileMax && p.hauteur == barre, "réveil replié (caméra \(Int(cam))) : \(Int(p.bande - cam / 2)) pt dans la barre (≤ 66), rien sous la barre")
        let d = TraceIlot.calculer(GeoIlot.valeurs(.agendaDebut, hauteurBarre: barre, demiCamera: cam / 2, contenu: 360), demiCamera: cam / 2, barre: barre)
        verifier(d.bande - cam / 2 <= GeoIlot.aileMax, "rendez-vous qui commence (caméra \(Int(cam))) : \(Int(d.bande - cam / 2)) pt dans la barre")
    }
    verifier(VueIlot.reveilFini.estAlerte && VueIlot.reveilRegle.estBandeau && !VueIlot.reveilCompact.estBandeau, "le réveil qui sonne est une alerte ; « Réveil réglé », un bandeau")
    verifier(GeoIlot.profondeur(.agendaDebut) == 114 && GeoIlot.ajusteAuContenu(.agendaDebut), "rendez-vous qui commence : 114 pt sous la barre (la ligne, puis Rejoindre · Noter la réunion), la forme épouse son contenu")
    func etat(_ f: (inout EtatIlot) -> Void) -> ResolutionIlot { var e = EtatIlot(); f(&e); return ArbitrageIlot.resoudre(e) }
    verifier(etat { $0.reveil = true }.principal == .reveilCompact && etat { $0.reveil = true }.survol == .centre, "réveil seul : replié dans les ailes ; au survol, le Centre (sa case Réveil)")
    let avecVideo = etat { $0.reveil = true; $0.lecture = true }
    verifier(avecVideo.principal == .lectureCompact && avecVideo.pastille == .reveil, "une vidéo : elle prend l'îlot, le réveil passe dans la bulle")
    verifier(etat { $0.reveil = true; $0.minuteur = true }.principal == .minuteurCompact, "un minuteur : il passe avant le réveil")
    verifier(etat { $0.reveil = true; $0.alerte = .reveilFini }.principal == .reveilFini && ArbitrageIlot.etage(dictee: false, reunion: false, ecran: .reveilFini) == 3,
             "il sonne : l'alerte (étage des alertes, sous la dictée et la réunion)")
    verifier(CartesIlot.pile(survol: .centre) == [.centre, .outils, .accueil, .dictees], "les cartes au survol du réveil : Centre, Outils, accueil, Dictées")

    groupe("Calendrier : le 6e rond, la visio")
    typealias D = DispositionCentre
    verifier(D.maxRonds == 6 && D.parDefaut.contains(.calendrier) && ElementCentre.calendrier.genre == .rond && ElementCentre.calendrier.rawValue == "calendrier",
             "six ronds au plus ; le calendrier est un rond du Centre par défaut (identifiant « calendrier »)")
    let six = D([.micro, .dictee, .telechargements, .calendrier, .claude, .rappel, .minuteur, .etagere, .reunion])
    verifier(six.ronds().count == 6 && six.ronds() == [.micro, .dictee, .telechargements, .calendrier, .claude, .rappel], "les six ronds de la maquette")
    // un Centre rangé avant l'arrivée du calendrier (« Modifier ») le reçoit une fois, devant Claude Code
    let ancien = D(identifiants: ["micro", "telechargements", "claude", "minuteur", "etagere", "reunion"])
    let n1 = ancien.avecNouveautes(dejaProposees: [])
    verifier(n1.disposition.elements == [.micro, .telechargements, .calendrier, .claude, .minuteur, .etagere, .reunion] && n1.proposees == [.calendrier],
             "Centre rangé sans calendrier : il arrive devant Claude Code, une fois (proposé : retenu)")
    verifier(ancien.avecNouveautes(dejaProposees: ["calendrier"]).disposition == ancien && ancien.avecNouveautes(dejaProposees: ["calendrier"]).proposees.isEmpty,
             "déjà proposé (puis retiré par « Modifier ») : il ne revient pas")
    let sansClaude = D(identifiants: ["rappel", "micro", "etagere"]).avecNouveautes(dejaProposees: [])
    verifier(sansClaude.disposition.elements == [.rappel, .micro, .calendrier, .etagere], "sans Claude Code dans le Centre : après le dernier rond")
    let plein = D(identifiants: ["micro", "dictee", "telechargements", "claude", "rappel", "derniere-dictee"]).avecNouveautes(dejaProposees: [])
    verifier(!plein.disposition.elements.contains(.calendrier) && plein.proposees == [.calendrier], "rangée déjà pleine (6) : rien n'est poussé dehors, « Modifier » le proposera")
    verifier(D(identifiants: ["micro", "calendrier"]).avecNouveautes(dejaProposees: []).disposition.elements == [.micro, .calendrier], "déjà là : rien ne change")
    // au lancement (`relire`) : un Centre jamais rangé contient déjà le calendrier ; il est retenu comme donné, sinon retiré par
    // « Modifier » il reviendrait au lancement suivant
    let jamais = D.relire(identifiants: nil, dejaProposees: [])
    verifier(jamais.disposition == D() && jamais.aRetenir == ["calendrier"] && jamais.ajoutees.isEmpty,
             "Centre jamais rangé : le Centre par défaut (calendrier compris), le calendrier retenu comme donné, rien d'enregistré")
    let retire = D.relire(identifiants: ["micro", "dictee", "telechargements", "claude", "minuteur", "etagere", "reunion"], dejaProposees: Set(jamais.aRetenir ?? []))
    verifier(!retire.disposition.elements.contains(.calendrier) && retire.aRetenir == nil && retire.ajoutees.isEmpty,
             "puis retiré par « Modifier » : au lancement suivant il ne revient pas")
    verifier(D.relire(identifiants: nil, dejaProposees: ["calendrier"]).aRetenir == nil, "jamais rangé, déjà retenu : rien à écrire")
    let vieux = D.relire(identifiants: ["micro", "telechargements", "claude"], dejaProposees: [])
    verifier(vieux.disposition.elements == [.micro, .telechargements, .calendrier, .claude] && vieux.aRetenir == ["calendrier"] && vieux.ajoutees == [.calendrier],
             "rangé avant le calendrier : il arrive une fois (retenu, disposition à enregistrer)")
    let pleinR = D.relire(identifiants: ["micro", "dictee", "telechargements", "claude", "rappel", "derniere-dictee"], dejaProposees: [])
    verifier(pleinR.aRetenir == ["calendrier"] && pleinR.ajoutees.isEmpty, "rangée pleine : retenu, rien d'ajouté ni d'enregistré")
    let p2 = D.plan(ronds: true, cases: true, bande: true, nomsSurDeuxLignes: true)
    verifier(p2.profondeur == GeoIlot.profondeurCentre + D.ligneNom && p2.hauts[.cases] == 158 + D.ligneNom, "un nom sur deux lignes : la rangée des ronds s'allonge d'une ligne (14 pt), le reste descend")
    verifier(D.poidsCase(.minuteur) == 1.16 && D.poidsCase(.etagere) == 0.84, "cases côte à côte : Minuteur 1,16, Étagère 0,84 (maquette)")
    verifier(LienVisio.service(URL(string: "https://meet.google.com/abc-defg-hij")!) == "Google Meet" && LienVisio.service(URL(string: "https://us02web.zoom.us/j/123")!) == "Zoom"
             && LienVisio.service(URL(string: "https://teams.microsoft.com/l/meetup-join/x")!) == "Teams" && LienVisio.service(URL(string: "https://whereby.com/salle")!) == "Whereby"
             && LienVisio.service(URL(string: "https://visio.exemple.fr/x")!) == "Visio", "« Maintenant · Google Meet » : Meet, Zoom, Teams, Whereby ; sinon « Visio »")
    verifier(LienVisio.estAutorise(URL(string: "https://us02web.zoom.us/j/123")!) && LienVisio.estAutorise(URL(string: "https://teams.microsoft.com/l/meetup-join/x")!)
             && !LienVisio.estAutorise(URL(string: "http://meet.google.com/abc")!) && !LienVisio.estAutorise(URL(string: "https://meet.google.com.piege.fr/abc")!),
             "« Rejoindre » n'ouvre que des liens https vers Meet, Zoom, Teams… (jamais http, jamais un faux domaine)")
}
