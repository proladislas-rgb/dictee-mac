using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Verbe.Coeur;

public enum Echec { PasDeCle, CleRefusee, Limite, Reseau, Serveur, Illisible }

public sealed class GroqException : Exception
{
    public Echec Genre { get; }
    public int? Code { get; }
    public double? AttenteSecondes { get; }
    public GroqException(Echec genre, string message, int? code = null, double? attente = null) : base(message) { Genre = genre; Code = code; AttenteSecondes = attente; }
}

/// Appels à Groq : Whisper large v3 turbo pour la transcription, petite IA pour la remise au propre.
/// Un seul HttpClient : la connexion HTTP/2 est réutilisée, `Prechauffer()` l'ouvre dès l'appui sur la touche.
/// La clé n'est jamais écrite dans le journal.
public sealed class Groq
{
    public const string WhisperRapide = "whisper-large-v3-turbo";
    public const string WhisperPrecis = "whisper-large-v3";
    /// Ordre des modèles de texte (même choix que la version Mac : qwen relit, les gpt-oss prennent le relais en cas de limite).
    public static readonly string[] ModelesTexte = { "qwen/qwen3.8-27b", "openai/gpt-oss-120b", "openai/gpt-oss-20b" };

    static readonly Uri Base = new("https://api.groq.com/openai/v1/");
    readonly HttpClient http;
    readonly Func<string?> lireCle;
    readonly Dictionary<string, DateTime> pauses = new();

    public Groq(Func<string?> lireCle)
    {
        this.lireCle = lireCle;
        var gestion = new SocketsHttpHandler
        {
            PooledConnectionIdleTimeout = TimeSpan.FromMinutes(5),
            PooledConnectionLifetime = TimeSpan.FromMinutes(20),
            EnableMultipleHttp2Connections = true,
            AutomaticDecompression = DecompressionMethods.All,
        };
        http = new HttpClient(gestion) { BaseAddress = Base, Timeout = Timeout.InfiniteTimeSpan, DefaultRequestVersion = HttpVersion.Version20 };
    }

    string Cle() => lireCle() is { Length: > 0 } c ? c : throw new GroqException(Echec.PasDeCle, "clé Groq absente");

