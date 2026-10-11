#!/bin/bash
# ci/macos-test.sh — Klonk smoke test. The contract the maclab runner calls.
#
# Two tiers:
#   Tier 1 (headless, GitHub-Actions-safe): structure, sound-set inventory,
#           the dependency-free presenter unit test.
#   Tier 2 (needs the GUI Hammerspoon; VM only): follow the DOCUMENTED install
#           steps, then exercise real features via the running Hammerspoon.
#
# Exit non-zero if any check FAILs. UNVERIFIABLE is reported distinctly and does
# NOT fail the run (brief: unverifiable != passed, but != failed either).
set -uo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
ART="/tmp/maclab-artifacts"; mkdir -p "$ART"
GUI_UID="$(stat -f%u /dev/console 2>/dev/null || echo 501)"
fails=0; unverified=0

hr(){ echo "------------------------------------------------------------"; }
pass(){ echo "PASS  $*"; }
fail(){ echo "FAIL  $*"; fails=$((fails+1)); }
unv(){  echo "UNV   $*"; unverified=$((unverified+1)); }

echo "== Klonk macOS smoke test =="
sw_vers 2>/dev/null | tr '\n' ' '; echo

# ---------- Tier 1: headless structure + inventory ----------
hr; echo "Tier 1 — headless checks"
[ -f Klonk.spoon/init.lua ] && pass "Spoon present: Klonk.spoon/init.lua" || fail "Klonk.spoon/init.lua missing"

VER="$(sed -n 's/^obj.version *= *"\(.*\)"/\1/p' Klonk.spoon/init.lua | head -1)"
[ -n "$VER" ] && pass "Spoon metadata version=$VER" || fail "no version in init.lua"

nsets=$(find Klonk.spoon/sounds -maxdepth 1 -type d -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
[ "$nsets" -gt 0 ] && pass "keyboard sound sets: $nsets" || fail "no sound sets found"

namb=$(find Klonk.spoon/ambient -maxdepth 1 -type f \( -name '*.mp3' -o -name '*.wav' \) 2>/dev/null | wc -l | tr -d ' ')
[ "$namb" -gt 0 ] && pass "ambient sounds: $namb" || fail "no ambient sounds found"

# presenter unit test (dependency-free; needs a standalone lua interpreter)
if command -v lua >/dev/null 2>&1; then
  if out=$(lua tests/presenter_test.lua 2>&1) && echo "$out" | grep -q "passed"; then
    pass "presenter unit test: $(echo "$out" | tail -1)"
  else
    fail "presenter unit test: $(echo "$out" | tail -1)"
  fi
else
  unv "presenter unit test skipped (no standalone 'lua'; install via brew for CI)"
fi

# ---------- Tier 2: live Hammerspoon feature manifest ----------
# Mechanism: wire the manifest into init.lua and restart the Hammerspoon APP in
# the GUI session (NOT a VM reboot — SSH survives). HS runs init.lua on load,
# which runs the manifest, which writes the result file we poll. This avoids the
# `hs -c` IPC entirely (unreliable over asuser/SSH — drops into legacy mode).
hr; echo "Tier 2 — live Hammerspoon features"
have_gui=0
if [ -e /dev/console ] && [ -d /Applications/Hammerspoon.app ] && who | grep -q console; then
  have_gui=1
fi

if [ "$have_gui" -ne 1 ]; then
  unv "no GUI/Aqua session with Hammerspoon — Tier 2 skipped (expected in GitHub Actions)"
else
  HSHOME="$(dscl . -read /Users/#$GUI_UID NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  HSHOME="${HSHOME:-/Users/admin}"
  HSDIR="$HSHOME/.hammerspoon"
  mkdir -p "$HSDIR/Spoons"

  # DOCUMENTED INSTALL STEP: copy the Spoon into ~/.hammerspoon/Spoons/
  rm -rf "$HSDIR/Spoons/Klonk.spoon"
  cp -R "$REPO_ROOT/Klonk.spoon" "$HSDIR/Spoons/Klonk.spoon"
  pass "installed Spoon to ~/.hammerspoon/Spoons/ (documented step)"

  # start() scans the video-desktop folder; create it so start() completes
  mkdir -p "$HSHOME/Music/Klonk/livedesktop"

  # wire the manifest to run on next HS config load
  cp "$REPO_ROOT/ci/hs-featuretest.lua" "$HSDIR/klonk-featuretest.lua"
  LOADER='dofile(os.getenv("HOME").."/.hammerspoon/klonk-featuretest.lua") -- MACLAB-TEST'
  grep -q 'MACLAB-TEST' "$HSDIR/init.lua" 2>/dev/null || echo "$LOADER" >> "$HSDIR/init.lua"
  rm -f "$ART/klonk-result.txt"

  # restart the Hammerspoon app in the GUI session -> reloads config -> runs manifest
  sudo pkill -x Hammerspoon 2>/dev/null; sleep 2
  sudo launchctl asuser "$GUI_UID" open -a Hammerspoon
  # manifest appends incrementally, ending with a DONE line; poll up to 40s
  for _ in $(seq 1 40); do grep -q '^CHECK DONE' "$ART/klonk-result.txt" 2>/dev/null && break; sleep 1; done

  if [ -f "$ART/klonk-result.txt" ]; then
    while IFS= read -r ln; do
      name=$(awk '{print $2}' <<<"$ln"); st=$(awk '{print $3}' <<<"$ln"); rest=${ln#*"$st"}
      case "$st" in
        PASS) pass "$name —$rest" ;;
        FAIL) fail "$name —$rest" ;;
        UNVERIFIABLE) unv "$name —$rest" ;;
      esac
    done < "$ART/klonk-result.txt"
  else
    fail "feature manifest produced no result file (HS did not run it)"
  fi

  # cleanup: remove the test loader so the image stays clean
  grep -v 'MACLAB-TEST' "$HSDIR/init.lua" > "$HSDIR/init.lua.tmp" 2>/dev/null && mv "$HSDIR/init.lua.tmp" "$HSDIR/init.lua"
  rm -f "$HSDIR/klonk-featuretest.lua"
fi

# ---------- summary ----------
hr
echo "SUMMARY: fails=$fails unverifiable=$unverified"
[ -d "$ART" ] && echo "artifacts in $ART:" && ls -1 "$ART" 2>/dev/null | sed 's/^/  /'
exit $(( fails > 0 ? 1 : 0 ))
