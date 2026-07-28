# ⌨ klonk

**Desktop ambiance for macOS based on Hammerspoon utility — mechanical keystroke sounds, ambient soundscapes,
a live video ON YOUR DESKTOP, and a presenter mode that makes keyboard and mouse clicks visible.**

klonk is a Hammerspoon menu-bar item with one icon and three groups, each covering different aspects of how you want to curate your Mac's working environment. Want cool keyboard sounds? Weird keyboard sounds? How about an ambient soundtrack of the beach, city life, or favorite sci-fi while you work. And how about we paint a moving desktop on your screen that simply taps into the existing Apple screensaver videos.

Best of all, as a Hammerspoon macOS utility its easily configurable - drop in your own keyboard sounds, videos, ambient soundloops any time.

**[Try the keyboard sounds and ambient sounds in your browser](https://giantravens.github.io/klonk/previews/gallery.html)** —
pick a set and type, then layer a soundscape underneath it; no install needed.
The test page includes the complete ten-pack Mechvibes DX mechanism collection,
the earlier Cherry MX Blue/Brown and Holy Panda recordings, and every bundled
ambient sound.

---

## Video desktop

The **Video desktop** submenu loops a scenic clip *behind* your desktop icons —
the desktop-window trick every live-wallpaper app uses, but with no extra app and
no login item. klonk renders the clip in an `hs.webview` pinned one level below the
icon layer (in front of the wallpaper, behind your icons), muted and looped, one
view per screen, and re-renders when your display layout changes.

Everything lives in `~/Music/Klonk/livedesktop`, and the picker scans it for
`.mp4` / `.mov` / `.m4v` — whether each entry is a file you dropped or a symlink.

**Drop your own clips.** Any H.264/HEVC clip appears as a pick. WebKit can't decode
ProRes / Animation / Sorenson, so transcode those first:

```sh
ffmpeg -i in.mov -c:v libx264 -pix_fmt yuv420p -movflags +faststart -an out.mp4
```

**Or use Apple's Aerials, zero-copy.** *Sync Apple aerials now* symlinks every
downloaded Apple **Aerial video** straight into the folder by its real name — symlinks,
not 250 MB copies, so they cost nothing and always reflect what Apple currently
ships. It scans **both** places macOS keeps them:

- the **screensaver** store (System Settings ▸ Screen Saver), and
- the per-user **wallpaper** store (System Settings ▸ Wallpaper).

> ⚠️ **Aerials only download when you *activate* one.** Scrolling past an aerial in
> the gallery downloads nothing — click to set it as your screensaver or wallpaper
> and macOS fetches the clip into one of the stores above. Then run *Sync Apple
> aerials now* and it appears in your picker. Names come from Apple's own catalogs;
> a brand-new aerial not yet catalogued shows as its raw UUID (it still plays).

**Loop or rotate.** By default, the chosen desktop loops continuously. **Shuffle
now** picks a different clip immediately; **Change desktop** can keep looping the
selection or choose a different clip every 20, 60, or 120 minutes. Each change
fades the old clip to black, then fades the playable replacement in. Shuffle draws
from the entire merged folder, so downloaded/synced Apple Aerials and user-supplied
videos participate together. A persistent black canvas sits beneath the transparent
video view during each swap, preventing WebKit's briefly unpainted white surface
from flashing through. It does not include non-video macOS screen savers.

**Slow motion.** The **Speed** submenu ranges from **0.75× Gentle** and **0.5×
Calm** through **0.25× Dreamy**, **0.1× Deep drift**, and **0.05× Near-still**.
Browser playback repeats source frames rather than inventing intermediate ones,
so the labels call out when the result becomes intentionally stepped: a typical
30 fps clip retains about 7.5 distinct frames per second at 0.25×, 3 at 0.1×, and
1.5 at 0.05×. A true 120 fps source remains fluid at 0.25×. Re-encoding a 30 fps
source as 120 fps only helps if the conversion uses motion interpolation to create
new frames. Speed changes apply *live* to the running wallpaper (no restart) and
are remembered.

For a fluid slow wallpaper, `tools/dreamify_video.sh` can create a pre-slowed
30 fps HEVC copy with either gentle frame blending or motion-compensated optical
flow. It probes first, predicts duration and size, and asks before encoding:

```sh
# A 15-minute excerpt becomes a one-hour 1440p loop.
tools/dreamify_video.sh --start 600 --duration 900 "/path/to/video.mp4"

# Inspect the plan without writing anything.
tools/dreamify_video.sh --dry-run "/path/to/video.mp4"
```

Play the resulting `-dreamy-4x.mp4` at **Normal** speed in Klonk.

**Compressor alternative.** Apply an HEVC preset, set the output frame rate to
30 fps and the output height to 1440, then set **General inspector ▸ Retiming ▸
Duration** to **400%**. In **Video inspector ▸ Quality ▸ Retiming quality**, use
**Good (Frame Blending)** for the soft look or **Best (Machine Learning)** on
Apple silicon for cleaner motion and occlusion handling. Disable audio and test a
short range before committing the entire clip.

**Battery-aware.** *Pause on battery* stops playback on battery power and resumes on
AC. Your pick, speed, and this toggle all persist and restore at login — klonk
launches with Hammerspoon, so there's no separate startup item.

---

## Install

klonk requires [Hammerspoon](https://www.hammerspoon.org).

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
  togglePresenter = {{"cmd", "alt"}, "p"}, -- show keys and highlight clicks
  nextSet     = {{"cmd", "alt"}, "]"},   -- next set
  prevSet     = {{"cmd", "alt"}, "["},   -- previous set
})
```

Reload Hammerspoon. A keyboard icon appears in the menu bar. **All sounds off**
mutes keyboard, mouse, and ambient audio together without forgetting the selected
set or ambient sound. The three groups — **Keyboard sounds**, **Ambient sounds**, and
**Video desktop** — keep only the current selection, off/switch actions, five
recent choices, and **Browse all / Controls / Library** at the first level.
Keyboard sets are grouped by character; ambient sounds split into Klonk's
included collection and your library; videos split into Apple Aerials and your
clips. Recent choices persist across restarts. Use **Open Klonk Studio…** at the
bottom of the menu when you want to search, audition, compare, or remix the full
collection.

macOS will ask to grant Hammerspoon **Accessibility** permission (needed to hear
keystrokes); klonk only *listens* — it never intercepts or alters your typing.

## Presenter mode

Choose **Presenter mode → Start** in the Klonk menu, or bind
`togglePresenter`, when sharing or recording your desktop. Klonk shows recent
key presses in a centered HUD, preserving the character actually produced
(`a` versus `A`), and flashes a translucent neutral-gray halo around clicks. The overlays
follow the display where you are working and
remain active if Klonk's sounds are muted.
Right-click uses the same halo with a small **R** badge in its upper-right edge;
left-click keeps the ring unmarked.

Special keys held together appear as one evolving chord—`⌘+⌥`,
`⌘+⌥+fn`, or `⌘+c`. Ordinary characters remain separate history elements
even when their physical key-down times overlap during fast typing, so Klonk
never turns normal letter sequences into `a+s`.

Under **Presenter mode → Keys shown**, choose **All keys** or **Special keys
only**. The latter keeps navigation, editing keys, function keys, modifiers,
and keyboard shortcuts visible while suppressing ordinary typed characters.
Klonk remembers this filter, but not whether presenter mode itself is running.

Presenter mode is intentionally session-only: it always starts off after a
Hammerspoon reload or restart so keystrokes are never exposed by surprise.
Password fields and other apps using macOS Secure Input may suppress key events;
Klonk warns if Secure Input is already active when presenter mode starts. The
event listener and visual overlays are observe-only and never intercept input.

All personal Klonk media lives together in one visible library:

```text
~/Music/Klonk/
├── ambient/       # long looping soundscapes
├── livedesktop/   # videos and linked Apple Aerials
└── keyboard/      # one folder per keyboard/input-sound set
```

Older `Sounds`, `Ambience`, and `~/.klonk` audio locations remain readable as
migration fallbacks, but every Klonk tool and **Add…** menu now writes to the
unified library. Existing live-desktop files should be moved once from
`~/Movies/Klonk/Wallpapers` to `~/Music/Klonk/livedesktop`.

---

## The built-in sets

The menu taxonomy describes how a set feels and where its sound comes from,
rather than putting every recording into one oversized “samples” bucket:

| Family | Sets | Character |
|---|---|---|
| Recorded keyboards | Cherry MX Black/Blue/Brown/Red, Everglide Crystal Purple/Oreo, Topre Purple Hybrid | real press **and release** recordings, including ABS/PBT variants |
| Percussive objects | `ping-pong` `tennis` | recorded table-tennis bounces and tennis-ball impacts |
| Machines & mechanisms | `thock` `crystal` `telegraph` `console` | contact, glass, sounder actions, and chunky console blips |
| Musical instruments | `vibraphone` `kalimba` `harpsichord` `jazzy` | minor-pentatonic notes, so random keypresses improvise a melody |
| Playful effects | `calligraph` `lcars` `pingpong` `spark` `splash` | more strongly themed input-sound worlds |

Saved Studio remixes appear first under **Environments**. Older personal sets
tagged `samples` are read as **Recorded keyboards** automatically.

## Add your own sets

Drop a folder of WAVs into `~/Music/Klonk/keyboard/<name>/` (the menu's **Add sound
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
python3 tools/make_set.py ~/sounds/paper calligraph    # -> ~/Music/Klonk/keyboard/calligraph
python3 tools/make_set.py ~/sounds/console console-ui --enter "Working.m4a" --space "Door Chime.aif"
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

Choose **Open Klonk Studio…** in the menubar to start its localhost server on
demand and open it in your browser. The Studio makes the whole setup visible: a
keyboard where every key shows which sound it plays, a mouse cluster, and a
library of all your sets and ambient sounds. It can also be started manually:

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
  set or ambient sound you're previewing — the studio header shows what's live.

The studio is a *view* over the same folders the Spoon plays — it keeps no
state of its own, needs no dependencies (Python stdlib only), and binds to
localhost.

### Environments — remix sounds across sets

The studio can also **edit**: click any key, drag its volume, or hit
"swap sound…" to assign that role a sound from *any* set in your inventory —
crystal's Return ding on a browns keyboard, console's scroll ticks, the
telegraph clack for right-click. Everything previews live in the page (nothing
is written while you experiment), and saving compiles the remix into a plain
set folder in `~/Music/Klonk/keyboard/<name>/`:

- **Per-sound volume is baked, not configured** — a gain of 60% rewrites the
  WAV's samples at compile time, so the engine plays a quieter file with zero
  new code paths.
- The recipe is saved alongside as `environment.json`, so an environment stays
  editable (reopen it in the studio, tweak, re-save) and self-describing.
- An environment can carry its **ambient sound** and a pinned `voices` count;
  "save + apply" switches the whole mood — keys and ambient sound together.
- To the engine an environment is just another set (it appears in the menu
  under **Environments**); deleting one from the studio never touches the
  source sets it borrowed from.

## Ambient sounds

klonk can also play a **looping background soundscape** under your typing — pick
one from the menu-bar **Ambient sounds** submenu (with its own volume). It now
ships all ten ambience tracks from
[Mechvibes DX](https://github.com/hainguyents13/mechvibes-dx/tree/main/assets/sounds):
`chatter`, `cricket`, `fire`, `forest`, `ocean`, `rain`, `river`, `stream`,
`thunderstorm`, and `wind`. The original CC0 ambient sounds remain available as
`synth-rain`, `surf`, and `synth-wind`.

Drop your own long, loopable audio into `~/Music/Klonk/ambient/<name>.m4a`
(waves, a thunderstorm, a starship bridge hum) and it joins the list. Ambient sounds are
independent of the keystroke switch and resume across restarts. You can audition
all bundled ambient sounds alongside the keyboard player on the
[browser preview](https://giantravens.github.io/klonk/previews/gallery.html).

## Real recorded keyboards

Ten real mechanism/material combinations now ship with Klonk, converted from the
[Mechvibes DX keyboard collection](https://github.com/hainguyents13/mechvibes-dx/tree/main/soundpacks/keyboard):

- Cherry MX Black, Blue, and Brown with both ABS and PBT keycaps
- Cherry MX Red with ABS keycaps
- Everglide Crystal Purple and Everglide Oreo
- Topre Purple Hybrid with PBT keycaps

Each set preserves eight distinct presses, four authentic releases, and dedicated
Space, Return, and Backspace recordings. The conversion tool observes every v2
pack before running, predicts its output, then reports actual counts and failure
classes:

```sh
git clone https://github.com/hainguyents13/mechvibes-dx.git /tmp/mechvibes-dx
python3 tools/import_dx_keyboards.py --source /tmp/mechvibes-dx
python3 tools/build_gallery.py
```

Every generated folder contains a `SOURCE.txt` with the upstream pack link,
pinned commit, license, source-audio hash, and source-config hash. Recordings and
pack configs are credited to [Hải Nguyễn](https://github.com/hainguyents13) and
Mechvibes DX under its [MIT license](https://github.com/hainguyents13/mechvibes-dx/blob/main/LICENSE).

For additional older community packs, the easiest source is the open-source
[Mechvibes sound-pack library on GitHub](https://github.com/hainguyents13/mechvibes).
Its packs contain recordings of real switches such as Cherry MX Blue, Cherry MX
Brown, and Holy Panda. **Recording credits:** the Cherry MX Blue and Cherry MX
Brown packs are by [Hải Nguyễn](https://github.com/hainguyents13), creator of
Mechvibes. The Holy Panda recordings are by
[Thomas Lai](https://github.com/tplai/kbsim); [Rob Landers](https://github.com/withinboredom)
adapted that pack for Mechvibes. You do not need to find or rearrange the audio yourself:
`tools/import_pack.py` downloads a named pack, converts it to Klonk's WAV layout,
and installs it in `~/Music/Klonk/keyboard/`. It can also download a CC0 typewriter
bell and bake it into a set's Return:

```sh
python3 tools/import_pack.py cherrymx-blue-pbt  blues
python3 tools/import_pack.py cherrymx-brown-pbt browns
python3 tools/import_pack.py holy-pandas        pandas
```

Run those commands from the cloned Klonk repository. The importer handles both
Mechvibes formats (single-file sprites and per-key "multi" packs). It requires
`ffmpeg` (`brew install ffmpeg`). Imported audio lands in your personal library,
never in this repo; reopen **Keyboard sounds** after import and the new set is
ready to choose. The browser test page links back to this guide as well.

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
- **One listener, two outputs.** Presenter mode and input sounds share that
  event tap. Muting sounds disables audio work without blinding presenter mode;
  turning presenter mode off removes its HUD and any in-flight click rings.
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
  single crisp voice, while a long sample (kalimba, ping-pong, tennis) fans out
  and layers. Drop a `voices` file (one integer) in a set folder
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
- **Synthesized bundled sounds** (`Klonk.spoon/sounds/`): originals released
  **CC0** (public domain) — use them anywhere. Recorded sets carry a `SOURCE.txt`
  beside their audio.
- **Ambient collection** (`Klonk.spoon/ambient/`): the `synth-*` WAVs are Klonk
  originals released as **CC0**. The other ten tracks come unchanged from
  [Mechvibes DX](https://github.com/hainguyents13/mechvibes-dx/tree/main/assets/sounds),
  copyright © 2026 [Hải Nguyễn](https://github.com/hainguyents13), under its
  [MIT license](https://github.com/hainguyents13/mechvibes-dx/blob/main/LICENSE).
  See [`Klonk.spoon/ambient/SOURCE.md`](Klonk.spoon/ambient/SOURCE.md) for the
  pinned source commit, hashes, and credits found in the files' metadata.
- **Recorded-keyboard previews** (`previews/recorded-keyboards/`): Cherry MX Blue
  and Brown recordings by [Hải Nguyễn](https://github.com/hainguyents13); Holy
  Panda recordings by [Thomas Lai](https://github.com/tplai/kbsim), adapted for
  Mechvibes by [Rob Landers](https://github.com/withinboredom). The MIT-licensed
  packs are converted and embedded in the browser test, not installed with the Spoon.
- **Bundled mechanism recordings** (`Klonk.spoon/sounds/cherrymx-*`,
  `Klonk.spoon/sounds/eg-*`, and `Klonk.spoon/sounds/topre-*`): converted from
  [Mechvibes DX's keyboard packs](https://github.com/hainguyents13/mechvibes-dx/tree/main/soundpacks/keyboard),
  copyright © 2026 [Hải Nguyễn](https://github.com/hainguyents13), MIT. Each
  set's `SOURCE.txt` records the exact upstream pack, commit, and input hashes.
- **`import_pack.py`** downloads, into *your* machine, third-party audio you
  should credit yourself: Mechvibes packs (MIT,
  [hainguyents13/mechvibes](https://github.com/hainguyents13/mechvibes)) and a
  CC0 typewriter bell (Hermes Precisa 305, recorded by Joseph SARDIN,
  [bigsoundbank.com](https://bigsoundbank.com)).

Built with [Hammerspoon](https://www.hammerspoon.org).
