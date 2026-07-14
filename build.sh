#!/bin/bash
# Build WhisperKey.app and install it into /Applications.
# The bundle is assembled in a temp dir so no duplicate .app copies linger
# on disk (duplicates confuse Spotlight and the Privacy & Security app lists).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

TMP=$(mktemp -d)
APP="$TMP/WhisperKey.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WhisperKey "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Sign with a stable identity when one exists. Ad-hoc signatures get a new
# CDHash every build, which resets the Accessibility (TCC) grant and silently
# kills event posting — so a real identity is strongly preferred.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) [A-F0-9]* "\(.*\)"$/\1/p' | head -1)
if [ -n "$IDENTITY" ]; then
    echo "Signing with: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "WARNING: no code-signing identity found — using ad-hoc signing."
    echo "         You will need to re-grant Accessibility after EVERY rebuild."
    echo "         Fix: create a free Apple Development certificate in Xcode."
    codesign --force --deep --sign - "$APP"
fi

rm -rf /Applications/WhisperKey.app
cp -R "$APP" /Applications/
rm -rf "$TMP"
echo "Installed /Applications/WhisperKey.app"
