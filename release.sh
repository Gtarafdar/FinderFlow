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
# in "Install & First Open.txt" and "Fix Gatekeeper.command" inside the DMG.

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
cp "dmg/Fix Gatekeeper.command" "$STAGE/"
chmod +x "$STAGE/Fix Gatekeeper.command"
mkdir -p "$STAGE/.background"
cp "dmg/background.png" "$STAGE/.background/background.png"

cat > "$STAGE/Install & First Open.txt" <<'EOF'
FinderFlow — Install & First Open
=================================

1. Drag FinderFlow onto the Applications folder in this window.

2. FIRST OPEN (safe, one-time):
   FinderFlow is free & open-source and is not signed with a paid Apple
   Developer certificate. macOS Gatekeeper will block it once — that is
   expected and safe.

   Sequoia / recent macOS:
     • Open FinderFlow once (it may be blocked or only offer Move to Trash).
     • Open System Settings → Privacy & Security.
     • Scroll to the message about FinderFlow and click Open Anyway.
     • Open FinderFlow again and confirm.

   Quick alternative — double-click "Fix Gatekeeper.command" in this window
   (after the app is in Applications). It only clears quarantine on
   /Applications/FinderFlow.app and then opens the app. No network, no password.

   Or in Terminal:
     xattr -dr com.apple.quarantine /Applications/FinderFlow.app

3. Folder permission prompts (normal — click Allow):
   Desktop / Documents / Downloads access, plus occasional Finder/Terminal
   control prompts for Get Info / Open in Terminal.

4. Optional Finder right-click menu:
   System Settings → General → Login Items & Extensions → Extensions → FinderFlow.

Requirements: macOS 14 Sonoma or newer · Apple Silicon & Intel.

https://github.com/Gtarafdar/FinderFlow
EOF

echo "==> Creating styled DMG (drag to Applications)"
TMP_DMG="$OUT/${APP_NAME}-tmp.dmg"
rm -f "$TMP_DMG" "$DMG"
# Writable image so we can set Finder window layout
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$TMP_DMG" >/dev/null

MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen 2>/dev/null \
    | awk -F'\t' '/\/Volumes\// {print $NF; exit}')
MOUNT_DIR=$(echo "$MOUNT_DIR" | sed 's/[[:space:]]*$//')
if [ -z "${MOUNT_DIR:-}" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "ERROR: could not mount temporary DMG" >&2
    exit 1
fi
echo "    Mounted: $MOUNT_DIR"

VOL_NAME=$(basename "$MOUNT_DIR")

# Apply Finder window layout (icon positions + background)
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 920, 620}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    try
      set background picture of theViewOptions to file ".background:background.png"
    end try
    set position of item "$APP_NAME.app" of container window to {160, 250}
    set position of item "Applications" of container window to {560, 250}
    try
      set position of item "Fix Gatekeeper.command" of container window to {360, 420}
    end try
    try
      set position of item "Install & First Open.txt" of container window to {160, 420}
    end try
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TMP_DMG"

echo "==> Done"
SHA256=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
CHECKSUM="$DMG.sha256"
# Standard `shasum -c` format: "<hash>  <basename>"
echo "$SHA256  $(basename "$DMG")" > "$CHECKSUM"
echo "    DMG:      $DMG"
echo "    Checksum: $CHECKSUM"
echo "    Size:     $(du -h "$DMG" | cut -f1)"
echo "    SHA256:   $SHA256"
echo ""
echo "Upload $DMG and $CHECKSUM to your GitHub Release."
