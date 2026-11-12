import Foundation
import DicteeCore

// Contrôles de logique pure : `swift run DicteeControles`. Code de sortie 1 si un contrôle échoue.
nonisolated(unsafe) var echecs = 0
nonisolated(unsafe) var total = 0
func verifier(_ condition: Bool, _ nom: String, file: String = #file, line: Int = #line) {
    total += 1
    if condition { print("  ok   \(nom)") } else { echecs += 1; print("  ÉCHEC \(nom)  (ligne \(line))") }
}
func groupe(_ nom: String) { print("\n\(nom)") }

groupe("EnvFile")
verifier(EnvFile.value(for: "GROQ_API_KEY", in: "GROQ_API_KEY=abc123\n") == "abc123", "ligne simple")
verifier(EnvFile.value(for: "GROQ_API_KEY", in: "GROQ_API_KEY=\"abc123\"\n") == "abc123", "guillemets doubles retirés")
verifier(EnvFile.value(for: "GROQ_API_KEY", in: "export GROQ_API_KEY='abc123'\r\n") == "abc123", "export + guillemets simples + fin de ligne Windows")
verifier(EnvFile.value(for: "GROQ_API_KEY", in: "# commentaire\nAUTRE=1\n") == nil, "clé absente")
verifier(EnvFile.value(for: "GROQ_API_KEY", in: "GROQ_API_KEY=\n") == nil, "valeur vide")

groupe("Historique")
do {
    var h = Historique()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    for i in 0..<5 { h.ajouter(EntreeHistorique(date: t0.addingTimeInterval(Double(i)), appNom: i % 2 == 0 ? "Mail" : "Notes", texte: "Dictée numéro \(i)"), limite: 3) }
    verifier(h.entrees.count == 3, "limite respectée (3 gardées sur 5)")
    verifier(h.entrees.first?.texte == "Dictée numéro 4", "la plus récente en tête")
    verifier(h.entrees.last?.texte == "Dictée numéro 2", "les plus anciennes sont retirées")
    verifier(h.filtrer("DICTEE 3").map(\.texte) == ["Dictée numéro 3"], "recherche sans casse ni accents")
    verifier(h.filtrer("mail").count == 2, "recherche aussi sur l'app de destination")
    verifier(h.filtrer("  ").count == 3, "recherche vide : tout")
    verifier(h.filtrer("introuvable").isEmpty, "aucun résultat")
    let donnees = h.donnees()
    verifier(donnees.flatMap { Historique.depuis($0) } == h, "enregistrement JSON aller-retour")
    verifier(Historique.depuis(Data("pas du json".utf8)) == nil, "fichier abîmé : nil, pas de plantage")
    var e = h; e.effacer(); verifier(e.estVide, "effacer vide tout")
    let id = h.entrees[1].id; var s = h; s.supprimer(id: id); verifier(s.entrees.count == 2 && !s.entrees.contains { $0.id == id }, "supprimer une entrée")
    var r = Historique(); r.ajouter(EntreeHistorique(texte: "échec", insere: false, raison: "champ protégé"))
    verifier(r.entrees[0].insere == false && r.entrees[0].texte == "échec", "texte gardé même si l'insertion a échoué")
}
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let maintenant = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15))!
    func a(_ jour: Int, _ heure: Int, mois: Int = 11, annee: Int = 2026) -> EntreeHistorique {
        EntreeHistorique(date: cal.date(from: DateComponents(year: annee, month: mois, day: jour, hour: heure))!, texte: "x")
    }
    let g = Historique.groupes([a(9, 14), a(9, 10), a(8, 18), a(3, 9), a(30, 9, mois: 12, annee: 2025)], maintenant: maintenant, calendrier: cal)
    verifier(g.map(\.titre).prefix(2) == ["Aujourd\u{2019}hui", "Hier"], "groupes : Aujourd'hui puis Hier")
    verifier(g[0].entrees.count == 2, "deux dictées aujourd'hui dans le même groupe")
    verifier(g.count == 4, "un groupe par jour")
    verifier(g[2].titre.lowercased().contains("novembre") && !g[2].titre.contains("2026"), "jour plus ancien : date sans année")
    verifier(g[3].titre.contains("2025"), "autre année : avec l'année")
}
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let jour = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15))!
    func e(_ j: Int, _ texte: String) -> EntreeHistorique { EntreeHistorique(date: cal.date(from: DateComponents(year: 2026, month: 11, day: j, hour: 10))!, texte: texte) }
    let h = Historique(entrees: [e(9, "On se voit mercredi pour parler du devis."), e(9, "J\u{2019}arrive dans dix minutes."), e(8, "Hier, trois mots")])
    verifier(Historique.compterMots("  Bonjour   Madame\nMartin ") == 3 && Historique.compterMots("") == 0, "compter les mots : espaces multiples, retours à la ligne, texte vide")
    verifier(h.motsLe(jour, calendrier: cal) == 8 + 4, "mots du jour : seulement les dictées d'aujourd'hui")
    verifier(Historique.groupes(h.entrees, maintenant: jour, calendrier: cal).first?.jour == h.entrees.first?.date, "groupe : son jour = celui de sa première dictée")
}
verifier(Selection.deplacer(0, de: 1, sur: 3) == 1 && Selection.deplacer(2, de: 1, sur: 3) == 0 && Selection.deplacer(0, de: -1, sur: 3) == 2, "sélection ↑↓ avec retour aux extrémités")
verifier(Selection.deplacer(5, de: 0, sur: 0) == 0 && Selection.deplacer(9, de: 1, sur: 3) == 0, "sélection : liste vide / indice hors limites")

groupe("RaccourcisVocaux")
do {
    let rs = [RaccourciVocal(expression: "ma signature", texte: "Hugues-Henri Delpit"),
              RaccourciVocal(expression: "mon mail", texte: "bonjour@exemple.fr"),
              RaccourciVocal(expression: "mes dispos", texte: "Mardi ou jeudi après-midi"),
              RaccourciVocal(expression: "mon mail pro", texte: "pro@exemple.fr")]
    verifier(RaccourcisVocaux.appliquer("Ma signature.", raccourcis: rs) == "Hugues-Henri Delpit", "dictée réduite au raccourci : texte exact, sans point final")
    verifier(RaccourcisVocaux.appliquer("Voici mon mail, merci.", raccourcis: rs) == "Voici bonjour@exemple.fr, merci.", "au milieu d'une phrase : ponctuation gardée")
    verifier(RaccourcisVocaux.appliquer("Envoie à mon mail pro demain.", raccourcis: rs) == "Envoie à pro@exemple.fr demain.", "le plus long raccourci gagne")
    verifier(RaccourcisVocaux.appliquer("MES DISPOS", raccourcis: rs) == "Mardi ou jeudi après-midi", "sans tenir compte des majuscules")
    verifier(RaccourcisVocaux.appliquer("mes dispos sont bonnes, ma signature", raccourcis: rs) == "Mardi ou jeudi après-midi sont bonnes, Hugues-Henri Delpit", "plusieurs raccourcis dans une phrase")
    verifier(RaccourcisVocaux.appliquer("Le mail est parti.", raccourcis: rs) == "Le mail est parti.", "mot seul : pas de remplacement")
    verifier(RaccourcisVocaux.appliquer("mon maillot", raccourcis: rs) == "mon maillot", "mots entiers seulement")
    verifier(RaccourcisVocaux.appliquer("rien à remplacer", raccourcis: []) == "rien à remplacer", "aucun raccourci : texte intact")
    let apo = [RaccourciVocal(expression: "l'adresse", texte: "12 rue des Lilas")]
    verifier(RaccourcisVocaux.appliquer("Voici l’adresse.", raccourcis: apo) == "Voici 12 rue des Lilas.", "apostrophe courbe reconnue")
    let acc = [RaccourciVocal(expression: "à bientôt", texte: "À très vite, Hugues")]
    verifier(RaccourcisVocaux.appliquer("a bientot", raccourcis: acc) == "À très vite, Hugues", "sans tenir compte des accents")
    verifier(RaccourcisVocaux.appliquer("Merci. Ma signature", raccourcis: rs) == "Merci. Hugues-Henri Delpit", "raccourci en fin de dictée")
}
groupe("ListeDeMots")
verifier(ListeDeMots.ajouter("Sillonia", a: ["Ladislas"]) == .ajoute(["Ladislas", "Sillonia"]), "ajout d'un mot")
verifier(ListeDeMots.ajouter("  ladislas ", a: ["Ladislas"]) == .dejaPresent, "mot déjà enregistré (casse et espaces)")
verifier(ListeDeMots.ajouter("Élodie", a: ["elodie"]) == .dejaPresent, "mot déjà enregistré (accents)")
verifier(ListeDeMots.ajouter("   ", a: []) == .vide, "mot vide refusé")
verifier(ListeDeMots.retirer("SILLONIA", de: ["Ladislas", "Sillonia"]) == ["Ladislas"], "retrait d'un mot")

groupe("PropositionsMots")
do {
    var p = PropositionsMots()
    verifier(p.proposer("Premium CI", motsConnus: ["Ladislas"]), "nouvelle proposition")
    verifier(!p.proposer("premium ci", motsConnus: []), "pas deux fois la même proposition")
    verifier(!p.proposer("ladislas", motsConnus: ["Ladislas"]), "pas de proposition pour un mot déjà dans la liste")
    verifier(p.enAttente == ["Premium CI"], "la proposition attend (rien n'est ajouté tout seul)")
    p.ignorer("Premium CI")
    verifier(p.enAttente.isEmpty && !p.proposer("Premium CI", motsConnus: []), "mot ignoré : jamais reproposé")
    var q = PropositionsMots(); _ = q.proposer("Abidjan", motsConnus: [])
    verifier(q.accepter("Abidjan") == "Abidjan" && q.enAttente.isEmpty, "accepter retire la proposition")
}

groupe("TextPreview")
verifier(TextPreview.preview("court") == "court", "texte court intact")
verifier(TextPreview.preview(String(repeating: "a", count: 100)).count == 31, "coupé à 30 caractères + …")
verifier(!TextPreview.preview("a\nb").contains("\n"), "retours à la ligne aplatis")

groupe("FnGestureDetector")
func jouer(_ scenario: [(FnEvent, Double)]) -> (actions: [[GestureAction]], swallow: [Bool]) {
    var d = FnGestureDetector()
    var a: [[GestureAction]] = [], w: [Bool] = []
    for (e, t) in scenario { let o = d.handle(e, at: t); a.append(o.actions); w.append(o.swallow) }
    return (a, w)
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 1.2)])
    verifier(r.actions == [[.begin(handsFree: false)], [.end]], "tenir 1,2 s : début puis fin")
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 0.1)])
    verifier(r.actions == [[.begin(handsFree: false)], [.cancel]], "appui court isolé : annulé en silence")
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 0.1), (.fnDown, 0.3), (.fnUp, 0.4)])
    verifier(r.actions == [[.begin(handsFree: false)], [.cancel], [.begin(handsFree: true)], []], "deux appuis courts : mains libres, le relâchement ne l'arrête pas")
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 0.1), (.fnDown, 0.3), (.fnUp, 0.4), (.fnDown, 5), (.fnUp, 5.1)])
    verifier(r.actions[4] == [.end] && r.actions[5] == [], "mains libres arrêté par un nouvel appui")
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 0.1), (.fnDown, 0.6), (.fnUp, 1.9)])
    verifier(r.actions[2] == [.begin(handsFree: false)] && r.actions[3] == [.end], "second appui trop tardif (0,5 s) : simple dictée tenue")
}
do {
    let r = jouer([(.fnDown, 0), (.otherKey, 0.5), (.fnUp, 1.0)])
    verifier(r.actions == [[.begin(handsFree: false)], [.cancel], []], "fn + autre touche : annulé")
}
do {
    var d = FnGestureDetector()
    _ = d.handle(.fnDown, at: 0); _ = d.handle(.otherKey, at: 0.5); _ = d.handle(.fnUp, at: 0.6)
    let o = d.handle(.fnDown, at: 0.7)
    verifier(o.actions == [.begin(handsFree: false)], "après une annulation, on peut redicter tout de suite (pas de faux double appui)")
}
do {
    let r = jouer([(.fnDown, 0), (.escape, 1), (.fnUp, 1.5)])
    verifier(r.actions == [[.begin(handsFree: false)], [.cancel], []] && r.swallow[1], "Échap en dictée : annule et est avalé")
}
do {
    let r = jouer([(.escape, 0)])
    verifier(r.actions == [[]] && !r.swallow[0], "Échap sans dictée : transmis à l'app")
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 0.1), (.fnDown, 0.3), (.fnUp, 0.4), (.escape, 2)])
    verifier(r.actions[4] == [.cancel] && r.swallow[4], "Échap en mains libres : annule")
}
do {
    let r = jouer([(.fnDown, 0), (.fnUp, 0.1), (.fnDown, 0.3), (.fnUp, 0.4), (.otherKey, 1)])
    verifier(r.actions[4] == [], "mains libres : taper une autre touche n'annule pas")
}
do {
    var d = FnGestureDetector()
    verifier(!d.isActive, "inactif au départ")
    _ = d.handle(.fnDown, at: 0)
    verifier(d.isActive, "actif pendant la dictée")
    _ = d.handle(.fnUp, at: 1)
    verifier(!d.isActive, "inactif après la fin")
}

groupe("EspacesIntelligents")
do {
    let mots = ["Ladislas", "Premium CI", "Abidjan"]
    func a(_ t: String, _ p: String?) -> String { EspacesIntelligents.adapter(t, precedent: p, mots: mots) }
    verifier(a("Ok, pas mal !", "ok") == " ok, pas mal !", "le cas du journal : « ok » puis « Ok, pas mal ! » → espace + minuscule")
    verifier(a("Pas mal, alors comment vas-tu aujourd'hui ?", "ok ok, pas mal !") == " Pas mal, alors comment vas-tu aujourd'hui ?", "après « ! » : espace, majuscule gardée")
    verifier(a("Bonjour", nil) == "Bonjour", "contexte inconnu : rien ne change")
    verifier(a("Bonjour", "") == "Bonjour", "début de champ : rien ne change")
    verifier(a("Bonjour", "Salut ") == "bonjour", "après une espace : pas de seconde espace, minuscule")
    verifier(a("Bonjour", "Salut.\n") == "Bonjour", "après un retour à la ligne : majuscule gardée, pas d'espace")
    verifier(a("Bonjour", "Salut.\n  ") == "Bonjour", "retour à la ligne puis espaces : début de phrase")
    verifier(a("merci", "Salut.") == " merci", "après un point : espace, texte intact")
    verifier(a("Merci", "Quoi ?") == " Merci", "après « ? » : majuscule gardée")
    verifier(a("Merci", "Quoi…") == " Merci", "après « … » : majuscule gardée")
    verifier(a("Il vient", "Il a dit « Oui. »") == " Il vient", "point suivi d'un guillemet fermant : fin de phrase")
    verifier(a("Il vient", "voici (") == "il vient", "après une parenthèse ouvrante : pas d'espace")
    verifier(a("texte", "il a dit «") == "texte", "après un guillemet ouvrant : pas d'espace")
    verifier(a("ami", "l'") == "ami", "après une apostrophe : pas d'espace")
    verifier(a("Il vient", "voici,") == " il vient", "après une virgule : espace et minuscule")
    verifier(a(", donc voilà", "ok") == ", donc voilà", "texte qui commence par une virgule : pas d'espace devant")
    verifier(a("Abidjan est prête", "on parle de") == " Abidjan est prête", "mot du dictionnaire : majuscule gardée")
    verifier(a("Premium CI est là", "chez") == " Premium CI est là", "entrée du dictionnaire de plusieurs mots : majuscule gardée")
    verifier(a("Ladislas arrive", "alors") == " Ladislas arrive", "nom du dictionnaire (en tête)")
    verifier(a("Ladislasse arrive", "alors") == " ladislasse arrive", "un mot qui ressemble seulement au dictionnaire est mis en minuscule")
    verifier(a("API disponible", "la") == " API disponible", "sigle : majuscules gardées")
    verifier(a("I think so", "well") == " I think so", "« I » anglais gardé")
    verifier(a("J'ai fini", "alors") == " j'ai fini", "élision : « J'ai » → « j'ai »")
    verifier(a("3 fois", "il y a") == " 3 fois", "chiffre : intact")
    verifier(a("\"Bonjour\" dit-il", "il a dit") == " \"bonjour\" dit-il", "guillemet droit en tête : la lettre suivante passe en minuscule")
    verifier(a("Premier point", "Liste :\n- ") == "Premier point", "après une puce de liste : phrase neuve")
    verifier(a("Suite", "Titre") == " suite", "après un mot sans ponctuation : suite de phrase")
    verifier(a("", "ok") == "", "texte vide")
    verifier(EspacesIntelligents.finDePhrase(precedent: nil) == nil, "finDePhrase : inconnu")
    verifier(EspacesIntelligents.finDePhrase(precedent: "fait.") == true && EspacesIntelligents.finDePhrase(precedent: "fait") == false, "finDePhrase : point / pas de point")
}
do {
    let m = MemoireInsertion(appId: "com.apple.Terminal", queue: "ok", instant: 100, frappes: 5)
    verifier(m.precedent(appId: "com.apple.Terminal", instant: 130, frappes: 5) == "ok", "mémoire : même app, 30 s, aucune frappe → curseur après la dernière insertion")
    verifier(m.precedent(appId: "com.apple.Terminal", instant: 130, frappes: 6) == nil, "mémoire : une touche tapée depuis → inconnu")
    verifier(m.precedent(appId: "com.apple.Terminal", instant: 221, frappes: 5) == nil, "mémoire : plus de 2 minutes → inconnu")
    verifier(m.precedent(appId: "com.apple.Notes", instant: 130, frappes: 5) == nil, "mémoire : autre app → inconnu")
    verifier(m.precedent(appId: nil, instant: 130, frappes: 5) == nil, "mémoire : app inconnue → inconnu")
    verifier(MemoireInsertion.queue(de: String(repeating: "a", count: 500)).count == 200, "mémoire : 200 derniers caractères")
}

groupe("RemiseAuPropre")
do {
    func ctx(_ b: String?, _ r: String? = nil, _ t: String? = nil) -> ContexteMiseEnForme { RemiseAuPropre.contexte(bundleID: b, role: r, titreFenetre: t) }
    verifier(ctx("com.apple.Terminal") == .terminal && ctx("com.googlecode.iterm2") == .terminal, "contexte : terminaux")
    verifier(ctx("com.google.Chrome", "AXTextField") == .recherche && ctx("com.apple.Safari", "AXTextField") == .recherche, "contexte : barre d'adresse / recherche (AXTextField)")
    verifier(ctx("com.google.Chrome", "AXTextArea", "Boîte de réception - Gmail") == .courriel, "contexte : Gmail reconnu par le titre de la fenêtre")
    verifier(ctx("com.google.Chrome", "AXWebArea", "Un site") == .general, "contexte : page web ordinaire")
    verifier(ctx("com.apple.mail") == .courriel && ctx("com.microsoft.Outlook") == .courriel, "contexte : Mail, Outlook")
    verifier(ctx("com.apple.MobileSMS") == .messagerie && ctx("com.tinyspeck.slackmacgap") == .messagerie && ctx("com.hnc.Discord") == .messagerie, "contexte : Messages, Slack, Discord")
    verifier(ctx("com.apple.Notes") == .notes && ctx("com.apple.iWork.Pages") == .notes && ctx("com.microsoft.Word") == .notes, "contexte : Notes, Pages, Word")
    verifier(ctx("com.anthropic.claudefordesktop") == .assistantIA && ctx("com.openai.chat") == .assistantIA, "contexte : Claude, ChatGPT")
    verifier(ctx(nil) == .general && ctx("com.example.autre") == .general, "contexte : autre app")

    func utile(_ s: String) -> Bool { RemiseAuPropre.analyser(s).utile }
    verifier(!utile("Bonjour tout le monde"), "utilité : phrase courte et propre → inutile")
    verifier(utile("je voulais te demander si tu es libre demain après-midi"), "utilité : plus de 6 mots → utile")
    verifier(utile("euh bonjour"), "utilité : « euh » → utile")
    verifier(utile("E bonjour"), "utilité : « E » isolé → utile")
    verifier(utile("je je viens"), "utilité : bégaiement → utile")
    verifier(utile("mardi non plutôt mercredi"), "utilité : correction dite → utile")
    verifier(utile("bonjour à la ligne merci"), "utilité : commande « à la ligne » → utile")
    verifier(utile("merci point"), "utilité : « point » en fin de dictée → utile")
    verifier(!utile("un point important"), "utilité : « point » ordinaire → inutile")
    verifier(!utile("merci beaucoup"), "utilité : deux mots propres → inutile")

    func ok(_ e: String, _ s: String) -> Bool { if case .accepte = RemiseAuPropre.verifier(entree: e, sortie: s) { return true }; return false }
    verifier(ok("euh comment vas-tu aujourd'hui", "Comment vas-tu aujourd'hui ?"), "garde-fou : nettoyage normal accepté")
    verifier(!ok("comment vas-tu aujourd'hui", "Je vais très bien, merci ! Et toi, comment vas-tu ?"), "garde-fou : réponse à la question refusée")
    verifier(!ok("comment vas-tu aujourd'hui", "Voici le texte : Comment vas-tu aujourd'hui ?"), "garde-fou : « Voici le texte… » refusé")
    verifier(!ok("quelle est la capitale de la France", "Paris."), "garde-fou : réponse courte refusée")
    verifier(!ok("quelle est la capitale de la France", "La capitale de la France est Paris, une ville magnifique située sur la Seine."), "garde-fou : réponse longue refusée")
    verifier(!ok("je pars demain matin tôt", ""), "garde-fou : sortie vide refusée")
    verifier(!ok("je pars demain matin tôt pour Abidjan avec Ladislas", "Je pars."), "garde-fou : sortie trop courte (< 50 %) refusée")
    verifier(ok("euh euh euh alors je pars demain", "Alors je pars demain."), "garde-fou : plus court accepté s'il y avait des « euh »")
    verifier(!ok("ok", "Ok, je comprends parfaitement ce que tu veux dire, merci beaucoup."), "garde-fou : sortie trop longue refusée")
    verifier(ok("ok", "Ok."), "garde-fou : mot unique ponctué accepté")
    verifier(ok("premièrement du pain deuxièmement du lait", "- Du pain\n- Du lait"), "garde-fou : liste dictée acceptée")
    verifier(RemiseAuPropre.verifier(entree: "un rendez-vous demain", sortie: "Un rendez\u{2011}vous demain.") == .accepte("Un rendez-vous demain."), "garde-fou : trait d'union insécable normalisé")
    verifier(RemiseAuPropre.verifier(entree: "bonjour tout le monde", sortie: "\"Bonjour tout le monde.\"") == .accepte("Bonjour tout le monde."), "garde-fou : guillemets ajoutés autour retirés")

    verifier(RemiseAuPropre.typographieFrancaise("Comment vas-tu?") == "Comment vas-tu ?" && RemiseAuPropre.typographieFrancaise("Super!") == "Super !", "typographie : espace avant ? et !")
    verifier(RemiseAuPropre.typographieFrancaise("Quoi ?!") == "Quoi ?!" && RemiseAuPropre.typographieFrancaise("Il faut :") == "Il faut :" && RemiseAuPropre.typographieFrancaise("Il faut:") == "Il faut :", "typographie : déjà bonne gardée, deux points corrigés")
    verifier(RemiseAuPropre.typographieFrancaise("RDV à 10:30 sur https://x.fr") == "RDV à 10:30 sur https://x.fr", "typographie : heures et adresses intactes")
    verifier(RemiseAuPropre.estFrancais("comment vas-tu aujourd'hui et qu'est-ce que tu as prévu") && !RemiseAuPropre.estFrancais("what is the report for you"), "langue : français / anglais")
    verifier(RemiseAuPropre.retoucher("What time is it?", entree: "what time is it", contexte: .general) == "What time is it?", "retouche : anglais sans espace avant ?")
    verifier(RemiseAuPropre.retoucher("ls -la.", entree: "ls la", contexte: .terminal) == "ls -la" && RemiseAuPropre.retoucher("Pizza.", entree: "pizza", contexte: .recherche) == "Pizza", "retouche : terminal et recherche sans point final")
    let dico = ["Ladislas", "Sillonia", "Premium CI"]
    verifier(RemiseAuPropre.corrigerMots("J'ai vu ladislas et SILLONIA chez premium ci.", dictionnaire: dico) == "J'ai vu Ladislas et Sillonia chez Premium CI.", "dictionnaire : orthographe exacte rétablie")
    verifier(RemiseAuPropre.corrigerMots("Ladislasse", dictionnaire: dico) == "Ladislasse", "dictionnaire : mots entiers seulement")
    let c = RemiseAuPropre.consignes(contexte: .terminal, mots: dico)
    verifier(c.contains("Sillonia") && c.contains("une seule ligne") && c.contains("JAMAIS"), "consignes : dictionnaire, forme du terminal, interdiction de répondre")
    verifier(RemiseAuPropre.consigne(pour: .recherche).contains("sans point final"), "consignes : recherche sans point final")
}

