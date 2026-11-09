#!/bin/zsh
# Fabrique le fichier d'installation : dist/Verbe-<version>.dmg
#   ./release.sh
# Ne touche pas à ~/Applications (l'app installée n'est ni remplacée ni fermée).
# La version vient du fichier VERSION. Signature ad hoc (pas de compte développeur Apple).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION illisible : « $VERSION »"; exit 1; }
DIST="dist"
CONTENU="$DIST/contenu-dmg"
DMG="$DIST/Verbe-$VERSION.dmg"

rm -rf "$DIST/app" "$CONTENU" "$DMG"
mkdir -p "$DIST/app" "$CONTENU"

echo "==> Construction de l'app (release, version $VERSION)"
./build.sh --sortie "$DIST/app"

echo "==> Contenu de l'image disque"
cp -R "$DIST/app/Verbe.app" "$CONTENU/Verbe.app"
ln -s /Applications "$CONTENU/Applications"
cat > "$CONTENU/Lisez-moi.txt" <<LISEZMOI
Verbe $VERSION

Installer
  1. Glisse Verbe.app sur le dossier Applications, à côté.
  2. Ouvre Verbe depuis Applications.

Première ouverture (une seule fois)
  Verbe n'est pas signé par un compte développeur Apple (c'est payant, le projet reste
  gratuit). Sur un Mac récent, macOS refuse donc de l'ouvrir la première fois, et le
  clic droit › Ouvrir ne suffit plus. Fais ceci :
    1. Ouvre Verbe. Une fenêtre s'affiche avec deux boutons : « Placer dans la corbeille »
       et « Terminé ». Clique sur « Terminé » (surtout PAS sur la corbeille).
    2. Ouvre Réglages Système › Confidentialité et sécurité, descends tout en bas :
       tu y vois « Verbe a été bloqué… ». Clique sur « Ouvrir quand même »,
       puis confirme avec ton mot de passe ou Touch ID.
    3. Rouvre Verbe depuis Applications.
  Pour les initiés, une seule commande dans le Terminal fait la même chose :
    xattr -dr com.apple.quarantine /Applications/Verbe.app

Ensuite
  Accepte les autorisations demandées (micro, accessibilité, surveillance de l'entrée).
  Si ta touche 🌐 ouvre les emoji, Verbe te guide : Réglages Système › Clavier,
  « Appuyer sur la touche 🌐 pour » : « Ne rien faire ».

Clé Groq (gratuite)
  Verbe envoie ta voix à Groq pour la transcrire. Crée un compte gratuit sur
  console.groq.com, copie une clé API, puis colle-la quand Verbe la demande
  au premier lancement. Elle est rangée dans le Trousseau de ton Mac.

Utiliser
  Tiens fn, parle, relâche : le texte s'écrit là où est le curseur.

Sons et vibration
  Un petit son et une vibration du trackpad marquent le début, la fin et l'annulation.
  Réglages › Sons et Vibration pour les couper. La vibration ne se sent que si un doigt
  est posé sur le trackpad.

Si tu as déjà la version 0.1.0 (qui s'appelait Dictée)
  Verbe garde tes autorisations, ton historique et ton dictionnaire. Ferme Dictée, ouvre
  Verbe, puis jette l'ancienne Dictee.app.

Désinstaller
  Clic droit sur les guillemets de la barre des menus › Désinstaller Verbe…
  (ou Réglages › Désinstaller). Cela efface l'historique, les mots, les réglages,
  le journal et la clé du Trousseau, puis place l'app à la corbeille (et une
  éventuelle ancienne Dictee.app, après confirmation).
  Sinon, glisse simplement Verbe.app à la corbeille.
LISEZMOI

echo "==> Vérification de la signature de l'app"
codesign --verify --strict "$CONTENU/Verbe.app"

echo "==> Image disque"
hdiutil create -volname "Verbe" -srcfolder "$CONTENU" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
rm -rf "$CONTENU"

echo "==> Prête : $DMG ($(du -h "$DMG" | cut -f1))"
echo "    SHA-256 : $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
