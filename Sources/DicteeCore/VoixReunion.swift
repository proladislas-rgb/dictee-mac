import Foundation

// Les voix des autres participants séparées sur le Mac (diarisation, faite dans l'app) : la piste « Eux » (le son du Mac) est découpée
// en tours de parole, « voix A de 12 s à 19 s, voix B de 19 s à 31 s… ». Ici, la logique pure : poser ces voix sur les passages de la
// transcription (qui vient de Groq, horodatée), les nommer « Personne 1, Personne 2… » dans l'ordre où elles parlent, et se replier
// proprement sur « Eux » quand la séparation n'apporte rien. La piste « Moi » (le micro) reste toujours « Moi ».

/// Un tour de parole trouvé par la séparation des voix, en secondes de réunion. `voix` est l'étiquette du séparateur (« S1 »…),
/// qui ne sert qu'à regrouper les tours d'une même voix.
public struct TourDeParole: Codable, Equatable, Sendable {
    public var voix: String
    public var debut: Double
    public var fin: Double
    public init(voix: String, debut: Double, fin: Double) { self.voix = voix; self.debut = debut; self.fin = max(fin, debut) }
}

/// Ce que rend la séparation des voix : les tours de parole et, par voix, son empreinte (un vecteur qui résume le timbre ; il servira
/// à reconnaître une voix déjà nommée d'une réunion à l'autre).
public struct VoixSeparees: Equatable, Sendable {
    public var tours: [TourDeParole]
    public var empreintes: [String: [Float]]
    public init(tours: [TourDeParole], empreintes: [String: [Float]] = [:]) { self.tours = tours; self.empreintes = empreintes }
}

/// Une voix déjà nommée, gardée pour la reconnaître dans les réunions suivantes (pas encore utilisé : la structure est prête).
public struct VoixConnue: Codable, Equatable, Sendable {
    public var nom: String
    public var empreinte: [Float]
    public init(nom: String, empreinte: [Float]) { self.nom = nom; self.empreinte = empreinte }
}

public enum SeparationVoix {
    /// L'identifiant d'orateur de la n-ième voix séparée (1, 2…) : « p1 », « p2 »…
    public static func id(rang: Int) -> String { "p\(rang)" }
    /// Le nom donné tant qu'on ne l'a pas renommée : « Personne 1 ».
    public static func nomParDefaut(rang: Int) -> String { "Personne \(rang)" }

    /// « p3 » → 3 ; nil pour « moi », « eux » ou tout autre identifiant.
    public static func rang(id: String) -> Int? {
        guard id.count > 1, id.first == "p", let n = Int(id.dropFirst()), n > 0 else { return nil }
        return n
    }

    /// Le nom d'un orateur tant qu'il n'est pas renommé : « Moi », « Eux », « Personne 2 »… nil pour un identifiant inconnu.
    public static func nomParDefaut(id: String) -> String? {
        if let l = Locuteur(rawValue: id) { return l.libelle }
        return rang(id: id).map(nomParDefaut(rang:))
    }

    /// Ce nom est-il un nom donné par Verbe (« Eux », « Personne 3 »), pas un vrai nom ?
    public static func estNomParDefaut(_ nom: String) -> Bool {
        if nom == Locuteur.eux.libelle { return true }
        guard nom.hasPrefix("Personne "), let n = Int(nom.dropFirst("Personne ".count)) else { return false }
        return n > 0
    }

    /// Les passages et les orateurs (« Personne 1 »…) après la séparation. `orateurs` vide : repli sur « Eux ».
    public struct Attribution: Equatable, Sendable {
        public var segments: [SegmentReunion]
        public var orateurs: [OrateurReunion]
        public var separees: Bool { !orateurs.isEmpty }
    }

