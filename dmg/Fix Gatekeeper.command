#!/bin/bash
# FinderFlow — one-time Gatekeeper helper (unsigned free build).
# Only clears quarantine on /Applications/FinderFlow.app — no network, no sudo.
set -e
APP="/Applications/FinderFlow.app"
if [ ! -d "$APP" ]; then
  osascript -e 'display alert "FinderFlow not found" message "Drag FinderFlow into Applications first, then run this helper again." as critical'
  exit 1
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
osascript -e 'display notification "FinderFlow is ready to open." with title "FinderFlow"'