groupe("WAV")
do {
    let w = WAV.encode(samples: [1, -2, 300], sampleRate: 16_000)
    verifier(w.count == 44 + 6, "taille = 44 + 2 octets par échantillon")
    verifier(String(decoding: w[0..<4], as: UTF8.self) == "RIFF" && String(decoding: w[8..<12], as: UTF8.self) == "WAVE", "RIFF / WAVE")
    func u32(_ o: Int) -> UInt32 { w.subdata(in: o..<o+4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    func u16(_ o: Int) -> UInt16 { w.subdata(in: o..<o+2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }
    verifier(u32(4) == 36 + 6 && u32(40) == 6, "tailles RIFF et data")
    verifier(u16(20) == 1 && u16(22) == 1 && u32(24) == 16_000 && u32(28) == 32_000 && u16(32) == 2 && u16(34) == 16, "PCM, mono, 16 kHz, 16 bits")
    verifier(w.subdata(in: 44..<46).withUnsafeBytes { $0.loadUnaligned(as: Int16.self) } == 1 && w.subdata(in: 46..<48).withUnsafeBytes { $0.loadUnaligned(as: Int16.self) } == -2, "échantillons dans l'ordre")
}

groupe("Touche fn / 🌐 (keyDown émis par le système)")
do {
    func evenement(_ code: Int64) -> FnEvent? { FnGestureDetector.evenement(pourToucheCode: code) }
    verifier(evenement(63) == nil && evenement(179) == nil, "keyDown de fn (63) et de 🌐 (179) ignorés")
    verifier(evenement(53) == .escape && evenement(0) == .otherKey, "Échap et lettres inchangés")
    // Séquence réelle du journal : fn tenue 59 ms, keyDown de fn au relâchement, puis second appui 85 ms plus tard.
    var d = FnGestureDetector()
    var actions: [[GestureAction]] = []
    func rejouer(_ e: FnEvent?, _ t: Double) { if let e { actions.append(d.handle(e, at: t).actions) } }
    rejouer(.fnDown, 0.000); rejouer(.fnUp, 0.059); rejouer(evenement(63), 0.060); rejouer(.fnDown, 0.144)
    verifier(actions.last == [.begin(handsFree: true)], "fnDown, fnUp (59 ms), keyDown fn, fnDown : mains libres")
    var sans = FnGestureDetector()
    _ = sans.handle(.fnDown, at: 0); _ = sans.handle(.fnUp, at: 0.059); _ = sans.handle(.otherKey, at: 0.060)
    verifier(sans.handle(.fnDown, at: 0.144).actions == [.begin(handsFree: false)], "sans le filtre, ce keyDown cassait bien le double appui (reproduction du bug)")
}

groupe("VoiceChunker")
func jouerChunker(_ segments: [(db: Float, frames: Int)]) -> (coupes: [VoiceChunker.Range], fin: VoiceChunker.Range?, total: Int) {
    var c = VoiceChunker()
    var coupes: [VoiceChunker.Range] = []
    var n = 0
    for seg in segments { for _ in 0..<seg.frames { n += 1; if let r = c.feed(levelDb: seg.db) { coupes.append(r) } } }
    return (coupes, c.finish(totalSamples: n * 320), n)
}
do {
    let r = jouerChunker([(-70, 50), (-20, 150), (-70, 60), (-20, 100)]) // 1 s calme, 3 s de parole, 1,2 s de pause, 2 s de parole
    verifier(r.coupes.count == 1, "une pause de 1,2 s coupe une fois")
    if let c = r.coupes.first {
        verifier(c.start >= (50 - 15 - 1) * 320 && c.start <= 50 * 320, "le silence de début est rogné (0,3 s gardées)")
        verifier(c.end == (50 + 150 + 12) * 320, "coupe 0,5 s après la fin de la parole, silence de fin rogné à 0,25 s")
    }
    verifier(r.fin != nil && r.fin!.start >= (50 + 150 + 25) * 320 && r.fin!.start <= (50 + 150 + 60) * 320 && r.fin!.end == r.total * 320, "le dernier morceau part au relâchement (parole jusqu'au bout : rien de rogné)")
}
do {
    let r = jouerChunker([(-70, 50), (-20, 30), (-70, 40), (-20, 30)]) // morceau de 1,5 s : trop court pour couper
    verifier(r.coupes.isEmpty && r.fin != nil, "pause dans un morceau trop court : pas de coupe")
}
do {
    let r = jouerChunker([(-70, 200)])
    verifier(r.coupes.isEmpty && r.fin == nil, "silence seul : rien à envoyer")
}
do {
    let r = jouerChunker([(-70, 50), (-20, 3), (-70, 50)]) // un petit claquement de 60 ms
    verifier(r.fin == nil, "un bruit très bref n'est pas de la parole")
}
do {
    let r = jouerChunker([(-52, 100), (-25, 150), (-52, 100), (-25, 100)]) // bruit de fond de -52 dB, parole à -25
    verifier(r.coupes.count == 1, "bruit de fond de -52 dB : la pause est quand même trouvée")
}
// Envoi anticipé et rognage de fin
func jouerAvecAnticipation(_ segments: [(db: Float, frames: Int)]) -> (anticipations: [VoiceChunker.Range], coupes: [VoiceChunker.Range], fin: VoiceChunker.Range?, total: Int) {
    var c = VoiceChunker()
    var anticipations: [VoiceChunker.Range] = [], coupes: [VoiceChunker.Range] = []
    var n = 0
    for seg in segments { for _ in 0..<seg.frames {
        n += 1
        if let r = c.feed(levelDb: seg.db) { coupes.append(r) } else if let a = c.anticipation { anticipations.append(a) }
    } }
    return (anticipations, coupes, c.finish(totalSamples: n * 320), n)
}
do {
    // 0,3 s de calme, 2,5 s de parole, puis 0,45 s de pause avant le relâchement
    let r = jouerAvecAnticipation([(-70, 15), (-20, 125), (-70, 22)])
    verifier(r.anticipations.count == 1, "pause de 0,3 s : un seul envoi anticipé")
    verifier(r.coupes.isEmpty, "pas de coupe avant 0,5 s de pause")
    verifier(r.fin != nil && r.anticipations.first == r.fin, "relâchement sans nouvelle parole : le dernier morceau est exactement l'envoi anticipé")
    verifier(r.fin?.end == (15 + 125 + 12) * 320, "silence de fin rogné à 0,25 s après le dernier son")
}
do {
    // parole, pause de 0,4 s (anticipation), la parole reprend, puis relâchement : l'anticipation ne vaut plus
    let r = jouerAvecAnticipation([(-70, 15), (-20, 60), (-70, 20), (-20, 40)])
    verifier(r.anticipations.count == 1 && r.fin != nil && r.anticipations.first != r.fin, "parole reprise : le dernier morceau diffère de l'anticipation")
    verifier(r.fin?.end == r.total * 320, "parole jusqu'au relâchement : rien n'est rogné")
}
do {
    // pause de 1 s dans un long morceau : anticipation à 0,3 s, coupe à 0,5 s, même morceau
    let r = jouerAvecAnticipation([(-70, 15), (-20, 150), (-70, 50), (-20, 100)])
    verifier(r.anticipations.count >= 1 && r.coupes.count == 1 && r.anticipations.first == r.coupes.first, "la coupe à 0,5 s est le morceau déjà envoyé à l'avance")
}
do {
    // trois mots avec pauses de 0,2 s : jamais d'anticipation
    let r = jouerAvecAnticipation([(-70, 15), (-20, 40), (-70, 10), (-20, 40), (-70, 10), (-20, 40)])
    verifier(r.anticipations.isEmpty, "pauses de 0,2 s : aucun envoi anticipé")
}
do {
    // un petit bruit à -30 dB (hors parole) pendant la pause repousse l'anticipation : jamais de coupe dans un mot qui reprend
    let r = jouerAvecAnticipation([(-70, 15), (-20, 60), (-70, 10), (-30, 2), (-70, 10)])
    verifier(r.anticipations.isEmpty, "un bruit pendant la pause repousse l'envoi anticipé")
}
// Longues dictées d'une traite
func parleContinue(frames: Int, creuxTousLes: Int = 17) -> [(db: Float, frames: Int)] {
    // niveau -20 dB avec un petit creux de 2 tranches (-38 dB, entre deux syllabes) régulier : jamais de vrai silence
    var segs: [(db: Float, frames: Int)] = [(-70, 15)]
    var reste = frames
    while reste > 0 { let n = min(creuxTousLes, reste); segs.append((-20, n)); reste -= n; if reste > 0 { segs.append((-38, 2)); reste -= 2 } }
    return segs
}
do {
    let r = jouerAvecAnticipation(parleContinue(frames: 1000)) // 20 s d'une traite
    verifier(r.coupes.count == 1 && r.fin != nil, "20 s d'une traite : une coupe forcée, puis le reste au relâchement (\(r.coupes.count) coupe(s))")
    if let c = r.coupes.first, let f = r.fin {
        verifier(Double(c.count) <= 12.2 * 16_000 && Double(c.count) >= 11 * 16_000, "le premier morceau fait ~12 s (\(Double(c.count) / 16_000) s)")
        verifier(c.end == f.start, "le morceau suivant reprend exactement où le précédent finit")
        verifier(Double(f.count) / 16_000 < 10, "le dernier morceau reste court (\(Double(f.count) / 16_000) s)")
    }
}
do {
    let r = jouerAvecAnticipation(parleContinue(frames: 3000)) // 60 s d'une traite
    let morceaux = r.coupes + (r.fin.map { [$0] } ?? [])
    verifier(morceaux.count >= 5 && morceaux.count <= 7, "60 s d'une traite : \(morceaux.count) requêtes (5 à 7 attendues)")
    verifier(zip(morceaux, morceaux.dropFirst()).allSatisfy { $0.end == $1.start }, "60 s : aucun trou, aucun recouvrement entre les morceaux")
    verifier(morceaux.allSatisfy { Double($0.count) / 16_000 <= 12.3 }, "60 s : aucun morceau au-delà de ~12 s")
}
do {
    // la coupe forcée tombe dans le creux le plus profond des 1,5 dernière seconde, pas dans un pic
    var segs: [(db: Float, frames: Int)] = [(-70, 15), (-20, 590), (-20, 20), (-42, 4), (-20, 60)]
    segs = [(-70, 15), (-20, 560), (-42, 4), (-20, 30), (-20, 20)]   // creux profond à ~11,3 s
    let r = jouerAvecAnticipation(segs)
    verifier(r.coupes.count == 1, "creux profond dans la fenêtre : coupe forcée")
    if let c = r.coupes.first {
        let tr = c.end / 320
        verifier(tr >= 15 + 560 - 1 && tr <= 15 + 560 + 5, "coupée dans le creux (tranche \(tr), creux en \(15 + 560)–\(15 + 564))")
    }
}
do {
    // micro-pause de 0,26 s après 9 s de parole : coupe (au-delà de 8 s)
    let r = jouerAvecAnticipation([(-70, 15), (-20, 450), (-70, 13), (-20, 100)])
    verifier(r.coupes.count == 1 && r.coupes[0].end == (15 + 450 + 12) * 320, "morceau de 9 s : une micro-pause de 0,26 s coupe")
    // la même pause après 5 s de parole : pas de coupe (il faut 0,5 s)
    let r2 = jouerAvecAnticipation([(-70, 15), (-20, 250), (-70, 13), (-20, 100)])
    verifier(r2.coupes.isEmpty, "morceau de 5 s : une pause de 0,26 s ne coupe pas")
}
do {
    let s: [Int16] = Array(repeating: 0, count: 320)
    verifier(s.withUnsafeBufferPointer { VoiceChunker.levelDb(of: $0) } == -120, "silence numérique = -120 dB")
    let f: [Int16] = Array(repeating: 16384, count: 320)
    let db = f.withUnsafeBufferPointer { VoiceChunker.levelDb(of: $0) }
    verifier(abs(db - (-6.02)) < 0.1, "niveau d'une demi-échelle = -6 dB")
}

groupe("TextAssembler")
verifier(TextAssembler.joindre(["Bonjour,", " tout le monde.", nil, ""]) == "Bonjour, tout le monde.", "morceaux recollés dans l'ordre, vides ignorés")
verifier(TextAssembler.joindre(["Merci d'avoir regardé cette vidéo !"]) == "", "phrase fantôme de Whisper retirée")
verifier(TextAssembler.joindre(["Je te remercie.", "Sous-titres réalisés par la communauté d'Amara.org"]) == "Je te remercie.", "fantôme en fin de dictée retiré")
verifier(TextAssembler.estFantome("  ...  "), "ponctuation seule = fantôme")
verifier(!TextAssembler.estFantome("Merci"), "« Merci » seul est un vrai mot")
verifier(TextAssembler.prompt(mots: ["Ladislas", "Sillonia"], contexte: nil) == "Ladislas, Sillonia.", "prompt : dictionnaire seul")
verifier(TextAssembler.prompt(mots: ["Ladislas"], contexte: "fin de phrase") == "Ladislas. fin de phrase", "prompt : dictionnaire puis contexte")
verifier(TextAssembler.prompt(mots: ["A"], contexte: String(repeating: "x", count: 2000)).count <= 600, "prompt borné à 600 caractères")
verifier(TextAssembler.prompt(mots: [], contexte: nil) == "", "prompt vide")

groupe("TextFormatter")
verifier(TextFormatter.kind(bundleID: "com.apple.Terminal") == .terminal && TextFormatter.kind(bundleID: "com.googlecode.iterm2") == .terminal, "Terminal et iTerm reconnus")
verifier(TextFormatter.kind(bundleID: "dev.warp.Warp-Stable") == .terminal && TextFormatter.kind(bundleID: "com.mitchellh.ghostty") == .terminal && TextFormatter.kind(bundleID: "net.kovidgoyal.kitty") == .terminal && TextFormatter.kind(bundleID: "co.zeit.hyper") == .terminal, "Warp, Ghostty, kitty, Hyper reconnus")
verifier(TextFormatter.kind(bundleID: "com.microsoft.VSCode") == .terminal, "VS Code traité comme un terminal")
verifier(TextFormatter.kind(bundleID: "com.apple.Safari") == .browser && TextFormatter.kind(bundleID: "com.google.Chrome") == .browser, "navigateurs reconnus")
verifier(TextFormatter.kind(bundleID: "com.apple.Notes") == .other && TextFormatter.kind(bundleID: nil) == .other, "autres apps")
verifier(TextFormatter.prepare("ls -la\n", for: .terminal) == "ls -la", "terminal : retour final retiré")
verifier(TextFormatter.prepare("ls\n\n", for: .terminal) == "ls", "terminal : plusieurs retours finaux retirés")
verifier(TextFormatter.prepare("première ligne\ndeuxième ligne\r\ntroisième", for: .terminal) == "première ligne deuxième ligne troisième", "terminal : retours internes remplacés par des espaces")
verifier(!TextFormatter.prepare("a\u{2028}b\nc", for: .terminal).unicodeScalars.contains { CharacterSet.newlines.contains($0) }, "terminal : aucun saut de ligne, même Unicode")
verifier(TextFormatter.prepare("  bonjour   tout  le monde  ", for: .other) == "bonjour tout le monde", "espaces en trop retirés")
verifier(TextFormatter.prepare("Un.\n\nDeux  .", for: .other) == "Un.\n\nDeux .", "autres apps : paragraphes gardés")
verifier(TextFormatter.prepare("meilleur restaurant à Abidjan.", for: .browser) == "meilleur restaurant à Abidjan", "navigateur : requête courte sans point final")
verifier(TextFormatter.prepare("Je voudrais comparer les prix des billets entre Paris et Abidjan pour décembre.", for: .browser).hasSuffix("décembre."), "navigateur : phrase longue gardée telle quelle")
verifier(TextFormatter.prepare("attends...", for: .browser) == "attends...", "navigateur : points de suspension gardés")
verifier(TextFormatter.prepare("Où manger ?", for: .browser) == "Où manger ?", "navigateur : point d'interrogation gardé")
verifier(TextFormatter.nombreDeMots("un deux  trois\nquatre") == 4, "comptage des mots")
verifier(TextFormatter.prepare("", for: .terminal) == "" && TextFormatter.prepare("   \n ", for: .other) == "", "texte vide")

groupe("Désinstallation (sur un faux dossier personnel)")
do {
    let fm = FileManager.default
    let maison = fm.temporaryDirectory.appendingPathComponent("dictee-controle-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: maison) }
    func creer(_ relatif: String, dossier: Bool = false) {
        let u = maison.appendingPathComponent(relatif)
        if dossier { try? fm.createDirectory(at: u, withIntermediateDirectories: true) }
        else { try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); fm.createFile(atPath: u.path, contents: Data("x".utf8)) }
    }
    let liste = Desinstallation.elements(maison: maison).map { $0.path.replacingOccurrences(of: maison.path + "/", with: "") }
    verifier(liste.contains("Library/Application Support/Dictee") && liste.contains("Library/Logs/Dictee") && liste.contains("Library/Preferences/com.hugues.dictee.plist"), "la liste couvre données, journal et préférences")
    verifier(liste.allSatisfy { $0.hasPrefix("Library/") && !$0.contains("..") }, "tout est rangé sous Library, aucun ..")
    verifier(!liste.contains { $0.contains(".config") || $0.contains("groq") || $0.hasSuffix(".env") }, "~/.config/groq/.env n'est jamais dans la liste")
    verifier(!liste.contains { $0 == "Library" || $0 == "Library/Application Support" || $0 == "Library/Logs" || $0 == "Library/Preferences" || $0 == "Library/Caches" }, "jamais un dossier système en entier")
    verifier(Desinstallation.serviceTrousseau == "com.hugues.dictee" && Desinstallation.compteTrousseau == "groq", "l'élément du Trousseau visé est celui de la clé Groq")

    creer("Library/Application Support/Dictee/historique.json"); creer("Library/Application Support/Dictee/mots.txt"); creer("Library/Application Support/Dictee/raccourcis.json")
    creer("Library/Logs/Dictee/dictee.log"); creer("Library/Preferences/com.hugues.dictee.plist"); creer("Library/Caches/com.hugues.dictee/Cache.db")
    // Des voisins qu'il ne faut surtout pas toucher :
    creer(".config/groq/.env"); creer("Library/Application Support/AutreApp/donnees.json"); creer("Library/Preferences/com.autre.app.plist"); creer("Documents/lettre.txt")
    let r = Desinstallation.effacer(maison: maison)
    func existe(_ relatif: String) -> Bool { fm.fileExists(atPath: maison.appendingPathComponent(relatif).path) }
    verifier(!existe("Library/Application Support/Dictee") && !existe("Library/Logs/Dictee") && !existe("Library/Preferences/com.hugues.dictee.plist") && !existe("Library/Caches/com.hugues.dictee"), "historique, mots, raccourcis, journal, réglages effacés")
    verifier(existe(".config/groq/.env"), "~/.config/groq/.env est conservé")
    verifier(existe("Library/Application Support/AutreApp/donnees.json") && existe("Library/Preferences/com.autre.app.plist") && existe("Documents/lettre.txt"), "les autres apps et documents sont intacts")
    verifier(r.effaces.count == 4 && r.echecs.isEmpty && r.absents.count == Desinstallation.cheminsRelatifs.count - 4, "compte rendu : 4 effacés, le reste absent, aucun échec")
    let r2 = Desinstallation.effacer(maison: maison)
    verifier(r2.effaces.isEmpty && r2.echecs.isEmpty, "rejouable sans erreur")
    verifier(Desinstallation.effacer(maison: URL(fileURLWithPath: "/")).effaces.isEmpty, "refuse la racine comme dossier personnel")
}

groupe("BudgetRequetes")
do {
    let b = BudgetRequetes(limiteMinute: 18)
    verifier(b.restantMinute(a: 100) == 18 && b.permet(.anticipation, a: 100), "au départ : tout est permis")
    for i in 0..<10 { b.noterEnvoi(a: 100 + Double(i)) }
    verifier(b.restantMinute(a: 110) == 8, "10 envois : 8 restants")
    verifier(b.permet(.anticipation, a: 110) && b.permet(.secours, a: 110), "8 restants : l'envoi anticipé passe encore")
    b.noterEnvoi(a: 111)
    verifier(!b.permet(.anticipation, a: 111) && b.permet(.secours, a: 111), "7 restants : plus d'envoi anticipé, la requête de secours passe")
    for i in 0..<4 { b.noterEnvoi(a: 112 + Double(i)) }
    verifier(!b.permet(.secours, a: 120), "3 restants : plus rien de confort")
    verifier(b.restantMinute(a: 165) == 18 - 9, "les envois de plus d'une minute sortent du compte")
    verifier(b.restantMinute(a: 300) == 18, "une minute plus tard : budget plein")
    b.noterRestantJour(150)
    verifier(!b.permet(.anticipation, a: 300) && b.permet(.secours, a: 300), "peu de requêtes restantes dans la journée : plus d'envoi anticipé")
    b.noterRestantJour(10)
    verifier(!b.permet(.secours, a: 300), "presque plus rien dans la journée : plus de secours non plus")
    let j = BudgetRequetes.init(limiteMinute: 10, margeAnticipation: 6, margeSecours: 3)
    j.noterRestantJetons(2000, a: 10)
    verifier(!j.permet(.anticipation, a: 20) && j.permet(.secours, a: 20) && j.permet(.anticipation, a: 41), "peu de jetons restants : plus d'anticipation ; valeur de plus de 30 s ignorée")
    let c = BudgetRequetes()
    c.noter429(retryAfter: 12, a: 50)
    verifier(!c.permet(.secours, a: 55) && c.enPause(a: 55) && c.permet(.secours, a: 63), "après un 429 : pause de confort pendant retry-after")
    c.noter429(retryAfter: nil, a: 100)
    verifier(c.enPause(a: 119) && !c.enPause(a: 121), "429 sans retry-after : 20 s de pause")
    verifier(BudgetRequetes.secondes(deEnTete: "2m52.8s") == 172.8, "durée « 2m52.8s » lue")
    verifier(BudgetRequetes.secondes(deEnTete: "340ms") == 0.34, "durée « 340ms » lue")
    verifier(BudgetRequetes.secondes(deEnTete: "12s") == 12 && BudgetRequetes.secondes(deEnTete: "7") == 7, "durées « 12s » et « 7 » lues")
    verifier(BudgetRequetes.secondes(deEnTete: nil) == nil && BudgetRequetes.secondes(deEnTete: "abc") == nil, "en-tête absent ou illisible : rien")
}

groupe("ChoixLangue")
do {
    verifier(ChoixLangue.parametre(reglage: nil) == "fr" && ChoixLangue.parametre(reglage: "") == "fr", "aucun réglage : français")
    verifier(ChoixLangue.parametre(reglage: "en") == "en" && ChoixLangue.parametre(reglage: "FR") == "fr", "anglais et français choisis")
    verifier(ChoixLangue.parametre(reglage: "auto") == nil, "Automatique : pas de langue envoyée")
    verifier(ChoixLangue.code(nom: "French") == "fr" && ChoixLangue.code(nom: "german") == "de" && ChoixLangue.code(nom: "xx") == "xx" && ChoixLangue.code(nom: "Klingon") == nil, "noms de langue de Groq lus")
    verifier(ChoixLangue.accepter(nomDetecte: "French", autorisees: ["fr", "en"]) && ChoixLangue.accepter(nomDetecte: "English", autorisees: ["fr", "en"]), "français et anglais acceptés")
    verifier(!ChoixLangue.accepter(nomDetecte: "German", autorisees: ["fr", "en"]), "allemand refusé : le morceau est relancé en français")
    verifier(!ChoixLangue.accepter(nomDetecte: "Klingon", autorisees: ["fr", "en"]), "langue inconnue refusée")
    verifier(ChoixLangue.accepter(nomDetecte: nil, autorisees: ["fr", "en"]) && ChoixLangue.accepter(nomDetecte: " ", autorisees: ["fr"]), "langue non indiquée : acceptée")
    verifier(ChoixLangue.accepter(nomDetecte: "Spanish", autorisees: ["fr", "es"]), "liste personnalisée respectée")
    verifier(ChoixLangue.phraseAncre(langue: "fr") == "Transcription d'une dictée en français." && ChoixLangue.phraseAncre(langue: nil) == nil, "phrase d'ancrage en français, aucune en automatique")
    let p = TextAssembler.prompt(mots: ["Sillonia", "Ladislas"], contexte: "Bonjour à tous.", ancre: ChoixLangue.phraseAncre(langue: "fr"))
    verifier(p == "Transcription d'une dictée en français. Sillonia, Ladislas. Bonjour à tous.", "le prompt commence par la phrase d'ancrage, puis le dictionnaire, puis le contexte")
    verifier(TextAssembler.estFantome("Transcription d'une dictée en français.") && TextAssembler.joindre(["Transcription d'une dictée en français.", "Bonjour."]) == "Bonjour.", "si Whisper répète la phrase d'ancrage sur du silence, elle est retirée")
    verifier(TextAssembler.prompt(mots: [], contexte: String(repeating: "a", count: 900), ancre: "Ancre.").count <= 600, "le prompt reste borné à 600 caractères avec l'ancre")
}

groupe("ChoixMicro")
do {
    let mac = PeripheriqueEntree(uid: "BuiltInMic", nom: "Micro du MacBook Air", transport: .integre)
    let airpods = PeripheriqueEntree(uid: "AP-1", nom: "AirPods de Hugues", transport: .bluetooth)
    let usb = PeripheriqueEntree(uid: "USB-1", nom: "Shure MV7", transport: .usb)
    let tous = [mac, airpods, usb]
    verifier(ChoixMicro.decider(reglage: nil, peripheriques: tous, defautUID: "AP-1") == .impose(mac, raison: "casque Bluetooth connecté (AirPods de Hugues) : micro intégré préféré"), "Automatique + AirPods par défaut : micro intégré")
    verifier(ChoixMicro.decider(reglage: "", peripheriques: tous, defautUID: "BuiltInMic").raison.hasPrefix("micro par défaut"), "Automatique + micro intégré par défaut : on laisse le système")
    verifier(ChoixMicro.decider(reglage: nil, peripheriques: tous, defautUID: "USB-1") == .systeme(raison: "micro par défaut du système (Shure MV7)"), "Automatique + micro USB par défaut : on le garde")
    verifier(ChoixMicro.decider(reglage: "AP-1", peripheriques: tous, defautUID: "BuiltInMic") == .impose(airpods, raison: "micro choisi dans les Réglages"), "AirPods choisis explicitement : respectés")
    verifier(ChoixMicro.decider(reglage: ChoixMicro.systeme, peripheriques: tous, defautUID: "AP-1") == .systeme(raison: "Micro du système choisi dans les Réglages"), "« Micro du système » : jamais d'imposition, même avec AirPods")
    verifier(ChoixMicro.decider(reglage: "AP-9", peripheriques: tous, defautUID: "AP-1").raison.hasPrefix("micro choisi absent, casque Bluetooth"), "micro choisi débranché : retour à l'automatique")
    verifier(ChoixMicro.decider(reglage: nil, peripheriques: [airpods], defautUID: "AP-1") == .systeme(raison: "micro par défaut du système (AirPods de Hugues)"), "AirPods seuls (Mac sans micro intégré) : on les utilise")
    verifier(ChoixMicro.decider(reglage: nil, peripheriques: [], defautUID: nil) == .systeme(raison: "micro par défaut du système"), "aucun périphérique connu : le système décide")
}

groupe("Coupe forcée")
verifier(TextAssembler.sansPonctuationDeCoupe(" Il reste à tester. ") == "Il reste à tester", "le point de fin d'un morceau coupé en pleine parole est retiré")
verifier(TextAssembler.sansPonctuationDeCoupe("Tu viens ?") == "Tu viens ?" && TextAssembler.sansPonctuationDeCoupe("Super !") == "Super !", "? et ! sont gardés")
verifier(TextAssembler.joindre([TextAssembler.sansPonctuationDeCoupe("Il reste à tester."), "la vitesse de l'ensemble."]) == "Il reste à tester la vitesse de l'ensemble.", "recollage sans faux point au milieu de la phrase")

groupe("DecoupeEnUnites")
do {
    var d = DecoupeEnUnites()
    verifier(d.recevoir(numero: 1, texte: "On commence par le début de la phrase", finParPause: true).isEmpty, "phrase sans point : pas d'unité")
    let u = d.recevoir(numero: 2, texte: "et on la termine ici.", finParPause: true)
    verifier(u.count == 1 && u[0].brut == "On commence par le début de la phrase et on la termine ici.", "deux morceaux, une phrase : une unité")
    verifier(d.queue(parties: ["On commence par le début de la phrase", "et on la termine ici.", "reste de la fin"]) == "reste de la fin", "la queue = ce qui suit la dernière unité")
}
do {
    var d = DecoupeEnUnites()
    verifier(d.recevoir(numero: 2, texte: "Deuxième phrase.", finParPause: true).isEmpty, "le morceau 2 arrive avant le 1 : on attend")
    let u = d.recevoir(numero: 1, texte: "Première phrase.", finParPause: true)
    verifier(u.count == 2 && u[0].brut == "Première phrase." && u[1].brut == "Deuxième phrase.", "morceaux arrivés dans le désordre : unités dans l'ordre")
}
do {
    var d = DecoupeEnUnites()
    verifier(d.recevoir(numero: 1, texte: "Il a dit que c'est fini.", finParPause: false).isEmpty, "coupe en pleine parole, une seule phrase (la dernière n'est pas sûre) : pas d'unité")
    let u = d.recevoir(numero: 2, texte: "Et voilà.", finParPause: true)
    verifier(u.count == 1 && u[0].brut == "Il a dit que c'est fini. Et voilà.", "l'unité se ferme à la pause suivante, avec tout")
}
do {
    // dictée d'une traite : le 1er morceau (coupé en pleine parole) contient deux phrases entières et un début de troisième
    var d = DecoupeEnUnites()
    let p1 = "Alors voilà je voulais te faire un point rapide. Nous avons terminé la première version de l'application. Il reste à tester la"
    let u = d.recevoir(numero: 1, texte: p1, finParPause: false)
    verifier(u.count == 1 && u[0].brut == "Alors voilà je voulais te faire un point rapide. Nous avons terminé la première version de l'application.", "coupe forcée : l'unité va jusqu'à la dernière fin de phrase du texte")
    verifier(d.queue(parties: [p1]) == "Il reste à tester la", "le bout de phrase reste pour la suite")
    let parties: [String?] = [p1, "vitesse de l'ensemble et à vérifier la précision sur des cas difficiles."]
    verifier(d.recevoir(numero: 2, texte: parties[1]!, finParPause: true).first?.brut == "Il reste à tester la vitesse de l'ensemble et à vérifier la précision sur des cas difficiles.", "la fin de la dictée complète le bout de phrase")
    verifier(d.queue(parties: parties).isEmpty, "plus rien en queue")
}
do {
    verifier(DecoupeEnUnites.derniereFinDePhrase("M. Dupont arrive demain matin") == nil, "« M. Dupont » n'est pas une fin de phrase")
    verifier(DecoupeEnUnites.derniereFinDePhrase("Il coûte 3. Ensuite on verra") == nil, "« 3. » n'est pas une fin de phrase")
    verifier(DecoupeEnUnites.derniereFinDePhrase("C'est fini. et puis le reste") == nil, "pas de majuscule après : pas une fin de phrase")
    verifier(DecoupeEnUnites.derniereFinDePhrase("Bonjour tout le monde ? Alors on commence") == 23, "point d'interrogation suivi d'une majuscule")
}
do {
    verifier(DecoupeEnUnites.finitUnePhrase("C'est bon !") && DecoupeEnUnites.finitUnePhrase("Vraiment ?") && DecoupeEnUnites.finitUnePhrase("Il a dit « oui. »") && DecoupeEnUnites.finitUnePhrase("Alors…"), "points, ?, !, … et guillemets fermants")
    verifier(!DecoupeEnUnites.finitUnePhrase("et puis,") && !DecoupeEnUnites.finitUnePhrase("") && !DecoupeEnUnites.finitUnePhrase("  "), "virgule ou vide : pas une fin de phrase")
    verifier(DecoupeEnUnites.separationSure(["Je passe mardi à dix heures.", "On se retrouve au café."]), "deux phrases ordinaires : séparables")
    verifier(!DecoupeEnUnites.separationSure(["Je passe mardi.", "Non plutôt mercredi à dix heures."]), "correction au début de l'unité suivante : pas séparable")
    verifier(DecoupeEnUnites.separationSure(["Je passe mardi non plutôt mercredi à dix heures.", "On se retrouve au café ce soir."]), "correction au milieu d'une unité : séparable")
    verifier(!DecoupeEnUnites.separationSure(["Il faut acheter premièrement du pain.", "Deuxièmement du lait."]), "liste sur deux unités : pas séparable")
    verifier(DecoupeEnUnites.contexteAdapte(.general) && DecoupeEnUnites.contexteAdapte(.terminal) && !DecoupeEnUnites.contexteAdapte(.courriel) && !DecoupeEnUnites.contexteAdapte(.notes) && !DecoupeEnUnites.contexteAdapte(.assistantIA), "courriel, notes, assistant : texte entier")
    verifier(DecoupeEnUnites.assembler(["Bonjour.", " ", "Comment vas-tu ?"]) == "Bonjour. Comment vas-tu ?", "recollage avec une espace, vides ignorés")
    verifier(DecoupeEnUnites.assembler(["Voici :\n", "la suite."]) == "Voici :\nla suite.", "pas d'espace après un retour à la ligne")
    verifier(RemiseAuPropre.retoucher("On part.", entree: "on part", contexte: .terminal, finDeTexte: false) == "On part." && RemiseAuPropre.retoucher("On part.", entree: "on part", contexte: .terminal) == "On part", "point final gardé dans une partie, retiré sur le tout")
}

groupe("Installation")
do {
    verifier(Installation.doitProposerDeplacement(chemin: "/Volumes/Verbe/Verbe.app", volumeEnLectureSeule: true), "lancée depuis l'image disque : proposer")
    verifier(Installation.doitProposerDeplacement(chemin: "/private/var/folders/ab/T/AppTranslocation/ABC/d/Verbe.app", volumeEnLectureSeule: true), "app translocalisée : proposer")
    verifier(!Installation.doitProposerDeplacement(chemin: "/Applications/Verbe.app", volumeEnLectureSeule: false), "dans /Applications : rien à proposer")
    verifier(!Installation.doitProposerDeplacement(chemin: "/tmp/maison-exemple/Applications/Verbe.app", volumeEnLectureSeule: false), "dans ~/Applications : rien à proposer")
    verifier(!Installation.doitProposerDeplacement(chemin: "/Volumes/DisqueExterne/Verbe.app", volumeEnLectureSeule: false), "disque externe inscriptible : on ne dérange pas")
    let maison = URL(fileURLWithPath: "/tmp/maison-exemple", isDirectory: true)
    verifier(Installation.dossierDestination(maison: maison, applicationsEcrivable: true).path == "/Applications", "destination : /Applications si possible")
    verifier(Installation.dossierDestination(maison: maison, applicationsEcrivable: false).path == "/tmp/maison-exemple/Applications", "destination : ~/Applications sinon")

    let fm = FileManager.default
    let racine = fm.temporaryDirectory.appendingPathComponent("dictee-install-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: racine) }
    let source = racine.appendingPathComponent("dmg/Verbe.app/Contents", isDirectory: true)
    try? fm.createDirectory(at: source, withIntermediateDirectories: true)
    try? Data("v2".utf8).write(to: source.appendingPathComponent("version.txt"))
    let app = racine.appendingPathComponent("dmg/Verbe.app")
    let dest = racine.appendingPathComponent("Applications", isDirectory: true)
    let copie = try? Installation.copier(app: app, dansDossier: dest)
    verifier(copie?.path == dest.appendingPathComponent("Verbe.app").path && fm.fileExists(atPath: dest.appendingPathComponent("Verbe.app/Contents/version.txt").path), "copie dans un dossier créé au besoin")
    // une ancienne version déjà installée est remplacée, sans reste
    try? Data("v1".utf8).write(to: dest.appendingPathComponent("Verbe.app/Contents/version.txt"))
    try? Data("v3".utf8).write(to: source.appendingPathComponent("version.txt"))
    _ = try? Installation.copier(app: app, dansDossier: dest)
    verifier((try? String(contentsOf: dest.appendingPathComponent("Verbe.app/Contents/version.txt"), encoding: .utf8)) == "v3", "remplace l'ancienne version")
    verifier((try? fm.contentsOfDirectory(atPath: dest.path))?.filter { $0.contains("installation") }.isEmpty == true, "aucun fichier temporaire laissé")
    verifier((try? Installation.copier(app: racine.appendingPathComponent("absente.app"), dansDossier: dest)) == nil, "source absente : erreur, pas de plantage")
}

groupe("Ancien nom (Dictee.app)")
do {
    let fm = FileManager.default
    let racine = fm.temporaryDirectory.appendingPathComponent("dictee-ancien-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: racine) }
    let a1 = racine.appendingPathComponent("A", isDirectory: true), a2 = racine.appendingPathComponent("B", isDirectory: true)
    for d in [a1, a2] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try? fm.createDirectory(at: a1.appendingPathComponent("Dictee.app/Contents"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: a1.appendingPathComponent("Verbe.app/Contents"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: a2.appendingPathComponent("Autre.app"), withIntermediateDirectories: true)
    let trouvees = Desinstallation.anciennesApps(dossiers: [a1, a2], exclure: a1.appendingPathComponent("Verbe.app"), fm: fm)
    verifier(trouvees.map(\.lastPathComponent) == ["Dictee.app"] && trouvees.first?.deletingLastPathComponent().path == a1.path, "trouve seulement l'ancienne Dictee.app, jamais Verbe.app ni une autre app")
    verifier(Desinstallation.anciennesApps(dossiers: [a1, a2], exclure: a1.appendingPathComponent("Dictee.app"), fm: fm).isEmpty, "l'app qui tourne n'est jamais comptée comme ancienne copie")
    verifier(Desinstallation.anciennesApps(dossiers: [a2], exclure: a1.appendingPathComponent("Verbe.app"), fm: fm).isEmpty, "aucune ancienne copie : liste vide")
    let maison = URL(fileURLWithPath: "/tmp/maison-exemple")
    verifier(Desinstallation.dossiersApplications(maison: maison).map(\.path) == ["/Applications", "/tmp/maison-exemple/Applications"], "dossiers visés : /Applications et ~/Applications")
    verifier(Desinstallation.cheminsRelatifs.contains("Library/Application Support/Dictee") && Desinstallation.identifiant == "com.hugues.dictee", "dossiers internes et identifiant gardés (autorisations, historique, dictionnaire)")
}

groupe("Sons de début, de fin, d'annulation")
do {
    // Le son de début, capté par le micro, ne doit pas passer pour de la voix : les premières tranches sont ignorées.
    func fin(ignorees: Int, _ segments: [(db: Float, frames: Int)]) -> VoiceChunker.Range? {
        var cfg = VoiceChunker.Config(); cfg.ignoredStartFrames = ignorees
        var c = VoiceChunker(config: cfg); var n = 0
        for seg in segments { for _ in 0..<seg.frames { n += 1; _ = c.feed(levelDb: seg.db) } }
        return c.finish(totalSamples: n * 320)
    }
    verifier(fin(ignorees: 0, [(-30, 8), (-70, 60)]) != nil, "sans masque, un son de 160 ms au tout début passe pour de la parole")
    verifier(fin(ignorees: 10, [(-30, 8), (-70, 60)]) == nil, "avec masque, le même son au tout début n'est pas de la parole")
    let parole = fin(ignorees: 16, [(-30, 10), (-70, 10), (-20, 60)])
    verifier(parole != nil && parole!.start == 0 && parole!.end == 80 * 320, "la parole qui suit le masque est gardée, et rien avant elle n'est perdu (début à 0)")
    let tot = fin(ignorees: 16, [(-20, 40)])
    verifier(tot != nil && tot!.start == 0, "parole commencée dans le masque : détectée juste après, morceau complet gardé")
    for son in SonSynthese.Son.allCases {
        let n = SonSynthese.notes(son)
        let e = SonSynthese.echantillons(n)
        let d = Double(e.count) / Double(SonSynthese.frequenceEchantillonnage)
        let pic = Double(e.map { abs(Int($0)) }.max() ?? 0) / Double(Int16.max)
        verifier(d >= 0.04 && d <= 0.35, "\(son) : durée \(Int(d * 1000)) ms (entre 40 et 350 ms)")
        verifier(pic > 0.05 && pic <= 0.40, "\(son) : volume modéré (pic \(String(format: "%.2f", pic)) de la pleine échelle, 0,40 au plus)")
        verifier(abs(Int(e.first ?? 0)) < 40 && abs(Int(e.last ?? 0)) < 40, "\(son) : départ et arrivée à zéro, pas de clic")
        let wav = SonSynthese.wav(son)
        verifier(wav.count == 44 + e.count * 2 && wav.prefix(4) == Data("RIFF".utf8), "\(son) : fichier WAV valide en mémoire")
    }
    let debut = SonSynthese.notes(.debut), fin2 = SonSynthese.notes(.fin), annul = SonSynthese.notes(.annulation)
    verifier(debut[0].frequenceFin > debut[0].frequenceDebut && debut[0].frequenceDebut < 400, "début : un son grave qui monte")
    verifier(fin2[0].frequenceFin < fin2[0].frequenceDebut && fin2[0].frequenceDebut < 400, "fin : un son grave qui descend")
    verifier(annul.count == 1 && annul[0].frequenceDebut < 250, "annulation : un tic grave")
    verifier(SonSynthese.duree(.debut) <= 0.30 + 1e-9, "début : 300 ms au plus")
}

groupe("Adresses dictées")
do {
    func r(_ t: String) -> String { AdressesDictees.reconstituer(t) }
    verifier(r("jean arobase gmail point com") == "jean@gmail.com", "cas simple : X arobase Y point com")
    verifier(r("h2delpit arobase gmail point com") == "h2delpit@gmail.com", "mot avec chiffre")
    verifier(r("h 2 d e l p i t arobase gmail point com") == "h2delpit@gmail.com", "lettres et chiffres épelés collés")
    verifier(r("H, 2, D, E, L, P, I, T arobase gmail point com.") == "h2delpit@gmail.com.", "épelé avec virgules de Whisper, point final de la phrase gardé")
    verifier(r("jean point dupont arobase gmail point com") == "jean.dupont@gmail.com", "point dans la partie locale")
    verifier(r("jean tiret louis arobase gmail point com") == "jean-louis@gmail.com", "tiret")
    verifier(r("jean tiret du bas louis arobase gmail point com") == "jean_louis@gmail.com", "tiret du bas")
    verifier(r("jean underscore louis arobase gmail point com") == "jean_louis@gmail.com", "underscore")
    verifier(r("contact arobase sillonia point fr") == "contact@sillonia.fr", "extension .fr")
    verifier(r("contact arobase ecodistrib point net") == "contact@ecodistrib.net", "extension .net")
    verifier(r("paul arobase mon tiret site point co point uk") == "paul@mon-site.co.uk", "domaine à deux extensions et tiret")
    verifier(r("Écris à Jean arobase Gmail point com demain.") == "Écris à jean@gmail.com demain.", "majuscules retirées, « à » reste un mot de la phrase")
    verifier(r("Mon adresse est jean arobase gmail point com, merci.") == "Mon adresse est jean@gmail.com, merci.", "virgule après l'adresse gardée")
    verifier(r("Envoie à (jean arobase gmail point com) tout de suite") == "Envoie à (jean@gmail.com) tout de suite", "parenthèses gardées")
    verifier(r("contact arobase sillonia point fr point merci") == "contact@sillonia.fr point merci", "ce qui suit l'extension n'est pas mangé")
    verifier(r("jean @ gmail point com") == "jean@gmail.com", "« @ » resté seul")
    verifier(r("jean@gmail point com") == "jean@gmail.com", "« @ » collé, domaine dicté")
    verifier(r("jean@Gmail.com") == "jean@gmail.com", "adresse déjà écrite : minuscules")
    verifier(r("Écris-moi à h2delpit@gmail.com, merci") == "Écris-moi à h2delpit@gmail.com, merci", "adresse correcte : intacte")
    verifier(r("jean arobase gmail point com et marie arobase yahoo point fr") == "jean@gmail.com et marie@yahoo.fr", "deux adresses")
    verifier(r("hugues arobase sillonia point com") == "hugues@sillonia.com", "nom simple")
    verifier(r("pense à écrire à Hugues-Henri Delpit arobase gmail point com") == "pense à écrire à Hugues-Henri delpit@gmail.com", "un seul mot entier avant l'arobase")
    // pas de fausses adresses
    verifier(r("on se voit à l'arobase de la rue") == "on se voit à l'arobase de la rue", "arobase sans domaine : inchangé")
    verifier(r("le point com du site") == "le point com du site", "« point com » seul : inchangé")
    verifier(r("il faut mettre un arobase point") == "il faut mettre un arobase point", "arobase sans partie locale ni domaine : inchangé")
    verifier(r("jean arobase gmail point machin") == "jean arobase gmail point machin", "extension inconnue : inchangé")
    verifier(r("Bonjour, comment vas-tu ?") == "Bonjour, comment vas-tu ?", "texte ordinaire : inchangé")
    verifier(r("point. tiret du pain") == "point. tiret du pain", "commandes de liste : inchangées")
    // adresses web
    verifier(r("www point sillonia point fr") == "www.sillonia.fr", "adresse web")
    verifier(r("va sur www point google point com, puis ferme") == "va sur www.google.com, puis ferme", "adresse web dans une phrase")
    verifier(r("w w w point sillonia point fr.") == "www.sillonia.fr.", "w w w épelé, point final gardé")
    verifier(r("www point machin point truc") == "www point machin point truc", "web : extension inconnue, inchangé")
    verifier(r("Voici\nh2 arobase gmail point com\nmerci") == "Voici\nh2@gmail.com\nmerci", "retours à la ligne gardés")
}

groupe("Raccourcis vocaux : adresse, après la remise au propre")
do {
    let adresse = "h2delpit@gmail.com"
    let rac = [RaccourciVocal(expression: "mon mail", texte: adresse), RaccourciVocal(expression: "mon adresse mail", texte: adresse)]
    func a(_ t: String) -> String { RaccourcisVocaux.appliquer(t, raccourcis: rac) }
    verifier(a("Envoie-le à mon mail, merci.") == "Envoie-le à \(adresse), merci.", "« à mon mail, merci » : virgule gardée")
    verifier(a("Mon adresse mail, c'est ça.") == "\(adresse), c'est ça.", "le raccourci le plus long gagne (mon adresse mail)")
    verifier(a("Mon mail.") == adresse, "dictée réduite au raccourci : adresse seule, sans point")
    verifier(a("Écris à mon mail.") == "Écris à \(adresse).", "point final de la phrase gardé")
    verifier(a("Mon mail : h2.") == "\(adresse) : h2.", "deux-points gardés")
    // même chaîne que l'app : règle locale d'abord, raccourcis ensuite
    let texte = RaccourcisVocaux.appliquer(AdressesDictees.reconstituer("Écris à jean arobase gmail point com ou à mon mail, merci."), raccourcis: rac)
    verifier(texte == "Écris à jean@gmail.com ou à \(adresse), merci.", "adresse dictée puis raccourci dans la même phrase")
    verifier(RemiseAuPropre.consignes(contexte: .general, mots: []).contains("arobase") && RemiseAuPropre.consignes(contexte: .general, mots: []).contains("www.sillonia.fr"), "consignes de l'IA : adresses")
}

groupe("Mots collés : expressions courantes à travers toute la chaîne de texte")
do {
    let phrases = ["À plus tard.", "Bon, à plus tard, et merci.", "À plus.", "Ça dépend du point de vue.", "C'est plus ou moins ça.", "Il y a deux points à voir.", "On se voit plus tard", "Il y a un point, un autre point et plus encore."]
    let rac = [RaccourciVocal(expression: "mon mail", texte: "h2delpit@gmail.com")]
    for p in phrases {
        verifier(AdressesDictees.reconstituer(p) == p, "adresses dictées : « \(p) » inchangé")
        verifier(RaccourcisVocaux.appliquer(p, raccourcis: rac) == p, "raccourcis vocaux : « \(p) » inchangé")
        verifier(TextFormatter.prepare(p, for: .other) == p, "mise en forme : « \(p) » inchangé")
        verifier(RemiseAuPropre.typographieFrancaise(p) == p, "typographie : « \(p) » inchangé")
        verifier(RemiseAuPropre.corrigerMots(p, dictionnaire: ["Ladislas", "Premium CI", "macOS"]) == p, "dictionnaire : « \(p) » inchangé")
        verifier(EspacesIntelligents.adapter(p, precedent: "d'accord,", mots: ["Ladislas"]).trimmingCharacters(in: .whitespaces) == (p.first!.isUppercase ? String(p.first!).lowercased() + p.dropFirst() : p), "espaces intelligents : « \(p) » garde ses espaces")
    }
    // adresses : un « point » ou un « plus » ordinaire à côté d'une vraie adresse
    verifier(AdressesDictees.reconstituer("À plus tard, écris à jean arobase gmail point com.") == "À plus tard, écris à jean@gmail.com.", "à plus tard avant une adresse : seule l'adresse change")
    verifier(AdressesDictees.reconstituer("Du point de vue de jean arobase gmail point com") == "Du point de vue de jean@gmail.com", "point de vue avant une adresse")
    verifier(AdressesDictees.reconstituer("Il a jean arobase gmail point com") == "Il a jean@gmail.com", "« a » (verbe) devant une adresse n'est pas une lettre épelée")
    verifier(AdressesDictees.reconstituer("a b c arobase gmail point com") == "abc@gmail.com", "lettres épelées dont « a »")
    // jonction de morceaux
    verifier(TextAssembler.joindre(["Je te dis à plus", "tard pour la suite"]) == "Je te dis à plus tard pour la suite", "jonction « … à plus » + « tard »")
    verifier(TextAssembler.joindre([" Bonjour ", "", "à plus tard"]) == "Bonjour à plus tard", "morceaux vides et espaces de Whisper")
    verifier(TextAssembler.joindre(["Tu sais, lorsqu'", "on parle"]) == "Tu sais, lorsqu'on parle", "apostrophe en fin de morceau : pas d'espace")
    verifier(TextAssembler.joindre(["Tu sais, lorsqu\u{2019}", "on parle"]) == "Tu sais, lorsqu\u{2019}on parle", "apostrophe courbe en fin de morceau")
    verifier(TextAssembler.joindre(["C'est peut-", "être vrai"]) == "C'est peut-être vrai", "trait d'union en fin de morceau")
    verifier(TextAssembler.joindre(["On se voit demain", ", si tu veux"]) == "On se voit demain, si tu veux", "virgule en début de morceau")
    verifier(TextAssembler.joindre(["Tu viens", "? Dis-moi"]) == "Tu viens? Dis-moi", "point d'interrogation en début de morceau")
    verifier(TextAssembler.joindre(["Je pense", "... enfin non"]) == "Je pense ... enfin non", "points de suspension : gardés à part")
    verifier(TextAssembler.joindre(["On y va -", "tiret de liste"]) == "On y va - tiret de liste", "tiret de liste isolé : espace gardée")
    verifier(DecoupeEnUnites.assembler(["Bonjour.", "À plus tard."]) == "Bonjour. À plus tard.", "unités remises au propre : espace entre elles")
    // sortie de l'IA : mots collés remis en mots séparés
    func repare(_ e: String, _ s: String) -> String { MotsColles.reparer(entree: e, sortie: s).texte }
    verifier(repare("bon à plus tard hein", "Bon, àplus tard, hein.") == "Bon, à plus tard, hein.", "« àplus tard » → « à plus tard »")
    verifier(repare("bon à plus tard hein", "Bon, àplustard, hein.") == "Bon, à plus tard, hein.", "« àplustard » → « à plus tard »")
    verifier(repare("à plus tard", "Àplustard.") == "À plus tard.", "majuscule gardée : « Àplustard. »")
    verifier(repare("je veux dire à plus tard", "Je veux dire, à plus tard.") == "Je veux dire, à plus tard.", "texte correct : inchangé")
    verifier(repare("pour quoi faire", "Pourquoi faire ?") == "Pourquoi faire ?", "mots qui s'écrivent d'un bloc : gardés")
    verifier(repare("c'est du bien joué", "C'est dubien joué.") == "C'est du bien joué.", "« dubien » → « du bien »")
    verifier(MotsColles.reparer(entree: "à plus tard", sortie: "À plus tard.").repares.isEmpty, "rien à réparer : liste vide")
    verifier(RemiseAuPropre.verifier(entree: "bon à plus tard hein c'est tout pour moi", sortie: "Bon, àplus tard, hein. C'est tout pour moi.") == .accepte("Bon, à plus tard, hein. C'est tout pour moi."), "garde-fou de l'IA : mot collé réparé et sortie acceptée")
}

groupe("Journal : texte Groq → texte final")
do {
    verifier(ComparaisonJournal.ligne(groq: "bonjour tout le monde", final: "Bonjour, tout le monde.") == nil, "ponctuation et majuscule seules : pas de ligne")
    verifier(ComparaisonJournal.ligne(groq: "peut-être demain", final: "Peut être demain") == nil, "trait d'union : pas de ligne")
    let l = ComparaisonJournal.ligne(groq: "Bon à plus tard hein", final: "Bon àplus tard hein")
    verifier(l?.contains("\u{2192}") == true && l?.contains("àplus") == true, "mot collé : ligne écrite")
    let longA = String(repeating: "mot ", count: 40) + "à plus tard et la suite"
    let longB = String(repeating: "mot ", count: 40) + "àplus tard et la suite"
    let ll = ComparaisonJournal.ligne(groq: longA, final: longB)
    verifier(ll != nil && ll!.contains("àplus"), "texte long : la fenêtre est centrée sur la différence")
    if let ll { let morceaux = ll.components(separatedBy: "\""); verifier(morceaux.count == 5 && morceaux[1].count <= 62 && morceaux[3].count <= 62, "chaque côté tient en 60 caractères (+ points de suspension)") }
    verifier(ComparaisonJournal.ligne(groq: "un deux", final: "un deux trois")?.contains("trois") == true, "mot ajouté en fin : visible")
}

groupe("Filet de sécurité : l'écriture a-t-elle réussi ?")
do {
    let t = "Bonjour Madame Martin, je vous confirme le rendez-vous de jeudi. À plus tard."
    func v(_ o: ObservationChamp?, _ genre: AppKind = .other, texte: String = t) -> VerdictInsertion { VerificationInsertion.evaluer(texte: texte, observation: o, genre: genre) }
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: "Salut. " + t)) == .inseree, "texte relu juste avant le curseur : inséré")
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: "Salut. " + t.replacingOccurrences(of: " ", with: "\u{00A0}"))) == .inseree, "espaces insécables de l'app : inséré")
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: "Bonjour.\n\nÀ plus tard.")) .estEchec, "autre texte devant le curseur : échec")
    verifier(v(ObservationChamp(focus: .element(role: "AXTextField"), avantLeCurseur: "")).estEchec, "champ lisible mais vide : échec")
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: "Le début\n" + "À plus tard.\n"), texte: "Le début\nÀ plus tard.\n") == .inseree, "retour à la ligne final du texte : inséré")
    verifier(v(ObservationChamp(focus: .element(role: "AXTextField"), avantLeCurseur: "e\u{0301}te\u{0301} e\u{0301}te\u{0301}"), texte: "été été") == .inseree, "accents décomposés ou composés : inséré")
    verifier(v(ObservationChamp(focus: .element(role: "AXWebArea"), avantLeCurseur: t)) == .inseree, "zone web qui expose le curseur : inséré")
    verifier(v(ObservationChamp(focus: .element(role: "AXWebArea"), avantLeCurseur: "autre chose")).estEchec, "zone web lisible sans le texte : échec")
    // aucune lecture possible : jamais d'alarme
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: nil)) == .indetermine, "champ texte illisible : indéterminé, pas d'alarme")
    verifier(v(ObservationChamp(focus: .element(role: "AXGroup"), avantLeCurseur: nil)) == .indetermine, "rôle ambigu illisible : indéterminé")
    verifier(v(ObservationChamp(focus: .element(role: nil), avantLeCurseur: nil)) == .indetermine, "rôle inconnu illisible : indéterminé")
    verifier(v(ObservationChamp(focus: .inconnu)) == .indetermine, "Accessibilité muette : indéterminé")
    verifier(v(nil) == .indetermine, "aucune observation : indéterminé")
    // terminaux
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: "$ ls"), .terminal) == .indetermine, "Terminal : jamais d'échec même si le texte n'est pas relu")
    verifier(v(ObservationChamp(focus: .element(role: "AXTextArea"), avantLeCurseur: nil), .terminal) == .indetermine, "Terminal illisible : indéterminé")
    verifier(v(ObservationChamp(focus: .aucun), .terminal).estEchec, "Terminal sans élément focalisé : échec")
    // aucun élément focalisé, rôle sans texte
    verifier(v(ObservationChamp(focus: .aucun)).estEchec, "aucun élément focalisé : échec")
    verifier(v(ObservationChamp(focus: .element(role: "AXButton"), avantLeCurseur: nil)).estEchec, "bouton focalisé, texte non relisible : échec")
    verifier(v(ObservationChamp(focus: .element(role: "AXStaticText"), avantLeCurseur: nil)).estEchec, "texte fixe focalisé : échec")
    verifier(v(ObservationChamp(focus: .element(role: "AXButton"), avantLeCurseur: t)) == .inseree, "preuve d'écriture même sur un rôle surprenant : inséré")
    // plusieurs relectures
    verifier(VerificationInsertion.conclure([.nonInseree(raison: "x"), .inseree]) == .inseree, "relecture tardive qui voit le texte : inséré")
    verifier(VerificationInsertion.conclure([.nonInseree(raison: "x"), .nonInseree(raison: "x"), .nonInseree(raison: "y")]).estEchec, "jamais vu : échec")
    verifier(VerificationInsertion.conclure([.nonInseree(raison: "x"), .indetermine]) == .indetermine, "lecture qui devient impossible : pas d'alarme")
    verifier(VerificationInsertion.conclure([]) == .indetermine, "aucune relecture : indéterminé")
    verifier(VerificationInsertion.delaisDeRelecture.reduce(0, +) <= 700 && VerificationInsertion.delaisDeRelecture[0] >= 250, "première relecture à 250 ms, tout fini en 700 ms")
    // longueur lue
    verifier(VerificationInsertion.queueAttendue("  Salut\n  tout le monde  ") == "Salut tout le monde", "queue attendue : espaces réduites")
    verifier(VerificationInsertion.queueAttendue(t).count == VerificationInsertion.tailleQueue && VerificationInsertion.longueurALire(t) > VerificationInsertion.tailleQueue, "queue de 24 caractères, lecture avec marge")
}

