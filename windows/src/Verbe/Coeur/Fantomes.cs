using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Verbe.Coeur;

/// Ce que Whisper « entend » dans le silence ou le bruit (portage de DicteeCore/TextAssembler.swift).
public static class Fantomes
{
    static readonly string[] PhrasesBrutes =
    {
        "merci d'avoir regardé cette vidéo", "merci d'avoir regardé la vidéo",
        "sous-titres réalisés par la communauté d'amara.org", "sous-titres réalisés para la communauté d'amara.org",
        "sous-titrage société radio-canada", "sous-titrage st' 501", "sous-titrage st'501",
        "thanks for watching", "thank you for watching", "n'oubliez pas de vous abonner", "abonnez-vous",
        "transcription d'une dictée en français", "transcription of a dictation in english", "merci", "thank you",
    };
    static readonly HashSet<string> Ensemble = PhrasesBrutes.Select(Normaliser).ToHashSet();

    static string Normaliser(string s)
    {
        var sb = new StringBuilder();
        foreach (var ch in s.ToLowerInvariant()) if (!".,;:!?…\"«»()[]".Contains(ch)) sb.Append(ch);
        return sb.ToString().Trim().Replace("  ", " ");
    }

    /// Vrai si le texte est vide ou n'est qu'une phrase fantôme. « Merci » seul n'est fantôme que sur un son très court ou très faible :
    /// c'est l'appelant qui passe `sonFaible`.
    public static bool EstFantome(string texte, bool sonFaible = false)
    {
        var n = Normaliser(texte);
        if (n.Length == 0) return true;
        if (n is "merci" or "thank you") return sonFaible;
        return Ensemble.Contains(n);
    }

    /// Le « prompt » envoyé à Whisper : les mots du dictionnaire (Whisper ne retient que ~224 jetons : 600 caractères au plus).
    public static string Prompt(IEnumerable<string> mots)
    {
        var p = string.Join(", ", mots.Select(m => m.Trim()).Where(m => m.Length > 0));
        if (p.Length > 0) p += ".";
        return p.Length > 600 ? p[..600] : p;
    }
}
