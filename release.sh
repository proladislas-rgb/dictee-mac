#!/bin/zsh
# Fabrique les fichiers d'une release : dist/Voxile-<version>.dmg et dist/Voxile-<version>.dmg.sha256, plus, pour le passage de nom,
# dist/Verbe-<version>.dmg (et son .sha256) : la MÊME app, rangée sous le nom Verbe.app, que les Verbe 0.3.x déjà installées savent
# télécharger et installer (elles cherchent « Verbe-<version>.dmg », « Verbe.app » et « Contents/MacOS/Verbe ») ; au lancement, cette
# app se renomme seule en Voxile.app (MigrationNom). Joindre les quatre fichiers à la release.
#   ./release.sh
#   ./release.sh --version 9.9.9 --sortie /un/dossier   (faux DMG de test, par exemple pour la mise à jour automatique)
# Ne touche pas à ~/Applications (l'app installée n'est ni remplacée ni fermée).
# La version vient du fichier VERSION (sauf --version). Signature ad hoc (pas de compte développeur Apple).
# Le fichier .sha256 est au format de `shasum -a 256` : l'app le compare au DMG avant de se mettre à jour. Il se joint à la release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="dist"
TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ -n "${2:-}" ]] || { echo "--version demande un numéro"; exit 2; }; VERSION="$2"; TEST=1; shift 2 ;;
    --sortie) [[ -n "${2:-}" ]] || { echo "--sortie demande un dossier"; exit 2; }; DIST="$2"; shift 2 ;;
    *) echo "Option inconnue : $1"; exit 2 ;;
  esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION illisible : « $VERSION »"; exit 1; }
export VERBE_VERSION="$VERSION"
CONTENU="$DIST/contenu-dmg"
DMG="$DIST/Voxile-$VERSION.dmg"
DMG_COMPAT="$DIST/Verbe-$VERSION.dmg"

rm -rf "$DIST/app" "$CONTENU" "$DMG" "$DMG.sha256" "$DMG_COMPAT" "$DMG_COMPAT.sha256"
mkdir -p "$DIST/app" "$CONTENU"

echo "==> Construction de l'app (release, version $VERSION)"
./build.sh --sortie "$DIST/app"

echo "==> Contenu de l'image disque"
cp -R "$DIST/app/Voxile.app" "$CONTENU/Voxile.app"
ln -s /Applications "$CONTENU/Applications"
cat > "$CONTENU/Lisez-moi.txt" <<LISEZMOI
Voxile $VERSION

Installer
  1. Glisse Voxile.app sur le dossier Applications, à côté.
  2. Ouvre Voxile depuis Applications.

Première ouverture (une seule fois)
  Voxile n'est pas signé par un compte développeur Apple (c'est payant, le projet reste
  gratuit). Sur un Mac récent, macOS refuse donc de l'ouvrir la première fois, et le
  clic droit › Ouvrir ne suffit plus. Fais ceci :
    1. Ouvre Voxile. Une fenêtre s'affiche avec deux boutons : « Placer dans la corbeille »
       et « Terminé ». Clique sur « Terminé » (surtout PAS sur la corbeille).
    2. Ouvre Réglages Système › Confidentialité et sécurité, descends tout en bas :
       tu y vois « Voxile a été bloqué… ». Clique sur « Ouvrir quand même »,
       puis confirme avec ton mot de passe ou Touch ID.
    3. Rouvre Voxile depuis Applications.
  Pour les initiés, une seule commande dans le Terminal fait la même chose :
    xattr -dr com.apple.quarantine /Applications/Voxile.app