groupe("Touche 🌐")
do {
    verifier(!ToucheGlobe.doitEtreReglee(valeur: 0), "0 (Ne rien faire) : rien à régler")
    verifier(ToucheGlobe.doitEtreReglee(valeur: 2) && ToucheGlobe.doitEtreReglee(valeur: 1) && ToucheGlobe.doitEtreReglee(valeur: 3), "1, 2 ou 3 : à régler")
    verifier(ToucheGlobe.doitEtreReglee(valeur: nil), "clé absente (réglage d'origine du Mac) : à régler")
    verifier(ToucheGlobe.interpreter(NSNumber(value: 0)) == 0 && ToucheGlobe.interpreter(NSNumber(value: 2)) == 2, "nombre lu")
    verifier(ToucheGlobe.interpreter("3") == 3 && ToucheGlobe.interpreter(" 0 ") == 0, "texte lu")
    verifier(ToucheGlobe.interpreter(nil) == nil && ToucheGlobe.interpreter("abc") == nil, "absent ou illisible : nil")
    verifier(ToucheGlobe.phrase(valeur: 2) == "Ta touche 🌐 ouvre les emoji" && ToucheGlobe.phrase(valeur: nil) == "Ta touche 🌐 ouvre les emoji", "phrase : emoji")
    verifier(ToucheGlobe.phrase(valeur: 3).contains("dictée d\u{2019}Apple") && ToucheGlobe.phrase(valeur: 1).contains("méthode de saisie"), "phrase : dictée d'Apple, méthode de saisie")
    verifier(ToucheGlobe.adresseVoletClavier == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension", "adresse du volet Clavier")
    verifier(ToucheGlobe.consigne == "Appuyer sur la touche 🌐 pour : Ne rien faire", "consigne")
    let lue = ToucheGlobe.lire()   // lecture seule des préférences système, aucun accès au clavier
    verifier(lue == nil || (0...3).contains(lue!), "lecture réelle du réglage : \(lue.map(String.init) ?? "absent")")
}

groupe("ClePhonetique")
do {
    verifier(ClePhonetique.plier("\u{00C9}co-Distrib") == "ecodistrib", "plier : casse, accents, trait d'union")
    verifier(ClePhonetique.plier("Fran\u{00E7}ois") == "fransois", "plier : ç se prononce s")
    verifier(ClePhonetique.cle("Philippe") == ClePhonetique.cle("Filip") || ClePhonetique.distance(ClePhonetique.cle("Philippe"), ClePhonetique.cle("Filip")) <= 1, "ph = f")
    verifier(ClePhonetique.cle("quatre") == ClePhonetique.cle("katre"), "qu = k")
    verifier(ClePhonetique.cle("Brillonia") != "" && ClePhonetique.distance(ClePhonetique.cle("Brillonia"), ClePhonetique.cle("Brionia")) <= 1, "ll écrasé : Brillonia ~ Brionia")
    verifier(ClePhonetique.cle("Ladomir") == ClePhonetique.cle("Ladomirs"), "s final muet")
    verifier(ClePhonetique.cle("") == "" && ClePhonetique.cle("123") == "123", "mot vide ou chiffres")
    verifier(ClePhonetique.distance("chat", "chats") == 1 && ClePhonetique.distance("abc", "abc") == 0 && ClePhonetique.distance("", "ab") == 2, "distance d'édition")
    verifier(ClePhonetique.distance("abcdef", "uvwxyz", plafond: 2) == 3, "distance : arrêt au plafond")
}

groupe("ExtractionLexique")
do {
    var e = ExtractionLexique()
    let inconnus: Set<String> = ["ecoverdix", "brillonia", "zorbaltech", "supabasix", "cee", "iphonix"]
    let connu: (String) -> Bool = { !inconnus.contains(ClePhonetique.plier($0)) }
    let doc1 = """
    # R\u{00E9}union avec Ecoverdix
    Nous avons vu Brillonia hier. Le projet avec Ecoverdix avance, merci. On parle de la fiche TRA-SE-104 et du CEE.
    ```swift
    let zorbaltech = HistoriqueStoreVueModele()
    ```
    Voir https://exemple.zorbaltech.fr/page et /Users/moi/dossier/fichier.md ou contact@zorbaltech.fr.
    Le d\u{00E9}p\u{00F4}t Supabasix est pr\u{00EA}t. Il utilise zorbaltech, iPhonix et monObjetCode. Id: 3f2a9c1b7d4e5a60.
    Aujourd'hui, pour l'Ecoverdix, nous parlons de supabasix et de tableaux.
    """
    e.ajouter(texte: doc1, source: "projet-a", document: 1)
    e.ajouter(texte: "Brillonia et Ecoverdix reviennent. Bonjour. La fiche TRA-SE-104 est la suivante, CEE, CEE, supabasix ! iPhonix encore.", source: "projet-b", document: 2)
    e.ajouter(texte: "Bonjour tout le monde. Bonjour encore. iPhonix supabasix zorbaltech zorbaltech zorbaltech", source: "projet-b", document: 3)
    for (i, texte) in ["Un iPhonix de plus. iPhonix partout.", "Voir iPhonix ici.", "Et iPhonix encore, iPhonix toujours."].enumerated() { e.ajouter(texte: texte, source: "projet-c", document: 10 + i) }
    var seuils = ExtractionLexique.Seuils(); seuils.sigleFrequence = 2
    let c = e.candidats(seuils: seuils, estConnu: connu)
    let mots = Set(c.map(\.mot))
    verifier(mots.contains("Ecoverdix") && mots.contains("Brillonia"), "noms propres retenus")
    verifier(mots.contains("TRA-SE-104") && mots.contains("CEE"), "sigles retenus (TRA-SE-104, CEE)")
    verifier(mots.contains("supabasix") && mots.contains("zorbaltech"), "jargon en minuscules retenu")
    verifier(mots.contains("iPhonix"), "majuscule intérieure retenue")
    verifier(!mots.contains("Bonjour") && !mots.contains("Nous") && !mots.contains("merci"), "mots courants écartés (début de phrase compris)")
    verifier(!mots.contains("HistoriqueStoreVueModele") && !mots.contains("monObjetCode"), "identifiants de code écartés")
    verifier(!c.contains { $0.mot.lowercased().contains("3f2a") || $0.mot.contains("fichier") || $0.mot.contains("exemple") }, "adresses, chemins et hexadécimaux écartés")
    verifier(c.first?.frequence ?? 0 >= (c.last?.frequence ?? 0), "classé par fréquence décroissante")
    verifier(c.first(where: { $0.mot == "Ecoverdix" })?.type == .nom && c.first(where: { $0.mot == "CEE" })?.type == .sigle && c.first(where: { $0.mot == "supabasix" })?.type == .technique, "types : nom, sigle, technique")
    verifier((c.first(where: { $0.mot == "Ecoverdix" })?.documents ?? 0) == 2, "documents distincts comptés")
    var f = ExtractionLexique(); f.ajouterImposes(["Abidjanix"], source: "base"); f.ajouterImposes(["Yamoussoukrix"], source: "base")
    let b = f.candidats(estConnu: connu)
    verifier(b.count == 2 && b.allSatisfy { $0.source == "base" }, "mots imposés gardés malgré une fréquence de 1")
    var g = ExtractionLexique(); g.ajouter(texte: "Le Zorbaltech arrive. Le Zorbaltech repart.", source: "x", document: 1)
    verifier(g.candidats(estConnu: connu).isEmpty == false, "un nom toujours en début de phrase mais inconnu reste candidat")
    var h = ExtractionLexique(); h.ajouter(texte: "Pour moi. Pour toi. Pour nous. Pour eux.", source: "x", document: 1)
    verifier(h.candidats(estConnu: { _ in true }).isEmpty, "tout connu du correcteur : rien")
    var k = ExtractionLexique(); k.ajouter(texte: "Un cree zorbaltech zorbaltech zorbaltech. Un cr\u{00E9}\u{00E9} cr\u{00E9}\u{00E9} cr\u{00E9}\u{00E9} cree cree cree.", source: "x", document: 1); k.ajouter(texte: "cree cr\u{00E9}\u{00E9} zorbaltech", source: "y", document: 2)
    verifier(!k.candidats(estConnu: { ClePhonetique.plier($0) != "zorbaltech" }).contains { $0.mot.hasPrefix("cr") }, "« cree » sans accent n'est pas un mot nouveau si « créé » est connu")
}

groupe("CorrectionOreille")
do {
    let lex = [EntreeLexique(mot: "Brillonia", frequence: 40, source: "a", type: .nom), EntreeLexique(mot: "Ladomir", frequence: 30, source: "a", type: .nom),
               EntreeLexique(mot: "Ecoverdix", frequence: 20, source: "a", type: .nom), EntreeLexique(mot: "CEE", frequence: 50, source: "a", type: .sigle),
               EntreeLexique(mot: "Abidjanix", frequence: 5, source: "base", type: .nom)]
    let index = IndexCorrection(motsChoisis: ["Zorbaltech"], lexique: lex)
    let communs: Set<String> = ["on", "parle", "de", "avec", "demain", "bonjour", "le", "la", "dossier", "merci", "pour", "rendez", "vous", "hier", "ce", "matin", "mon", "ami", "avons", "vu", "et", "du", "nous", "sommes", "chez", "elle", "est", "venue"]
    let connu: (String) -> Bool = { communs.contains(ClePhonetique.plier($0)) }
    func c(_ t: String) -> (String, [Correction]) { let r = CorrectionOreille.corriger(t, index: index, estConnu: connu); return (r.texte, r.corrections) }
    verifier(c("On parle de Brionia demain.").0 == "On parle de Brillonia demain.", "« Brionia » devient « Brillonia »")
    verifier(c("On parle de Brionia demain.").1 == [Correction(original: "Brionia", remplacement: "Brillonia")], "la correction est journalisée")
    verifier(c("Bonjour Ladomire, merci.").0 == "Bonjour Ladomir, merci.", "« Ladomire » devient « Ladomir »")
    verifier(c("Rendez-vous avec Eco verdix demain.").0 == "Rendez-vous avec Ecoverdix demain.", "deux mots collés : « Eco verdix » devient « Ecoverdix »")
    verifier(c("Rendez-vous avec ecoverdix demain.").0 == "Rendez-vous avec ecoverdix demain.", "un nom du lexique en minuscules est laissé tel quel")
    verifier(c("Chez zorbaltech demain.").0 == "Chez Zorbaltech demain.", "un mot choisi par Hugues retrouve sa majuscule")
    let casse = IndexCorrection(motsChoisis: [], lexique: [EntreeLexique(mot: "iPhonix", frequence: 9, source: "a", type: .technique)])
    verifier(CorrectionOreille.corriger("Avec un iphonix demain", index: casse, estConnu: connu).texte == "Avec un iPhonix demain", "majuscule intérieure imposée (iPhonix)")
    verifier(c("Les Brillonias sont venues.").0 == "Les Brillonias sont venues.", "pluriel déjà juste : rien à faire")
    verifier(c("Les brillonias sont venues.").0 == "Les Brillonias sont venues.", "pluriel en minuscules : casse corrigée")
    verifier(c("de l'Brionia").0 == "de l'Brillonia", "élision conservée")
    verifier(c("Zorbaltek est chez nous.").0 == "Zorbaltech est chez nous.", "les mots choisis (mots.txt) servent aussi")
    verifier(c("Merci à l'adomir demain.").0 == "Merci à Ladomir demain.", "le « l' » entendu était la première lettre du nom (l'adomir → Ladomir)")
    verifier(c("Merci à la Domir demain.").0 == "Merci à Ladomir demain.", "mot coupé en deux par Whisper (la Domir → Ladomir)")
    verifier(c("Avec brionia demain").0 == "Avec brillonia demain", "une minuscule de Whisper est gardée pour un nom du lexique")
    verifier(c("Avec Brionia demain").0 == "Avec Brillonia demain", "une majuscule de Whisper est gardée")
    let unelettre = IndexCorrection(motsChoisis: [], lexique: [EntreeLexique(mot: "Vermiflow", frequence: 9, source: "a", type: .nom)])
    verifier(CorrectionOreille.corriger("Chez Vermflow demain", index: unelettre, estConnu: connu).texte == "Chez Vermiflow demain", "une seule lettre de différence dans un mot assez long")
    verifier(CorrectionOreille.corriger("Chez Vermflaw demain", index: unelettre, estConnu: connu).corrections.isEmpty, "deux lettres de différence et sons éloignés : rien")
    let multi = IndexCorrection(motsChoisis: [], lexique: [EntreeLexique(mot: "Prime Zorba", frequence: 9, source: "a", type: .nom)])
    verifier(CorrectionOreille.corriger("Chez Prime Zorba demain", index: multi, estConnu: connu).corrections.isEmpty, "expression de plusieurs mots déjà juste : aucune « correction »")
    // prudence
    let tout: (String) -> Bool = { _ in true }
    verifier(CorrectionOreille.corriger("On parle de Brionia demain.", index: index, estConnu: tout).corrections.isEmpty, "mot connu du correcteur : jamais remplacé")
    verifier(c("La cee est venue, cee.").0 == "La cee est venue, cee.", "moins de 4 lettres : jamais")
    verifier(c("Mon ami Brillonia.").1.isEmpty, "déjà bien écrit : rien")
    verifier(c("contact brionia.fr et @brionia et brionia_test").0 == "contact brionia.fr et @brionia et brionia_test", "adresses et identifiants intouchés")
    verifier(c("Elle est venue pour Marseille.").1.isEmpty, "mot inconnu mais sans ressemblance : rien")
    let ambigu = IndexCorrection(motsChoisis: [], lexique: [EntreeLexique(mot: "Ladomir", frequence: 3, source: "a", type: .nom), EntreeLexique(mot: "Ladomic", frequence: 3, source: "a", type: .nom)])
    verifier(CorrectionOreille.corriger("Bonjour Ladomis", index: ambigu, estConnu: connu).corrections.isEmpty, "deux candidats aussi proches : aucun remplacement")
    verifier(CorrectionOreille.corriger("Bonjour Ladomar", index: IndexCorrection(motsChoisis: [], lexique: []), estConnu: connu).corrections.isEmpty, "lexique vide : rien")
    verifier(c("").0 == "" && c("   ").0 == "   ", "texte vide")
    verifier(Correction(original: String(repeating: "a", count: 100), remplacement: "b").ligneDeJournal.count < 150, "ligne de journal bornée à 60 caractères par côté")
    verifier(c("Bonjour Brionia et Brionia").1.count == 2, "plusieurs occurrences")
}

groupe("ChoixMotsPrompt")
do {
    var lex: [EntreeLexique] = []
    for i in 0..<3000 { lex.append(EntreeLexique(mot: "Mot" + String(repeating: "x", count: i % 9) + String(i), frequence: 3000 - i, documents: 1 + i % 4, source: i % 2 == 0 ? "a" : "b", type: i % 3 == 0 ? .nom : (i % 3 == 1 ? .sigle : .technique))) }
    lex.append(EntreeLexique(mot: "Zorbaltech", frequence: 2, documents: 1, source: "c", type: .nom))
    lex.append(EntreeLexique(mot: "Ecoverdix", frequence: 1, documents: 1, source: "c", type: .nom))
    let ancre = ChoixLangue.phraseAncre(langue: "fr")
    let sans = ChoixMotsPrompt.prompt(motsChoisis: ["Groq", "Whisper"], lexique: [], contexte: ContexteMots(), texteDavant: "La fin du morceau pr\u{00E9}c\u{00E9}dent.", ancre: ancre)
    verifier(sans.hasPrefix(ancre!) && sans.contains("Groq, Whisper.") && sans.hasSuffix("La fin du morceau pr\u{00E9}c\u{00E9}dent."), "sans lexique : ancre, mots choisis, puis fin du texte précédent")
    let p = ChoixMotsPrompt.prompt(motsChoisis: ["Groq", "Whisper"], lexique: lex, contexte: ContexteMots(), texteDavant: nil, ancre: ancre)
    verifier(p.contains("Groq, Whisper,") && p.range(of: "Groq")!.lowerBound < p.range(of: "Mot")!.lowerBound, "mots.txt toujours devant")
    verifier(ChoixMotsPrompt.jetons(p) <= ChoixMotsPrompt.budgetParDefaut, "sous le budget de jetons")
    verifier(!p.contains("Zorbaltech"), "sans contexte, un mot rare du lexique n'entre pas")
    let motsDuPrompt = p.components(separatedBy: ". ").dropFirst().first.map { $0.components(separatedBy: ", ") } ?? []
    verifier(motsDuPrompt.count <= 2 + 10 + 1, "sans contexte : mots.txt et une dizaine de mots fréquents seulement (\(motsDuPrompt.count))")
    let types = Dictionary(uniqueKeysWithValues: lex.map { ($0.mot, $0.type) })
    verifier(motsDuPrompt.filter { types[$0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ] == .sigle }.count <= 2, "sans contexte : deux sigles au plus (Whisper en imite le style)")
    let t = ChoixMotsPrompt.prompt(motsChoisis: [], lexique: lex, contexte: ContexteMots(titreFenetre: "Brouillon pour Zorbaltech \u{2014} Mail"), texteDavant: nil, ancre: ancre)
    verifier(t.contains("Zorbaltech"), "le titre de la fenêtre fait remonter un mot rare")
    let u = ChoixMotsPrompt.prompt(motsChoisis: [], lexique: lex, contexte: ContexteMots(texteAutour: "Bonjour, je reviens vers vous au sujet de l'Ecoverdix et de la suite."), texteDavant: nil, ancre: ancre)
    verifier(u.contains("Ecoverdix"), "le texte autour du curseur fait remonter un mot rare")
    let r = ChoixMotsPrompt.prompt(motsChoisis: [], lexique: lex, contexte: ContexteMots(recents: ["Rien de sp\u{00E9}cial.", "On a parl\u{00E9} de Zorbaltech hier."]), texteDavant: nil, ancre: ancre)
    verifier(r.contains("Zorbaltech"), "les dictées récentes font remonter un mot rare")
    let v = ChoixMotsPrompt.prompt(motsChoisis: [], lexique: lex, contexte: ContexteMots(dejaDicte: "On parle de Zorbaltech"), texteDavant: nil, ancre: ancre)
    verifier(v.contains("Zorbaltech"), "ce qui vient d'être dicté compte aussi")
    var mauvais = 0
    for taille in [0, 5, 80, 400] {
        let longueTexte = String(repeating: "Un texte assez long pour remplir le contexte pr\u{00E9}c\u{00E9}dent. ", count: taille)
        for genre in [AppKind.terminal, .browser, .other] {
            let motsLongs = (0..<(taille / 2)).map { "MotChoisiTresLong\($0)" }
            let q = ChoixMotsPrompt.prompt(motsChoisis: motsLongs, lexique: lex, contexte: ContexteMots(genre: genre, recents: [longueTexte]), texteDavant: longueTexte, ancre: ancre)
            if ChoixMotsPrompt.jetons(q) > ChoixMotsPrompt.budgetParDefaut { mauvais += 1 }
        }
    }
    verifier(mauvais == 0, "jamais au-dessus du budget, même avec un énorme texte précédent et beaucoup de mots choisis")
    let long = ChoixMotsPrompt.prompt(motsChoisis: [], lexique: lex, contexte: ContexteMots(), texteDavant: String(repeating: "mot ", count: 300), ancre: ancre)
    verifier(long.contains(". mot") || long.hasSuffix("mot"), "un long texte précédent est tronqué en gardant sa fin")
    let term = ChoixMotsPrompt.classer(lexique: lex, contexte: ContexteMots(genre: .terminal)).prefix(10)
    let mail = ChoixMotsPrompt.classer(lexique: lex, contexte: ContexteMots(genre: .other)).prefix(10)
    verifier(term.filter { $0.type == .technique }.count > mail.filter { $0.type == .technique }.count, "terminal : plus de termes techniques ; mail : plus de noms")
    verifier(ChoixMotsPrompt.classer(lexique: lex, contexte: ContexteMots(), exclus: [lex[0].mot]).first?.mot != lex[0].mot, "un mot déjà choisi n'est pas répété")
    var grand: [EntreeLexique] = []
    for i in 0..<6000 { grand.append(EntreeLexique(mot: "Terme\(i)x", frequence: 1 + i % 50, documents: 1 + i % 7, source: "s\(i % 9)", type: .nom)) }
    let t0 = ProcessInfo.processInfo.systemUptime
    for _ in 0..<5 { _ = ChoixMotsPrompt.prompt(motsChoisis: ["Groq"], lexique: grand, contexte: ContexteMots(titreFenetre: "Une page quelconque", texteAutour: String(repeating: "du texte avant le curseur ", count: 8), recents: Array(repeating: "une dictée récente avec des mots", count: 20)), texteDavant: "la fin du morceau", ancre: ancre) }
    let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000 / 5
    verifier(ms < 150, "choix des mots pour un lexique de 6 000 mots : \(Int(ms)) ms par dictée (version de contrôle non optimisée)")
    let index6000 = IndexCorrection(motsChoisis: ["Groq"], lexique: grand)
    let t1 = ProcessInfo.processInfo.systemUptime
    for _ in 0..<5 { _ = CorrectionOreille.corriger(String(repeating: "Bonjour, nous parlons de Terme12x et de Termx5y avec Ladomir demain matin chez nous. ", count: 5), index: index6000, estConnu: { _ in false }) }
    let ms2 = (ProcessInfo.processInfo.systemUptime - t1) * 1000 / 5
    verifier(ms2 < 400, "correction à l'oreille d'un texte de 70 mots avec 6 000 mots du lexique : \(Int(ms2)) ms (version de contrôle non optimisée)")
    verifier(ChoixMotsPrompt.prompt(motsChoisis: ["Groq"], lexique: lex, contexte: ContexteMots(), texteDavant: nil, ancre: nil, maxMots: 3).split(separator: ",").count <= 3, "nombre de mots borné")
}

groupe("ApprentissageCorrections")
do {
    let inseree = "Rendez-vous avec Brionia demain matin pour le dossier."
    let fin = " Et ensuite on continue la journ\u{00E9}e comme pr\u{00E9}vu avec tout le monde."
    let avant = inseree + fin
    let inconnu: (String) -> Bool = { ["brillonia", "ecoverdix", "brionia", "ecoverdi"].contains(ClePhonetique.plier($0)) ? false : true }
    verifier(ApprentissageCorrections.remplacements(inseree: inseree, avant: avant, apres: avant.replacingOccurrences(of: "Brionia", with: "Brillonia")) == [.init(ancien: "Brionia", nouveau: "Brillonia")], "mot corrigé détecté")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: avant.replacingOccurrences(of: "Brionia", with: "Brillonia"), estConnu: inconnu) == ["Brillonia"], "le mot corrigé est proposé")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: avant, estConnu: inconnu).isEmpty, "rien changé : rien proposé")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: avant.replacingOccurrences(of: "demain", with: "lundi"), estConnu: inconnu).isEmpty, "mot remplacé par un mot sans rapport : rien proposé")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: "Tout autre chose a \u{00E9}t\u{00E9} \u{00E9}crit ici, bien loin de la dict\u{00E9}e d'avant.", estConnu: inconnu).isEmpty, "champ devenu autre chose : rien proposé")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: avant.replacingOccurrences(of: "Brionia", with: "Brillonia"), estConnu: { _ in true }).isEmpty, "mot connu du correcteur : pas de proposition")
    let ajout = avant + " Je tape encore une suite de mots apr\u{00E8}s."
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: ajout, estConnu: inconnu).isEmpty, "du texte tapé après la dictée : rien proposé")
    let fusion = avant.replacingOccurrences(of: "Brionia demain", with: "Ecoverdix demain")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: fusion, estConnu: inconnu).isEmpty, "mot remplacé par un mot trop différent : rien proposé")
    let colles = "Parlons d'Eco verdi avec elle."
    let a2 = colles + fin
    verifier(ApprentissageCorrections.propositions(inseree: colles, avant: a2, apres: a2.replacingOccurrences(of: "Eco verdi", with: "Ecoverdi"), estConnu: inconnu) == ["Ecoverdi"], "deux mots réunis en un : proposé")
    verifier(ApprentissageCorrections.propositions(inseree: inseree, avant: avant, apres: avant.replacingOccurrences(of: "Rendez-vous", with: "Rendez-vous").replacingOccurrences(of: "dossier", with: "Dossier"), estConnu: { _ in true }).isEmpty, "simple majuscule sur un mot courant : rien")
    var mots = PropositionsMots(); _ = mots.proposer("Brillonia", motsConnus: [])
    verifier(mots.proposer("Brillonia", motsConnus: []) == false, "une proposition déjà en attente n'est pas répétée")
}


