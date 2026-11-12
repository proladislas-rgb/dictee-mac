import Foundation
import DicteeCore

// Contrôles de l'usage de Groq et du relais sur le Mac (DicteeCore/UsageGroq.swift) : l'heure est fabriquée, aucun réseau, aucun micro.
func controlesGroq() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    // le 12/11/2026 à 14:00, heure de Paris
    let t0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 0))!
    let large = "whisper-large-v3", turbo = "whisper-large-v3-turbo"
    func entetes(_ d: [String: String]) -> (String) -> String? { { cle in d.first { $0.key.lowercased() == cle.lowercased() }?.value } }

    groupe("Groq : limites et comptage")
    verifier(LimitesWhisper.gratuit.secondesJour == 28_800 && LimitesWhisper.gratuit.secondesHeure == 7200
             && LimitesWhisper.gratuit.requetesJour == 2000 && LimitesWhisper.gratuit.requetesMinute == 20, "limites gratuites de la doc : 20/min, 2 000/jour, 7 200 s/h, 28 800 s/jour")
    do {
        var c = CompteurGroq()
        c.noterEnvoi(secondesAudio: 3.2, modele: large, a: t0)
        verifier(c.secondes(modele: large, fenetre: 3600, a: t0) == 10, "une requête de 3,2 s compte 10 s (minimum facturé par Groq)")
        c.noterEnvoi(secondesAudio: 25, modele: large, a: t0.addingTimeInterval(60))
        verifier(c.secondes(modele: large, fenetre: 3600, a: t0.addingTimeInterval(61)) == 35, "25 s comptent 25 s")
        c.noterEnvoi(secondesAudio: 12, modele: turbo, a: t0.addingTimeInterval(62))
        verifier(c.secondes(modele: large, fenetre: 86_400, a: t0.addingTimeInterval(63)) == 35 && c.secondes(modele: turbo, fenetre: 86_400, a: t0.addingTimeInterval(63)) == 12,
                 "chaque modèle est compté à part")
        let b = c.bilan(modele: large, a: t0.addingTimeInterval(3700))
        verifier(b.secondesHeure == 0 && b.secondesJour == 35, "au-delà d'une heure : sorti de l'heure, toujours dans la journée")
        let apres = c.bilan(modele: large, a: t0.addingTimeInterval(86_400 + 120))
        verifier(apres.secondesJour == 0, "au-delà de 24 h : oublié")
        var e = c; e.elaguer(a: t0.addingTimeInterval(86_400 + 120))
        verifier(e.envois.isEmpty, "élagage : rien de plus vieux que 24 h n'est gardé")
        let d = c.donnees()
        verifier(d.flatMap(CompteurGroq.depuis) == c, "fichier local : aller-retour JSON")
        verifier(CompteurGroq.depuis(Data("abîmé".utf8)) == nil, "fichier abîmé : nil, pas de plantage")
    }

    groupe("Groq : en-têtes et 429")
    do {
        var c = CompteurGroq()
        c.noterEnvoi(secondesAudio: 5, modele: large, a: t0)
        c.noterReponse(modele: large, statut: 200, entete: entetes(["X-RateLimit-Limit-Requests": "2000", "x-ratelimit-remaining-requests": "1940"]), messageErreur: nil, a: t0)
        let b = c.bilan(modele: large, a: t0)
        verifier(b.requetesRestantes == 1940 && b.requetesLimite == 2000, "remaining/limit-requests lus (sans casse) : 1 940 sur 2 000")
        verifier(c.bilan(modele: large, a: t0.addingTimeInterval(3601)).requetesRestantes == nil, "marge des requêtes vieille d'une heure : plus crue")
        c.noterReponse(modele: large, statut: 429, entete: entetes(["retry-after": "3600"]),
                       messageErreur: "Rate limit reached for model `whisper-large-v3` in organization `org_x` service tier `on_demand` on seconds of audio per hour (ASH): Limit 7200, Used 7195, Requested 10. Please try again in 1h.",
                       a: t0.addingTimeInterval(10))
        let p = c.bilan(modele: large, a: t0.addingTimeInterval(20))
        verifier(p.niveau == .epuise && p.pauseJusqua == t0.addingTimeInterval(3610), "429 : en pause jusqu'à maintenant + retry-after")
        verifier(p.cause == .audioHeure && p.secondesHeure == 7195, "la limite nommée (ASH) et ce que Groq a compté (Used 7195) sont repris")
        verifier(c.bilan(modele: large, a: t0.addingTimeInterval(3611)).niveau != .epuise, "la pause passée : plus en pause")
        c.noterReponse(modele: large, statut: 200, entete: entetes([:]), messageErreur: nil, a: t0.addingTimeInterval(30))
        verifier(c.bilan(modele: large, a: t0.addingTimeInterval(31)).pauseJusqua == nil, "une réponse 200 lève la pause")
        verifier(CauseLimite.depuis(message: "… on requests per day (RPD): Limit 2000, Used 2000") == .requetesJour, "RPD reconnu")
        verifier(CauseLimite.depuis(message: "… seconds of audio per day (ASD): Limit 28800") == .audioJour, "ASD reconnu")
        verifier(CauseLimite.depuis(message: "… requests per minute (RPM)") == .requetesMinute, "RPM reconnu")
        verifier(CauseLimite.depuis(message: "inattendu") == .autre, "message inconnu : autre")
        var s = CompteurGroq()
        s.noterReponse(modele: large, statut: 429, entete: entetes(["retry-after": "2m30s"]), messageErreur: nil, a: t0)
        verifier(s.bilan(modele: large, a: t0).pauseJusqua == t0.addingTimeInterval(150), "retry-after « 2m30s » lu comme 150 s")
    }

    groupe("Groq : marge et niveau")
    do {
        var c = CompteurGroq()
        // 400 min ce matin (de 8 h à 12 h 30, hors de l'heure en cours)
        for i in 0..<400 { c.noterEnvoi(secondesAudio: 60, modele: large, a: t0.addingTimeInterval(-6 * 3600 + Double(i) * 40)) }
        let b = c.bilan(modele: large, a: t0)
        verifier(b.minutesJour == 400 && b.limiteMinutesJour == 480, "400 min sur 480")
        verifier(b.niveau == .ok, "16 % : tout va bien")
        for i in 0..<20 { c.noterEnvoi(secondesAudio: 60, modele: large, a: t0.addingTimeInterval(-3000 + Double(i))) }
        let bas = c.bilan(modele: large, a: t0)
        verifier(bas.niveau == .bas && bas.limitant == .jour, "420 min sur 480 (12 %) : bas, limité par le jour")
        let e = EtatGroq.calculer(c, modele: large, secours: turbo, a: t0)
        verifier(TexteGroq.ligne(e, a: t0, calendrier: cal) == "Il te reste 1 h de dictée gratuite aujourd\u{2019}hui", "ligne : « Il te reste 1 h de dictée gratuite aujourd'hui » (\(TexteGroq.ligne(e, a: t0, calendrier: cal)))")
        verifier(TexteGroq.court(e, a: t0, calendrier: cal) == "Reste 1 h", "sous le rond : « Reste 1 h »")
        var h = CompteurGroq()
        for i in 0..<115 { h.noterEnvoi(secondesAudio: 60, modele: large, a: t0.addingTimeInterval(-3000 + Double(i))) }
        let bh = h.bilan(modele: large, a: t0)
        verifier(bh.niveau == .bas && bh.limitant == .heure, "115 min dans l'heure : bas, limité par l'heure")
        verifier(AlerteGroq().basDit == false, "rien de dit au départ")
        var a = AlerteGroq()
        let annonce = a.apres(EtatGroq.calculer(h, modele: large, secours: nil, a: t0), a: t0, calendrier: cal)
        verifier(annonce?.titre == "Plus que 5 min de dictée gratuite cette heure" && annonce?.sousTitre == "Ensuite, le Mac écrit à ta place", "annonce de l'heure : « Plus que 5 min de dictée gratuite cette heure »")
        let eh = EtatGroq.calculer(h, modele: large, secours: nil, a: t0)
        verifier(TexteGroq.court(eh, a: t0, calendrier: cal) == "Reste 5 min" && TexteGroq.detail(eh, a: t0, calendrier: cal).titre == "Plus que 5 min cette heure", "l'heure qui manque : « Reste 5 min », « Plus que 5 min cette heure »")
        var plein = CompteurGroq()
        for i in 0..<121 { plein.noterEnvoi(secondesAudio: 60, modele: large, a: t0.addingTimeInterval(-3000 + Double(i))) }
        let bp = plein.bilan(modele: large, a: t0)
        verifier(bp.niveau == .epuise && bp.pauseJusqua == t0.addingTimeInterval(-3000 + 3600), "nos comptes au bout de l'heure sans 429 : pause estimée jusqu'à la sortie du plus ancien envoi")
    }

    groupe("Groq : état avec le turbo en relais")
    do {
        var c = CompteurGroq()
        c.noterEnvoi(secondesAudio: 30, modele: large, a: t0)
        let ok = EtatGroq.calculer(c, modele: large, secours: turbo, a: t0)
        verifier(ok.niveau == .ok && TexteGroq.ligne(ok, a: t0, calendrier: cal) == "Il te reste 7 h 59 de dictée gratuite aujourd\u{2019}hui", "« Il te reste 7 h 59 de dictée gratuite aujourd'hui »")
        verifier(TexteGroq.court(ok, a: t0, calendrier: cal) == "Reste 7 h 59", "sous le rond : « Reste 7 h 59 » (la journée, pas l'heure, tant que tout va bien)")
        verifier(TexteGroq.duree(0) == "0 min" && TexteGroq.duree(42) == "42 min" && TexteGroq.duree(60) == "1 h" && TexteGroq.duree(438) == "7 h 18" && TexteGroq.duree(65) == "1 h 05", "durées : 42 min, 1 h, 7 h 18, 1 h 05")
        c.noterReponse(modele: large, statut: 429, entete: entetes(["retry-after": "3600"]), messageErreur: "(ASD)", a: t0)
        let relais = EtatGroq.calculer(c, modele: large, secours: turbo, a: t0)
        verifier(relais.relaisTurbo && relais.niveau == .bas && relais.pauseJusqua == nil, "large-v3 en pause, le turbo répond : bas, pas en pause")
        verifier(TexteGroq.court(relais, a: t0, calendrier: cal) == "Relais", "sous le rond : « Relais »")
        let seul = EtatGroq.calculer(c, modele: large, secours: nil, a: t0)
        verifier(seul.niveau == .epuise, "sans relais (modèle turbo réglé, ou large-v3 sans secours) : en pause")
        c.noterReponse(modele: turbo, statut: 429, entete: entetes(["retry-after": "1800"]), messageErreur: nil, a: t0)
        let fini = EtatGroq.calculer(c, modele: large, secours: turbo, a: t0)
        verifier(fini.niveau == .epuise && fini.pauseJusqua == t0.addingTimeInterval(1800), "les deux en pause : Groq répondra au premier libéré (14:30)")
        verifier(TexteGroq.ligne(fini, a: t0, calendrier: cal).hasSuffix("en pause jusqu\u{2019}à 14:30"), "« … en pause jusqu'à 14:30 »")
        verifier(TexteGroq.court(fini, a: t0, calendrier: cal) == "Pause 14:30" && fini.utilise == 1, "sous le rond : « Pause 14:30 », anneau plein")
        verifier(TexteGroq.quand(t0.addingTimeInterval(12 * 3600), a: t0, calendrier: cal) == "demain 2:00", "une pause qui finit demain : « demain 2:00 »")
        verifier(TexteGroq.milliers(1940) == "1\u{202F}940" && TexteGroq.milliers(940) == "940", "1 940 avec une espace fine")
        let d = TexteGroq.detail(ok, a: t0, calendrier: cal)
        verifier(d.titre == "Il te reste 7 h 59 aujourd\u{2019}hui" && d.sousTitre == "De dictée gratuite avec Groq (8 h par jour)", "détail : « Il te reste 7 h 59 aujourd'hui » · « De dictée gratuite avec Groq (8 h par jour) »")
        verifier(TexteGroq.note(ok) == "Groq écrit ta voix gratuitement : 8 h par jour, 2 h par heure au plus. Déjà dicté sur 24 h : 1 min.", "note des Réglages")
    }

    groupe("Groq : annonces (une fois par passage)")
    do {
        var a = AlerteGroq()
        var c = CompteurGroq()
        verifier(a.apres(EtatGroq.calculer(c, modele: large, secours: nil, a: t0), a: t0, calendrier: cal) == nil, "tout va bien : rien")
        for i in 0..<420 { c.noterEnvoi(secondesAudio: 60, modele: large, a: t0.addingTimeInterval(-7 * 3600 + Double(i) * 30)) }
        let bas = a.apres(EtatGroq.calculer(c, modele: large, secours: nil, a: t0), a: t0, calendrier: cal)
        verifier(bas == .bas(titre: "Plus que 1 h de dictée gratuite aujourd\u{2019}hui", sousTitre: "Ensuite, le Mac écrit à ta place"), "sous 15 % : « Plus que 1 h de dictée gratuite aujourd'hui · Ensuite, le Mac écrit à ta place » (\(String(describing: bas)))")
        c.noterEnvoi(secondesAudio: 20, modele: large, a: t0)
        verifier(a.apres(EtatGroq.calculer(c, modele: large, secours: nil, a: t0), a: t0, calendrier: cal) == nil, "toujours bas : pas répété")
        c.noterReponse(modele: large, statut: 429, entete: entetes(["retry-after": "3600"]), messageErreur: nil, a: t0)
        let pause = a.apres(EtatGroq.calculer(c, modele: large, secours: nil, a: t0), a: t0, calendrier: cal)
        verifier(pause == .epuise(titre: "Dictée gratuite en pause jusqu\u{2019}à 15:00", sousTitre: "Le Mac écrit à ta place"), "limite atteinte : « Dictée gratuite en pause jusqu'à 15:00 · Le Mac écrit à ta place »")
        c.noterReponse(modele: large, statut: 429, entete: entetes(["retry-after": "3570"]), messageErreur: nil, a: t0.addingTimeInterval(30))
        verifier(a.apres(EtatGroq.calculer(c, modele: large, secours: nil, a: t0.addingTimeInterval(30)), a: t0.addingTimeInterval(30), calendrier: cal) == nil,
                 "la même pause redite par une autre 429 : pas d'annonce de plus")
        let apres = t0.addingTimeInterval(86_400 + 3700)
        c.noterReponse(modele: large, statut: 200, entete: entetes([:]), messageErreur: nil, a: apres)
        verifier(a.apres(EtatGroq.calculer(c, modele: large, secours: nil, a: apres), a: apres, calendrier: cal) == nil && !a.basDit, "de nouveau tout va bien : rien, et tout est oublié")
        var b = AlerteGroq()
        var r = CompteurGroq()
        r.noterReponse(modele: large, statut: 429, entete: entetes(["retry-after": "600"]), messageErreur: nil, a: t0)
        let turboAnnonce = b.apres(EtatGroq.calculer(r, modele: large, secours: turbo, a: t0), a: t0, calendrier: cal)
        verifier(turboAnnonce == .bas(titre: "Dictée précise en pause jusqu\u{2019}à 14:10", sousTitre: "La dictée rapide prend le relais"), "large-v3 en pause, turbo en relais : annoncé une fois")
    }

    groupe("Relais de la dictée sur le Mac")
    do {
        verifier(RelaisDictee.essayerGroq(cleDisponible: true), "chaque dictée commence par Groq (la suivante retente Groq après un relais)")
        verifier(!RelaisDictee.essayerGroq(cleDisponible: false), "sans clé : directement le Mac")
        verifier(EchecGroq.depuis(codeHTTP: 429, reseau: false, pasDeCle: false) == .limite, "429 : limite")
        verifier(EchecGroq.depuis(codeHTTP: 503, reseau: false, pasDeCle: false) == .panne, "503 : panne")
        verifier(EchecGroq.depuis(codeHTTP: nil, reseau: true, pasDeCle: false) == .reseau, "réseau coupé")
        verifier(EchecGroq.depuis(codeHTTP: nil, reseau: false, pasDeCle: true) == .pasDeCle, "clé absente")
        verifier(RelaisDictee.utiliserLeMac(echec: .reseau, relaisPermis: true, texteDuMac: "Bonjour"), "Groq en échec, relais permis, texte : le Mac")
        verifier(!RelaisDictee.utiliserLeMac(echec: nil, relaisPermis: true, texteDuMac: "Bonjour"), "Groq a répondu : jamais le Mac")
        verifier(!RelaisDictee.utiliserLeMac(echec: .reseau, relaisPermis: false, texteDuMac: "Bonjour"), "relais éteint dans les Réglages : rien")
        verifier(!RelaisDictee.utiliserLeMac(echec: .reseau, relaisPermis: true, texteDuMac: "  "), "le Mac n'a rien entendu : rien")
        var s = RelaisDictee.Suivi()
        verifier(s.apresRelais(.reseau, pauseJusqua: nil, a: t0, calendrier: cal) == .bandeau(titre: "Dicté sur le Mac", sousTitre: "Pas de réseau"), "1er relais : « Dicté sur le Mac · Pas de réseau »")
        verifier(s.apresRelais(.reseau, pauseJusqua: nil, a: t0, calendrier: cal) == .ailes, "relais suivant, même raison : « Mac » dans les ailes seulement")
        verifier(s.apresRelais(.panne, pauseJusqua: nil, a: t0, calendrier: cal) == .bandeau(titre: "Dicté sur le Mac", sousTitre: "Groq ne répond pas"), "autre raison : de nouveau dite")
        s.apresGroq()
        verifier(s.apresRelais(.panne, pauseJusqua: nil, a: t0, calendrier: cal) != .ailes, "Groq a répondu entre-temps : le relais suivant se redit")
        verifier(s.apresRelais(.limite, pauseJusqua: t0.addingTimeInterval(3600), a: t0, calendrier: cal) == .ailes, "limite : les ailes seules (l'annonce de la limite dit déjà tout)")
        verifier(RelaisDictee.raison(.limite, pauseJusqua: t0.addingTimeInterval(3600), a: t0, calendrier: cal) == "Dictée gratuite en pause jusqu\u{2019}à 15:00", "raison de la limite : « Dictée gratuite en pause jusqu'à 15:00 »")
    }

    groupe("Page Outils : la jauge de Groq")
    do {
        verifier(DispositionCentre.parDefautOutils.contains(.groq) && ElementCentre.groq.page == .outils && ElementCentre.groq.genre == .rond, "Groq : un rond de la page Outils, montré par défaut")
        verifier(DispositionCentre(DispositionCentre.parDefautOutils, page: .outils).ronds().count <= DispositionCentre.maxRonds, "les ronds des Outils tiennent (5 au plus)")
        verifier(ElementCentre.groq.aide.count <= ElementCentre.aideMax, "aide au survol assez courte")
        // le mécanisme des nouveautés est celui du calendrier (DispositionCentre.relire), page par page
        let jamais = DispositionCentre.relire(identifiants: nil, dejaProposees: [], page: .outils)
        verifier(jamais.disposition.elements == DispositionCentre.parDefautOutils && jamais.ajoutees.isEmpty && jamais.aRetenir == ["groq"],
                 "jamais rangée : rien à toucher (le défaut montre déjà Groq), Groq retenu comme donné")
        let rangee = DispositionCentre.relire(identifiants: ["notes", "eveil", "note-rapide"], dejaProposees: [], page: .outils)
        verifier(rangee.disposition.identifiants == ["notes", "eveil", "groq", "note-rapide"] && rangee.ajoutees == [.groq],
                 "déjà rangée : Groq ajouté une fois, à la fin des ronds (\(rangee.disposition.identifiants))")
        let retiree = DispositionCentre.relire(identifiants: ["notes", "eveil"], dejaProposees: ["groq"], page: .outils)
        verifier(retiree.disposition.identifiants == ["notes", "eveil"] && retiree.aRetenir == nil, "déjà proposé puis retiré par Hugues : on ne le remet pas")
        let centre = DispositionCentre.relire(identifiants: ["micro"], dejaProposees: ["calendrier", "concentration"], page: .centre)
        verifier(centre.disposition.identifiants == ["micro"] && centre.aRetenir == nil, "le Centre n'est pas touché par Groq")
        let outilsSansCalendrier = DispositionCentre.relire(identifiants: ["notes"], dejaProposees: ["groq"], page: .outils)
        verifier(outilsSansCalendrier.aRetenir == nil && !outilsSansCalendrier.disposition.elements.contains(.calendrier), "les Outils ne reçoivent pas le calendrier")
    }
}