    /// Pose les voix séparées sur les passages « Eux » de la transcription :
    /// - chaque passage prend la voix qui le recouvre le plus longtemps ; s'il ne touche aucun tour (les horodatages de Whisper et du
    ///   séparateur ne coïncident jamais tout à fait), celle du tour le plus proche à `tolerance` secondes près ; sinon il reste « Eux » ;
    /// - une voix qui ne garde presque rien (moins de `minimum` secondes de passages en tout) est une erreur du séparateur (un rire,
    ///   un bruit, un bout de voix déformé) : ses passages vont à la voix qui les recouvre ensuite le plus, ou à la plus proche ;
    /// - moins de deux voix au bout du compte : rien ne change (« Eux », comme avant la séparation) ;
    /// - les voix sont numérotées dans l'ordre où elles parlent pour la première fois (« Personne 1 » parle la première).
    /// Les passages « Moi » ne sont jamais touchés. Un passage qui a déjà un orateur (« Refaire la note ») est réattribué.
    public static func attribuer(_ segments: [SegmentReunion], voix: VoixSeparees, tolerance: Double = 1.5, minimum: Double = 3) -> Attribution {
        let tours = voix.tours.filter { $0.fin > $0.debut }.sorted { $0.debut < $1.debut }
        let rangsEux = segments.indices.filter { segments[$0].locuteur == .eux }
        func recouvrements(_ s: SegmentReunion) -> [String: Double] {
            var r: [String: Double] = [:]
            for t in tours where t.debut < s.fin && s.debut < t.fin {
                r[t.voix, default: 0] += min(s.fin, t.fin) - max(s.debut, t.debut)
            }
            return r
        }
        /// La voix la plus proche (écart en secondes entre le passage et le tour), parmi `permises`.
        func plusProche(_ s: SegmentReunion, parmi permises: Set<String>?, limite: Double) -> String? {
            var meilleure: (voix: String, ecart: Double)?
            for t in tours where permises?.contains(t.voix) ?? true {
                let ecart = max(0, max(t.debut - s.fin, s.debut - t.fin))
                if ecart <= limite, meilleure == nil || ecart < meilleure!.ecart { meilleure = (t.voix, ecart) }
            }
            return meilleure?.voix
        }
        func meilleure(_ r: [String: Double], parmi permises: Set<String>?) -> String? {
            r.filter { permises?.contains($0.key) ?? true && $0.value > 0 }
                .max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        }

        var choix: [Int: String] = [:]
        for i in rangsEux {
            let s = segments[i]
            if let v = meilleure(recouvrements(s), parmi: nil) ?? plusProche(s, parmi: nil, limite: tolerance) { choix[i] = v }
        }
        // les voix presque muettes sont fondues dans les autres
        var temps: [String: Double] = [:]
        for (i, v) in choix { temps[v, default: 0] += max(0.1, segments[i].fin - segments[i].debut) }
        let grandes = Set(temps.filter { $0.value >= minimum }.keys)
        if !grandes.isEmpty {
            for (i, v) in choix where !grandes.contains(v) {
                let s = segments[i]
                choix[i] = meilleure(recouvrements(s), parmi: grandes) ?? plusProche(s, parmi: grandes, limite: .infinity)
            }
        }
        // l'ordre de première parole donne les numéros
        var ordre: [String] = []
        for i in rangsEux.sorted(by: { segments[$0].debut < segments[$1].debut }) {
            if let v = choix[i], !ordre.contains(v) { ordre.append(v) }
        }
        guard ordre.count >= 2 else {
            var inchanges = segments
            for i in rangsEux { inchanges[i].orateur = nil }
            return Attribution(segments: inchanges, orateurs: [])
        }
        var sortie = segments
        for i in rangsEux { sortie[i].orateur = choix[i].flatMap { ordre.firstIndex(of: $0) }.map { id(rang: $0 + 1) } }
        let orateurs = ordre.enumerated().map { n, v in
            OrateurReunion(id: id(rang: n + 1), nom: nomParDefaut(rang: n + 1), piste: .eux, empreinte: voix.empreintes[v])
        }
        return Attribution(segments: sortie, orateurs: orateurs)
    }

    /// Ressemblance de deux empreintes de voix (cosinus, de -1 à 1) ; 0 si elles ne sont pas comparables.
    public static func ressemblance(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in a.indices { let x = Double(a[i]), y = Double(b[i]); ab += x * y; aa += x * x; bb += y * y }
        guard aa > 0, bb > 0 else { return 0 }
        return ab / (aa.squareRoot() * bb.squareRoot())
    }

    /// La voix connue qui ressemble le plus à cette empreinte, si elle ressemble assez (`seuil`). Pour plus tard : « Personne 2 »
    /// reconnue comme « Claire » parce que sa voix a déjà été nommée dans une réunion précédente.
    public static func reconnaitre(_ empreinte: [Float], parmi connues: [VoixConnue], seuil: Double = 0.7) -> VoixConnue? {
        connues.map { ($0, ressemblance(empreinte, $0.empreinte)) }.filter { $0.1 >= seuil }.max { $0.1 < $1.1 }?.0
    }

    // MARK: mesure (essai sur un son fabriqué dont on connaît les voix)

