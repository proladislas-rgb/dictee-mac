using System;
using System.IO;
using System.Threading.Tasks;
using NAudio.Wave;
using Verbe.Coeur;

namespace Verbe;

/// Le micro par défaut de Windows, en 16 kHz mono 16 bits (ce que Whisper attend : rien à convertir).
/// Ouvert seulement pendant une dictée : le témoin « micro utilisé » de Windows ne s'allume que là.
sealed class Micro
{
    /// Niveau efficace de chaque tranche de 40 ms (fil du micro, pas celui de l'écran).
    public event Action<double>? Niveau;

    WaveInEvent? entree;
    MemoryStream tampon = new();
    TaskCompletionSource<bool>? arret;

    public bool Ouvert => entree != null || simulation != null;

    /// Essai : une voix simulée (son de 220 Hz qui monte et descend), 40 ms à la fois, comme le vrai micro.
    void DemarrerSimulation()
    {
        var t = tampon; int n = 0;
        simulation = new System.Threading.Timer(_ =>
        {
            var morceau = new byte[Wav.Frequence / 25 * 2];
            for (int i = 0; i < morceau.Length / 2; i++, n++)
            {
                double a = 0.3 * (0.5 + 0.5 * Math.Sin(n / 3000.0));
                BitConverter.GetBytes((short)(Math.Sin(2 * Math.PI * 220 * n / Wav.Frequence) * a * 32767)).CopyTo(morceau, i * 2);
            }
            lock (t) t.Write(morceau, 0, morceau.Length);
            Niveau?.Invoke(Wav.Efficace(morceau));
        }, null, 0, 40);
    }

    bool ArreterSimulation()
    {
        var s = simulation; simulation = null;
        if (s == null) return false;
        s.Dispose();
        return true;
    }

    System.Threading.Timer? simulation;

    public void Demarrer()
    {
        Abandonner();
        tampon = new MemoryStream(Wav.OctetsParSeconde * 10);
        if (Essai.Actif) { DemarrerSimulation(); return; }
        var e = new WaveInEvent
        {
            DeviceNumber = -1,   // WAVE_MAPPER : le micro choisi dans les paramètres de son de Windows
            WaveFormat = new WaveFormat(Wav.Frequence, 16, 1),
            BufferMilliseconds = 40,
            NumberOfBuffers = 4,
        };
        var t = tampon;
        e.DataAvailable += (_, a) =>
        {
            lock (t) t.Write(a.Buffer, 0, a.BytesRecorded);
            Niveau?.Invoke(Wav.Efficace(a.Buffer, 0, a.BytesRecorded));
        };
        var fin = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        e.RecordingStopped += (_, _) => fin.TrySetResult(true);
        arret = fin;
        try { e.StartRecording(); }   // lève une exception s'il n'y a aucun micro
        catch { e.Dispose(); arret = null; throw; }
        entree = e;
    }

    public double DureeEnCours { get { lock (tampon) return tampon.Length / (double)Wav.OctetsParSeconde; } }

    /// Arrête et rend tout le son enregistré (PCM 16 bits).
    public async Task<byte[]> Arreter()
    {
        if (ArreterSimulation()) { await Task.Delay(50); lock (tampon) return tampon.ToArray(); }
        var e = entree; entree = null;
        if (e == null) return Array.Empty<byte>();
        try { e.StopRecording(); } catch { }
        if (arret != null) await Task.WhenAny(arret.Task, Task.Delay(800));
        try { e.Dispose(); } catch { }
        lock (tampon) return tampon.ToArray();
    }

    public void Abandonner()
    {
        ArreterSimulation();
        var e = entree; entree = null;
        if (e == null) return;
        try { e.StopRecording(); } catch { }
        try { e.Dispose(); } catch { }
    }
}
