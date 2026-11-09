#!/usr/bin/env python3
"""Fabrique un dialogue d'essai (deux pistes WAV 16 kHz mono) pour `Verbe --reunion-test moi.wav eux.wav`.

Usage : python3 scripts/dialogue-reunion.py DOSSIER [--echo]
  DOSSIER/moi.wav  : la voix de « Moi » (Camille), silence quand les autres parlent
  DOSSIER/eux.wav  : les voix des autres (Nathalie et Paul), silence quand Moi parle
  --echo           : ajoute à moi.wav la voix des autres, très atténuée (haut-parleurs captés par le micro)

Les voix viennent de `say` (voix du Mac). Les deux fichiers ont exactement la même durée et le même axe de temps :
c'est ce que donnerait une vraie réunion enregistrée en deux pistes. Rien n'est écrit dans le dépôt.
"""
import array, os, subprocess, sys, tempfile, wave

MOI, NATHALIE, PAUL = "Thomas", "Shelley (Français (France))", "Jacques"
# (voix, pause avant en secondes, texte). Le texte contient des choses précises pour juger la note :
# des décisions, des actions avec qui/quand, une action SANS date, un « on verra » qui n'est pas une décision.
DIALOGUE = [
    (NATHALIE, 0.5, "Bonjour Camille, merci de prendre cet appel. Paul est avec moi, il s'occupe de la logistique chez Garnier et Fils."),
    (MOI, 0.6, "Bonjour Nathalie, bonjour Paul. Merci à vous deux. Je propose qu'on reprenne l'offre point par point, et qu'on finisse avec le calendrier."),
    (PAUL, 0.7, "Très bien. Pour rappel, nous avons deux ateliers à équiper, un à Lyon et un à Annecy."),
    (NATHALIE, 0.4, "Oui, et on voudrait que tout soit en place avant janvier, parce que la saison démarre début février."),
    (MOI, 0.8, "C'est noté. L'offre complète comprend les machines, l'installation et la maintenance pendant deux ans. La formation des équipes est une option."),
    (NATHALIE, 0.6, "La formation, on la fera nous-mêmes. Prenons l'offre complète sans l'option."),
    (MOI, 0.5, "Très bien, je note : offre complète, sans la formation."),
    (PAUL, 0.9, "Pour les volumes de commande, je peux vous donner les chiffres vendredi. On devrait être autour de douze cents pièces par mois."),
    (MOI, 0.6, "Parfait, ça me suffit pour chiffrer deux options, une avec paiement en une fois et une avec paiement en deux fois."),
    (NATHALIE, 0.7, "Le prix reste le point sensible. J'en parle à mon associé jeudi, et j'aurais besoin de la proposition chiffrée avant."),
    (MOI, 0.6, "D'accord, je vous envoie la proposition avec les deux options mercredi soir."),
    (NATHALIE, 0.5, "Parfait. Et pour le paiement, on préférerait en deux fois."),
    (MOI, 0.4, "Alors je retiens le paiement en deux fois."),
    (PAUL, 0.8, "Est-ce qu'on pourrait aussi parler de la livraison ? On aimerait recevoir les machines à Lyon en premier."),
    (MOI, 0.7, "Je ne peux pas vous donner de date de livraison aujourd'hui, je dois vérifier avec l'usine. Je reviens vers vous là-dessus."),
    (NATHALIE, 0.6, "D'accord. Sur la signature, on vise avant le vingt novembre."),
    (MOI, 0.4, "Très bien. Signature visée avant le vingt novembre."),
    (PAUL, 0.9, "J'ai une dernière question. Est-ce que la maintenance couvre aussi les déplacements ?"),
    (MOI, 0.6, "Je ne sais pas, je vérifierai le contrat et je vous répondrai."),
    (NATHALIE, 0.8, "On verra ça plus tard alors. Peut-être qu'on pourra aussi parler d'un troisième atelier l'an prochain, mais rien n'est décidé."),
    (MOI, 0.5, "Bien sûr, on en reparlera quand vous voudrez."),
    (NATHALIE, 0.6, "Merci Camille, bonne journée."),
    (PAUL, 0.3, "Merci, à bientôt."),
    (MOI, 0.4, "Merci à vous deux, bonne journée."),
]

def voix(nom, texte, dossier):
    aiff, wav = os.path.join(dossier, "v.aiff"), os.path.join(dossier, "v.wav")
    subprocess.run(["say", "-v", nom, "-o", aiff, texte], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, wav], check=True)
    with wave.open(wav) as w:
        a = array.array("h"); a.frombytes(w.readframes(w.getnframes()))
    return a

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    sortie, echo = sys.argv[1], "--echo" in sys.argv
    os.makedirs(sortie, exist_ok=True)
    moi, eux = array.array("h"), array.array("h")
    with tempfile.TemporaryDirectory() as tmp:
        for locuteur, pause, texte in DIALOGUE:
            clip = voix(locuteur, texte, tmp)
            silence = array.array("h", [0] * int(pause * 16000))
            moi.extend(silence); eux.extend(silence)
            if locuteur == MOI:
                moi.extend(clip); eux.extend(array.array("h", [0] * len(clip)))
            else:
                eux.extend(clip); moi.extend(array.array("h", [0] * len(clip)))
    fin = array.array("h", [0] * 16000)
    moi.extend(fin); eux.extend(fin)
    if echo:  # la voix des autres, à 12 % et un peu en retard (acoustique de la pièce), dans le micro
        retard = int(0.04 * 16000)
        for i, v in enumerate(eux):
            if v and i + retard < len(moi):
                moi[i + retard] = max(-32768, min(32767, moi[i + retard] + int(v * 0.12)))
    for nom, donnees in (("moi.wav", moi), ("eux.wav", eux)):
        with wave.open(os.path.join(sortie, nom), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(donnees.tobytes())
    print(f"{sortie}/moi.wav et eux.wav : {len(moi) / 16000:.0f} s chacun" + (" (avec écho dans moi.wav)" if echo else ""))

main()
