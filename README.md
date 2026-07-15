# ⌨ klonk

**Desktop ambiance for macOS — mechanical keystroke sounds, ambient beds, and a looping video desktop.**

klonk is a Hammerspoon menu-bar item with one icon and three groups, each built
on the same idea — *the folder is the config*:

- **Keyboard sounds** — a sound as you type, in any voice you like.
- **Ambient sounds** — a loopable background bed (rain, surf, a bridge hum) under the typing.
- **Video desktop** — a scenic clip looping behind your desktop icons (your own, or Apple's Aerials).

Together they're one control surface for **curating your entire workspace
experience** — what you hear as you type, the soundscape underneath it, and what
moves behind your icons — from a single menu-bar icon, all remembered across
restarts. Every pillar follows the same rule, *the folder is the config*: add a
WAV set, a loopable bed, or a video clip and it just shows up in the menu. Nothing
to configure, no accounts, no daemon — set the mood and get back to work.

klonk plays a sound as you type, anywhere in macOS. A *sound set* is just a folder
of WAVs, so the built-in synthesized and recorded sets—and anything you drop in—play
the same way. Each set gives Return its own flourish through `enter.wav`.

**Mouse clicks and scrolling ring too.** A click is mechanically just a
down-then-up, so every set voices the mouse for free from its `down`/`up` pool —
no new files needed. Trackpad scroll and the wheel tick as you scroll (throttled,
and silent during inertial coasting). A **Mouse clicks** menu toggle turns it
on/off independently of the keyboard. macOS reports a trackpad tap and a physical
mouse click identically, so both are covered by the same click sound; a set can
ship dedicated `click` / `clickup` / `rightclick` / `scroll` WAVs to give the
mouse its own voice.

▶️ **[Try it in your browser](https://giantravens.github.io/klonk/previews/gallery.html)** —
pick a set and type; it runs the same logic client-side, no install.

---

## Video desktop

The **Video desktop** submenu loops a scenic clip *behind* your desktop icons —
the desktop-window trick every live-wallpaper app uses, but with no extra app and
no login item. klonk renders the clip in an `hs.webview` pinned one level below the
icon layer (in front of the wallpaper, behind your icons), muted and looped, one
view per screen, and re-renders when your display layout changes.

Everything lives in `~/Movies/Klonk/Wallpapers`, and the picker scans it for
`.mp4` / `.mov` / `.m4v` — whether each entry is a file you dropped or a symlink.

**Drop your own clips.** Any H.264/HEVC clip appears as a pick. WebKit can't decode
ProRes / Animation / Sorenson, so transcode those first:

```sh
ffmpeg -i in.mov -c:v libx264 -pix_fmt yuv420p -movflags +faststart -an out.mp4
```

**Or use Apple's Aerials, zero-copy.** *Sync Apple aerials now* symlinks every
Aerial macOS has downloaded straight into the folder by its real name — symlinks,
not 250 MB copies, so they cost nothing and always reflect what Apple currently
ships. It scans **both** places macOS keeps them:

- the **screensaver** store (System Settings ▸ Screen Saver), and
- the per-user **wallpaper** store (System Settings ▸ Wallpaper).

> ⚠️ **Aerials only download when you *activate* one.** Scrolling past an aerial in
> the gallery downloads nothing — click to set it as your screensaver or wallpaper
> and macOS fetches the clip into one of the stores above. Then run *Sync Apple
> aerials now* and it appears in your picker. Names come from Apple's own catalogs;
> a brand-new aerial not yet catalogued shows as its raw UUID (it still plays).

**Slow motion.** The **Speed** submenu — Normal / 0.5× / 0.25× / 0.1× — sets the
clip's `playbackRate`. Apple's Aerials are high-bitrate cinematic drone footage, so
0.25× drifts by dreamily instead of stuttering. Speed changes apply *live* to the
running wallpaper (no restart) and are remembered.

**Battery-aware.** *Pause on battery* stops playback on battery power and resumes on
AC. Your pick, speed, and this toggle all persist and restore at login — klonk
launches with Hammerspoon, so there's no separate startup item.

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

Reload Hammerspoon. A keyboard icon appears in the menu bar; clicking it opens the
three groups — **Keyboard sounds**, **Ambient sounds**, and **Video desktop** —
each remembering your choice across restarts.

macOS will ask to grant Hammerspoon **Accessibility** permission (needed to hear
keystrokes); klonk only *listens* — it never intercepts or alters your typing.

---

## The built-in sets

Nine sets are synthesized from scratch by `tools/generate.py`; Telegraph is
curated from recorded sounder actions:

| Family | Sets | Character |
|---|---|---|
| Percussive | `thock` `crystal` `typewriter` | deep contact, glass/crystal tings, and Selectric character |
| Mechanical | `telegraph` `console` | recorded sounder actions and chunky old-school console beeps/bops |
| Tonal | `trek` | pitched glides — LCARS-style blips |
| Musical | `vibraphone` `kalimba` `harpsichord` `jazzy` | notes from a **minor-pentatonic** scale, so random keypresses improvise a melody |

## Add your own sets

Drop a folder of WAVs into `~/Music/Klonk/Sounds/<name>/` (the menu's **Add sound
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
python3 tools/make_set.py ~/sounds/paper calligraph    # -> ~/Music/Klonk/Sounds/calligraph
python3 tools/make_set.py ~/trek lcars --enter "Working.m4a" --space "Door Chime.aif"
```

It **prints a manifest first** — every input's duration and attack, then which
source landed on which role — so you see its decisions before trusting the audio.
`--enter FILE` / `--space FILE` pin a semantic sound to a key (and keep it out of
the random keystroke pool, so a door chime doesn't fire on every letter). Short
samples become keys and clicks; the fullest becomes space/enter. Needs `ffmpeg`.
Output lands in your personal dir, never the repo.

## Build a set from ONE recording

Don't have pre-cut samples? Capture one continuous recording and let
`tools/slice_recording.py` find the hits: it runs transient detection over the
whole file, prints a manifest of every detected hit (time, duration, peak,
attack), slices them into one-shots, and hands them to `make_set.py`:

```sh
python3 tools/slice_recording.py recording.m4a myset --dry-run   # look first
python3 tools/slice_recording.py recording.m4a myset --bell      # then build
```

The natural capture tool on macOS is [Piezo](https://rogueamoeba.com/piezo/)
(or any app-audio recorder): set its **source to the app making the sound** —
QuickTime's audio recording only captures microphones, i.e. your speakers
re-recorded through the room. Tap objects near a real mic, or play a video, a
game, a synth page in the browser; ~10–30 distinct hits with a beat of quiet
between them make the best material. Tune `--thresh` (onset sensitivity) and
`--gap-ms` (quiet time separating two hits) against the `--dry-run` manifest
until the hit count matches what you heard; `--keep-slices DIR` saves the raw
one-shots for hand-curation. Needs `ffmpeg`.

## The studio — see and organize your sound world

`tools/studio.py` serves a local page that makes the whole setup visible: a
keyboard where every key shows which sound it plays, a mouse cluster, and a
library of all your sets and ambient beds:

```sh
python3 tools/studio.py          # then open http://127.0.0.1:8801
```

- **Click any key** (or just type in the test bar) to audition it; the detail
  panel shows the exact files behind that role — length, attack, ring time,
  and how many voices the engine will bank for it.
- **Dashed keys are fallbacks**: a set with no `click1.wav` shows the mouse
  borrowing the `down` pool, so the engine's fallback chains are visible
  instead of implicit.
- **Every set gets a chunky ↔ flowy meter**, measured from the audio itself:
  ring time (how long the tail stays audible) plus attack sharpness. Real
  recorded keyboards read chunky; the pentatonic musical sets read flowy.
- **Live apply**: with the Hammerspoon CLI installed (`hs.ipc.cliInstall()`
  once in the HS console), "apply to Mac" switches the running engine to the
  set or bed you're previewing — the studio header shows what's live.

The studio is a *view* over the same folders the Spoon plays — it keeps no
state of its own, needs no dependencies (Python stdlib only), and binds to
localhost.

### Environments — remix sounds across sets

The studio can also **edit**: click any key, drag its volume, or hit
"swap sound…" to assign that role a sound from *any* set in your inventory —
crystal's Return ding on a browns keyboard, console's scroll ticks, the
telegraph clack for right-click. Everything previews live in the page (nothing
is written while you experiment), and saving compiles the remix into a plain
set folder in `~/Music/Klonk/Sounds/<name>/`:

- **Per-sound volume is baked, not configured** — a gain of 60% rewrites the
  WAV's samples at compile time, so the engine plays a quieter file with zero
  new code paths.
- The recipe is saved alongside as `environment.json`, so an environment stays
  editable (reopen it in the studio, tweak, re-save) and self-describing.
- An environment can carry its **ambient bed** and a pinned `voices` count;
  "save + apply" switches the whole mood — keys and bed together.
- To the engine an environment is just another set (it appears in the menu
  under **Environments**); deleting one from the studio never touches the
  source sets it borrowed from.

## Ambient beds

klonk can also play a **looping background soundscape** under your typing — pick
one from the menu-bar **Ambient sounds** submenu (with its own bed volume). Three CC0
beds ship synthesized: `rain`, `wind`, `surf`. Drop your own long, loopable audio
into `~/Music/Klonk/Ambience/<name>.m4a` (waves, a thunderstorm, a starship bridge hum)
and it joins the list. Beds are independent of the keystroke switch and resume
across restarts.

## Real recorded keyboards

`tools/import_pack.py` pulls real recorded switch packs from
[Mechvibes](https://github.com/hainguyents13/mechvibes) (MIT) and slices them
into Klonk sets in `~/Music/Klonk/Sounds/` — it also downloads a CC0 typewriter bell
and can optionally bake it into a set's Return:

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
- **Return is per-set.** Each set's Return sound lives in its own `enter.wav`:
  Console uses a drum-pad action without a ding, Telegraph uses a recorded
  physical action, and musical sets can run a glissando — no universal overlay.
- **Mechanical vs. digital.** The recorded `telegraph` and synthesized `console`
  sets use distinct source material while sharing a tactile workstation role.
  Console's generator uses a broadband
  impact + a low body tone that *sags in pitch* as it decays + soft saturation —
  the three things clean sine partials can't fake.
- **Voices layer, adaptively.** A single `hs.sound` is monophonic — retriggering
  it cuts its own tail — so each sound is loaded as a *bank* of copies the engine
  round-robins through, letting fast keystrokes ring out and overlap into a wash.
  The bank size is sized to each sound's own length (≈one voice per 0.1s, capped
  at `Klonk.voices`, default 6): a short recorded-keyboard clack resolves to a
  single crisp voice, while a long sample (calligraph, splash, kalimba, the LCARS
  console) fans out and layers. Drop a `voices` file (one integer) in a set folder
  to pin it — `import_pack.py` writes `1` so real keyboards stay crisp.
- **Mouse for free.** The same `eventtap` also taps left/right mouse and scroll.
  A click plays through a `click`→`down` fallback chain and a scroll through
  `scroll`→`up`, so every existing set voices the mouse with no new files. Scroll
  is throttled and ignores the inertial *momentum* phase, so a flung trackpad
  swipe ticks gently instead of roaring.
- **The video desktop is a browser, not a player.** The wallpaper is a muted,
  looping `<video>` inside an `hs.webview` pinned below the desktop-icon layer — so
  slow motion is one HTML property (`playbackRate`) with no re-encoding, and a
  local clip plays by *relative* name from a wrapper page written into the same
  folder. That relative-name trick is also why a symlink to a root-owned Apple
  Aerial under `/Library` plays: WebKit resolves it within the folder it was
  granted. Aerials are linked, never copied, and the sync reads Apple's own JSON
  catalogs (both stores') for their names.

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
