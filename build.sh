#!/bin/zsh
# Fabrique Verbe.app : compile, assemble, signe, installe dans ~/Applications.
#   ./build.sh                     compile + assemble + signe + installe dans ~/Applications
#   ./build.sh --sans-installer    s'arrête après l'assemblage (dans .build/Verbe.app)
#   ./build.sh --sortie DOSSIER    assemble dans DOSSIER/Verbe.app, sans rien installer (utilisé par release.sh)
# Nom : l'app s'appelle Verbe (paquet Verbe.app, exécutable Verbe). Le produit Swift et les dossiers internes gardent
# le nom Dictee, et l'identifiant reste com.hugues.dictee : les autorisations, l'historique et le dictionnaire sont conservés.
# La version vient du fichier VERSION, seul endroit où elle s'écrit.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION illisible : « $VERSION »"; exit 1; }
NOM_APP="Verbe"
PRODUIT_SWIFT="Dictee"   # nom interne du produit SwiftPM (voir Package.swift)
BUNDLE_ID="com.hugues.dictee"
DEST="$HOME/Applications/$NOM_APP.app"
ASSEMBLAGE=".build/$NOM_APP.app"
SANS_INSTALLER=0
case "${1:-}" in
  --sans-installer) SANS_INSTALLER=1 ;;
  --sortie) [[ -n "${2:-}" ]] || { echo "--sortie demande un dossier"; exit 2; }
            ASSEMBLAGE="$2/$NOM_APP.app"; SANS_INSTALLER=1 ;;
  "") ;;
  *) echo "Option inconnue : $1"; exit 2 ;;
esac

echo "==> Compilation (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$PRODUIT_SWIFT"
[[ -x "$BIN" ]] || { echo "Exécutable introuvable : $BIN"; exit 1; }

echo "==> Assemblage de $NOM_APP.app"
rm -rf "$ASSEMBLAGE"
mkdir -p "$ASSEMBLAGE/Contents/MacOS" "$ASSEMBLAGE/Contents/Resources"
cp "$BIN" "$ASSEMBLAGE/Contents/MacOS/$NOM_APP"

# Police du texte dicté (Newsreader, licence OFL) et sa licence
cp Resources/Polices/Newsreader.ttf Resources/Polices/OFL.txt "$ASSEMBLAGE/Contents/Resources/"

# Icône d'app : dessinée en vectoriel par l'app elle-même (--rendu-icones : PNG seulement, ni micro ni clavier), puis iconutil.
echo "==> Icône (AppIcon.icns)"
rm -rf .build/icones
"$BIN" --rendu-icones .build/icones >/dev/null
iconutil -c icns .build/icones/AppIcon.iconset -o "$ASSEMBLAGE/Contents/Resources/AppIcon.icns"

cat > "$ASSEMBLAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>CFBundleExecutable</key><string>$NOM_APP</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>$NOM_APP</string>
  <key>CFBundleDisplayName</key><string>$NOM_APP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Verbe écoute ta voix quand tu tiens la touche fn pour dicter, et pendant que tu notes une réunion.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Verbe écoute le son de ton Mac (la voix des autres pendant un appel) seulement quand tu notes une réunion.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Verbe utilise la reconnaissance vocale du Mac, sur l'appareil, pour afficher ton texte en direct et en secours.</string>
</dict>
</plist>
PLIST

echo "==> Signature"
# Un certificat auto-signé n'est utilisable par codesign qu'après une approbation manuelle dans une fenêtre du
# système (pas faisable sans écran). On signe donc "ad hoc" MAIS avec une exigence désignée fixe (l'identifiant
# de l'app) : elle ne change pas d'une construction à l'autre, donc macOS garde micro / accessibilité accordés.
codesign --force --sign - --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" "$ASSEMBLAGE"
codesign --verify --strict "$ASSEMBLAGE"

if [[ "$SANS_INSTALLER" == 1 ]]; then
  echo "==> Assemblée dans $ASSEMBLAGE"
  exit 0
fi

echo "==> Installation dans $DEST"
mkdir -p "$HOME/Applications"
# Si l'app tourne, on la ferme proprement avant de remplacer le dossier (elle sera relancée à la main).
if pgrep -x "$NOM_APP" >/dev/null 2>&1 || pgrep -x "$PRODUIT_SWIFT" >/dev/null 2>&1; then
  echo "    $NOM_APP tourne : fermeture avant remplacement"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || pkill -x "$NOM_APP" || pkill -x "$PRODUIT_SWIFT" || true
  sleep 1
fi
rm -rf "$DEST"
cp -R "$ASSEMBLAGE" "$DEST"
codesign --verify --strict "$DEST"
echo "==> Prête : $DEST"
for ancienne in "$HOME/Applications/Dictee.app" "/Applications/Dictee.app"; do
  [[ -d "$ancienne" ]] && echo "    Ancienne app trouvée (nom d'avant Verbe) : $ancienne — à jeter une fois Verbe essayée (elle a le même identifiant)."
done
echo "    Lancer : open \"$DEST\""