// MARK: Notes de réunion

groupe("Réunion : formats, Markdown, archive")
do {
    verifier(FormatReunion.duree(2280) == "38 min" && FormatReunion.duree(4320) == "1 h 12" && FormatReunion.duree(45) == "45 s" && FormatReunion.duree(7200) == "2 h", "durées à la française")
    verifier(FormatReunion.horloge(768) == "12:48" && FormatReunion.horloge(3735) == "1:02:15", "minuterie")
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let debut = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14, minute: 2))!
    let r = Reunion(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, debut: debut, duree: 2280, titre: "Appel Garnier", participants: ["Moi", "Nathalie"],
                    dit: ["Nathalie veut équiper ses ateliers."], decisions: ["Offre complète retenue."],
                    actions: [ActionReunion(qui: "Moi", quoi: "Envoyer la proposition", quand: "jeudi"), ActionReunion(qui: nil, quoi: "Valider le budget", fait: true)],
                    segments: [SegmentReunion(debut: 12, fin: 20, locuteur: .moi, texte: "Bonjour."), SegmentReunion(debut: 30, fin: 40, locuteur: .eux, texte: "Bonjour, on commence ?")], etat: .prete)
    let md = ReunionMarkdown.rendre(r, calendrier: cal)
    verifier(md.hasPrefix("# Appel Garnier\n"), "Markdown : titre")
    verifier(md.contains("- [ ] **Moi** : Envoyer la proposition (jeudi)") && md.contains("- [x] Valider le budget"), "Markdown : prochaines étapes cochables avec qui et quand")
    verifier(md.contains("## Ce qui a été dit") && md.contains("## Décisions") && md.contains("## Prochaines étapes") && md.contains("**Moi** · 14:02\nBonjour.") && md.contains("**Eux**\nBonjour, on commence ?"),
             "Markdown : ancienne note (« dit »), transcription avec l'orateur, l'heure seulement à la première ligne de chaque minute")
    verifier(!ReunionMarkdown.rendre(Reunion(debut: debut, titre: "Vide"), calendrier: cal).contains("## "), "Markdown : une réunion vide n'a aucune section")
    verifier(ArchiveReunions.decoder(ArchiveReunions.encoder(r)!) == r, "JSON aller-retour")
    verifier(ArchiveReunions.decoder(Data("pas du json".utf8)) == nil, "JSON abîmé : nil")
    verifier(ArchiveReunions.nomDeBase(r, calendrier: cal) == "2026-11-09_1402_11111111", "nom de fichier stable")
    verifier(Reunion(debut: debut).titreAffiche.hasPrefix("Réunion du "), "titre de repli d'après le jour")
    verifier(r.voix == 2 && r.motsTranscrits == 5, "voix et mots transcrits")
    var enCours = r; enCours.etat = .transcription
    verifier(ArchiveReunions.reprendreApresArret(enCours).etat == .sansNote && ArchiveReunions.reprendreApresArret(enCours).avertissements.count == 1, "arrêt brutal : sans note + avertissement, transcription gardée")
    verifier(ArchiveReunions.reprendreApresArret(r) == r, "une réunion finie n'est pas touchée")
}