Ensuite
  Accepte les autorisations demandées (micro, accessibilité, surveillance de l'entrée).
  Si ta touche 🌐 ouvre les emoji, Voxile te guide : Réglages Système › Clavier,
  « Appuyer sur la touche 🌐 pour » : « Ne rien faire ».

Clé Groq (gratuite)
  Voxile envoie ta voix à Groq pour la transcrire. Crée un compte gratuit sur
  console.groq.com, copie une clé API, puis colle-la quand Voxile la demande
  au premier lancement. Elle est rangée dans le Trousseau de ton Mac.

Utiliser
  Tiens fn, parle, relâche : le texte s'écrit là où est le curseur.

Sons et vibration
  Un petit son et une vibration du trackpad marquent le début, la fin et l'annulation.
  Réglages › Sons et Vibration pour les couper. La vibration ne se sent que si un doigt
  est posé sur le trackpad.

Si tu as déjà Voxile (l'ancien nom de Voxile)
  Voxile garde tes autorisations, ton historique et ton dictionnaire. Quitte Voxile, glisse
  Voxile.app dans Applications, ouvre-la : elle met l'ancienne Voxile.app à la corbeille.

Mises à jour
  Voxile cherche seul une nouvelle version sur GitHub (une fois par jour),
  te la propose sous l'encoche, puis se remplace et se relance. Réglages › Mises à jour pour
  le couper ou chercher tout de suite.

Désinstaller
  Clic droit sur les guillemets de la barre des menus › Désinstaller Voxile…
  (ou Réglages › Désinstaller). Cela efface l'historique, les mots, les réglages,
  le journal et la clé du Trousseau, puis place l'app à la corbeille (et une
  éventuelle ancienne Dictee.app, après confirmation).
  Sinon, glisse simplement Voxile.app à la corbeille.
LISEZMOI

echo "==> Vérification de la signature de l'app"
codesign --verify --strict "$CONTENU/Voxile.app"

echo "==> Image disque"
hdiutil create -volname "Voxile" -srcfolder "$CONTENU" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
rm -rf "$CONTENU"

# Le passage de nom : la même app sous le nom Verbe.app, avec un lien Contents/MacOS/Verbe vers l'exécutable Voxile (l'installateur
# des Verbe 0.3.x vérifie que ce fichier existe), signée de nouveau avec la même exigence (l'identifiant).
echo "==> Image disque de passage (Verbe-$VERSION.dmg, pour les Verbe déjà installées)"
COMPAT="$DIST/contenu-compat"
rm -rf "$COMPAT"; mkdir -p "$COMPAT"
cp -R "$DIST/app/Voxile.app" "$COMPAT/Verbe.app"
ln -s Voxile "$COMPAT/Verbe.app/Contents/MacOS/Verbe"
codesign --force --sign - --identifier com.hugues.dictee --requirements '=designated => identifier "com.hugues.dictee"' "$COMPAT/Verbe.app"
codesign --verify --strict --deep "$COMPAT/Verbe.app"
[[ -x "$COMPAT/Verbe.app/Contents/MacOS/Verbe" ]] || { echo "lien Verbe absent"; exit 1; }
hdiutil create -volname "Voxile" -srcfolder "$COMPAT" -fs HFS+ -format UDZO -ov "$DMG_COMPAT" >/dev/null
hdiutil verify "$DMG_COMPAT" >/dev/null
rm -rf "$COMPAT"

echo "==> Empreintes SHA-256"
( cd "$DIST" && for f in "Voxile-$VERSION.dmg" "Verbe-$VERSION.dmg"; do shasum -a 256 "$f" > "$f.sha256" && shasum -a 256 -c "$f.sha256" >/dev/null; done )

echo "==> Prête : $DMG ($(du -h "$DMG" | cut -f1))"
echo "    SHA-256 : $(cut -d' ' -f1 "$DMG.sha256")  ($DMG.sha256)"
echo "    Passage de nom : $DMG_COMPAT ($(cut -d' ' -f1 "$DMG_COMPAT.sha256"))"
if [[ "$TEST" == 1 ]]; then
  echo "    Version de test ($VERSION) : à ne jamais publier."
else
  echo "    Publier (Hugues, à la main) :"
  echo "      gh release create v$VERSION $DMG $DMG.sha256 $DMG_COMPAT $DMG_COMPAT.sha256 --target main --title \"Voxile $VERSION\" --notes-file dist/notes-v$VERSION.md"
  [[ -f "dist/notes-v$VERSION.md" ]] || echo "    ATTENTION : dist/notes-v$VERSION.md n'existe pas encore (les notes de la release, lues par « Nouveautés »)."
fi
