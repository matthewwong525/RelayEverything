#!/usr/bin/env bash
# Renders the ring models in cad/ to the PNGs the ring pages show. Run it again when a model changes.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/site/src/assets/ring"
mkdir -p "$out"
# OpenSCAD draws PNGs through OpenGL, so a computer with no screen needs a virtual one.
draw=(openscad)
[ -n "${DISPLAY:-}" ] || ! command -v xvfb-run >/dev/null || draw=(xvfb-run -a openscad)

render() {
  local name="$1" model="$2"; shift 2
  "${draw[@]}" -o "$out/$name.png" --imgsize=1200,900 --viewall --autocenter --colorscheme=Tomorrow \
    --camera=0,0,0,55,0,25,0 "$@" "$root/cad/$model" 2>/dev/null
  echo "$name.png $(( $(wc -c < "$out/$name.png") / 1024 )) KB"
}

render v1-assembly relay-v1-ring.scad -D 'part="assembly"'
render click-test relay-click-test.scad -D 'part="assembly"' -D 'button="tl3312"'
render wear-test relay-wear-test.scad