groupe("Réunion : fusion des pistes Moi / Eux")
do {
    func s(_ d: Double, _ f: Double, _ l: Locuteur, _ t: String) -> SegmentReunion { SegmentReunion(debut: d, fin: f, locuteur: l, texte: t) }
    let moi = [s(10, 14, .moi, "Bonjour Nathalie, merci de me recevoir."), s(40, 44, .moi, "Je vous envoie la proposition jeudi.")]
    let eux = [s(2, 8, .eux, "Bonjour Camille."), s(20, 30, .eux, "Alors le prix reste le point sensible pour mon associé.")]
    let f = FusionPistes.fusionner(moi: moi, eux: eux)
    verifier(f.map(\.locuteur) == [.eux, .moi, .eux, .moi], "fusion : ordre chronologique")
    verifier(FusionPistes.fusionner(moi: [s(5, 6, .moi, "a")], eux: [s(5, 6, .eux, "b")]).map(\.locuteur) == [.eux, .moi], "même instant : Eux avant Moi")
    // écho : la voix des autres captée par le micro
    let echo = [s(21, 31, .moi, "alors le prix reste le point sensible pour mon associé")]
    let r = FusionPistes.retirerEchos(moi: moi + echo, eux: eux)
    verifier(r.retires == 1 && r.moi.count == 2, "écho du haut-parleur retiré de la piste Moi")
    verifier(FusionPistes.retirerEchos(moi: [s(21, 31, .moi, "Oui, d'accord avec ça.")], eux: eux).retires == 0, "une vraie réponse pendant que l'autre parle est gardée")
    verifier(FusionPistes.retirerEchos(moi: [s(100, 110, .moi, "alors le prix reste le point sensible pour mon associé")], eux: eux).retires == 0, "même texte mais bien plus tard : gardé")
    verifier(FusionPistes.retirerEchos(moi: [s(21, 22, .moi, "le prix")], eux: eux).retires == 0, "phrase de moins de 4 mots : jamais retirée")
    let mele = FusionPistes.retirerEchos(moi: [s(18, 40, .moi, "Je vous écoute attentivement. Alors le prix reste le point sensible pour mon associé. Oui je comprends très bien.")], eux: eux)
    verifier(mele.retires == 1 && mele.moi.count == 1 && mele.moi[0].texte == "Je vous écoute attentivement. Oui je comprends très bien.", "écho mêlé à la vraie voix dans un même morceau : seule la phrase d'écho est retirée")
    verifier(FusionPistes.phrases("Bonjour. Ça va ? Oui!Non. Fin") == ["Bonjour.", "Ça va ?", "Oui!Non.", "Fin"], "découpe en phrases")
    let g = FusionPistes.regrouper([s(0, 10, .moi, "Je pense que"), s(11, 20, .moi, "oui."), s(30, 35, .moi, "Plus tard."), s(36, 40, .eux, "Ok.")])
    verifier(g.count == 3 && g[0].texte == "Je pense que oui." && g[0].fin == 20, "regroupement : même locuteur, silence court")
    verifier(g[1].debut == 30 && g[2].locuteur == .eux, "regroupement : silence long ou autre locuteur = nouveau passage")
    let t = FusionPistes.transcription(moi: moi + echo, eux: eux)
    verifier(t.echos == 1 && t.segments.count == 4, "transcription complète : écho retiré, fusion, regroupement")
    verifier(FusionPistes.mots("L'été, c'est Ça !") == ["l", "ete", "c", "est", "ca"], "mots sans accents ni ponctuation")
}

groupe("Réunion : découpe du son et de la transcription")
do {
    let c = DecoupeReunion.configurationSon()
    verifier(c.minChunkFrames == 500 && c.forcedCutFrames == 1500, "morceaux de 10 à 30 s")
    // un découpeur fait à la main : 25 s de parole continue, puis 1 s de silence, puis 12 s de parole, silence
    var d = VoiceChunker(config: c)
    var coupes: [VoiceChunker.Range] = []
    func nourrir(_ secondes: Double, _ db: Float) { for _ in 0..<Int(secondes * 50) { if let r = d.feed(levelDb: db) { coupes.append(r) } } }
    nourrir(1, -70); nourrir(25, -20); nourrir(1, -70); nourrir(12, -20); nourrir(2, -70)
    verifier(coupes.count == 2, "25 s de parole, 1 s de silence, 12 s de parole, silence : deux morceaux (\(coupes.count))")
    if let r = coupes.first { verifier(r.count / 16000 >= 24 && r.count / 16000 <= 26, "premier morceau de ~25 s (micro-pause après 20 s)") }
    if coupes.count > 1 { verifier(coupes[1].count / 16000 >= 12 && coupes[1].count / 16000 <= 14, "second morceau de ~12 s (pause de 0,6 s après 10 s)") }
    var d2 = VoiceChunker(config: c)
    var forcees = 0
    for _ in 0..<(40 * 50) { if d2.feed(levelDb: -20) != nil { forcees += 1 } }
    verifier(forcees == 1, "40 s de parole d'une traite : une coupe forcée vers 30 s")
    var d3 = VoiceChunker(config: c)
    var longueurs: [Int] = []
    for _ in 0..<5 { for _ in 0..<(2 * 50) { if let r = d3.feed(levelDb: -20) { longueurs.append(r.count / 16000) } }; for _ in 0..<(1 * 50) { if let r = d3.feed(levelDb: -70) { longueurs.append(r.count / 16000) } } }
    verifier(longueurs.count == 1 && longueurs[0] >= 9, "des phrases de 2 s séparées de 1 s : un seul morceau d'au moins 10 s, pas un par phrase (\(longueurs))")
    func s(_ d: Double, _ t: String) -> SegmentReunion { SegmentReunion(debut: d, fin: d + 5, locuteur: .moi, texte: t) }
    let segs = (0..<10).map { s(Double($0) * 6, String(repeating: "mot ", count: 50)) }
    let p = DecoupeReunion.parties(segs, maxCaracteres: 700)
    verifier(p.count > 1 && p.flatMap { $0 }.count == 10 && p.allSatisfy { !$0.isEmpty }, "transcription longue : plusieurs parties, aucun passage perdu")
    verifier(DecoupeReunion.parties(Array(segs.prefix(2))).count == 1, "transcription courte : une seule partie")
    verifier(DecoupeReunion.parties([]).isEmpty, "aucun passage : aucune partie")
    verifier(DecoupeReunion.ligne(SegmentReunion(debut: 764, fin: 770, locuteur: .eux, texte: "Oui.")) == "[12:44] Eux : Oui.", "ligne de transcription pour la rédaction")
}

groupe("Réunion : budgets (requêtes, audio, jetons)")
do {
    let b = BudgetRequetes(limiteMinute: 18, margeAnticipation: 8, margeSecours: 4)
    verifier(b.delaiAvantDePermettre(.anticipation, a: 100) == 0, "budget vide : la réunion envoie tout de suite")
    for i in 0..<11 { b.noterEnvoi(a: 100 + Double(i)) }   // 11 envois dans la minute : il reste 7 < 8
    verifier(!b.permet(.anticipation, a: 112), "dictée active : la réunion cède (marge de 8 gardée pour la dictée)")
    let attente = b.delaiAvantDePermettre(.anticipation, a: 112)
    verifier(attente > 0 && attente <= 60, "elle sait attendre : \(Int(attente)) s")
    verifier(b.delaiAvantDePermettre(.anticipation, a: 112 + attente + 0.01) == 0 || b.permet(.anticipation, a: 112 + attente + 0.01), "après ce délai, elle peut partir")
    b.noter429(retryAfter: 40, a: 112)
    verifier(b.delaiAvantDePermettre(.anticipation, a: 113) >= 39, "après un 429 : elle attend la fin de la pause")
    let a = BudgetAudio(limiteHeure: 7200, reserveDictee: 1500)
    verifier(BudgetAudio.facture(duree: 3) == 10 && BudgetAudio.facture(duree: 25) == 25, "Groq compte au moins 10 s par requête")
    verifier(a.delaiAvant(duree: 25, a: 0) == 0 && a.restantPourReunion(a: 0) == 5700, "5 700 s par heure pour la réunion, 1 500 s gardées pour la dictée")
    for i in 0..<228 { a.noter(duree: 25, a: Double(i)) }   // 5 700 s
    verifier(a.delaiAvant(duree: 25, a: 300) > 0, "quota d'audio atteint : elle attend")
    verifier(a.delaiAvant(duree: 25, a: 300) <= 3600, "…mais pas plus d'une heure")
    verifier(a.restantPourReunion(a: 300) == 0, "rien de plus pour la réunion")
    verifier(a.delaiAvant(duree: 25, a: 3601) == 0, "une heure plus tard : de la place")
    let j = BudgetJetons(limiteMinute: 8000)
    verifier(j.delaiAvant(jetons: 5000, a: 0) == 0, "note : première requête tout de suite")
    j.noter(jetons: 5000, a: 0)
    verifier(j.delaiAvant(jetons: 5000, a: 5) > 40, "note : la suivante attend la fin de la minute")
    verifier(j.delaiAvant(jetons: 5000, a: 61) == 0, "note : une minute plus tard, tout de suite")
    verifier(DecoupeReunion.jetons(String(repeating: "a", count: 3000)) == 1001, "estimation des jetons")
}

groupe("Réunion : note (lecture de la réponse, garde anti-invention)")
do {
    let json = """
    ```json
    {"titre": "Offre Garnier et calendrier", "dit": ["Nathalie veut équiper deux ateliers.", "Le prix reste sensible."], "decisions": ["Offre complète retenue, sans formation."],
     "actions": [{"qui": "Moi", "quoi": "Envoyer la proposition chiffrée", "quand": "jeudi"}, {"qui": "Nathalie", "quoi": "Valider le budget", "quand": null}, "Transmettre les volumes"],
     "participants": ["Nathalie", "Paul", "Moi"]}
    ```
    """
    let n = NoteReunion.analyser(json)
    verifier(n?.titre == "Offre Garnier et calendrier" && n?.decisions.count == 1 && n?.actions.count == 3, "lecture d'un JSON entouré de ```")
    verifier(n?.actions[0].qui == "Moi" && n?.actions[0].quand == "jeudi" && n?.actions[1].quand == nil && n?.actions[2].quoi == "Transmettre les volumes", "actions : qui, quoi, quand ou rien")
    verifier(NoteReunion.analyser("Voici la note : pas de JSON") == nil && NoteReunion.analyser("{pas du json}") == nil, "réponse sans JSON exploitable : nil")
    verifier(NoteReunion.analyser("{\"points\": [\"a\", \"b\"], \"decisions\": [], \"actions\": []}")?.dit == ["a", "b"] && NoteReunion.analyser("{\"resume\": \"Un texte.\"}")?.dit == ["Un texte."], "« points » ou un « resume » en texte : lus comme des points")
    verifier(NoteReunion.analyser("{\"titre\": \"null\", \"resume\": \"  \", \"decisions\": [\"\", \"x\"]}")?.decisions == ["x"] && NoteReunion.analyser("{\"titre\": \"null\"}")?.titre == "", "valeurs vides ou « null » ignorées")
    func s(_ t: String, _ l: Locuteur = .eux) -> SegmentReunion { SegmentReunion(debut: 0, fin: 1, locuteur: l, texte: t) }
    let dit = [s("Bonjour, c'est Nathalie. On prend l'offre complète pour Lyon, sans la formation, et on signe avant le vingt novembre."),
               s("Je valide le budget avec mon associé jeudi.", .moi), s("Paul vous donnera les volumes vendredi, environ 1200 pièces.")]
    let garde = GardeInvention(segments: dit)
    verifier(garde.soutenu("Offre complète retenue pour Lyon, sans la formation"), "garde : phrase soutenue par la transcription")
    verifier(!garde.soutenu("Rendez-vous chez Garnier à Annecy"), "garde : noms propres jamais dits refusés")
    verifier(garde.soutenu("Paul transmet les volumes"), "garde : un prénom dit est accepté")
    verifier(garde.soutenu("Signature avant le 20 novembre") && garde.soutenu("1200 pièces") && !garde.soutenu("Budget de 45000 euros"), "garde : nombres en chiffres ou en lettres, mais jamais inventés")
    verifier(garde.dit("Nathalie") && garde.dit("Nathali") && !garde.dit("Camille"), "garde : écriture presque pareille acceptée")
    let brute = NoteBrute(titre: "Appel avec Garnier à Annecy", dit: ["Nathalie prend l'offre complète.", "Le rendez-vous est chez Morel à Paris."], decisions: ["Offre complète sans formation", "Livraison à Annecy en mars"],
                          actions: [ActionReunion(qui: "Camille", quoi: "Envoyer la proposition", quand: "jeudi 12 novembre"), ActionReunion(qui: "Paul", quoi: "Donner les volumes", quand: "vendredi"),
                                    ActionReunion(qui: "Moi", quoi: "Valider le budget", quand: "mardi"), ActionReunion(quoi: "Appeler Dupont")], participants: ["Nathalie", "Paul", "Camille", "Moi"])
    let (propre, retraits) = garde.nettoyer(brute)
    verifier(propre.titre == "", "garde : titre avec un nom inventé retiré")
    verifier(propre.dit == ["Nathalie prend l'offre complète."], "garde : le point avec des noms inventés est retiré")
    verifier(propre.decisions == ["Offre complète sans formation"], "garde : décision inventée retirée, vraie décision gardée")
    verifier(propre.actions.count == 3 && !propre.actions.contains { $0.quoi.contains("Dupont") }, "garde : action avec un nom inventé retirée")
    verifier(propre.actions[0].qui == nil && propre.actions[0].quand == nil, "garde : « qui » inventé et « quand » non dit retirés, la tâche reste")
    verifier(propre.actions[1].qui == "Paul" && propre.actions[1].quand == "vendredi", "garde : qui et quand dits sont gardés")
    verifier(propre.actions[2].quand == nil && propre.actions[2].qui == "Moi", "garde : « mardi » jamais dit est retiré, « Moi » reste")
    verifier(propre.participants == ["Nathalie", "Paul"], "garde : participants dits seulement, sans Moi (ajouté ailleurs)")
    verifier(!retraits.isEmpty, "garde : ce qui a été retiré est listé pour le journal")
    let rien = GardeInvention(segments: dit).nettoyer(NoteBrute(titre: "Offre complète et signature", dit: ["On signe avant le vingt novembre."], decisions: [], actions: [], participants: []))
    verifier(rien.retraits.isEmpty && rien.note.titre == "Offre complète et signature", "garde : une note fidèle n'est pas touchée")
}

groupe("Réunion : « D'un coup d'œil » (échéances, tri, liste, citations)")
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let lundi = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14, minute: 2))!   // lundi 9 novembre 2026
    func quand(_ t: String) -> Echeance.Analyse { Echeance.analyser(t, depuis: lundi, calendrier: cal) }
    verifier(quand("jeudi").date == "2026-11-12" && quand("vendredi").date == "2026-11-13", "échéance : un nom de jour = le jour suivant la réunion (lundi + jeudi = le 12)")
    verifier(quand("lundi").date == "2026-11-16", "échéance : le jour même de la réunion = la semaine suivante, pas aujourd'hui")
    verifier(quand("mercredi soir").date == "2026-11-11" && quand("mercredi soir").moment == "soir" && quand("jeudi matin").moment == "matin" && quand("vendredi après-midi").moment == "après-midi", "échéance : moment de la journée gardé")
    verifier(quand("avant le vingt novembre").date == "2026-11-20" && quand("avant le vingt novembre").avant && !quand("jeudi").avant, "échéance : « avant le vingt novembre » = limite le 20")
    verifier(quand("le 20 novembre").date == "2026-11-20" && quand("jeudi 12 novembre").date == "2026-11-12" && quand("le vingt et un novembre").date == "2026-11-21" && quand("le premier décembre").date == "2026-12-01" && quand("1er décembre").date == "2026-12-01", "échéance : jour et mois en chiffres ou en lettres")
    verifier(quand("le trois novembre").date == "2027-11-03" && quand("le 3 novembre 2026").date == "2026-11-03", "échéance : une date déjà passée = l'an prochain, sauf année dite")
    verifier(quand("le 31 novembre").date == nil, "échéance : un jour qui n'existe pas ne donne rien")
    verifier(quand("demain").date == "2026-11-10" && quand("après-demain").date == "2026-11-11" && quand("ce soir").date == "2026-11-09" && quand("aujourd'hui").date == "2026-11-09", "échéance : demain, après-demain, ce soir")
    verifier(quand("dans trois jours").date == "2026-11-12" && quand("dans huit jours").date == "2026-11-16" && quand("dans deux semaines").date == "2026-11-23" && quand("dans un mois").date == "2026-12-09", "échéance : « dans … »")
    verifier(quand("d'ici la fin du mois").date == "2026-11-30" && quand("d'ici la fin du mois").avant && quand("fin de semaine").date == "2026-11-13", "échéance : fin du mois, fin de semaine")
    verifier(quand("bientôt").date == nil && quand("la semaine prochaine").date == nil && quand("").date == nil && quand("en novembre").date == nil, "échéance : trop vague = pas de date")
    verifier(Echeance.date("2026-11-12", calendrier: cal) != nil && Echeance.date("2026-02-30", calendrier: cal) == nil && Echeance.date("pas une date", calendrier: cal) == nil, "date lue ou refusée")
    verifier(Echeance.etiquette(quand: "mercredi soir", date: "2026-11-11", calendrier: cal).texte == "mer. 11 nov. · soir" && Echeance.etiquette(quand: "mercredi soir", date: "2026-11-11", court: true, calendrier: cal).texte == "mer. 11 · soir", "étiquette : jour, date et moment")
    verifier(Echeance.etiquette(quand: "avant le vingt novembre", date: "2026-11-20", calendrier: cal).texte == "avant le 20 nov." && Echeance.etiquette(quand: "avant le premier décembre", date: "2026-12-01", calendrier: cal).texte == "avant le 1er déc.", "étiquette : limite « avant le 20 nov. »")
    verifier(Echeance.etiquette(quand: nil, date: nil).sansDate && Echeance.etiquette(quand: nil, date: nil).texte == "sans date" && Echeance.etiquette(quand: "  ", date: nil).sansDate, "étiquette : « sans date » quand rien n'est dit")
    verifier(Echeance.etiquette(quand: "la semaine prochaine", date: nil).texte == "la semaine prochaine" && !Echeance.etiquette(quand: "la semaine prochaine", date: nil).sansDate, "étiquette : l'expression dite quand elle ne donne pas de date")

    let a1 = ActionReunion(qui: "Moi", quoi: "Proposition", quand: "mercredi soir", echeance: "2026-11-11")
    let a2 = ActionReunion(qui: "Nathalie", quoi: "Budget", quand: "jeudi", echeance: "2026-11-12")
    let a3 = ActionReunion(qui: "Paul", quoi: "Volumes", quand: "vendredi", echeance: "2026-11-13")
    let a4 = ActionReunion(qui: "Moi", quoi: "Livraison")
    let a5 = ActionReunion(qui: "Moi", quoi: "Fiche", fait: true)
    let a6 = ActionReunion(qui: "Paul", quoi: "Contrat", quand: "la semaine prochaine")
    let a7 = ActionReunion(qui: "Moi", quoi: "Matin", quand: "mercredi matin", echeance: "2026-11-11")
    let t = ActionsReunion.triees([a4, a3, a5, a6, a2, a1, a7])
    verifier(t.aFaire.map(\.quoi) == ["Matin", "Proposition", "Budget", "Volumes", "Contrat", "Livraison"], "tri : par date, le matin avant le soir, puis l'échéance en texte, puis « sans date »")
    verifier(t.faites.map(\.quoi) == ["Fiche"], "tri : les actions faites à part")
    verifier(ActionsReunion.triees([]).aFaire.isEmpty && ActionsReunion.triees([a4, a6]).aFaire.map(\.quoi) == ["Contrat", "Livraison"], "tri : sans date");

    var garnier = Reunion(debut: lundi, duree: 2280, titre: "Appel Garnier", dit: ["Deux ateliers, Lyon et Annecy"], actions: [a1, a2, a5], etat: .prete)
    var r = ResumeReunion.de(garnier)
    verifier(r.aFaire == 2 && r.faites == 1 && r.premiere == "2026-11-11" && !r.toutFait && r.noteEcrite, "liste : « 2 à faire dès mer. 11 »")
    verifier(r.enBref == "Deux ateliers, Lyon et Annecy", "liste : une ancienne note sans « En bref » montre son premier point")
    garnier.enBref = "Offre retenue."
    verifier(ResumeReunion.de(garnier).enBref == "Offre retenue.", "liste : « En bref » quand il existe")
    garnier.actions = [a5]
    r = ResumeReunion.de(garnier)
    verifier(r.toutFait && r.aFaire == 0 && r.premiere == nil, "liste : tout fait")
    var sans = Reunion(debut: lundi, etat: .sansNote)
    verifier(!ResumeReunion.de(sans).noteEcrite && !ResumeReunion.de(sans).toutFait, "liste : sans note")
    sans.etat = .prete
    let liste = [Reunion(debut: lundi, actions: [a1], etat: .prete), Reunion(debut: lundi, actions: [a5], etat: .prete), Reunion(debut: lundi, actions: [a1, a2], etat: .sansNote), Reunion(debut: lundi, actions: [a1, a2, a3], etat: .prete)]
    verifier(ListeReunions.avecActions(liste).count == 2 && ListeReunions.totalActions(liste) == 4, "liste : filtre « avec des actions à faire » et total (les réunions sans note ne comptent pas)")
    let cherche = Reunion(debut: lundi, titre: "Appel Garnier", segments: [SegmentReunion(debut: 0, fin: 5, locuteur: .eux, texte: "La livraison à Annecy")], etat: .prete, enBref: "Signature visée avant le 20 novembre")
    verifier(ListeReunions.correspond(cherche, requete: "signature NOVEMBRE") && ListeReunions.correspond(cherche, requete: "garnier annecy") && ListeReunions.correspond(cherche, requete: "") && !ListeReunions.correspond(cherche, requete: "lyon"), "recherche : titre, « En bref » et transcription, sans casse ni accents")

    // citations
    let seg = [SegmentReunion(debut: 12, fin: 30, locuteur: .moi, texte: "Bonjour Nathalie. Je propose qu'on reprenne l'offre point par point, et qu'on finisse avec le calendrier."),
               SegmentReunion(debut: 1300, fin: 1320, locuteur: .eux, texte: "Le prix reste le point sensible. J'en parle à mon associé jeudi, et j'aurais besoin de la proposition chiffrée avant."),
               SegmentReunion(debut: 1500, fin: 1510, locuteur: .moi, texte: "D'accord, je vous envoie la proposition avec les deux options mercredi soir.")]
    let c1 = CitationsReunion.trouver(point: "Prix sensible", proposee: "j'en parle à mon associé jeudi", segments: seg)
    verifier(c1?.segment == 1 && c1?.texte == "J'en parle à mon associé jeudi", "citation : la phrase proposée est rendue telle qu'elle est dans la transcription (casse, majuscule)")
    let c2 = CitationsReunion.trouver(point: "x", proposee: "« Le prix reste le point SENSIBLE. »", segments: seg)
    verifier(c2?.segment == 1 && c2?.texte == "Le prix reste le point sensible.", "citation : guillemets et casse du modèle ignorés, ponctuation de la phrase gardée")
    verifier(CitationsReunion.trouver(point: "Offre à reprendre", proposee: "on reprenne l’offre point par point", segments: seg)?.texte == "on reprenne l'offre point par point", "citation : apostrophe typographique ou droite")
    let c3 = CitationsReunion.trouver(point: "Envoi de la proposition avec deux options mercredi soir", proposee: "Le modèle a inventé cette phrase entièrement", segments: seg)
    verifier(c3?.segment == 2 && c3?.texte == "D'accord, je vous envoie la proposition avec les deux options mercredi soir.", "citation : phrase inventée refusée, la vraie phrase la plus proche est prise à la place")
    verifier(CitationsReunion.trouver(point: "Troisième atelier l'an prochain", proposee: nil, segments: seg) == nil, "citation : rien de proche dans la transcription = pas de citation")
    verifier(CitationsReunion.trouver(point: "Prix sensible", proposee: "prix", segments: seg)?.segment == 1, "citation : proposition trop courte ignorée, recherche du plus proche")
    verifier(CitationsReunion.trouver(point: "", proposee: nil, segments: seg) == nil && CitationsReunion.trouver(point: "Prix", proposee: nil, segments: []) == nil, "citation : cas vides")
    let toutes = seg.map(\.texte)
    for (point, proposee) in [("Prix", "Le prix reste le point sensible"), ("Calendrier", "Qu'on finisse avec le calendrier."), ("Envoi", "je vous envoie la proposition"), ("Prix sensible, associé", nil), ("Proposition mercredi", "inventée de toutes pièces ici")] as [(String, String?)] {
        if let c = CitationsReunion.trouver(point: point, proposee: proposee, segments: seg) { verifier(toutes[c.segment].contains(c.texte), "citation « \(c.texte) » : portion exacte de la transcription") }
    }

    // la note rédigée -> la réunion
    let json = """
    {"titre": "Offre Garnier", "en_bref": "Offre complète retenue, signature avant le vingt novembre.",
     "dit": [{"point": "Prix sensible, associé jeudi", "citation": "J'en parle à mon associé jeudi"}, {"point": "Calendrier", "citation": null}, "Un point en texte seul"],
     "decisions": [{"quoi": "Signature visée", "quand": "avant le vingt novembre"}, {"quoi": "Paiement en deux fois", "quand": null}, "Offre complète"],
     "actions": [{"qui": "Moi", "quoi": "Envoyer la proposition", "quand": "mercredi soir"}, {"qui": "Nathalie", "quoi": "Valider le budget", "quand": "jeudi"}, {"qui": "Moi", "quoi": "Vérifier la livraison", "quand": null}],
     "participants": ["Nathalie"]}
    """
    let brute = NoteReunion.analyser(json)
    verifier(brute?.enBref == "Offre complète retenue, signature avant le vingt novembre." && brute?.dit.count == 3 && brute?.citations == ["J'en parle à mon associé jeudi", "", ""], "note : « En bref » et points avec citation (objet, null ou texte seul)")
    verifier(brute?.decisions == ["Signature visée", "Paiement en deux fois", "Offre complète"] && brute?.decisionsQuand == ["avant le vingt novembre", "", ""], "note : décisions avec échéance (objet ou texte)")
    var reunion = Reunion(debut: lundi, duree: 2280, segments: seg, etat: .prete)
    if let brute { NoteReunion.appliquer(brute, a: &reunion, segments: seg, calendrier: cal) }
    verifier(reunion.enBref != nil && reunion.dit.count == 3 && reunion.participants == ["Moi", "Nathalie"], "appliquer : titre, « En bref », participants")
    verifier(reunion.citation(point: 0)?.texte == "J'en parle à mon associé jeudi" && reunion.citation(point: 0)?.locuteur == .eux && reunion.citation(point: 0)?.debut == 1300 && reunion.citation(point: 2) == nil, "appliquer : citation, qui et heure pris dans le passage de la transcription ; pas de citation quand rien n'est proche")
    verifier(reunion.citation(point: 1)?.texte.contains("calendrier") == true && reunion.citation(point: 1)?.locuteur == .moi && reunion.citation(point: 1)?.debut == 12, "appliquer : sans citation donnée par le modèle, la phrase la plus proche de la transcription")
    verifier(reunion.echeance(decision: 0)?.date == "2026-11-20" && reunion.echeance(decision: 1) == nil && reunion.echeance(decision: 2) == nil, "appliquer : échéance de la décision en vraie date")
    verifier(reunion.actions.map(\.echeance) == ["2026-11-11", "2026-11-12", nil], "appliquer : échéances des actions en vraies dates (mercredi = le 11, jeudi = le 12, rien = rien)")
    verifier(ArchiveReunions.decoder(ArchiveReunions.encoder(reunion)!) == reunion, "JSON aller-retour avec les nouveaux champs")
    // une ancienne note (sans aucun nouveau champ) se lit encore
    let ancien = """
    {"id": "11111111-2222-3333-4444-555555555555", "debut": "2026-11-09T13:02:00Z", "duree": 600, "titre": "Ancienne", "participants": ["Moi"], "dit": ["Un point"], "decisions": ["Une décision"],
     "actions": [{"id": "11111111-2222-3333-4444-555555555556", "quoi": "Faire", "quand": "jeudi", "fait": false}], "segments": [], "etat": "prete", "avertissements": [], "sonGarde": false}
    """
    let vieille = ArchiveReunions.decoder(Data(ancien.utf8))
    verifier(vieille != nil && vieille?.enBref == nil && vieille?.citations == nil && vieille?.actions.first?.echeance == nil && vieille?.citation(point: 0) == nil && vieille?.echeance(decision: 0) == nil, "ancienne note sans les nouveaux champs : lue sans erreur")
    if let vieille {
        verifier(ResumeReunion.de(vieille).enBref == "Un point" && ResumeReunion.de(vieille).aFaire == 1, "ancienne note : liste dégradée proprement")
        verifier(Echeance.etiquette(quand: vieille.actions[0].quand, date: vieille.actions[0].echeance).texte == "jeudi", "ancienne note : l'échéance reste telle que dite")
    }
    // la garde garde l'alignement points / citations
    let g = GardeInvention(segments: seg).nettoyer(NoteBrute(titre: "", dit: ["Point inventé chez Morel", "Prix sensible"], decisions: ["Signature chez Dupont", "Paiement"], participants: [], enBref: "Un résumé chez Morel", citations: ["x", "J'en parle à mon associé jeudi"], decisionsQuand: ["avant le vingt", "mardi"]))
    verifier(g.note.dit == ["Prix sensible"] && g.note.citations == ["J'en parle à mon associé jeudi"] && g.note.decisions == ["Paiement"] && g.note.decisionsQuand == [""] && g.note.enBref == "", "garde : points, citations et décisions restent alignés ; « En bref » inventé retiré ; « quand » jamais dit retiré")
    // consigne : un souhait n'est pas une décision
    verifier(NoteReunion.consigneNote.contains("n'est PAS une décision") && NoteReunion.consigneNote.contains("on aimerait") && NoteReunion.consigneNote.contains("en_bref") && NoteReunion.consigneNote.contains("\"sujets\""), "consigne : souhait ≠ décision (avec exemple), phrase d'ouverture et sujets demandés")
    verifier(NoteReunion.consigneAssemblage.contains("\"sujets\"") && NoteReunion.consignePartie.contains("MOT POUR MOT"), "consignes de partie (points et citation exacte) et d'assemblage (sujets)")
    let md = ReunionMarkdown.rendre(reunion, calendrier: cal)
    verifier(md.contains("\n\nOffre complète retenue") && md.contains("- Signature visée (avant le vingt novembre)"), "Markdown : phrase d'ouverture et échéance des décisions")
}

