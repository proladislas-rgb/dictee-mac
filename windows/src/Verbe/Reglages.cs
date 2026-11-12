using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Verbe;

/// Réglages dans %APPDATA%\Verbe\reglages.json. La clé Groq y est chiffrée par Windows (DPAPI, liée à la session) :
/// illisible depuis un autre compte ou un autre PC.
sealed class Reglages
{
    public string Langue { get; set; } = "fr";          // fr, en ou auto
    public bool Sons { get; set; } = true;
    public string? CleChiffree { get; set; }
    /// Mots à écrire exactement ainsi (noms propres, marques) : envoyés à Whisper et à la remise au propre.
    public List<string> Mots { get; set; } = new();
    public bool PremierLancementVu { get; set; }

    public static string Dossier => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Verbe");
    static string Fichier => Path.Combine(Dossier, "reglages.json");
    static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    static readonly byte[] Sel = Encoding.UTF8.GetBytes("Verbe pour Windows");

    public static Reglages Charger()
    {
        try { if (File.Exists(Fichier)) return JsonSerializer.Deserialize<Reglages>(File.ReadAllText(Fichier)) ?? new(); }
        catch (Exception e) { Journal.Ecrire("réglages illisibles, valeurs par défaut : " + e.GetType().Name); }
        return new();
    }

    public void Enregistrer()
    {
        try
        {
            Directory.CreateDirectory(Dossier);
            var tmp = Fichier + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(this, Options));
            File.Move(tmp, Fichier, true);
        }
        catch (Exception e) { Journal.Ecrire("réglages non enregistrés : " + e.GetType().Name); }
    }

    /// La clé : celle enregistrée dans Verbe, sinon la variable d'environnement GROQ_API_KEY.
    public string? Cle()
    {
        if (!string.IsNullOrEmpty(CleChiffree))
        {
            try { return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(CleChiffree), Sel, DataProtectionScope.CurrentUser)); }
            catch { }
        }
        var env = Environment.GetEnvironmentVariable("GROQ_API_KEY");
        return string.IsNullOrWhiteSpace(env) ? null : env.Trim();
    }

    public void DefinirCle(string cle)
    {
        CleChiffree = Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(cle.Trim()), Sel, DataProtectionScope.CurrentUser));
        Enregistrer();
    }

    public string? LangueWhisper => Langue == "auto" ? null : Langue;
}

/// Journal technique (durées, erreurs ; jamais le texte dicté ni la clé) : %APPDATA%\Verbe\journal.txt.
static class Journal
{
    static readonly object Verrou = new();
    public static void Ecrire(string ligne)
    {
        try
        {
            lock (Verrou)
            {
                Directory.CreateDirectory(Reglages.Dossier);
                var f = Path.Combine(Reglages.Dossier, "journal.txt");
                if (File.Exists(f) && new FileInfo(f).Length > 1_000_000) File.Move(f, f + ".ancien", true);
                File.AppendAllText(f, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  {ligne}{Environment.NewLine}");
            }
        }
        catch { }
    }
}
