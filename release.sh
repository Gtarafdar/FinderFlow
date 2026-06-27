#!/bin/bash
#
# release.sh — Build a Universal (Apple Silicon + Intel) Release of FinderFlow
# and package it into a distributable .dmg for GitHub Releases.
#
# Usage:  ./release.sh
#
# Output: build/FinderFlow-<version>.dmg
#
# NOTE: The app is ad-hoc signed and NOT notarized (no paid Apple Developer
# account). Downloaders must do a one-time Gatekeeper bypass — the steps are
# baked into the DMG as "READ ME FIRST.txt".

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="FinderFlow"
SCHEME="FinderFlow"
CONFIG="Release"
PROJECT="FinderFlow.xcodeproj"

DD="build/dd-release"          # derived data
PRODUCTS="$DD/Build/Products/$CONFIG"
OUT="build"                    # final artifacts land here
STAGE="build/dmg-stage"        # what gets imaged into the DMG

echo "==> Cleaning previous release artifacts"
rm -rf "$DD" "$STAGE"
mkdir -p "$OUT"

echo "==> Building Universal Release (arm64 + x86_64)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DD" \
    -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean build \
    | grep -E "error:|warning: .*deprecat|BUILD (SUCCEEDED|FAILED)" || true

APP="$PRODUCTS/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "ERROR: build did not produce $APP" >&2
    exit 1
fi

echo "==> Verifying Universal binary"
ARCHS_FOUND=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
echo "    Main app:  $ARCHS_FOUND"
if [[ "$ARCHS_FOUND" != *"arm64"* || "$ARCHS_FOUND" != *"x86_64"* ]]; then
    echo "ERROR: app is not Universal (got: $ARCHS_FOUND)" >&2
    exit 1
fi
EXT="$APP/Contents/PlugIns/FinderFlowExtension.appex/Contents/MacOS/FinderFlowExtension"
[ -f "$EXT" ] && echo "    Extension: $(lipo -archs "$EXT")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "==> Version $VERSION"

DMG="$OUT/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

echo "==> Staging DMG contents"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
FinderFlow — Installation
=========================

1. Drag FinderFlow.app onto the Applications folder (in this window).

2. FIRST LAUNCH (required once):
   Because FinderFlow is a free, open-source app that is not signed with a
   paid Apple Developer certificate, macOS Gatekeeper blocks it the first time.
   This is expected and only needs to be done once.

   EASIEST WAY:
     • Try to open FinderFlow once (it will be blocked).
     • Go to  System Settings → Privacy & Security
     • Scroll down — you'll see "FinderFlow was blocked".
     • Click  "Open Anyway",  then open FinderFlow again and confirm.

   OR, the one-line Terminal way:
     xattr -dr com.apple.quarantine /Applications/FinderFlow.app
   then open FinderFlow normally.

3. PERMISSION PROMPTS (normal — just click Allow):
   The first time you use FinderFlow, macOS may ask for a few permissions.
   These are standard for any file manager and are NOT extra installs:
     • "Access files in your Desktop/Documents/Downloads folder"  -> Allow
     • "FinderFlow wants to control Finder"   (used by Get Info)  -> OK
     • "FinderFlow wants to control Terminal" (Open in Terminal)  -> OK
   If you deny a folder prompt by mistake, re-enable it in:
     System Settings -> Privacy & Security -> Files and Folders.

4. (Optional) Enable the Finder integration ("Open in FinderFlow", etc.):
     System Settings → General → Login Items & Extensions
       → Extensions → Added Extensions (or Finder)  → enable FinderFlow.

Nothing else to install — FinderFlow is self-contained (the editor and all
tools are bundled; archive zip/unzip use macOS's built-in tools).

Requirements: macOS 14 (Sonoma) or newer. Apple Silicon AND Intel supported.

Enjoy! — https://github.com/  (your repo here)
EOF

echo "==> Creating compressed DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "==> Done"
echo "    DMG:    $DMG"
echo "    Size:   $(du -h "$DMG" | cut -f1)"
echo "    SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo ""
echo "Upload $DMG to your GitHub Release."