groupe("Réunion : état de l'encoche")
do {
    var m = MachineReunion()
    verifier(m.phase == .repos && !m.arreter() && !m.pause(), "au repos : arrêter et pause n'ont aucun effet")
    verifier(m.lancer() && m.enregistre && !m.lancer(), "lancer : une seule réunion à la fois")
    verifier(m.pause() && m.enPause && !m.pause(), "pause")
    verifier(m.reprendre() && !m.enPause && !m.reprendre(), "reprendre")
    verifier(m.proposer(app: "Zoom") == false, "jamais de proposition pendant l'enregistrement")
    verifier(m.arreter() && m.phase == .traitement && m.enTraitement == 1, "arrêter : traitement en arrière-plan")
    let id = UUID()
    m.traitementFini(note: id)
    verifier(m.phase == .prete(id) && m.enTraitement == 0, "note prête annoncée")
    m.acquitter()
    verifier(m.phase == .repos, "Ouvrir ou délai : retour au repos")
    var n = MachineReunion()
    n.lancer(); n.arreter(); n.lancer()
    verifier(n.enregistre && n.enTraitement == 1, "on peut en relancer une pendant le traitement de la précédente")
    let id2 = UUID()
    n.traitementFini(note: id2)
    verifier(n.enregistre && n.noteEnAttente == id2, "note prête pendant un nouvel enregistrement : mise de côté")
    n.arreter()
    verifier(n.phase == .traitement, "arrêt de la seconde")
    n.annoncerNoteEnAttente()
    verifier(n.phase == .prete(id2), "à l'arrêt, la première note est annoncée")
    var p = MachineReunion()
    verifier(p.proposer(app: "Zoom") && p.phase == .proposition(app: "Zoom"), "proposition au repos")
    p.refuserProposition()
    verifier(p.phase == .repos, "« Non » : retour au repos")
    verifier(p.proposer(app: "Teams") && p.lancer() && p.enregistre, "« Noter » : l'enregistrement part")
    var q = MachineReunion(); q.lancer(); q.arreter(); q.traitementFini(note: nil)
    verifier(q.phase == .repos, "échec du traitement sans note : retour au repos")
    var r = MachineReunion(); r.message("Micro seul"); verifier(r.phase == .message("Micro seul"), "message court au repos")
    r.lancer(); r.message("autre"); verifier(r.enregistre, "un message ne remplace jamais l'enregistrement")
}

groupe("Réunion : horloge")
do {
    let h = HorlogeReunion(maintenant: 100)
    verifier(h.temps(a: 160) == 60, "horloge : 60 s après 60 s")
    h.pause(a: 160)
    verifier(h.temps(a: 400) == 60, "horloge : arrêtée pendant la pause")
    h.reprendre(a: 400)
    verifier(h.temps(a: 430) == 90, "horloge : la pause n'est pas comptée")
    h.pause(a: 430); h.pause(a: 500); h.reprendre(a: 530); h.reprendre(a: 600)
    verifier(h.temps(a: 540) == 100, "horloge : pauses et reprises répétées sans effet")
}

groupe("Réunion : détection d'un appel")
do {
    verifier(DetectionAppel.reconnaitre(bundleID: "us.zoom.xos")?.nom == "Zoom", "Zoom reconnu")
    verifier(DetectionAppel.reconnaitre(bundleID: "com.microsoft.teams2")?.nom == "Teams", "Teams reconnu")
    verifier(DetectionAppel.reconnaitre(bundleID: "com.google.Chrome.helper")?.nom == "Chrome", "processus auxiliaire de Chrome reconnu (Meet dans un navigateur)")
    verifier(DetectionAppel.reconnaitre(bundleID: "com.apple.FaceTime")?.nom == "FaceTime", "FaceTime reconnu")
    verifier(DetectionAppel.reconnaitre(bundleID: "io.aircall.workspace")?.nom == "Aircall" && DetectionAppel.reconnaitre(bundleID: "net.whatsapp.WhatsApp.ServiceExtension")?.nom == "WhatsApp" && DetectionAppel.reconnaitre(bundleID: "com.hnc.Discord")?.nom == "Discord", "identifiants lus sur les apps installées ici : Aircall, WhatsApp, Discord")
    verifier(DetectionAppel.reconnaitre(bundleID: "com.anthropic.claudefordesktop") == nil && DetectionAppel.reconnaitre(bundleID: "com.apple.Siri") == nil && DetectionAppel.reconnaitre(bundleID: "com.apple.Terminal") == nil && DetectionAppel.reconnaitre(bundleID: "com.apple.corespeechd_system") == nil, "Claude, Siri, Terminal, reconnaissance vocale du système : jamais de proposition")
    verifier(DetectionAppel.reconnaitre(bundleID: "com.apple.Notes") == nil, "une app inconnue ne propose rien")
    verifier(DetectionAppel.reconnaitre(bundleID: "com.electron.wispr-flow") == nil && DetectionAppel.reconnaitre(bundleID: "com.apple.assistant_service") == nil, "dictée et assistant vocal ne proposent rien")
    verifier(DetectionAppel.appEnAppel(bundleIDs: ["com.hugues.dictee", "com.apple.FaceTime"])?.nom == "FaceTime", "Verbe lui-même est ignoré")
    verifier(DetectionAppel.appEnAppel(bundleIDs: ["com.hugues.dictee"]) == nil, "Verbe seul : rien")
    verifier(DetectionAppel.appEnAppel(bundleIDs: ["com.google.Chrome.helper", "us.zoom.xos"])?.nom == "Zoom", "l'app d'appel passe avant le navigateur")
    var s = SuiveurAppel()
    let zoom = DetectionAppel.reconnaitre(bundleID: "us.zoom.xos")
    verifier(s.observer(app: zoom, reunionEnCours: false, maintenant: 0) == nil, "début d'écoute : rien tout de suite")
    verifier(s.observer(app: zoom, reunionEnCours: false, maintenant: 4) == nil, "4 s : encore rien (test de micro)")
    verifier(s.observer(app: zoom, reunionEnCours: false, maintenant: 6)?.nom == "Zoom", "6 s d'écoute continue : proposition")
    verifier(s.observer(app: zoom, reunionEnCours: false, maintenant: 8) == nil && s.observer(app: zoom, reunionEnCours: false, maintenant: 600) == nil, "une seule proposition par appel")
    verifier(s.observer(app: nil, reunionEnCours: false, maintenant: 700) == nil, "fin de l'appel")
    verifier(s.observer(app: zoom, reunionEnCours: false, maintenant: 800) == nil && s.observer(app: zoom, reunionEnCours: false, maintenant: 806)?.nom == "Zoom", "un nouvel appel : une nouvelle proposition")
    var t = SuiveurAppel()
    _ = t.observer(app: zoom, reunionEnCours: true, maintenant: 0)
    verifier(t.observer(app: zoom, reunionEnCours: false, maintenant: 10) == nil, "réunion déjà en cours dans l'épisode : jamais de proposition")
    var u = SuiveurAppel()
    _ = u.observer(app: zoom, reunionEnCours: false, maintenant: 0)
    _ = u.observer(app: nil, reunionEnCours: false, maintenant: 3)
    verifier(u.observer(app: zoom, reunionEnCours: false, maintenant: 7)?.nom == "Zoom", "coupure brève du micro : l'épisode continue")
}


// MARK: Mise à jour automatique
groupe("Mise à jour : versions")
do {
    func v(_ t: String) -> VersionApp { VersionApp(t)! }
    verifier(v("0.2.10") > v("0.2.9"), "0.2.10 > 0.2.9 (comparaison par nombres, pas par texte)")
    verifier(v("0.3") == v("0.3.0") && v("v0.3.0") == v("0.3"), "0.3 == 0.3.0, préfixe v accepté")
    verifier(v("1.0.0") > v("0.99.99") && v("0.3.0") > v("0.2.2"), "ordre des versions")
    verifier(!(v("0.2.2") > v("0.2.2")) && !(v("0.2.2") < v("0.2.2")), "versions égales")
    verifier(VersionApp("") == nil && VersionApp("0.3.0-beta") == nil && VersionApp("abc") == nil && VersionApp("1..2") == nil && VersionApp("0.x") == nil, "versions illisibles refusées")
    verifier(VersionApp("1.2.3.4.5") == nil && VersionApp("1234567.0") == nil && VersionApp("-1.0") == nil, "versions trop longues ou négatives refusées")
    verifier(v("v0.3.0").description == "0.3.0", "affichage sans le v")
}

func releaseJSON(tag: String = "v0.3.0", brouillon: Bool = false, prerelease: Bool = false, assets: [(String, Int?, String?, String)]? = nil, corps: String = "# Verbe 0.3.0\n- une chose") -> Data {
    let a = assets ?? [("Verbe-0.3.0.dmg", 1_500_000, "sha256:" + String(repeating: "ab", count: 32), "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.3.0.dmg"),
                       ("Verbe-0.3.0.dmg.sha256", 90, nil, "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.3.0.dmg.sha256")]
    let liste = a.map { (nom, taille, digest, url) -> [String: Any] in
        var d: [String: Any] = ["name": nom, "browser_download_url": url]
        if let taille { d["size"] = taille }
        if let digest { d["digest"] = digest }
        return d
    }
    let json: [String: Any] = ["tag_name": tag, "html_url": "https://github.com/proladislas-rgb/dictee-mac/releases/tag/\(tag)", "body": corps,
                               "draft": brouillon, "prerelease": prerelease, "assets": liste]
    return try! JSONSerialization.data(withJSONObject: json)
}

groupe("Mise à jour : choix de la release et de l'asset")
do {
    let actuelle = VersionApp("0.2.2")!
    if case .proposition(let p) = ChoixMiseAJour.analyser(json: releaseJSON(), versionActuelle: actuelle) {
        verifier(p.version == VersionApp("0.3.0")! && p.nomDMG == "Verbe-0.3.0.dmg", "release plus récente : proposition de 0.3.0")
        verifier(p.taille == 1_500_000 && p.dmgURL.lastPathComponent == "Verbe-0.3.0.dmg", "asset Verbe-<version>.dmg choisi")
        verifier(p.empreinteJSON == String(repeating: "ab", count: 32), "empreinte du champ digest lue")
        verifier(p.empreinteURL?.lastPathComponent == "Verbe-0.3.0.dmg.sha256", "fichier .sha256 repéré")
        verifier(p.notes.contains("une chose") && p.pageURL != nil, "notes et page de la release gardées")
    } else { verifier(false, "release plus récente : proposition de 0.3.0") }
    verifier(ChoixMiseAJour.analyser(json: releaseJSON(), versionActuelle: VersionApp("0.3.0")!) == .aJour, "même version : à jour")
    verifier(ChoixMiseAJour.analyser(json: releaseJSON(), versionActuelle: VersionApp("0.4.0")!) == .aJour, "version installée plus récente : à jour")
    verifier(ChoixMiseAJour.analyser(json: releaseJSON(tag: "v0.2.10"), versionActuelle: VersionApp("0.2.9")!) != .aJour, "0.2.10 est plus récente que 0.2.9")
    verifier(ChoixMiseAJour.analyser(json: releaseJSON(brouillon: true), versionActuelle: actuelle) == .aJour, "brouillon ignoré")
    verifier(ChoixMiseAJour.analyser(json: releaseJSON(prerelease: true), versionActuelle: actuelle) == .aJour, "pré-version ignorée")
    verifier(ChoixMiseAJour.analyser(json: Data("pas du json".utf8), versionActuelle: actuelle) == .illisible, "JSON abîmé : illisible, pas de plantage")
    verifier(ChoixMiseAJour.analyser(json: releaseJSON(tag: "nightly"), versionActuelle: actuelle) == .illisible, "tag illisible : rien proposé")
    verifier(ChoixMiseAJour.analyser(json: Data("{}".utf8), versionActuelle: actuelle) == .illisible, "JSON vide : illisible")
    let autre = [("Verbe-0.2.9.dmg", 1_000_000, nil, "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.2.9.dmg"),
                 ("Verbe.dmg", 1_000_000, nil, "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe.dmg")] as [(String, Int?, String?, String)]
    if case .inutilisable = ChoixMiseAJour.analyser(json: releaseJSON(assets: autre), versionActuelle: actuelle) { verifier(true, "aucun asset au bon nom : jamais un autre fichier") }
    else { verifier(false, "aucun asset au bon nom : jamais un autre fichier") }
    let ailleurs = [("Verbe-0.3.0.dmg", 1_000_000, nil, "https://evil.example.com/proladislas-rgb/dictee-mac/Verbe-0.3.0.dmg")] as [(String, Int?, String?, String)]
    if case .inutilisable = ChoixMiseAJour.analyser(json: releaseJSON(assets: ailleurs), versionActuelle: actuelle) { verifier(true, "adresse hors GitHub refusée") } else { verifier(false, "adresse hors GitHub refusée") }
    let http = [("Verbe-0.3.0.dmg", 1_000_000, nil, "http://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.3.0.dmg")] as [(String, Int?, String?, String)]
    if case .inutilisable = ChoixMiseAJour.analyser(json: releaseJSON(assets: http), versionActuelle: actuelle) { verifier(true, "adresse en http refusée") } else { verifier(false, "adresse en http refusée") }
    let autreDepot = [("Verbe-0.3.0.dmg", 1_000_000, nil, "https://github.com/quelquun/autre/releases/download/v0.3.0/Verbe-0.3.0.dmg")] as [(String, Int?, String?, String)]
    if case .inutilisable = ChoixMiseAJour.analyser(json: releaseJSON(assets: autreDepot), versionActuelle: actuelle) { verifier(true, "autre dépôt GitHub refusé") } else { verifier(false, "autre dépôt GitHub refusé") }
    let grosse = [("Verbe-0.3.0.dmg", 900_000_000, nil, "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.3.0.dmg")] as [(String, Int?, String?, String)]
    if case .inutilisable = ChoixMiseAJour.analyser(json: releaseJSON(assets: grosse), versionActuelle: actuelle) { verifier(true, "fichier trop gros refusé") } else { verifier(false, "fichier trop gros refusé") }
    let sansTaille = [("Verbe-0.3.0.dmg", nil, nil, "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.3.0.dmg")] as [(String, Int?, String?, String)]
    if case .inutilisable = ChoixMiseAJour.analyser(json: releaseJSON(assets: sansTaille), versionActuelle: actuelle) { verifier(true, "taille absente : refusé") } else { verifier(false, "taille absente : refusé") }
    let sansEmpreinte = [("Verbe-0.3.0.dmg", 1_000_000, nil, "https://github.com/proladislas-rgb/dictee-mac/releases/download/v0.3.0/Verbe-0.3.0.dmg")] as [(String, Int?, String?, String)]
    if case .proposition(let p) = ChoixMiseAJour.analyser(json: releaseJSON(assets: sansEmpreinte), versionActuelle: actuelle) { verifier(p.empreinteJSON == nil && p.empreinteURL == nil, "ancienne release sans empreinte : proposée, sans empreinte") }
    else { verifier(false, "ancienne release sans empreinte : proposée, sans empreinte") }
    verifier(PolitiqueAdresses.production.accepteRedirection(URL(string: "https://objects.githubusercontent.com/github-production-release-asset/abc")!), "redirection vers objects.githubusercontent.com permise")
    verifier(!PolitiqueAdresses.production.accepteRedirection(URL(string: "https://githubusercontent.com.evil.fr/x")!), "faux sous-domaine refusé")
    verifier(!PolitiqueAdresses.production.accepte(URL(string: "https://user:mdp@github.com/proladislas-rgb/dictee-mac/x")!), "adresse avec identifiants refusée")
    verifier(PolitiqueAdresses.local.accepte(URL(string: "http://127.0.0.1:8123/Verbe-9.9.9.dmg")!) && !PolitiqueAdresses.production.accepte(URL(string: "http://127.0.0.1:8123/x")!), "http local permis seulement en mode de test")
}

groupe("Mise à jour : empreinte SHA-256")
do {
    let h = String(repeating: "0123456789abcdef", count: 4)
    verifier(EmpreinteSHA256.depuisDigest("sha256:" + h) == h, "digest GitHub lu")
    verifier(EmpreinteSHA256.depuisDigest("sha1:" + h) == nil && EmpreinteSHA256.depuisDigest("sha256:zz") == nil && EmpreinteSHA256.depuisDigest("sha256:" + h.uppercased()) == h, "digest : mauvais algorithme ou longueur refusés, majuscules acceptées")
    verifier(EmpreinteSHA256.depuisFichier("\(h)  Verbe-0.3.0.dmg\n", nomFichier: "Verbe-0.3.0.dmg") == h, "fichier .sha256 de shasum")
    verifier(EmpreinteSHA256.depuisFichier("\(h) *Verbe-0.3.0.dmg", nomFichier: "Verbe-0.3.0.dmg") == h, "variante binaire (*nom)")
    verifier(EmpreinteSHA256.depuisFichier(h + "\n", nomFichier: "Verbe-0.3.0.dmg") == h, "empreinte seule")
    verifier(EmpreinteSHA256.depuisFichier("\(h)  Verbe-0.2.0.dmg", nomFichier: "Verbe-0.3.0.dmg") == nil, "fichier .sha256 d'une autre version refusé")
    verifier(EmpreinteSHA256.depuisFichier("<html>404</html>", nomFichier: "Verbe-0.3.0.dmg") == nil && EmpreinteSHA256.depuisFichier("", nomFichier: "x") == nil, "page d'erreur ou fichier vide refusés")
    verifier(EmpreinteSHA256.depuisFichier("\(h)  Verbe-0.3.0.dmg\n\(h)  autre.dmg", nomFichier: "Verbe-0.3.0.dmg") == nil, "plusieurs lignes : refusé")
    verifier(EmpreinteSHA256.correspond(calculee: h, attendues: [h, h.uppercased()]), "empreintes identiques")
    verifier(!EmpreinteSHA256.correspond(calculee: h, attendues: [h, String(repeating: "f", count: 64)]), "une seule empreinte différente suffit à refuser")
    verifier(EmpreinteSHA256.correspond(calculee: h, attendues: []), "aucune empreinte publiée : rien à comparer")
    var c = EmpreinteSHA256.Calcul(); c.ajouter(Data("abc".utf8))
    verifier(c.resultat() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" && c.octets == 3, "SHA-256 de « abc » (valeur connue)")
    var d = EmpreinteSHA256.Calcul(); d.ajouter(Data("a".utf8)); d.ajouter(Data("bc".utf8))
    verifier(d.resultat() == c.resultat(), "calcul par morceaux identique au calcul d'un bloc")
    let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("controle-sha-\(UUID().uuidString)")
    try! Data("abc".utf8).write(to: fichier)
    verifier((try? EmpreinteSHA256.calculer(fichier: fichier)) == c.resultat(), "SHA-256 d'un fichier")
    try? FileManager.default.removeItem(at: fichier)
}

groupe("Mise à jour : quand vérifier GitHub")
do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func apres(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    verifier(PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: nil, derniereTentative: nil, pasAvant: nil, maintenant: t0), "jamais vérifié : on vérifie")
    verifier(!PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: t0, derniereTentative: t0, pasAvant: nil, maintenant: apres(23 * 3600)), "moins de 24 h : non")
    verifier(PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: t0, derniereTentative: t0, pasAvant: nil, maintenant: apres(24 * 3600 + 1)), "24 h passées : oui")
    verifier(!PlanVerification.doitVerifierSeul(automatique: false, derniereReussite: nil, derniereTentative: nil, pasAvant: nil, maintenant: t0), "interrupteur coupé : jamais seul")
    verifier(!PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: nil, derniereTentative: t0, pasAvant: nil, maintenant: apres(600)), "échec récent (hors ligne) : pas de nouvelle tentative avant 30 min")
    verifier(PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: nil, derniereTentative: t0, pasAvant: nil, maintenant: apres(1801)), "30 min après l'échec : on réessaie")
    verifier(!PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: nil, derniereTentative: nil, pasAvant: apres(1800), maintenant: t0), "limite de l'API atteinte : on attend l'heure donnée")
    verifier(PlanVerification.doitVerifierSeul(automatique: true, derniereReussite: apres(10 * 24 * 3600), derniereTentative: nil, pasAvant: nil, maintenant: t0), "dernière vérification dans le futur (horloge reculée) : on revérifie")
    verifier(!PlanVerification.demandePermise(derniereTentative: t0, pasAvant: nil, maintenant: apres(5)), "deux demandes à moins de 10 s : la seconde est refusée")
    verifier(PlanVerification.demandePermise(derniereTentative: t0, pasAvant: nil, maintenant: apres(11)), "demande 11 s après : permise")
    verifier(!PlanVerification.demandePermise(derniereTentative: nil, pasAvant: apres(100), maintenant: t0), "demande pendant la pause imposée par GitHub : refusée")
    verifier(PlanVerification.pasAvant(statut: 200, enTetes: [:], maintenant: t0) == nil && PlanVerification.pasAvant(statut: 404, enTetes: [:], maintenant: t0) == nil, "réponses normales : pas de pause")
    verifier(PlanVerification.pasAvant(statut: 429, enTetes: ["Retry-After": "120"], maintenant: t0) == apres(120), "429 avec Retry-After : on attend ce délai")
    verifier(PlanVerification.pasAvant(statut: 403, enTetes: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(t0.timeIntervalSince1970) + 1500)"], maintenant: t0) == apres(1500), "403 limite atteinte : on attend l'heure de remise à zéro")
    verifier(PlanVerification.pasAvant(statut: 403, enTetes: [:], maintenant: t0) == apres(3600), "403 sans précision : une heure")
}

groupe("Mise à jour : afficher ou non la proposition")
do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let actuelle = VersionApp("0.3.0")!, neuve = VersionApp("0.3.1")!
    func peut(_ c: ContexteAffichage = ContexteAffichage(), report: ReportProposition? = nil, version: VersionApp = neuve, maintenant: Date = t0) -> Bool {
        AffichageMiseAJour.peutProposer(version: version, versionActuelle: actuelle, contexte: c, report: report, maintenant: maintenant)
    }
    verifier(peut(), "rien en cours : on propose")
    verifier(!peut(ContexteAffichage(dicteeEnCours: true)), "jamais pendant une dictée")
    verifier(!peut(ContexteAffichage(reunionEnCours: true)), "jamais pendant une réunion")
    verifier(!peut(ContexteAffichage(autreAnnonce: true)), "jamais par-dessus une autre annonce de l'encoche")
    verifier(!peut(ContexteAffichage(installationPossible: false)), "jamais si l'app ne peut pas se remplacer (DMG, dossier en lecture seule)")
    verifier(!peut(version: actuelle), "version déjà installée : rien")
    let report = ReportProposition.plusTard(version: neuve, maintenant: t0)
    verifier(!peut(report: report, maintenant: t0.addingTimeInterval(3600)), "« Plus tard » : rien une heure après")
    verifier(!peut(report: report, maintenant: t0.addingTimeInterval(23 * 3600)), "« Plus tard » : rien 23 h après")
    verifier(peut(report: report, maintenant: t0.addingTimeInterval(24 * 3600 + 1)), "« Plus tard » : le lendemain, on repropose")
    verifier(peut(report: report, version: VersionApp("0.3.2")!, maintenant: t0.addingTimeInterval(3600)), "une version plus récente que celle repoussée est proposée tout de suite")
    verifier(peut(report: ReportProposition(version: neuve, jusqua: t0.addingTimeInterval(30 * 24 * 3600)), maintenant: t0), "report absurde (horloge déréglée) ignoré")
    verifier(AffichageMiseAJour.peutRedemarrer(contexte: ContexteAffichage()) && !AffichageMiseAJour.peutRedemarrer(contexte: ContexteAffichage(dicteeEnCours: true)) && !AffichageMiseAJour.peutRedemarrer(contexte: ContexteAffichage(reunionEnCours: true)), "le redémarrage attend la fin d'une dictée ou d'une réunion")
}

