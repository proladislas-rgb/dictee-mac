using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace Verbe.Coeur;

/// Ce qui sort d'une dictée : le texte à coller, ou rien (silence, fantôme).
public sealed record Resultat(string? Texte, string Journal);

/// La chaîne complète : son → Whisper → (remise au propre si utile, sinon texte brut) → retouche selon l'endroit.
/// Si la remise au propre échoue ou s'éloigne de la dictée, le texte de Whisper est collé tel quel : jamais de perte.
public sealed class Chaine
{
    readonly Groq groq;
    public Chaine(Groq groq) { this.groq = groq; }

    /// La remise au propre ne doit jamais faire attendre plus que ça.
    public static readonly TimeSpan DelaiNettoyage = TimeSpan.FromSeconds(2.5);

    public async Task<Resultat> Traiter(byte[] pcm, string? langue, Contexte contexte, IReadOnlyList<string> dictionnaire, CancellationToken ct)
    {
        var chrono = Stopwatch.StartNew();
        double duree = Wav.Duree(pcm), crete = Wav.Crete(pcm);
        bool sonFaible = duree < 1.2 || crete < 0.05;
        var brut = await groq.Transcrire(Wav.Depuis(pcm), langue, Fantomes.Prompt(dictionnaire), ct);
        long tWhisper = chrono.ElapsedMilliseconds;
        if (Fantomes.EstFantome(brut, sonFaible))
            return new Resultat(null, $"rien entendu (Whisper {tWhisper} ms, {duree:0.0} s de son)");

        var analyse = RemiseAuPropre.Analyser(brut);
        string texte = brut, voie = "brut";
        if (analyse.Utile)
        {
            try
            {
                var sortie = await groq.Nettoyer(RemiseAuPropre.Consignes(contexte, dictionnaire), brut, DelaiNettoyage, ct);
                var (ok, t) = RemiseAuPropre.Verifier(brut, sortie);
                if (ok) { texte = t; voie = "remis au propre"; } else voie = "brut (sortie refusée : " + t + ")";
            }
            catch (GroqException e) { voie = "brut (remise au propre : " + e.Message + ")"; }
        }
        texte = RemiseAuPropre.Retoucher(texte, brut, contexte);
        return new Resultat(texte, $"Whisper {tWhisper} ms, total {chrono.ElapsedMilliseconds} ms, {duree:0.0} s de son, {analyse.NombreDeMots} mots, {voie}, contexte {contexte}");
    }
}
