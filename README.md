# ⌨ klonk

**Mechanical keystroke sounds for macOS — in any voice you like.**

klonk plays a sound as you type, anywhere in macOS, from a Hammerspoon menu-bar
item. A *sound set* is just a folder of WAVs, so the eleven built-in synthesized
sets, real recorded keyboards, and anything you drop in all play the same way.
Every set rings a Return "ding" baked into its own `enter.wav`.

**Mouse clicks and scrolling ring too.** A click is mechanically just a
down-then-up, so every set voices the mouse for free from its `down`/`up` pool —
no new files needed. Trackpad scroll and the wheel tick as you scroll (throttled,
and silent during inertial coasting). A **Mouse clicks** menu toggle turns it
on/off independently of the keyboard. macOS reports a trackpad tap and a physical
mouse click identically, so both are covered by the same click sound; a set can
ship dedicated `click` / `clickup` / `rightclick` / `scroll` WAVs to give the
mouse its own voice.

▶️ **[Try it in your browser](previews/gallery.html)** — pick a set and type; it runs
the same logic client-side, no install.

---

## Install

klonk is a [Hammerspoon](https://www.hammerspoon.org) Spoon.

```sh
git clone https://github.com/giantravens/klonk.git
cp -r klonk/Klonk.spoon ~/.hammerspoon/Spoons/
```

Then in `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("Klonk")
spoon.Klonk:start()

-- optional hotkeys
spoon.Klonk:bindHotkeys({
  toggle      = {{"cmd", "alt"}, "k"},   -- mute/unmute everything
  toggleMouse = {{"cmd", "alt"}, "m"},   -- mute/unmute mouse clicks + scroll
  nextSet     = {{"cmd", "alt"}, "]"},   -- next set
  prevSet     = {{"cmd", "alt"}, "["},   -- previous set
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
click1.wav … clickN.wav  mouse-down    (optional; falls back to down)
clickup.wav rightclick.wav             (optional; fall back to up / click)
scroll1.wav … scrollN.wav mouse wheel / trackpad scroll tick (optional → up)
```

Any subset works — klonk plays whatever's present. `enter.wav` is your Return
ding, so give it some ring. Omit the mouse files and a click simply reuses your
`down`/`up` sounds.

## Build a set from any samples

Got a folder of one-shot recordings — paper crinkles, ping-pong bounces, sparks,
console blips? `tools/make_set.py` slices, trims, normalizes, and maps them onto
the whole convention (keys **and** mouse voices) in one shot:

```sh
python3 tools/make_set.py ~/sounds/paper paper              # -> ~/.klonk/sounds/paper
python3 tools/make_set.py ~/trek lcars --enter "Working.m4a" --space "Door Chime.aif"
```

It **prints a manifest first** — every input's duration and attack, then which
source landed on which role — so you see its decisions before trusting the audio.
`--enter FILE` / `--space FILE` pin a semantic sound to a key (and keep it out of
the random keystroke pool, so a door chime doesn't fire on every letter). Short
samples become keys and clicks; the fullest becomes space/enter. Needs `ffmpeg`.
Output lands in your personal dir, never the repo.

## Ambient beds

klonk can also play a **looping background soundscape** under your typing — pick
one from the menu-bar **Ambient** submenu (with its own bed volume). Three CC0
beds ship synthesized: `rain`, `wind`, `surf`. Drop your own long, loopable audio
into `~/.klonk/ambient/<name>.wav` (waves, a thunderstorm, a starship bridge hum)
and it joins the list. Beds are independent of the keystroke switch and resume
across restarts.

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
- **Voices layer, adaptively.** A single `hs.sound` is monophonic — retriggering
  it cuts its own tail — so each sound is loaded as a *bank* of copies the engine
  round-robins through, letting fast keystrokes ring out and overlap into a wash.
  The bank size is sized to each sound's own length (≈one voice per 0.1s, capped
  at `Klonk.voices`, default 6): a short recorded-keyboard clack resolves to a
  single crisp voice, while a long sample (paper, splash, kalimba, the LCARS
  console) fans out and layers. Drop a `voices` file (one integer) in a set folder
  to pin it — `import_pack.py` writes `1` so real keyboards stay crisp.
- **Mouse for free.** The same `eventtap` also taps left/right mouse and scroll.
  A click plays through a `click`→`down` fallback chain and a scroll through
  `scroll`→`up`, so every existing set voices the mouse with no new files. Scroll
  is throttled and ignores the inertial *momentum* phase, so a flung trackpad
  swipe ticks gently instead of roaring.

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