groupe("Mise à jour : emplacement et contrôle de l'app")
do {
    typealias E = EmplacementApp
    verifier(E.evaluer(chemin: "/Applications/Verbe.app", volumeEnLectureSeule: false, dossierEcrivable: true) == .possible, "/Applications modifiable : possible")
    verifier(E.evaluer(chemin: "/Users/x/Applications/Verbe.app", volumeEnLectureSeule: false, dossierEcrivable: true) == .possible, "~/Applications : possible")
    verifier(E.evaluer(chemin: "/Volumes/Verbe/Verbe.app", volumeEnLectureSeule: true, dossierEcrivable: false) != .possible, "depuis l'image disque : refusé")
    verifier(E.evaluer(chemin: "/private/var/folders/x/AppTranslocation/ABC/d/Verbe.app", volumeEnLectureSeule: false, dossierEcrivable: true) != .possible, "dossier translocalisé : refusé")
    verifier(E.evaluer(chemin: "/Applications/Verbe.app", volumeEnLectureSeule: true, dossierEcrivable: true) != .possible, "volume en lecture seule : refusé")
    verifier(E.evaluer(chemin: "/Applications/Verbe.app", volumeEnLectureSeule: false, dossierEcrivable: false) != .possible, "dossier non modifiable : refusé")
    verifier(E.evaluer(chemin: "/Users/x/dictee-mac/.build/release/Dictee", volumeEnLectureSeule: false, dossierEcrivable: true) != .possible, "binaire nu (hors app) : refusé")
    let sortie = "Executable=/x/Verbe\nIdentifier=com.hugues.dictee\nFormat=app bundle with Mach-O thin (arm64)\nSignature=adhoc\n"
    verifier(ControleApp.identifiant(sortieCodesign: sortie) == "com.hugues.dictee" && ControleApp.identifiant(sortieCodesign: "rien") == nil, "identifiant lu dans la sortie de codesign")
    let v = VersionApp("0.3.1")!
    verifier(ControleApp.refus(identifiantAttendu: "com.hugues.dictee", identifiantSignature: "com.hugues.dictee", identifiantPlist: "com.hugues.dictee", versionAttendue: v, versionPlist: "0.3.1") == nil, "app conforme : acceptée")
    verifier(ControleApp.refus(identifiantAttendu: "com.hugues.dictee", identifiantSignature: "com.autre.app", identifiantPlist: "com.hugues.dictee", versionAttendue: v, versionPlist: "0.3.1") != nil, "autre identifiant de signature : refusée")
    verifier(ControleApp.refus(identifiantAttendu: "com.hugues.dictee", identifiantSignature: "com.hugues.dictee", identifiantPlist: "com.autre.app", versionAttendue: v, versionPlist: "0.3.1") != nil, "autre identifiant dans Info.plist : refusée")
    verifier(ControleApp.refus(identifiantAttendu: "com.hugues.dictee", identifiantSignature: "com.hugues.dictee", identifiantPlist: "com.hugues.dictee", versionAttendue: v, versionPlist: "0.2.0") != nil, "version différente de celle annoncée (retour en arrière déguisé) : refusée")
    verifier(ControleApp.refus(identifiantAttendu: "com.hugues.dictee", identifiantSignature: nil, identifiantPlist: "com.hugues.dictee", versionAttendue: v, versionPlist: "0.3.1") != nil, "signature illisible : refusée")
}

groupe("Mise à jour : notes de version")
do {
    let b = NotesDeVersion.blocs("# Verbe 0.3.0\n\nIntro avec **gras** et [un lien](https://x.fr).\n\n## Ce qui change\n- **Mise à jour** automatique\n* Une autre `chose`\n<script>alert(1)</script>\n![img](http://x/y.png)\nFin")
    verifier(!b.contains(.titre("Verbe 0.3.0")), "le premier titre (le nom de la version) n'est pas répété")
    verifier(b.first == .paragraphe("Intro avec gras et un lien."), "gras et liens réduits au texte")
    verifier(b.contains(.titre("Ce qui change")) && b.contains(.puce("Mise à jour automatique")) && b.contains(.puce("Une autre chose")), "titres et puces")
    verifier(!b.contains { if case .paragraphe(let t) = $0 { return t.contains("<") || t.contains("http") } else { return false } }, "ni HTML ni adresse dans le texte montré")
    verifier(NotesDeVersion.blocs("").isEmpty && NotesDeVersion.blocs(String(repeating: "a\n", count: 10_000)).count < 5000, "notes vides ou démesurées : sans danger")
}

groupe("Journée : agrégation, moyenne, série, meilleure journée")
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!; cal.locale = Locale(identifier: "fr_FR")
    func date(_ j: Int, _ h: Int, _ m: Int = 0, mois: Int = 11) -> Date { cal.date(from: DateComponents(year: 2026, month: mois, day: j, hour: h, minute: m))! }
    func mots(_ n: Int) -> String { Array(repeating: "mot", count: n).joined(separator: " ") }
    func e(_ j: Int, _ h: Int, _ n: Int, app: String? = "Mail", parole: Double? = nil, insere: Bool = true, m: Int = 0, mois: Int = 11) -> EntreeHistorique {
        EntreeHistorique(date: date(j, h, m, mois: mois), appId: app.map { "id." + $0 }, appNom: app, texte: mots(n), insere: insere, dureeParole: parole)
    }
    let lundi = date(9, 12)   // lundi 9 novembre 2026

    // agrégation par heure et par app
    let jour = [e(9, 10, 58, parole: 20), e(9, 10, 7, app: "Notes", parole: 4), e(9, 10, 94, app: "Claude", parole: 30), e(9, 14, 40, parole: 12), e(8, 10, 500), e(9, 15, 30, insere: false)]
    let r = Journee.resume(jour: lundi, entrees: jour, calendrier: cal)
    verifier(r.dictees == 5 && r.mots == 58 + 7 + 94 + 40 + 30, "résumé : seulement les dictées du jour (hier ignoré)")
    verifier(r.motsParHeure.count == 24 && r.motsParHeure[10] == 159 && r.motsParHeure[14] == 40 && r.motsParHeure[9] == 0, "mots par heure : 24 cases, 10 h = 159, 14 h = 40")
    verifier(r.dicteesParHeure[10] == 3 && r.dicteesParHeure[14] == 1, "dictées par heure")
    verifier(r.heurePic == 10, "heure du pic = 10 h")
    verifier(r.apps.map(\.nom) == ["Mail", "Claude", "Notes"] && r.apps.map(\.mots) == [98, 94, 7], "apps : classées par mots, la dictée non écrite n'y est pas")
    verifier(r.dureeParole == 66 && r.sansDuree == 1, "temps de parole : somme des durées enregistrées, une dictée sans durée comptée à part")
    verifier(abs(r.tempsGagne - (Double(r.mots) / 40 * 60 - 66)) < 0.001, "temps gagné = mots ÷ 40 par minute, moins la parole")
    verifier(Journee.tempsGagne(mots: 10, dureeParole: 600) == 0, "temps gagné jamais négatif")
    let vide = Journee.resume(jour: lundi, entrees: [], calendrier: cal)
    verifier(vide.mots == 0 && vide.dictees == 0 && vide.heurePic == nil && vide.apps.isEmpty && vide.motsParHeure == Array(repeating: 0, count: 24), "journée sans dictée : tout à zéro, pas de pic")
    let egalite = Journee.resume(jour: lundi, entrees: [e(9, 16, 10), e(9, 9, 10)], calendrier: cal)
    verifier(egalite.heurePic == 9, "pic à égalité : la plus tôt")
    let tard = Journee.resume(jour: lundi, entrees: [EntreeHistorique(date: cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23, minute: 59))!, texte: "a b")], calendrier: cal)
    verifier(tard.motsParHeure[23] == 2, "23 h 59 reste dans la journée, case 23")
    // ancien historique (sans dureeParole) : se lit sans erreur
    let ancien = Data(#"{"entrees":[{"id":"6F0F2C2B-9C61-4A0B-8F1B-1E6A4A9D3A11","date":"2026-11-09T09:00:00Z","texte":"Bonjour","insere":true}]}"#.utf8)
    verifier(Historique.depuis(ancien)?.entrees.first?.dureeParole == nil && Historique.depuis(ancien)?.entrees.count == 1, "ancien historique sans durée de parole : lu, durée absente")
    var avecDuree = Historique(); avecDuree.ajouter(EntreeHistorique(texte: "x", dureeParole: 2.5))
    verifier(avecDuree.donnees().flatMap { Historique.depuis($0) }?.entrees.first?.dureeParole == 2.5, "durée de parole : enregistrée et relue")

    // moyenne glissante : 14 derniers jours actifs avant le jour
    var longue: [EntreeHistorique] = []
    for k in 1...20 { longue.append(e(k, 10, 100 * k, mois: 10)) }   // 20 jours actifs d'octobre : 100, 200 ... 2000 mots (1er au 20)
    longue.append(e(9, 10, 777))
    let moy = Journee.moyenne(avant: lundi, entrees: longue, calendrier: cal)
    verifier(moy?.jours == 14, "moyenne : 14 jours actifs au plus")
    verifier(moy.map { abs($0.mots - (Double((7...20).reduce(0) { $0 + 100 * $1 }) / 14)) < 0.001 } == true, "moyenne : les 14 derniers jours actifs (7 au 20), pas le jour lui-même")
    verifier(Journee.moyenne(avant: date(1, 12, mois: 10), entrees: longue, calendrier: cal) == nil, "premier jour : pas de moyenne")
    let trous = [e(2, 10, 100), e(4, 10, 300), e(5, 10, 500)]
    verifier(Journee.moyenne(avant: date(6, 12), entrees: trous, calendrier: cal)?.jours == 3 && Journee.moyenne(avant: date(6, 12), entrees: trous, calendrier: cal)?.mots == 300, "moyenne : les jours sans dictée ne comptent pas (3 jours actifs)")
    verifier(Journee.moyenne(avant: date(4, 12), entrees: trous, calendrier: cal)?.jours == 1, "moyenne : seulement les jours avant")

    // série
    let suite = [e(9, 10, 5), e(8, 10, 5), e(7, 10, 5), e(5, 10, 5), e(4, 10, 5)]
    verifier(Journee.serie(jusquA: lundi, entrees: suite, maintenant: lundi, calendrier: cal) == 3, "série : 9, 8, 7 de suite (le 6 manque)")
    verifier(Journee.serie(jusquA: date(8, 9), entrees: suite, maintenant: lundi, calendrier: cal) == 2, "série : se termine le jour affiché")
    verifier(Journee.serie(jusquA: lundi, entrees: [e(8, 10, 5), e(7, 10, 5)], maintenant: lundi, calendrier: cal) == 2, "série : aujourd'hui sans dictée, celle d'hier n'est pas rompue")
    verifier(Journee.serie(jusquA: date(9, 9), entrees: [e(8, 10, 5)], maintenant: date(10, 9), calendrier: cal) == 0, "série : un jour passé sans dictée = 0")
    verifier(Journee.serie(jusquA: lundi, entrees: [], maintenant: lundi, calendrier: cal) == 0, "série : rien = 0")

    // meilleure journée
    let jours = [e(5, 10, 300), e(5, 11, 400), e(6, 10, 700), e(9, 10, 700)]
    verifier(Journee.meilleure(entrees: jours, calendrier: cal)?.mots == 700 && Journee.meilleure(entrees: jours, calendrier: cal)?.jour == cal.startOfDay(for: lundi), "meilleure journée : égalité, la plus récente")
    verifier(Journee.meilleure(entrees: jours, avant: lundi, calendrier: cal)?.jour == cal.startOfDay(for: date(6, 9)), "meilleure journée avant le jour affiché")
    verifier(Journee.meilleure(entrees: [], calendrier: cal) == nil, "meilleure journée : rien = nil")

    // les 7 derniers jours
    let sept = Journee.septJours(jusquA: lundi, entrees: suite, maintenant: lundi, calendrier: cal)
    verifier(sept.count == 7 && sept.last?.etiquette == "auj." && sept.first?.etiquette == "mar." && sept[5].etiquette == "dim.", "7 jours : de mardi à aujourd'hui")
    verifier(sept.map(\.mots) == [0, 5, 5, 0, 5, 5, 5], "7 jours : mots de chaque jour (0 quand rien)")
    verifier(Journee.septJours(jusquA: date(8, 9), entrees: suite, maintenant: lundi, calendrier: cal).last?.etiquette == "dim.", "7 jours : un jour passé garde son nom")

    // les dictées d'une heure, heures voisines
    let h10 = Journee.dictees(jour: lundi, heure: 10, entrees: jour, calendrier: cal)
    verifier(h10.count == 3 && h10.map(\.date) == h10.map(\.date).sorted(), "dictées d'une heure : celles de l'heure, dans l'ordre de la journée")
    verifier(Journee.dictees(jour: lundi, heure: 11, entrees: jour, calendrier: cal).isEmpty, "heure sans dictée : liste vide")
    verifier(Journee.heureVoisine(motsParHeure: r.motsParHeure, depuis: 10, delta: 1) == 14 && Journee.heureVoisine(motsParHeure: r.motsParHeure, depuis: 14, delta: -1) == 10, "heure voisine : saute les heures vides")
    verifier(Journee.heureVoisine(motsParHeure: r.motsParHeure, depuis: 15, delta: 1) == nil && Journee.heureVoisine(motsParHeure: r.motsParHeure, depuis: 10, delta: -1) == nil, "heure voisine : aucune au-delà des extrémités")
}

groupe("Journée : courbe, formats")
do {
    var parHeure = Array(repeating: 0, count: 24)
    verifier(Journee.plageHeures(motsParHeure: parHeure) == (8, 18), "plage : 8 h à 18 h par défaut")
    parHeure[6] = 10; parHeure[21] = 10
    verifier(Journee.plageHeures(motsParHeure: parHeure) == (6, 22), "plage : élargie aux heures actives, bornes paires")
    parHeure[5] = 3; parHeure[23] = 3
    verifier(Journee.plageHeures(motsParHeure: parHeure) == (4, 24), "plage : plafonnée à 24 h")
    verifier(Journee.ligneRepere(pic: 700) == 400 && Journee.ligneRepere(pic: 1_000) == 500 && Journee.ligneRepere(pic: 90) == 50 && Journee.ligneRepere(pic: 3) == nil, "ligne repère : nombre rond sous le pic (700 → 400)")
    verifier(FormatJournee.nombre(4120) == "4\u{00A0}120" && FormatJournee.nombre(980) == "980" && FormatJournee.nombre(1_250_000) == "1\u{00A0}250\u{00A0}000" && FormatJournee.nombre(0) == "0", "nombres : espace insécable des milliers")
    verifier(FormatJournee.duree(80 * 60) == "1\u{00A0}h\u{00A0}20" && FormatJournee.duree(56 * 60) == "55\u{00A0}min" && FormatJournee.duree(7 * 60) == "7\u{00A0}min" && FormatJournee.duree(60 * 60) == "1\u{00A0}h" && FormatJournee.duree(10) == "moins d\u{2019}une minute", "durées : arrondies (1 h 20, 55 min, 7 min, 1 h)")
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    verifier(FormatJournee.heureLongue(cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9, minute: 5))!, calendrier: cal) == "9\u{00A0}h\u{00A0}05" && FormatJournee.heureLongue(cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14))!, calendrier: cal) == "14\u{00A0}h", "heure longue : 9 h 05, 14 h")
    let maintenant = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15))!
    verifier(Journee.titreJour(maintenant, maintenant: maintenant, calendrier: cal).relatif == "Aujourd\u{2019}hui" && Journee.titreJour(maintenant, maintenant: maintenant, calendrier: cal).date.lowercased() == "lundi 9 novembre", "titre du jour : Aujourd'hui · lundi 9 novembre")
    let hier = cal.date(byAdding: .day, value: -1, to: maintenant)!, avantHier = cal.date(byAdding: .day, value: -2, to: maintenant)!
    verifier(Journee.titreJour(hier, maintenant: maintenant, calendrier: cal).relatif == "Hier" && Journee.titreJour(avantHier, maintenant: maintenant, calendrier: cal).relatif == nil, "titre du jour : Hier, puis la date seule")
    verifier(Journee.titreJour(cal.date(from: DateComponents(year: 2025, month: 12, day: 30))!, maintenant: maintenant, calendrier: cal).date.contains("2025"), "titre du jour : l'année quand ce n'est pas l'année en cours")
    verifier(!Journee.piedDePage(sansDuree: 0).contains("compte pour 0") && Journee.piedDePage(sansDuree: 3).contains("3 dictées") && Journee.piedDePage(sansDuree: 3).contains("compte pour 0") && Journee.piedDePage(sansDuree: 1).contains("Une dictée"), "pied de page : la durée absente des anciennes dictées est dite")
    verifier(Journee.piedDePage(sansDuree: 0).hasPrefix("Temps gagné = mots ÷ 40 par minute (vitesse de frappe moyenne), moins ton temps de parole."), "pied de page : la formule")
}

groupe("Journée : phrase-bilan")
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!; cal.locale = Locale(identifier: "fr_FR")
    func jourDe(_ j: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: j, hour: 12))! }
    let lundi = jourDe(9), samedi = jourDe(7), mardi = jourDe(3)
    func r(_ jour: Date, mots: Int, gagne: Double? = nil, apps: [(String, Int)] = [("Mail", 1_480), ("Claude", 1_150), ("Messages", 640), ("WhatsApp", 480), ("Notes", 370)]) -> ResumeJournee {
        ResumeJournee(jour: cal.startOfDay(for: jour), dictees: mots > 0 ? 5 : 0, mots: mots, dureeParole: 0, sansDuree: 0, tempsGagne: gagne ?? Double(mots) / 40 * 60,
                      motsParHeure: Array(repeating: 0, count: 24), dicteesParHeure: Array(repeating: 0, count: 24),
                      apps: apps.map { AppJournee(appId: nil, nom: $0.0, mots: $0.1, dictees: 1) }, heurePic: nil)
    }
    func moy(_ m: Double, jours: Int = 14) -> MoyenneJournees { MoyenneJournees(mots: m, dictees: 46, tempsGagne: 3_000, jours: jours) }
    func p(_ resume: ResumeJournee, _ m: MoyenneJournees?, meilleur: Int? = 9_999, maintenant: Date? = nil) -> PhraseJournee {
        Journee.phrase(resume, moyenne: m, meilleurAvant: meilleur, maintenant: maintenant ?? lundi, calendrier: cal)
    }
    // journée chargée : l'exemple de la maquette
    let chargee = p(r(lundi, mots: 4_120, gagne: 4_800), moy(2_980))
    verifier(chargee.cas == .grosse, "4 120 mots pour une moyenne de 2 980 : grosse journée")
    verifier(chargee.texte == "Grosse journée : 4\u{00A0}120\u{00A0}mots dictés, 38\u{00A0}% de plus que ta moyenne. Tu as gagné environ 1\u{00A0}h\u{00A0}20 par rapport au clavier, surtout en écrivant dans Mail et Claude.", "phrase chargée : celle de la maquette, mot pour mot")
    print("    chargée : \(chargee.texte)")
    // belle, dans la moyenne
    verifier(p(r(lundi, mots: 3_300), moy(2_980)).cas == .belle && p(r(lundi, mots: 3_300), moy(2_980)).texte.hasPrefix("Belle journée"), "108 % à 125 % : belle journée")
    verifier(p(r(lundi, mots: 3_000), moy(2_980)).cas == .dansLaMoyenne && !p(r(lundi, mots: 3_000), moy(2_980)).texte.contains("de plus") && !p(r(lundi, mots: 3_000), moy(2_980)).texte.contains("de moins"), "autour de la moyenne : ni plus ni moins")
    // record
    let record = p(r(lundi, mots: 4_640), moy(2_980), meilleur: 4_000)
    verifier(record.cas == .record && record.texte.hasPrefix("Ta meilleure journée jusqu\u{2019}ici : 4\u{00A0}640"), "plus de mots que n'importe quel jour avant : record")
    verifier(p(r(lundi, mots: 4_640), moy(2_980), meilleur: nil).cas == .grosse, "pas de meilleur jour avant : pas de record (premier jour de la série)")
    // jours calmes : phrase calme, jamais de faux enthousiasme
    let calme = p(r(mardi, mots: 300, gagne: 100, apps: [("Notes", 300)]), moy(2_980), maintenant: lundi)
    verifier(calme.cas == .calme && calme.texte == "Journée calme : 300\u{00A0}mots dictés. Tu as écrit dans Notes.", "journée très calme : phrase calme, sans pourcentage ni temps gagné")
    print("    calme : \(calme.texte)")
    let plusCalme = p(r(mardi, mots: 2_000), moy(2_980), maintenant: lundi)
    verifier(plusCalme.cas == .calme && plusCalme.texte.hasPrefix("Une journée plus calme que d\u{2019}habitude : 2\u{00A0}000\u{00A0}mots dictés, 33\u{00A0}% de moins que ta moyenne."), "entre 50 % et 92 % : plus calme que d'habitude, dit simplement")
    for t in [calme.texte, plusCalme.texte] { verifier(!t.contains("!") && !t.lowercased().contains("bravo") && !t.lowercased().contains("super"), "ton sobre : aucun point d'exclamation ni félicitation (\(t.prefix(20))…)") }
    // aujourd'hui sous la moyenne : la journée n'est pas finie
    let enCours = p(r(lundi, mots: 800, apps: [("Mail", 800)]), moy(2_980), maintenant: lundi)
    verifier(enCours.cas == .enCours && enCours.texte.contains("pour l\u{2019}instant") && enCours.texte.contains("Ta moyenne sur une journée : 2\u{00A0}980") && !enCours.texte.contains("calme"), "aujourd'hui sous la moyenne : « pour l'instant », pas de verdict")
    // aucune dictée
    verifier(p(r(lundi, mots: 0), moy(2_980), maintenant: lundi).texte == "Pas encore de dictée aujourd\u{2019}hui." && p(r(lundi, mots: 0), moy(2_980), maintenant: lundi).cas == .aucune, "aujourd'hui sans dictée : phrase calme")
    verifier(p(r(mardi, mots: 0), moy(2_980), maintenant: lundi).texte == "Aucune dictée ce jour-là.", "jour passé sans dictée")
    verifier(p(r(samedi, mots: 0), moy(2_980), maintenant: lundi).texte == "Pas de dictée ce jour-là, c\u{2019}était le week-end.", "week-end passé sans dictée")
    // week-end : pas de comparaison à la moyenne de semaine
    let we = p(r(samedi, mots: 300, apps: [("Messages", 300)]), moy(2_980), maintenant: lundi)
    verifier(we.cas == .weekend && we.texte.hasPrefix("Week-end : 300\u{00A0}mots dictés.") && !we.texte.contains("moyenne"), "week-end : aucune comparaison avec la moyenne")
    print("    week-end : \(we.texte)")
    // premier jour
    let premier = p(r(lundi, mots: 420, gagne: 400, apps: [("Mail", 300), ("Notes", 120)]), nil)
    verifier(premier.cas == .premierJour && !premier.texte.contains("moyenne ") && !premier.texte.contains("% de"), "premier jour : aucune comparaison")
    verifier(premier.texte.hasPrefix("Première journée avec Verbe : 420\u{00A0}mots dictés.") && premier.texte.contains("arriveront"), "premier jour : phrase d'accueil")
    print("    premier jour : \(premier.texte)")
    // peu de recul (1 ou 2 jours avant) : pas de comparaison non plus
    let peu = p(r(lundi, mots: 420, gagne: 400, apps: [("Mail", 420)]), moy(100, jours: 2))
    verifier(peu.cas == .peuDeRecul && !peu.texte.contains("moyenne") && !peu.texte.contains("%"), "moins de 3 jours de recul : pas de comparaison")
    verifier(p(r(lundi, mots: 420, apps: [("Mail", 420)]), moy(100, jours: 3)).cas != .peuDeRecul, "3 jours de recul : on compare")
    // seconde phrase : temps gagné et apps
    let sans = p(r(lundi, mots: 3_000, gagne: 120, apps: [("Mail", 3_000)]), moy(2_980))
    verifier(sans.texte.hasSuffix("Tu as écrit dans Mail.") && !sans.texte.contains("gagné"), "moins de 3 min gagnées : on ne le dit pas (« Tu as écrit dans Mail »)")
    verifier(p(r(lundi, mots: 3_000, apps: [("Mail", 2_000), ("Claude", 500), ("Notes", 500)]), moy(2_980)).texte.contains("surtout en écrivant dans Mail,") == false, "phrase : un seul nom quand le deuxième pèse moins de 30 %")
    verifier(p(r(lundi, mots: 3_000, apps: [("Mail", 2_000), ("Claude", 500), ("Notes", 500)]), moy(2_980)).texte.hasSuffix("surtout en écrivant dans Mail."), "apps : une app dominante, « surtout » car il y en a d'autres")
    verifier(p(r(lundi, mots: 3_000, apps: [("Mail", 1_600), ("Claude", 1_400)]), moy(2_980)).texte.hasSuffix("en écrivant dans Mail et Claude."), "deux apps seulement : pas de « surtout »")
    verifier(p(r(lundi, mots: 3_000, apps: []), moy(2_980)).texte.hasSuffix("par rapport au clavier."), "sans app connue : seulement le temps gagné")
    verifier(p(r(lundi, mots: 1, gagne: 0, apps: []), nil).texte.contains("1\u{00A0}mot dicté."), "un seul mot : singulier")
}

groupe("Journée : réunions et actions du jour")
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!; cal.locale = Locale(identifier: "fr_FR")
    func date(_ j: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: j, hour: h, minute: m))! }
    let lundi = date(9, 18)
    let a1 = ActionReunion(quoi: "Envoyer la proposition", quand: "demain", echeance: "2026-11-10")
    let a2 = ActionReunion(quoi: "Mettre à jour le planning", quand: "jeudi", echeance: "2026-11-12")
    let a3 = ActionReunion(quoi: "Déjà fait", fait: true, echeance: "2026-11-10")
    let a4 = ActionReunion(quoi: "Sans date")
    let a5 = ActionReunion(quoi: "Aujourd'hui même", quand: "ce soir", echeance: "2026-11-09")
    let matin = Reunion(debut: date(9, 9, 15), duree: 32 * 60, titre: "Point devis", dit: ["Brume valide."], actions: [a2, a1, a3, a4], etat: .prete, enBref: "Brume valide les deux options.")
    let apresMidi = Reunion(debut: date(9, 15, 30), duree: 48 * 60, titre: "Revue du planning", actions: [a5], etat: .prete, enBref: "Novembre tient.")
    let sansNote = Reunion(debut: date(9, 17), duree: 600, titre: "", etat: .sansNote)
    let hier = Reunion(debut: date(8, 10), titre: "Hier", actions: [ActionReunion(quoi: "Pas aujourd'hui")], etat: .prete)
    let toutes = [apresMidi, hier, matin, sansNote]
    let rj = Journee.reunions(jour: lundi, reunions: toutes, calendrier: cal)
    verifier(rj.map(\.titre) == ["Point devis", "Revue du planning", "Réunion du lun. 9 nov. 2026, 17:00"], "réunions du jour : seulement celles du jour, par heure")
    verifier(rj[0].heure == "9\u{00A0}h\u{00A0}15" && rj[0].duree == "32 min" && rj[0].actions == "3 actions à faire sur 4" && rj[0].enBref == "Brume valide les deux options.", "réunion : heure, durée, actions à faire sur le total, En bref")
    verifier(rj[1].actions == "1 action à faire sur 1", "une seule action : singulier")
    verifier(rj[2].noteEcrite == false && rj[2].enBref.isEmpty && rj[2].actions == nil, "réunion sans note : pas d'En bref ni d'actions")
    let aj = Journee.actions(jour: lundi, reunions: toutes, maintenant: lundi, calendrier: cal)
    verifier(aj.map(\.quoi) == ["Aujourd'hui même", "Envoyer la proposition", "Mettre à jour le planning", "Sans date"], "actions : non cochées seulement, échéances proches d'abord, sans date à la fin")
    verifier(aj[0].etiquette == "aujourd\u{2019}hui" && aj[0].urgente && aj[1].etiquette == "demain" && aj[1].urgente, "étiquettes « aujourd'hui » et « demain »")
    verifier(aj[2].etiquette == "jeu. 12" && !aj[2].urgente && aj[3].sansDate, "autre échéance : « jeu. 12 » ; sans date signalée")
    verifier(aj.allSatisfy { $0.reunion == matin.id || $0.reunion == apresMidi.id }, "chaque action garde sa réunion (pour la cocher dans la note)")
    let tard = Journee.actions(jour: lundi, reunions: [matin], maintenant: date(11, 9), calendrier: cal)
    verifier(tard.first { $0.quoi == "Envoyer la proposition" }?.etiquette == "en retard", "échéance passée : « en retard »")
    var cochee = matin; cochee.actions[1].fait = true   // « Envoyer la proposition » cochée dans la note
    verifier(!Journee.actions(jour: lundi, reunions: [cochee], maintenant: lundi, calendrier: cal).contains { $0.quoi == "Envoyer la proposition" }, "action cochée : disparaît de la liste")
    let gardee = Journee.actions(jour: lundi, reunions: [cochee], aussi: [a1.id], maintenant: lundi, calendrier: cal)
    verifier(gardee.first?.quoi == "Envoyer la proposition" && gardee.first?.fait == true && gardee.first?.urgente == false, "action qu'on vient de cocher ici : reste à sa place, barrée")
    verifier(Journee.actions(jour: date(20, 9), reunions: toutes, maintenant: lundi, calendrier: cal).isEmpty && Journee.reunions(jour: date(20, 9), reunions: toutes, calendrier: cal).isEmpty, "jour sans réunion : rien")
}

