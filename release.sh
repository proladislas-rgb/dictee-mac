#!/bin/zsh
# Fabrique le fichier d'installation : dist/Dictee-<version>.dmg
#   ./release.sh
# Ne touche pas à ~/Applications (l'app installée n'est ni remplacée ni fermée).
# La version vient du fichier VERSION. Signature ad hoc (pas de compte développeur Apple).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION illisible : « $VERSION »"; exit 1; }
DIST="dist"
CONTENU="$DIST/contenu-dmg"
DMG="$DIST/Dictee-$VERSION.dmg"

rm -rf "$DIST/app" "$CONTENU" "$DMG"
mkdir -p "$DIST/app" "$CONTENU"

echo "==> Construction de l'app (release, version $VERSION)"
./build.sh --sortie "$DIST/app"

echo "==> Contenu de l'image disque"
cp -R "$DIST/app/Dictee.app" "$CONTENU/Dictee.app"
ln -s /Applications "$CONTENU/Applications"
cat > "$CONTENU/Lisez-moi.txt" <<LISEZMOI
Dictée $VERSION

Installer
  1. Glisse Dictee.app sur le dossier Applications, à côté.
  2. Ouvre Dictée depuis Applications.
  3. Première ouverture : Dictée n'est pas signée par un compte développeur Apple,
     donc macOS demande une confirmation.
       - clic droit sur Dictee › Ouvrir › Ouvrir,
       - ou, si Ouvrir ne propose rien : Réglages Système › Confidentialité et
         sécurité › en bas, « Ouvrir quand même ».
  4. Accepte les autorisations demandées (micro, accessibilité, surveillance de l'entrée).

Réglage à faire une fois
  Réglages Système › Clavier › « Appuyer sur 🌐 pour » : choisis « Ne rien faire »,
  sinon les emoji s'ouvrent quand tu tiens la touche fn.

Clé Groq (gratuite)
  Dictée envoie ta voix à Groq pour la transcrire. Crée un compte gratuit sur
  console.groq.com, copie une clé API, puis colle-la quand Dictée la demande
  au premier lancement. Elle est rangée dans le Trousseau de ton Mac.

Utiliser
  Tiens fn, parle, relâche : le texte s'écrit là où est le curseur.

Désinstaller
  Clic droit sur les guillemets de la barre des menus › Désinstaller Dictée…
  (ou Réglages › Désinstaller). Cela efface l'historique, les mots, les réglages,
  le journal et la clé du Trousseau, puis place l'app à la corbeille.
  Sinon, glisse simplement Dictee.app à la corbeille.
LISEZMOI

echo "==> Vérification de la signature de l'app"
codesign --verify --strict "$CONTENU/Dictee.app"

echo "==> Image disque"
hdiutil create -volname "Dictee" -srcfolder "$CONTENU" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
rm -rf "$CONTENU"

echo "==> Prête : $DMG ($(du -h "$DMG" | cut -f1))"
echo "    SHA-256 : $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
