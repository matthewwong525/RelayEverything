#!/usr/bin/env bash
# Makes the Mac disk image: make-dmg.sh <app> <dmg>. It opens as the Relay Everything install window that
# settings.py lays out, on background.png and its @2x (from brand/make-icons.mjs). Needs dmgbuild on a Mac.
set -euo pipefail
if [ $# -ne 2 ]; then
  echo "usage: make-dmg.sh <app> <dmg>" >&2
  exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
app=$1
dmg=$2
[ -d "$app" ] || { echo "no app at $app" >&2; exit 1; }
[ -f "$app/Contents/Resources/AppIcon.icns" ] || { echo "no AppIcon.icns in $app: the disk would show a plain icon" >&2; exit 1; }
rm -f "$dmg"
dmgbuild -s "$here/settings.py" -D app="$app" -D background="$here/background.png" "Relay Everything" "$dmg"