// MARK: Lecture en cours dans l'encoche

groupe("Lecture en cours : lignes du programme d'aide")
do {
    verifier(AideLecture.decoder("{\"t\":\"pret\"}") == .pret, "ligne « pret »")
    verifier(AideLecture.decoder("{\"t\":\"rien\"}") == .rien, "ligne « rien »")
    verifier(AideLecture.decoder("{\"t\":\"echec\",\"raison\":\"MediaRemote introuvable\"}") == .echec("MediaRemote introuvable"), "ligne « echec » avec sa raison")
    verifier(AideLecture.decoder("pas du json") == nil && AideLecture.decoder("{\"x\":1}") == nil && AideLecture.decoder("{\"t\":\"inconnu\"}") == nil, "ligne illisible ou inconnue : ignorée")
    let ligne = "{\"t\":\"etat\",\"titre\":\"Le Retour\",\"artiste\":\"Une chaîne\",\"app\":\"com.google.Chrome\",\"pid\":686,\"joue\":true,\"duree\":2530.5,\"pos\":724,\"depuis\":1794262856.5,\"vitesse\":1,\"image\":\"/tmp/x.bin\"}"
    if case .etat(let m)? = AideLecture.decoder(ligne) {
        verifier(m.titre == "Le Retour" && m.artiste == "Une chaîne" && m.app == "com.google.Chrome" && m.pid == 686 && m.joue, "état : titre, artiste, app, pid, lecture")
        verifier(m.duree == 2530.5 && m.position == 724 && m.vitesse == 1 && m.cheminImage == "/tmp/x.bin", "état : durée, position, vitesse, image")
        verifier(m.depuis == Date(timeIntervalSince1970: 1794262856.5) && m.positionnable, "état : instant de référence, barre utilisable")
        verifier(m.album == nil, "état : album absent = nil")
    } else { verifier(false, "état décodé") }
    if case .etat(let d)? = AideLecture.decoder("{\"t\":\"etat\",\"titre\":\"Direct\",\"app\":\"com.google.Chrome\",\"joue\":false,\"vitesse\":0,\"pos\":0}") {
        verifier(d.duree == nil && !d.positionnable && !d.joue, "direct (pas de durée) : pas de barre, en pause")
    } else { verifier(false, "direct décodé") }
    verifier(AideLecture.decoder("{\"t\":\"etat\",\"joue\":true}") == .rien, "état sans titre ni app : rien")
    if case .etat(let s)? = AideLecture.decoder("{\"t\":\"etat\",\"app\":\"com.spotify.client\",\"joue\":true}") {
        verifier(s.titre == "Lecture en cours", "app sans titre : titre générique")
    } else { verifier(false, "app sans titre décodée") }
    verifier(AideLecture.ligne(.pause) == "{\"cmd\":\"pause\"}\n" && AideLecture.ligne(.bascule) == "{\"cmd\":\"toggle\"}\n"
             && AideLecture.ligne(.suivant) == "{\"cmd\":\"next\"}\n" && AideLecture.ligne(.precedent) == "{\"cmd\":\"prev\"}\n" && AideLecture.ligne(.lecture) == "{\"cmd\":\"play\"}\n", "commandes envoyées au programme d'aide")
    verifier(AideLecture.ligne(.position(100)) == "{\"cmd\":\"seek\",\"pos\":100.000}\n" && AideLecture.ligne(.position(-5)).contains("0.000"), "position : jamais négative")
}

groupe("Lecture en cours : position, temps et barre")
do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var m = MorceauEnCours(titre: "T", joue: true, duree: 214, position: 96, depuis: t0, vitesse: 1)
    verifier(m.positionA(t0.addingTimeInterval(5)) == 101, "en lecture : la position avance toute seule (96 s + 5 s)")
    verifier(m.positionA(t0.addingTimeInterval(500)) == 214, "jamais au-delà de la durée")
    verifier(m.positionA(t0.addingTimeInterval(-3)) == 96, "avant l'instant de référence : la position de référence")
    m.vitesse = 1.5; verifier(m.positionA(t0.addingTimeInterval(10)) == 111, "vitesse 1,5 : avance plus vite")
    m.joue = false; verifier(m.positionA(t0.addingTimeInterval(10)) == 96, "en pause : la position ne bouge pas")
    verifier(MorceauEnCours(titre: "T", joue: true).positionA(t0) == nil, "sans position : nil")
    let a = MorceauEnCours(titre: "T", app: "x", joue: true, duree: 100), b = MorceauEnCours(titre: "T", app: "x", joue: false, duree: 100, position: 50)
    verifier(a.cle == b.cle, "même morceau : même clé, quelles que soient la position et la lecture")
    verifier(a.cle != MorceauEnCours(titre: "T2", app: "x", joue: true, duree: 100).cle, "autre titre : autre clé")
    verifier(TempsLecture.format(97) == "1:37" && TempsLecture.format(725) == "12:05" && TempsLecture.format(0) == "0:00" && TempsLecture.format(3723) == "1:02:03", "format des temps : 1:37, 12:05, 0:00, 1:02:03")
    verifier(TempsLecture.format(59.9) == "0:59" && TempsLecture.format(-4) == "0:00" && TempsLecture.format(.infinity) == "0:00", "temps : arrondi vers le bas, jamais négatif ni infini")
    verifier(TempsLecture.restant(position: 96, duree: 214) == "\u{2212}1:58" && TempsLecture.restant(position: 300, duree: 214) == "\u{2212}0:00", "temps restant avec le vrai signe moins")
    verifier(TempsLecture.fraction(position: 107, duree: 214) == 0.5 && TempsLecture.fraction(position: 5, duree: 0) == 0 && TempsLecture.fraction(position: 999, duree: 214) == 1, "position -> barre (bornée)")
    verifier(TempsLecture.position(fraction: 0.25, duree: 200) == 50 && TempsLecture.position(fraction: 1.7, duree: 200) == 200 && TempsLecture.position(fraction: -1, duree: 200) == 0, "barre -> position (bornée)")
    verifier(TempsLecture.fractionSousSouris(x: 188, largeur: 376) == 0.5 && TempsLecture.fractionSousSouris(x: -20, largeur: 376) == 0 && TempsLecture.fractionSousSouris(x: 900, largeur: 376) == 1, "souris sur la barre -> fraction (glisser hors de la barre : bornée)")
    let aller = TempsLecture.position(fraction: TempsLecture.fraction(position: 123, duree: 456), duree: 456)
    verifier(abs(aller - 123) < 1e-9, "position -> barre -> position : aller-retour")
    verifier(TempsLecture.saut(position: 100, delta: -10, duree: 214) == 90 && TempsLecture.saut(position: 4, delta: -10, duree: 214) == 0 && TempsLecture.saut(position: 210, delta: 10, duree: 214) == 214 && TempsLecture.saut(position: 10, delta: 10, duree: nil) == 20, "reculer / avancer de 10 s sans sortir de la piste")
    let h = TraceSonore.hauteurs()
    verifier(h.count == 54 && h.allSatisfy { $0 >= 0.22 && $0 <= 1 } && h == TraceSonore.hauteurs(), "trace sonore : 54 barres entre 0,22 et 1, toujours les mêmes")
    verifier(TraceSonore.barresTeintees(fraction: 0.5) == 27 && TraceSonore.barresTeintees(fraction: 2) == 54 && TraceSonore.barresTeintees(fraction: -1) == 0, "barres teintées selon la progression")
}

groupe("Lecture en cours : source")
do {
    verifier(SourceLecture.libelle(bundle: "com.google.Chrome", nomApp: "Google Chrome", artiste: "Une chaîne", album: nil, site: "YouTube") == "Chrome \u{00B7} YouTube", "Chrome sur YouTube : « Chrome · YouTube »")
    verifier(SourceLecture.libelle(bundle: "com.google.Chrome", nomApp: "Google Chrome", artiste: "Snayzy", album: nil, site: nil) == "Chrome \u{00B7} Snayzy", "Chrome, site inconnu : on n'invente pas, la chaîne annoncée")
    verifier(SourceLecture.libelle(bundle: "com.google.Chrome", nomApp: nil, artiste: nil, album: nil, site: nil) == "Chrome", "Chrome sans rien d'autre : « Chrome »")
    verifier(SourceLecture.libelle(bundle: "com.spotify.client", nomApp: "Spotify", artiste: "Un groupe", album: "Un disque", site: nil) == "Spotify \u{00B7} Un groupe", "Spotify : l'artiste")
    verifier(SourceLecture.libelle(bundle: "com.apple.Music", nomApp: "Music", artiste: nil, album: "Un disque", site: nil) == "Musique \u{00B7} Un disque", "Musique : nom français, album à défaut d'artiste")
    verifier(SourceLecture.libelle(bundle: "com.exemple.Lecteur", nomApp: "Google Lecteur", artiste: nil, album: nil, site: nil) == "Lecteur", "app inconnue : nom du système sans « Google »")
    verifier(SourceLecture.libelle(bundle: nil, nomApp: nil, artiste: nil, album: nil, site: nil) == "Lecture", "rien du tout : « Lecture »")
    verifier(SourceLecture.estNavigateur("com.apple.Safari") && SourceLecture.estNavigateur("org.mozilla.firefox") && !SourceLecture.estNavigateur("com.spotify.client") && !SourceLecture.estNavigateur(nil), "navigateurs reconnus")
    verifier(SourceLecture.genre(bundle: "com.spotify.client", album: nil, duree: nil, site: nil) == .musique && SourceLecture.genre(bundle: "com.apple.Music", album: nil, duree: nil, site: nil) == .musique, "Spotify et Musique : musique (pochette ronde)")
    verifier(SourceLecture.genre(bundle: "com.google.Chrome", album: nil, duree: 2530, site: "YouTube") == .video && SourceLecture.genre(bundle: "com.google.Chrome", album: nil, duree: nil, site: nil) == .video, "Chrome sur YouTube : vidéo (pochette carrée)")
    verifier(SourceLecture.genre(bundle: "com.google.Chrome", album: "Un disque", duree: 200, site: "YouTube Music") == .musique && SourceLecture.genre(bundle: "com.google.Chrome", album: nil, duree: 200, site: "SoundCloud") == .musique, "YouTube Music, SoundCloud : musique")
    verifier(SourceLecture.genre(bundle: "com.apple.podcasts", album: "Une émission", duree: 3000, site: nil) == .video, "Podcasts : pochette carrée")
    verifier(SourceLecture.genre(bundle: "com.exemple.Lecteur", album: "Un disque", duree: 180, site: nil) == .musique && SourceLecture.genre(bundle: "com.exemple.Lecteur", album: "Un film", duree: 7000, site: nil) == .video, "app inconnue avec album court : musique ; album très long : non")
}

groupe("Lecture en cours : site lu dans le titre des fenêtres")
do {
    let titreYT = "Série · S2 É4 · Le Retour"
    verifier(SourceLecture.site(titresDeFenetres: ["Série · S2 É4 · Le Retour - YouTube - Google Chrome"], titreMedia: titreYT) == "YouTube", "« Titre - YouTube - Google Chrome » : YouTube")
    verifier(SourceLecture.site(titresDeFenetres: ["(3) Série · S2 É4 · Le Retour - YouTube - Google Chrome \u{2013} Hugues"], titreMedia: titreYT) == "YouTube", "compteur de notifications et profil : YouTube")
    verifier(SourceLecture.site(titresDeFenetres: ["Netflix - Google Chrome"], titreMedia: "Une série") == "Netflix", "onglet « Netflix » : Netflix")
    verifier(SourceLecture.site(titresDeFenetres: ["Album · Titre 3 - YouTube Music - Mozilla Firefox"], titreMedia: "Album · Titre 3") == "YouTube Music", "YouTube Music se distingue de YouTube")
    verifier(SourceLecture.site(titresDeFenetres: ["Mes mails - Gmail - Google Chrome", "Autre page - Google Chrome"], titreMedia: titreYT) == nil, "onglet qui joue non affiché : nil, on n'invente pas")
    verifier(SourceLecture.site(titresDeFenetres: ["Un autre titre - YouTube - Google Chrome"], titreMedia: titreYT) == nil, "autre vidéo YouTube affichée : pas de lien avec le média -> nil")
    verifier(SourceLecture.site(titresDeFenetres: [], titreMedia: titreYT) == nil && SourceLecture.site(titresDeFenetres: ["x"], titreMedia: "") == nil, "aucune fenêtre ou titre vide : nil")
    verifier(SourceLecture.site(titresDeFenetres: ["Mes mails - Gmail - Google Chrome", "Série · S2 É4 · Le Retour - YouTube - Google Chrome"], titreMedia: titreYT) == "YouTube", "plusieurs fenêtres : celle qui correspond")
}

groupe("Lecture en cours : miniature YouTube (repli de l'image)")
do {
    let id = "dQw4w9WgXcQ"
    func i(_ a: String) -> String? { MiniatureYouTube.identifiant(adresse: a) }
    verifier(i("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == id, "youtube.com/watch?v= : identifiant")
    verifier(i("youtube.com/watch?v=dQw4w9WgXcQ") == id && i("www.youtube.com/watch?v=dQw4w9WgXcQ") == id, "adresse affichée sans https:// ni www.")
    verifier(i("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PLabc&index=3") == id, "paramètres en plus (&t=, &list=)")
    verifier(i("https://www.youtube.com/watch?list=PLabc&v=dQw4w9WgXcQ&pp=ygUHdGVzdA%3D%3D") == id, "v= pas en premier")
    verifier(i("https://youtu.be/dQw4w9WgXcQ") == id && i("https://youtu.be/dQw4w9WgXcQ?si=abcdef&t=10") == id, "youtu.be/ID, avec paramètres")
    verifier(i("https://www.youtube.com/shorts/dQw4w9WgXcQ") == id && i("https://youtube.com/shorts/dQw4w9WgXcQ?feature=share") == id, "/shorts/ID")
    verifier(i("https://www.youtube.com/embed/dQw4w9WgXcQ") == id && i("https://www.youtube.com/live/dQw4w9WgXcQ?si=x") == id, "/embed/ID, /live/ID")
    verifier(i("https://m.youtube.com/watch?v=dQw4w9WgXcQ") == id && i("https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM") == id, "m.youtube.com, music.youtube.com")
    verifier(i("https://www.youtube.com/") == nil && i("youtube.com") == nil && i("https://www.youtube.com/feed/subscriptions") == nil, "page d'accueil ou autre page : nil")
    verifier(i("https://www.youtube.com/playlist?list=PLabc") == nil && i("https://www.youtube.com/@chaine") == nil, "liste ou chaîne sans vidéo : nil")
    verifier(i("https://exemple.com/watch?v=dQw4w9WgXcQ") == nil && i("https://notyoutube.com/watch?v=dQw4w9WgXcQ") == nil && i("https://youtube.com.evil.fr/watch?v=dQw4w9WgXcQ") == nil, "autre site (même ressemblant) : nil")
    verifier(i("https://www.youtube.com/watch?v=court") == nil && i("https://www.youtube.com/watch?v=dQw4w9WgXcQdQw") == nil && i("https://www.youtube.com/watch?v=../../etc/pw") == nil, "identifiant de mauvaise longueur ou piégé : nil")
    verifier(i("") == nil && i("deux mots youtube.com/watch?v=dQw4w9WgXcQ") == nil && i("Rechercher avec Google ou saisir une URL") == nil, "texte qui n'est pas une adresse : nil")
    verifier(SourceLecture.fenetreMontre(titreFenetre: "(3) Série · S2 É4 · Le Retour - YouTube - Google Chrome \u{2013} Hugues", titreMedia: "Série · S2 É4 · Le Retour"), "la fenêtre qui montre la vidéo (compteur, profil) est reconnue")
    verifier(!SourceLecture.fenetreMontre(titreFenetre: "Mes mails - Gmail - Google Chrome", titreMedia: "Série · S2 É4 · Le Retour") && !SourceLecture.fenetreMontre(titreFenetre: "Ab - Google Chrome", titreMedia: "Ab"), "une autre fenêtre, ou un titre de média trop court : non")
    verifier(MiniatureYouTube.adresseMiniature(identifiant: id)?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg" && MiniatureYouTube.adresseMiniature(identifiant: "x/../y") == nil, "adresse de la miniature, refusée pour un identifiant invalide")
}

groupe("Lecture en cours : couleur dominante de la pochette")
do {
    func image(_ l: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var p = [UInt8](); for y in 0..<h { for x in 0..<l { let c = f(x, y); p += [c.0, c.1, c.2, c.3] } }; return p
    }
    func teinte(_ c: CouleurRVB) -> Double { CouleurDominante.hsv(r: c.r, g: c.g, b: c.b).h }
    func ecart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }
    let bleue = image(24, 24) { x, y in y < 18 ? (20, 70 + UInt8(x), 200, 255) : (8, 20, 40, 255) }   // bleu franc + fond sombre
    let t1 = CouleurDominante.teinte(rgba: bleue, largeur: 24, hauteur: 24)
    verifier(ecart(teinte(t1.clair), 220) < 20, "pochette bleue : teinte claire bleue (\(t1.clair.hexa))")
    verifier(CouleurDominante.hsv(r: t1.clair.r, g: t1.clair.g, b: t1.clair.b).v == 1, "teinte claire : toujours lumineuse")
    let rose = image(24, 24) { x, _ in x < 14 ? (255, 60, 150, 255) : (255, 150, 40, 255) }   // rose (58 %) et orange (42 %)
    let t2 = CouleurDominante.teinte(rgba: rose, largeur: 24, hauteur: 24)
    verifier(ecart(teinte(t2.clair), 333) < 20 && ecart(teinte(t2.profond), 30) < 25, "rose et orange : le rose domine, l'orange est la deuxième couleur (\(t2.clair.hexa) / \(t2.profond.hexa))")
    let orange = image(24, 24) { _, _ in (250, 140, 60, 255) }
    let t3 = CouleurDominante.teinte(rgba: orange, largeur: 24, hauteur: 24)
    verifier(ecart(teinte(t3.clair), 25) < 20 && ecart(teinte(t3.profond), teinte(t3.clair)) < 25 && t3.profond != t3.clair, "pochette d'une seule couleur : la deuxième est une variante plus profonde")
    verifier(CouleurDominante.teinte(rgba: image(24, 24) { x, _ in (UInt8(x * 10), UInt8(x * 10), UInt8(x * 10), 255) }, largeur: 24, hauteur: 24) == .neutre, "pochette en niveaux de gris : teinte neutre")
    verifier(CouleurDominante.teinte(rgba: image(24, 24) { _, _ in (255, 0, 0, 0) }, largeur: 24, hauteur: 24) == .neutre, "pochette transparente : teinte neutre")
    verifier(CouleurDominante.teinte(rgba: [], largeur: 0, hauteur: 0) == .neutre && CouleurDominante.teinte(rgba: [1, 2, 3], largeur: 5, hauteur: 5) == .neutre, "données absentes ou trop courtes : neutre, sans plantage")
    let taches = image(24, 24) { x, y in x < 1 && y < 1 ? (255, 0, 0, 255) : (240, 240, 240, 255) }
    verifier(CouleurDominante.teinte(rgba: taches, largeur: 24, hauteur: 24) == .neutre, "un seul pixel coloré sur une image blanche : neutre (moins de 3 %)")
}

groupe("Lecture en cours : priorités sur l'encoche")
do {
    func aff(_ o: OccupationEncoche, morceau: Bool = true, reglage: Bool = true) -> AffichageLecture { PrioriteLecture.affichage(occupation: o, morceau: morceau, reglageAffichage: reglage) }
    verifier(aff(OccupationEncoche()) == .ilot, "rien d'autre : l'îlot s'affiche")
    verifier(aff(OccupationEncoche(), morceau: false) == .aucun, "rien ne joue : rien")
    verifier(aff(OccupationEncoche(), reglage: false) == .aucun && aff(OccupationEncoche(dictee: true), reglage: false) == .aucun, "réglage coupé : rien, même pendant une dictée")
    verifier(aff(OccupationEncoche(dictee: true)) == .miniature, "dictée : l'îlot s'efface, la lecture devient une mini-miniature dans le ruban de la dictée")
    verifier(aff(OccupationEncoche(reunion: true)) == .ilot, "réunion : la lecture reste dans l'îlot (la réunion a l'îlot, la vidéo passe dans la bulle)")
    verifier(aff(OccupationEncoche(dictee: true, reunion: true)) == .miniature, "dictée pendant une réunion : comme toute dictée")
    verifier(aff(OccupationEncoche(filet: true)) == .aucun && aff(OccupationEncoche(miseAJour: true)) == .aucun && aff(OccupationEncoche(autreAnnonce: true)) == .aucun, "filet, mise à jour, autre annonce : la lecture s'efface")
    verifier(aff(OccupationEncoche(dictee: true, filet: true)) == .miniature, "dictée + filet : la dictée garde la place, la lecture reste une mini-miniature")
}

groupe("Lecture en cours : pause pendant la dictée")
do {
    let joue = MorceauEnCours(titre: "A", app: "com.spotify.client", joue: true, duree: 200)
    let enPause = MorceauEnCours(titre: "A", app: "com.spotify.client", joue: false, duree: 200)
    var p = PauseDictee()
    verifier(p.debut(morceau: joue, reglage: true, reunion: false) == .pause && p.pauseParNous, "quelque chose joue : pause au début")
    verifier(p.debut(morceau: joue, reglage: true, reunion: false) == .rien, "pas de deuxième pause")
    verifier(p.fin(morceau: enPause) == .reprendre && !p.pauseParNous, "fin de dictée : reprise (c'est nous qui avions mis en pause)")
    verifier(p.fin(morceau: enPause) == .rien, "pas de deuxième reprise")
    var q = PauseDictee()
    verifier(q.debut(morceau: enPause, reglage: true, reunion: false) == .rien && q.fin(morceau: enPause) == .rien, "déjà en pause avant la dictée : on ne touche à rien, on ne relance pas")
    verifier(q.debut(morceau: nil, reglage: true, reunion: false) == .rien, "rien ne joue : rien")
    var r = PauseDictee()
    verifier(r.debut(morceau: joue, reglage: false, reunion: false) == .rien && r.fin(morceau: enPause) == .rien, "réglage coupé : ni pause ni reprise")
    var u = PauseDictee()
    verifier(u.debut(morceau: joue, reglage: true, reunion: true) == .rien && u.fin(morceau: enPause) == .rien, "pendant une réunion : pas de pause automatique")
    var v = PauseDictee()
    _ = v.debut(morceau: joue, reglage: true, reunion: false)
    verifier(v.fin(morceau: joue) == .rien, "l'utilisateur a relancé la lecture pendant la dictée : pas de commande en plus")
    var w = PauseDictee()
    _ = w.debut(morceau: joue, reglage: true, reunion: false)
    verifier(w.fin(morceau: MorceauEnCours(titre: "B", app: "com.spotify.client", joue: false, duree: 180)) == .rien, "autre morceau à la fin : on ne reprend pas")
    var x = PauseDictee()
    _ = x.debut(morceau: joue, reglage: true, reunion: false)
    verifier(x.fin(morceau: nil) == .rien && !x.pauseParNous, "plus rien à la fin (app fermée) : on ne reprend pas, l'état est remis à zéro")
    var y = PauseDictee()
    verifier(y.fin(morceau: enPause) == .rien, "fin sans début : rien")
}

groupe("Lecture en cours : relance du programme d'aide")
do {
    verifier([1, 2, 3, 4, 5, 6, 7, 8].map { PlanRelanceAide.delai(apresEchecs: $0) } == [1, 2, 4, 8, 16, 32, 60, 60], "délais croissants 1, 2, 4, 8, 16, 32, puis 60 s au plus")
    var p = PlanRelanceAide()
    verifier(p.processusArrete(dureeDeVie: 0.3, echecMediaRemote: false) == .relancer(apres: 1), "premier arrêt rapide : relance après 1 s")
    verifier(p.processusArrete(dureeDeVie: 0.3, echecMediaRemote: false) == .relancer(apres: 2), "deuxième : 2 s")
    verifier(p.processusArrete(dureeDeVie: 120, echecMediaRemote: false) == .relancer(apres: 1), "après 2 minutes de vie, le compteur repart de zéro")
    var q = PlanRelanceAide()
    var derniere = PlanRelanceAide.Decision.relancer(apres: 0)
    for _ in 0..<7 { derniere = q.processusArrete(dureeDeVie: 0.1, echecMediaRemote: false) }
    verifier(derniere == .abandonner(raison: "le programme d'aide s'arrête sans cesse"), "7 arrêts de suite : on abandonne")
    var r = PlanRelanceAide()
    verifier(r.processusArrete(dureeDeVie: 5, echecMediaRemote: true) == .abandonner(raison: "MediaRemote inaccessible sur cette version de macOS"), "MediaRemote inaccessible : abandon tout de suite")
    r.reinitialiser(); verifier(r.echecs == 0, "réinitialisation")
}
groupe("Journal : les modes de vérification écrivent à part")
do {
    let x = "/Applications/Verbe.app/Contents/MacOS/Verbe"
    verifier(!ModesLancement.journalAPart([x]), "la vraie app (aucune option) : le vrai journal")
    verifier(!ModesLancement.journalAPart([x, "--sans-interface", "--duree=4", "--verifier-parole=a.wav"]), "--sans-interface (lancé par open) : le vrai journal")
    verifier(["--ilot-essai", "--rendu-ilot", "--transcrire", "--lecture-test", "--verifier-collage", "--rendu-icones", "--option-inconnue"]
                .allSatisfy { ModesLancement.journalAPart([x, $0]) }, "tout autre mode (essais, rendus, réseau, option inconnue) : un journal à part")
    let j = ModesLancement.journalTemporaire.path
    verifier(!j.contains("/Library/Logs/") && j.hasPrefix(FileManager.default.temporaryDirectory.path), "le journal à part est dans le dossier temporaire (\(j))")
}
controlesPrecision()
controlesIlot()
controlesLucarne()
controlesSecondBrain()
controlesGroq()
controlesPlacesLucarne()
controlesReunionIlot()
controlesReunionNote()
controlesVoixReunion()
controlesExtraitsReunion()
controlesBureau()

print("\n\(total - echecs)/\(total) contrôles passés")
exit(echecs == 0 ? 0 : 1)