    /// Ouvre la connexion TLS à l'avance (requête sans clé : seule la poignée de main compte).
    public void Prechauffer()
    {
        _ = Task.Run(async () =>
        {
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Head, "models");
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4));
                using var _r = await http.SendAsync(req, cts.Token);
            }
            catch { }
        });
    }

    /// Vérifie qu'une clé est acceptée (liste des modèles). Vrai / faux, ou exception réseau.
    public async Task<bool> TesterCle(string cle, CancellationToken ct = default)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "models");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", cle.Trim());
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct); cts.CancelAfter(TimeSpan.FromSeconds(8));
        try
        {
            using var r = await http.SendAsync(req, cts.Token);
            return r.IsSuccessStatusCode;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException && !ct.IsCancellationRequested)
        { throw new GroqException(Echec.Reseau, "réseau"); }
    }

    /// Transcription. `langue` null = détection automatique. Limite atteinte sur le turbo : le modèle précis (quota séparé) prend le relais.
    public async Task<string> Transcrire(byte[] wav, string? langue, string prompt, CancellationToken ct)
    {
        try { return await TranscrireAvec(WhisperRapide, wav, langue, prompt, ct); }
        catch (GroqException e) when (e.Genre is Echec.Limite or Echec.Serveur)
        { return await TranscrireAvec(WhisperPrecis, wav, langue, prompt, ct); }
    }

    async Task<string> TranscrireAvec(string modele, byte[] wav, string? langue, string prompt, CancellationToken ct)
    {
        var cle = Cle();
        using var corps = new MultipartFormDataContent("verbe-" + Guid.NewGuid().ToString("N"));
        corps.Add(new StringContent(modele), "model");
        corps.Add(new StringContent("json"), "response_format");
        corps.Add(new StringContent("0"), "temperature");
        if (!string.IsNullOrEmpty(langue)) corps.Add(new StringContent(langue), "language");
        if (!string.IsNullOrEmpty(prompt)) corps.Add(new StringContent(prompt), "prompt");
        var fichier = new ByteArrayContent(wav);
        fichier.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
        corps.Add(fichier, "file", "dictee.wav");

        using var req = new HttpRequestMessage(HttpMethod.Post, "audio/transcriptions") { Content = corps };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", cle);
        // 8 s pour une dictée courte, un peu plus pour une longue (le fichier part plus lentement sur une connexion faible).
        var delai = TimeSpan.FromSeconds(8 + wav.Length / (double)Wav.OctetsParSeconde / 10);
        var json = await Envoyer(req, delai, ct);
        return json["text"]?.GetValue<string>()?.Trim() ?? throw new GroqException(Echec.Illisible, "réponse illisible");
    }

    /// Remise au propre : essaie les modèles dans l'ordre, saute ceux en pause (limite atteinte). `delaiTotal` borne l'attente.
    public async Task<string> Nettoyer(string systeme, string texte, TimeSpan delaiTotal, CancellationToken ct)
    {
        var fin = DateTime.UtcNow + delaiTotal;
        GroqException derniere = new(Echec.Limite, "tous les modèles en pause");
        foreach (var m in ModelesTexte)
        {
            lock (pauses) if (pauses.TryGetValue(m, out var jusqua) && jusqua > DateTime.UtcNow) continue;
            var reste = fin - DateTime.UtcNow;
            if (reste < TimeSpan.FromMilliseconds(150)) break;
            try { return await NettoyerAvec(m, systeme, texte, reste, ct); }
            catch (GroqException e) when (e.Genre == Echec.Limite)
            {
                lock (pauses) pauses[m] = DateTime.UtcNow + TimeSpan.FromSeconds(Math.Clamp(e.AttenteSecondes ?? 30, 5, 3600));
                derniere = e;
            }
        }
        throw derniere;
    }

    async Task<string> NettoyerAvec(string modele, string systeme, string texte, TimeSpan delai, CancellationToken ct)
    {
        var cle = Cle();
        var corps = new JsonObject
        {
            ["model"] = modele,
            ["temperature"] = 0.1,
            ["stream"] = false,
            ["max_completion_tokens"] = 300 + texte.Length,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = systeme },
                new JsonObject { ["role"] = "user", ["content"] = texte }),
        };
        // qwen3 réfléchit par défaut : on le coupe (sinon plusieurs secondes). Les gpt-oss ne descendent pas sous « low ».
        if (modele.StartsWith("qwen/qwen3")) corps["reasoning_effort"] = "none";
        if (modele.StartsWith("openai/gpt-oss")) { corps["reasoning_effort"] = "low"; corps["include_reasoning"] = false; }

        using var req = new HttpRequestMessage(HttpMethod.Post, "chat/completions")
        { Content = new StringContent(corps.ToJsonString(), Encoding.UTF8, "application/json") };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", cle);
        var json = await Envoyer(req, delai, ct);
        return json["choices"]?[0]?["message"]?["content"]?.GetValue<string>() ?? throw new GroqException(Echec.Illisible, "réponse illisible");
    }

    async Task<JsonNode> Envoyer(HttpRequestMessage req, TimeSpan delai, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(delai);
        HttpResponseMessage r;
        try { r = await http.SendAsync(req, cts.Token); }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (OperationCanceledException) { throw new GroqException(Echec.Reseau, "délai dépassé"); }
        catch (HttpRequestException) { throw new GroqException(Echec.Reseau, "réseau"); }
        using (r)
        {
            string texte;
            try { texte = await r.Content.ReadAsStringAsync(cts.Token); }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception) { throw new GroqException(Echec.Reseau, "réponse coupée"); }
            int code = (int)r.StatusCode;
            if (code == 401 || code == 403) throw new GroqException(Echec.CleRefusee, "clé refusée", code);
            if (code == 429)
            {
                double? attente = null;
                if (r.Headers.RetryAfter?.Delta is { } d) attente = d.TotalSeconds;
                else if (r.Headers.TryGetValues("retry-after", out var v) && double.TryParse(string.Join("", v), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var s)) attente = s;
                throw new GroqException(Echec.Limite, "limite atteinte", code, attente);
            }
            if (code >= 500) throw new GroqException(Echec.Serveur, "Groq en panne", code);
            if (code != 200) throw new GroqException(Echec.Illisible, "HTTP " + code, code);
            try { return JsonNode.Parse(texte) ?? throw new GroqException(Echec.Illisible, "réponse vide"); }
            catch (JsonException) { throw new GroqException(Echec.Illisible, "réponse illisible"); }
        }
    }
}
