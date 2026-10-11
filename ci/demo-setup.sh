#!/bin/bash
# ci/demo-setup.sh — set up klonk for a LIVE HUMAN DEMO inside the VM and leave
# it running. Called by `lab demo klonk`. Installs per the documented steps,
# starts klonk so the menu-bar icon is live and keystrokes make sound, and drops
# a short motion clip into the video-desktop folder so the moving wallpaper has
# something to play. Then it leaves everything running for you to review.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
GUI_UID="$(stat -f%u /dev/console 2>/dev/null || echo 501)"
HSHOME="$(dscl . -read /Users/admin NFSHomeDirectory 2>/dev/null | awk '{print $2}')"; HSHOME="${HSHOME:-/Users/admin}"
HSDIR="$HSHOME/.hammerspoon"

echo "installing Klonk.spoon (documented: cp -r Klonk.spoon ~/.hammerspoon/Spoons/)"
mkdir -p "$HSDIR/Spoons" "$HSHOME/Music/Klonk/livedesktop"
rm -rf "$HSDIR/Spoons/Klonk.spoon"
cp -R "$REPO_ROOT/Klonk.spoon" "$HSDIR/Spoons/Klonk.spoon"

echo "creating a short motion clip for the video desktop"
# record 4s of the current screen as a demo clip with guaranteed motion
sudo launchctl asuser "$GUI_UID" /usr/sbin/screencapture -v -V 4 "$HSHOME/Music/Klonk/livedesktop/demo-motion.mov" >/dev/null 2>&1 &

echo "wiring init.lua to load + start klonk (documented steps)"
cat > "$HSDIR/init.lua" <<'LUA'
require("hs.ipc"); hs.ipc.cliInstall()
hs.loadSpoon("Klonk")
spoon.Klonk:start()
spoon.Klonk:bindHotkeys({
  toggle          = {{"cmd","alt"}, "k"},
  togglePresenter = {{"cmd","alt"}, "p"},
  nextSet         = {{"cmd","alt"}, "]"},
  prevSet         = {{"cmd","alt"}, "["},
})
LUA

echo "restarting Hammerspoon so it loads the config"
sudo pkill -x Hammerspoon 2>/dev/null; sleep 2
sudo launchctl asuser "$GUI_UID" open -a Hammerspoon
sleep 5
echo "Hammerspoon running: $(pgrep -x Hammerspoon >/dev/null && echo yes || echo NO)"

cat <<'EOTXT'

  ----------------------------------------------------------------
  klonk is installed and RUNNING in this VM. To verify by hand:
   • TYPE anywhere in the VM  -> you should HEAR keyboard sounds
     (audio routes to your Mac's speakers).
   • Click the keyboard icon in the VM menu bar -> Keyboard sounds
     -> pick a different set and type again.
   • Menu -> Video desktop -> "demo-motion" to see the moving
     wallpaper behind the icons.
   • Menu -> Ambient sounds -> pick one for a soundscape.
   • Cmd-Alt-P toggles Presenter mode (shows keys / click rings).
  ----------------------------------------------------------------
EOTXT
