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
        verifier(c.end == (50 + 150 + 25) * 320, "coupe 0,5 s après la fin de la parole")
    }
    verifier(r.fin != nil && r.fin!.start >= (50 + 150 + 25) * 320 && r.fin!.start <= (50 + 150 + 60) * 320 && r.fin!.end == r.total * 320, "le dernier morceau part au relâchement")
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

print("\n\(total - echecs)/\(total) contrôles passés")
exit(echecs == 0 ? 0 : 1)
