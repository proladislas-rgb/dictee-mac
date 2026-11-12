using System;
using System.IO;
using System.Linq;
using System.Threading;
using Verbe.Coeur;

// Contrôles du cœur de Verbe pour Windows (logique pure + un essai réel chez Groq si une clé et un son sont fournis).
// dotnet run -- [chemin.wav-16k-mono]
int ok = 0, ko = 0;
void V(bool c, string nom) { if (c) ok++; else { ko++; Console.WriteLine("ÉCHEC : " + nom); } }

// contexte
V(RemiseAuPropre.ContexteDe("WindowsTerminal", "") == Contexte.Terminal, "Windows Terminal = terminal");
V(RemiseAuPropre.ContexteDe("cmd.exe", "") == Contexte.Terminal, "cmd.exe = terminal");
V(RemiseAuPropre.ContexteDe("chrome", "Boîte de réception - Gmail") == Contexte.Courriel, "Gmail dans Chrome = courriel");
V(RemiseAuPropre.ContexteDe("msedge", "ChatGPT") == Contexte.AssistantIA, "ChatGPT dans Edge = assistant");
V(RemiseAuPropre.ContexteDe("OUTLOOK", "") == Contexte.Courriel, "Outlook = courriel");
V(RemiseAuPropre.ContexteDe("WhatsApp", "") == Contexte.Messagerie, "WhatsApp = messagerie");
V(RemiseAuPropre.ContexteDe("WINWORD", "") == Contexte.Notes, "Word = notes");
V(RemiseAuPropre.ContexteDe("explorer", "") == Contexte.General, "Explorateur = général");
V(RemiseAuPropre.ContexteDe(null, null) == Contexte.General, "rien = général");

// analyse
V(RemiseAuPropre.Mots("Écris-moi, s’il te plaît !").SequenceEqual(new[] { "ecris", "moi", "s'il", "te", "plait" }), "mots sans accents ni ponctuation");
V(!RemiseAuPropre.Analyser("Bonjour à tous.").Utile, "phrase courte propre : pas de remise au propre");
V(RemiseAuPropre.Analyser("euh bonjour").Hesitations, "« euh » = hésitation");
V(RemiseAuPropre.Analyser("mardi non plutôt mercredi").CorrectionsDites, "correction dite");
V(RemiseAuPropre.Analyser("bonjour à la ligne merci").CommandesDites, "« à la ligne » = commande");
V(RemiseAuPropre.Analyser("je je pense").Hesitations, "bégaiement");
V(RemiseAuPropre.Analyser("un deux trois quatre cinq six sept").Utile, "7 mots = utile");
V(!RemiseAuPropre.Analyser("le point de vue est bon").CommandesDites, "« point » au milieu n'est pas une commande");
V(RemiseAuPropre.Analyser("c'est fini point").CommandesDites, "« point » final = commande");

// garde-fou
V(!RemiseAuPropre.Verifier("quelle heure est-il", "Voici le texte : Quelle heure est-il ?").accepte, "préambule refusé");
V(!RemiseAuPropre.Verifier("quelle est la capitale de la France", "La capitale de la France est Paris, une ville magnifique et très visitée.").accepte, "réponse à la question refusée");
V(RemiseAuPropre.Verifier("euh je passe mardi non plutôt mercredi", "Je passe mercredi.").accepte, "correction acceptée");
V(RemiseAuPropre.Verifier("bonjour comment ça va", "\"Bonjour, comment ça va ?\"").texte == "Bonjour, comment ça va ?", "guillemets retirés");
V(!RemiseAuPropre.Verifier("bonjour", "").accepte, "sortie vide refusée");

// retouche
V(RemiseAuPropre.TypographieFrancaise("Ça va?") == "Ça va ?", "espace avant ?");
V(RemiseAuPropre.TypographieFrancaise("Il est 10:30.") == "Il est 10:30.", "heure intacte");
V(RemiseAuPropre.TypographieFrancaise("https://exemple.fr") == "https://exemple.fr", "adresse intacte");
V(RemiseAuPropre.Retoucher("Git status.", "git status", Contexte.Terminal) == "Git status", "terminal : pas de point final");
V(RemiseAuPropre.Retoucher("ls -la\n", "ls -la", Contexte.Terminal) == "ls -la", "terminal : jamais de retour à la ligne (la commande partirait)");
V(RemiseAuPropre.Retoucher("Bonjour.", "bonjour", Contexte.Courriel) == "Bonjour.", "courriel : point gardé");

// fantômes
V(Fantomes.EstFantome("Sous-titres réalisés par la communauté d'Amara.org"), "Amara = fantôme");
V(Fantomes.EstFantome("  "), "vide = fantôme");
V(!Fantomes.EstFantome("Merci.", sonFaible: false), "« Merci » dit clairement = gardé");
V(Fantomes.EstFantome("Merci.", sonFaible: true), "« Merci » sur du silence = fantôme");
V(Fantomes.Prompt(new[] { "Verbe", " Groq ", "" }) == "Verbe, Groq.", "prompt du dictionnaire");

// son
var pcm = new byte[Wav.Frequence * 2];   // 1 s de silence
var wav = Wav.Depuis(pcm);
V(wav.Length == 44 + pcm.Length && System.Text.Encoding.ASCII.GetString(wav, 0, 4) == "RIFF" && BitConverter.ToInt32(wav, 24) == 16000, "en-tête WAV");
V(Math.Abs(Wav.Duree(pcm) - 1.0) < 1e-9 && Wav.Crete(pcm) == 0, "durée et crête");
V(Wav.Signal(880, 1320).Length > 44, "signal sonore");

// consignes
V(RemiseAuPropre.Consignes(Contexte.Terminal, new[] { "Verbe" }).Contains("Écris exactement ainsi ces mots : Verbe."), "dictionnaire dans la consigne");

Console.WriteLine($"logique : {ok} ok, {ko} échec(s)");

// essai réel (facultatif)
if (args.Length > 0)
{
    var cle = Environment.GetEnvironmentVariable("GROQ_API_KEY");
    var octets = File.ReadAllBytes(args[0]);
    var son = octets.Skip(44).ToArray();
    var chaine = new Chaine(new Groq(() => cle));
    foreach (var (ctx, nom) in new[] { (Contexte.Courriel, "courriel"), (Contexte.Terminal, "terminal") })
    {
        var r = chaine.Traiter(son, "fr", ctx, new[] { "Verbe" }, CancellationToken.None).GetAwaiter().GetResult();
        Console.WriteLine($"[{nom}] « {r.Texte} »  —  {r.Journal}");
    }
    var r2 = chaine.Traiter(new byte[Wav.Frequence * 2], "fr", Contexte.General, Array.Empty<string>(), CancellationToken.None).GetAwaiter().GetResult();
    Console.WriteLine($"[silence] {(r2.Texte == null ? "rien collé" : "COLLÉ : " + r2.Texte)}  —  {r2.Journal}");
    try { new Groq(() => "gsk_fausse").Transcrire(Wav.Depuis(son), "fr", "", CancellationToken.None).GetAwaiter().GetResult(); Console.WriteLine("ÉCHEC : fausse clé acceptée"); }
    catch (GroqException e) { Console.WriteLine($"[fausse clé] {e.Genre} ({e.Code})"); }
}
return ko == 0 ? 0 : 1;
