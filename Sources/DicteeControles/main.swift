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
    verifier(ToucheGlobe.phrase(valeur: 2) == "Votre touche 🌐 ouvre les emoji" && ToucheGlobe.phrase(valeur: nil) == "Votre touche 🌐 ouvre les emoji", "phrase : emoji")
    verifier(ToucheGlobe.phrase(valeur: 3).contains("dictée d\u{2019}Apple") && ToucheGlobe.phrase(valeur: 1).contains("méthode de saisie"), "phrase : dictée d'Apple, méthode de saisie")
    verifier(ToucheGlobe.adresseVoletClavier == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension", "adresse du volet Clavier")
    verifier(ToucheGlobe.consigne == "Appuyer sur la touche 🌐 pour : Ne rien faire", "consigne")
    let lue = ToucheGlobe.lire()   // lecture seule des préférences système, aucun accès au clavier
    verifier(lue == nil || (0...3).contains(lue!), "lecture réelle du réglage : \(lue.map(String.init) ?? "absent")")
}

print("\n\(total - echecs)/\(total) contrôles passés")
exit(echecs == 0 ? 0 : 1)
