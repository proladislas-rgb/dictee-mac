#!/bin/zsh
# Fabrique Dictee.app : compile, assemble, signe, installe dans ~/Applications.
#   ./build.sh            compile + assemble + signe + installe
#   ./build.sh --sans-installer   s'arrête après l'assemblage (dans .build/Dictee.app)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.1.0"
NOM_APP="Dictee"
BUNDLE_ID="com.hugues.dictee"
DEST="$HOME/Applications/$NOM_APP.app"
ASSEMBLAGE=".build/$NOM_APP.app"

echo "==> Compilation (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$NOM_APP"
[[ -x "$BIN" ]] || { echo "Exécutable introuvable : $BIN"; exit 1; }

echo "==> Assemblage de $NOM_APP.app"
rm -rf "$ASSEMBLAGE"
mkdir -p "$ASSEMBLAGE/Contents/MacOS" "$ASSEMBLAGE/Contents/Resources"
cp "$BIN" "$ASSEMBLAGE/Contents/MacOS/$NOM_APP"

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
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Dictée écoute ta voix seulement pendant que tu tiens la touche fn, pour écrire ce que tu dis.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Dictée utilise la reconnaissance vocale du Mac, sur l'appareil, pour afficher ton texte en direct et en secours.</string>
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

if [[ "${1:-}" == "--sans-installer" ]]; then
  echo "==> Assemblée dans $ASSEMBLAGE"
  exit 0
fi

echo "==> Installation dans $DEST"
mkdir -p "$HOME/Applications"
# Si l'app tourne, on la ferme proprement avant de remplacer le dossier (elle sera relancée à la main).
if pgrep -x "$NOM_APP" >/dev/null 2>&1; then
  echo "    $NOM_APP tourne : fermeture avant remplacement"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || pkill -x "$NOM_APP" || true
  sleep 1
fi
rm -rf "$DEST"
cp -R "$ASSEMBLAGE" "$DEST"
codesign --verify --strict "$DEST"
echo "==> Prête : $DEST"
echo "    Lancer : open \"$DEST\""
