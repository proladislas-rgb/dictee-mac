using System;
using System.IO;
using System.Text;

namespace Verbe.Coeur;

/// Son brut (PCM 16 bits mono) → fichier WAV en mémoire, et mesures simples du niveau.
public static class Wav
{
    public const int Frequence = 16000;
    public const int OctetsParSeconde = Frequence * 2;

    public static byte[] Depuis(byte[] pcm, int frequence = Frequence)
    {
        using var ms = new MemoryStream(44 + pcm.Length);
        using var w = new BinaryWriter(ms, Encoding.ASCII, leaveOpen: true);
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + pcm.Length);
        w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(frequence); w.Write(frequence * 2); w.Write((short)2); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(pcm.Length); w.Write(pcm);
        w.Flush();
        return ms.ToArray();
    }

    public static double Duree(byte[] pcm) => pcm.Length / (double)OctetsParSeconde;

    /// Crête du morceau, de 0 à 1.
    public static double Crete(byte[] pcm, int debut = 0, int longueur = -1)
    {
        if (longueur < 0) longueur = pcm.Length - debut;
        int max = 0;
        for (int i = debut; i + 1 < debut + longueur; i += 2)
        {
            int v = Math.Abs((int)BitConverter.ToInt16(pcm, i));
            if (v > max) max = v;
        }
        return max / 32768.0;
    }

    /// Niveau efficace (RMS) du morceau, de 0 à 1.
    public static double Efficace(byte[] pcm, int debut = 0, int longueur = -1)
    {
        if (longueur < 0) longueur = pcm.Length - debut;
        double somme = 0; int n = 0;
        for (int i = debut; i + 1 < debut + longueur; i += 2) { double v = BitConverter.ToInt16(pcm, i) / 32768.0; somme += v * v; n++; }
        return n == 0 ? 0 : Math.Sqrt(somme / n);
    }

    /// Petit son de début / fin (deux notes très brèves, douces), en WAV.
    public static byte[] Signal(double f1, double f2, double secondes = 0.09, double volume = 0.12)
    {
        int n = (int)(Frequence * secondes);
        var pcm = new byte[n * 2];
        double phase = 0;
        for (int i = 0; i < n; i++)
        {
            double t = i / (double)n;
            double f = t < 0.5 ? f1 : f2;
            phase += 2 * Math.PI * f / Frequence;
            double local = t < 0.5 ? t * 2 : (t - 0.5) * 2;       // chaque note monte puis s'éteint
            double enveloppe = Math.Sin(Math.PI * local);
            short v = (short)(Math.Sin(phase) * enveloppe * volume * 32767);
            BitConverter.GetBytes(v).CopyTo(pcm, i * 2);
        }
        return Depuis(pcm);
    }
}
