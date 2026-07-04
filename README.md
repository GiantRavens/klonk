# ⌨ klonk

**Mechanical keystroke sounds for macOS — in any voice you like.**

klonk plays a sound as you type, anywhere in macOS, from a Hammerspoon menu-bar
item. A *sound set* is just a folder of WAVs, so the eleven built-in synthesized
sets, real recorded keyboards, and anything you drop in all play the same way.
Every set rings a Return "ding" baked into its own `enter.wav`.

▶️ **[Try it in your browser](previews/gallery.html)** — pick a set and type; it runs
the same logic client-side, no install.

---

## Install

klonk is a [Hammerspoon](https://www.hammerspoon.org) Spoon.

```sh
git clone https://github.com/skiplevens/klonk.git
cp -r klonk/Klonk.spoon ~/.hammerspoon/Spoons/
```

Then in `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("Klonk")
spoon.Klonk:start()

-- optional hotkeys
spoon.Klonk:bindHotkeys({
  toggle  = {{"cmd", "alt"}, "k"},   -- mute/unmute
  nextSet = {{"cmd", "alt"}, "]"},   -- next set
  prevSet = {{"cmd", "alt"}, "["},   -- previous set
})
```

Reload Hammerspoon. A keyboard icon appears in the menu bar — click it to toggle
sound, pick a set, or set the volume. Your choice persists across restarts.

macOS will ask to grant Hammerspoon **Accessibility** permission (needed to hear
keystrokes); klonk only *listens* — it never intercepts or alters your typing.

---

## The built-in sets

All eleven are synthesized from scratch (no samples) by `tools/generate.py`:

| Family | Sets | Character |
|---|---|---|
| Percussive | `thock` `clicky` `typewriter` | noise-burst contact + resonant body |
| Mechanical | `telegraph` `manual` | impact + pitch-sagging thump + saturation — reads as *physical* |
| Tonal | `trek` `water` | pitched glides — LCARS blips, water drips |
| Musical | `vibraphone` `kalimba` `harpsichord` `jazzy` | notes from a **minor-pentatonic** scale, so random keypresses improvise a melody |

## Add your own sets

Drop a folder of WAVs into `~/.klonk/sounds/<name>/` (the menu's **Add sound
sets…** opens it). The naming convention:

```
down1.wav … downN.wav    generic key-down (a random one plays per key)
up1.wav   … upN.wav       key-up / release
space.wav  enter.wav  backspace.wav    dedicated keys
```

Any subset works — klonk plays whatever's present. `enter.wav` is your Return
ding, so give it some ring.

## Real recorded keyboards

`tools/import_pack.py` pulls real recorded switch packs from
[Mechvibes](https://github.com/hainguyents13/mechvibes) (MIT) and slices them
into klonk sets in `~/.klonk/sounds/` — it also downloads a CC0 typewriter bell
and bakes it into each set's Return:

```sh
python3 tools/import_pack.py cherrymx-blue-pbt  blues
python3 tools/import_pack.py cherrymx-brown-pbt browns
python3 tools/import_pack.py holy-pandas        pandas
```

It handles both Mechvibes formats (single-file sprites and per-key "multi"
packs). Requires `ffmpeg` (`brew install ffmpeg`). Imported audio lands in your
personal dir, never in this repo.

## Tune the synthesized sets

Every timbre is a few numbers in `tools/generate.py` — partials, decay, the
pentatonic scale, the mechanical impact model. Edit and regenerate:

```sh
python3 tools/generate.py Klonk.spoon/sounds   # rewrite the bundled sets
python3 tools/build_gallery.py                 # rebuild the browser demo
```

---

## How it works

- **A set is a folder of WAVs.** The engine never learns what "Cherry MX Blue"
  or "vibraphone" *is* — synthesis and real recordings land in the same
  `down1.wav` / `space.wav` convention and play identically. The contract is the
  filesystem, not the code, which is why adding real samples took zero engine
  changes.
- **Zero idle cost.** A set is preloaded into `hs.sound` objects when selected,
  so a keystroke is a table lookup + play with no disk I/O. The `eventtap` is
  observe-only (`return false`) — it hears keys, never swallows them.
- **The ding is per-set.** Each set's Return sound lives in its own `enter.wav`,
  so a telegraph rings an office bell, a manual rings a carriage bell, and the
  musical sets run a glissando — no universal overlay.
- **Mechanical vs. digital.** The `telegraph`/`manual` sets use a broadband
  impact + a low body tone that *sags in pitch* as it decays + soft saturation —
  the three things clean sine partials can't fake.

## License & credits

- **Code** (`Klonk.spoon/init.lua`, `tools/`): MIT — see [LICENSE](LICENSE).
- **Bundled sounds** (`Klonk.spoon/sounds/`): synthesized originals, released
  **CC0** (public domain) — use them anywhere.
- **`import_pack.py`** downloads, into *your* machine, third-party audio you
  should credit yourself: Mechvibes packs (MIT,
  [hainguyents13/mechvibes](https://github.com/hainguyents13/mechvibes)) and a
  CC0 typewriter bell (Hermes Precisa 305, recorded by Joseph SARDIN,
  [bigsoundbank.com](https://bigsoundbank.com)).

Built with [Hammerspoon](https://www.hammerspoon.org).
