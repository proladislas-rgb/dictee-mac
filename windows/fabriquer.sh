#!/bin/zsh
# Fabrique dist/Verbe.exe (Windows 64 bits, autonome, un seul fichier) depuis un Mac ou un Linux. Il faut le SDK .NET 8.
set -e
cd "$(dirname "$0")"
DOTNET="${DOTNET:-$(command -v dotnet || echo ~/.dotnet/dotnet)}"
echo "==> Contrôles du cœur"
"$DOTNET" run --project controles -c Release
echo "==> Verbe.exe"
rm -rf dist/Verbe
"$DOTNET" publish src/Verbe/Verbe.csproj -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=none \
  -o dist/Verbe
cp LIS-MOI.txt dist/Verbe/
VERSION=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/Verbe/Verbe.csproj)
rm -f "dist/Verbe-Windows-$VERSION.zip"
(cd dist && zip -qr "Verbe-Windows-$VERSION.zip" Verbe)
ls -la dist/Verbe "dist/Verbe-Windows-$VERSION.zip"
