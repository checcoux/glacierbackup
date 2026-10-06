#!/bin/bash
# Compila l'app (universale: Apple Silicon + Intel) e crea build/Glacier Backup.app e build/GlacierBackup.zip
#
# Fuori dal branch main produce "Glacier Backup Beta": un'app distinta, con impostazioni e
# credenziali proprie, che può convivere con quella rilasciata.
#
# Per distribuirla ad altri:
#   SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" NOTARY_PROFILE=nome-profilo ./build.sh
# dove nome-profilo è stato creato una volta con `xcrun notarytool store-credentials`.
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)
IDENTITY="${SIGN_IDENTITY:--}"
NAME="Glacier Backup"
BUNDLE_ID="com.suertestudio.glacierbackup"
ZIP="build/GlacierBackup.zip"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "HEAD" ]; then
    NAME="$NAME Beta"
    BUNDLE_ID="$BUNDLE_ID.beta"
    ZIP="build/GlacierBackupBeta.zip"
fi
APP="build/$NAME.app"

swift build -c release "${ARCHS[@]}"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/GlacierBackup" "$APP/Contents/MacOS/GlacierBackup"
cp Support/Info.plist "$APP/Contents/Info.plist"
for key in CFBundleName CFBundleDisplayName; do
    /usr/libexec/PlistBuddy -c "Set :$key $NAME" "$APP/Contents/Info.plist"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"

# Icona: Support/AppIcon.png (1024x1024) convertita in .icns
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -z $size $size Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "Creati: $APP e $ZIP"