    /// Part du temps de parole attribué à la bonne voix, après avoir apparié au mieux les voix trouvées et les vraies (chaque voix
    /// trouvée va à la vraie voix avec laquelle elle partage le plus de temps, sans doublon). Le temps où le séparateur n'a vu
    /// personne compte comme faux. De 0 à 1.
    public static func justesse(trouves: [TourDeParole], verite: [TourDeParole]) -> Double {
        let total = verite.reduce(0) { $0 + ($1.fin - $1.debut) }
        guard total > 0 else { return 0 }
        var commun: [String: [String: Double]] = [:]
        for v in verite {
            for t in trouves where t.debut < v.fin && v.debut < t.fin {
                commun[t.voix, default: [:]][v.voix, default: 0] += min(v.fin, t.fin) - max(v.debut, t.debut)
            }
        }
        let paires = commun.flatMap { t, d in d.map { (t, $0.key, $0.value) } }.sorted { $0.2 > $1.2 }
        var prisT = Set<String>(), prisV = Set<String>()
        var juste = 0.0
        for (t, v, d) in paires where !prisT.contains(t) && !prisV.contains(v) { prisT.insert(t); prisV.insert(v); juste += d }
        return juste / total
    }

    /// Part des passages « Eux » dont l'orateur est le bon (même appariement : chaque orateur trouvé va à la vraie voix qu'il porte le
    /// plus souvent). `vraies[i]` : la vraie voix du passage i. Un passage resté « Eux » compte comme faux.
    public static func passagesJustes(_ segments: [SegmentReunion], vraies: [String]) -> Double {
        let paires = zip(segments, vraies).filter { $0.0.locuteur == .eux }
        guard !paires.isEmpty else { return 0 }
        var compte: [String: [String: Int]] = [:]
        for (s, v) in paires { if let o = s.orateur { compte[o, default: [:]][v, default: 0] += 1 } }
        let liste = compte.flatMap { o, d in d.map { (o, $0.key, $0.value) } }.sorted { $0.2 > $1.2 }
        var prisO = Set<String>(), prisV = Set<String>()
        var justes = 0
        for (o, v, n) in liste where !prisO.contains(o) && !prisV.contains(v) { prisO.insert(o); prisV.insert(v); justes += n }
        return Double(justes) / Double(paires.count)
    }
}

/// Le traitement d'après l'appel montré dans l'îlot : la relecture (réseau) et la séparation des voix (sur le Mac) tournent en même
/// temps ; la barre suit les deux, l'étape dit ce qu'on attend. Les étapes et la progression d'ensemble viennent d'ici, logique pure.
public struct AvancementNote: Equatable, Sendable {
    /// Relecture : 0 à 1.
    public var relecture = 0.0
    public var relectureFinie = false
    /// Séparation des voix (téléchargement du modèle compris) : 0 à 1, nil quand il n'y a rien à séparer.
    public var voix: Double?
    public var voixFinie = false
    /// Vrai pendant le téléchargement du modèle (premier usage seulement).
    public var telechargement = false

    private var aTelecharge = false

    public init(separation: Bool) { voix = separation ? 0 : nil; voixFinie = !separation }

    /// Le modèle se télécharge (0 à 1) : la première moitié de la part des voix.
    public mutating func telechargement(_ p: Double) {
        telechargement = true; aTelecharge = true
        voix = 0.5 * min(1, max(0, p))
    }

    /// La séparation avance (0 à 1) : toute la part des voix, ou la seconde moitié après un téléchargement.
    public mutating func separation(_ p: Double) {
        telechargement = false
        let x = min(1, max(0, p))
        voix = aTelecharge ? 0.5 + 0.5 * x : x
    }

    /// Part de la séparation des voix dans la première partie de la barre (le reste : la relecture).
    public static let partVoix = 0.15

    /// La progression de la première partie (relecture + voix), de 0 à `PreparationNote.partRelecture`.
    public var progres: Double {
        let r = relectureFinie ? 1 : min(1, max(0, relecture))
        guard let v = voix else { return PreparationNote.partRelecture * r }
        let x = voixFinie ? 1 : min(1, max(0, v))
        return PreparationNote.partRelecture * ((1 - Self.partVoix) * r + Self.partVoix * x)
    }

    /// Ce qu'on attend : le téléchargement du modèle d'abord (il ne se voit qu'une fois), puis la relecture, puis les voix ; les
    /// deux finies, la rédaction de la note prend la suite.
    public var etape: String {
        if telechargement && !voixFinie { return PreparationNote.telechargementVoix }
        if !relectureFinie { return PreparationNote.relecture }
        if voix != nil && !voixFinie { return PreparationNote.voix }
        return PreparationNote.redaction
    }
}
