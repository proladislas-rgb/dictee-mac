#!/bin/zsh
# Fabrique les sons du banc d'essai du lexique : lit DOSSIER/phrases.json (une phrase, sa voix, les mots du lexique attendus)
# et écrit DOSSIER/NN.wav (16 kHz, mono, 16 bits) avec `say` puis `afconvert`. Aucun micro. Les phrases contiennent des noms de la
# vie de Hugues : leur dossier reste local (jamais dans git). Ensuite : `Verbe --banc-lexique DOSSIER` (réseau seulement).
#   scripts/banc-lexique.sh DOSSIER
set -euo pipefail
DOSSIER="${1:?Usage : scripts/banc-lexique.sh DOSSIER}"
[[ -f "$DOSSIER/phrases.json" ]] || { echo "Pas de $DOSSIER/phrases.json"; exit 1; }
python3 -I - "$DOSSIER" <<'PY' | while IFS=$'\t' read -r id voix texte; do
import json, sys
for c in json.load(open(sys.argv[1] + "/phrases.json")):
    # `dit` : comment prononcer ce que la phrase écrit (sigles épelés, par exemple) ; sinon le texte lui-même
    print("\t".join([c["id"], c["voix"], c.get("dit") or c["texte"]]))
PY
  say -v "$voix" -o "$DOSSIER/$id.aiff" -- "$texte"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$DOSSIER/$id.aiff" "$DOSSIER/$id.wav"
  rm -f "$DOSSIER/$id.aiff"
  echo "$id ($voix) ok"
done
