#!/usr/bin/env python3
"""Build the browser demo of Klonk's keyboard sets and ambient sounds.

Reads the bundled sets plus preview-only recorded keyboards, base64-embeds every
WAV, discovers the bundled ambient files, and emits previews/gallery.html. The
keyboard voices stay self-contained; the longer ambient files use relative URLs
so the generated page does not duplicate tens of megabytes of audio as base64.

    python3 tools/build_gallery.py
"""
import base64, json, os, sys
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUND_DIRS = [
    os.path.join(ROOT, "previews", "recorded-keyboards"),
    os.path.join(ROOT, "Klonk.spoon", "sounds"),
]
OUT = os.path.join(ROOT, "previews", "gallery.html")
AMBIENT_DIR = os.path.join(ROOT, "Klonk.spoon", "ambient")
AMBIENT_EXTS = {".wav", ".mp3", ".m4a", ".aif", ".aiff"}

def datauri(path):
    with open(path, "rb") as f:
        return "data:audio/wav;base64," + base64.b64encode(f.read()).decode()

sets = {}
for sounds_dir in SOUND_DIRS:
    if not os.path.isdir(sounds_dir):
        continue
    for name in sorted(os.listdir(sounds_dir)):
        d = os.path.join(sounds_dir, name)
        if not os.path.isdir(d) or name.startswith((".", "_")) or name in sets:
            continue
        entry = {"down": [], "up": []}
        for f in sorted(os.listdir(d)):
            if not f.endswith(".wav"):
                continue
            stem = f[:-4].rstrip("0123456789")
            uri = datauri(os.path.join(d, f))
            if stem in ("down", "up"):
                entry[stem].append(uri)
            elif stem in ("space", "enter", "backspace"):
                entry[stem] = uri
        sets[name] = entry

ambient_sounds = {}
if os.path.isdir(AMBIENT_DIR):
    for filename in sorted(os.listdir(AMBIENT_DIR)):
        name, ext = os.path.splitext(filename)
        if filename.startswith((".", "_")) or ext.lower() not in AMBIENT_EXTS:
            continue
        ambient_sounds[name] = "../Klonk.spoon/ambient/" + quote(filename)

# rough per-family labels for the chips
FAMILY = {
    "thock": "synth · deep", "crystal": "synth · glass tings",
    "telegraph": "recorded · sounder", "console": "synth · 8-bit",
    "ping-pong": "recorded · sports", "tennis": "recorded · sports",
    "blues": "recorded · Cherry MX Blue", "browns": "recorded · Cherry MX Brown",
    "pandas": "recorded · Holy Panda",
    "cherrymx-black-abs": "recorded · MX Black / ABS",
    "cherrymx-black-pbt": "recorded · MX Black / PBT",
    "cherrymx-blue-abs": "recorded · MX Blue / ABS",
    "cherrymx-blue-pbt": "recorded · MX Blue / PBT",
    "cherrymx-brown-abs": "recorded · MX Brown / ABS",
    "cherrymx-brown-pbt": "recorded · MX Brown / PBT",
    "cherrymx-red-abs": "recorded · MX Red / ABS",
    "eg-crystal-purple": "recorded · Everglide Crystal Purple",
    "eg-oreo": "recorded · Everglide Oreo",
    "topre-purple-hybrid-pbt": "recorded · Topre Purple Hybrid / PBT",
    "vibraphone": "musical · pentatonic", "kalimba": "musical · pentatonic",
    "harpsichord": "musical · pentatonic", "jazzy": "musical · pentatonic",
}

payload = json.dumps(sets)
labels = json.dumps(FAMILY)
ambient = json.dumps(ambient_sounds)

html = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>klonk — desktop ambiance · input-sound preview</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.5 -apple-system, system-ui, sans-serif;
         background: #0d0f12; color: #e7e9ec; display: flex; min-height: 100vh;
         flex-direction: column; align-items: center; padding: 40px 20px; }
  h1 { font: 700 44px/1 ui-monospace, Menlo, monospace; letter-spacing: -1px; margin: 14px 0 8px; }
  h2 { font: 700 20px/1.2 ui-monospace, Menlo, monospace; margin: 32px 0 10px; }
  .back { display: inline-block; color: #9aa0a8; text-decoration: none; }
  .back:hover { color: #e7e9ec; }
  p.sub { color: #b4bac3; margin: 0 0 14px; max-width: 650px; font-size: 16px; }
  .scope { color: #9aa0a8; background: #161a20; border-left: 3px solid #7ab7ff;
           border-radius: 0 8px 8px 0; padding: 10px 14px; margin: 0 0 24px; }
  .wrap { width: 100%; max-width: 720px; }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 20px; }
  .chip { border: 1px solid #2a2f37; background: #161a20; color: #c8ccd2;
          padding: 7px 13px; border-radius: 20px; cursor: pointer; font-size: 13px;
          transition: all .12s; user-select: none; }
  .chip:hover { border-color: #4a525e; }
  .chip.on { background: #e7e9ec; color: #0d0f12; border-color: #e7e9ec; font-weight: 600; }
  .chip small { opacity: .55; margin-left: 6px; }
  textarea { width: 100%; height: 190px; background: #161a20; color: #e7e9ec;
             border: 1px solid #2a2f37; border-radius: 12px; padding: 18px 20px;
             font: 16px/1.6 ui-monospace, Menlo, monospace; resize: vertical; outline: none; }
  textarea:focus { border-color: #6b7480; }
  .hint { color: #6b7280; font-size: 13px; margin-top: 12px; text-align: center; }
  .recorded { color: #9aa0a8; font-size: 13px; margin: 18px 0 0; text-align: center; }
  .row { display: flex; align-items: center; gap: 14px; margin-top: 18px; justify-content: center; }
  .ambient-status { color: #b4bac3; min-height: 1.5em; margin: 10px 0 0; }
  input[type=range] { accent-color: #e7e9ec; }
  a { color: #7ab7ff; }
  footer { color: #6b7280; font-size: 12px; margin-top: 40px; text-align: center; }
</style></head>
<body>
  <div class="wrap">
    <a class="back" href="https://github.com/GiantRavens/klonk#readme">&larr; Klonk overview &amp; README</a>
    <h1>klonk</h1>
    <p class="sub">Desktop ambiance for macOS: responsive keyboard and mouse voices,
      ambient soundscapes, and a looping video desktop—all from one menu-bar control.</p>
    <p class="scope"><strong>Try Klonk before installing:</strong> pick a keyboard voice
      and type, then layer one of the bundled ambient sounds underneath it. Explore video
      desktops, installation, and customization in the
      <a href="https://github.com/GiantRavens/klonk#readme">main Klonk README</a>.</p>
    <h2>keyboard + mouse voice</h2>
    <div class="chips" id="keyboard-chips"></div>
    <textarea id="pad" placeholder="type here — every key makes a sound…" autofocus></textarea>
    <div class="row">
      <label>volume</label>
      <input type="range" id="vol" min="0" max="1" step="0.05" value="0.7">
    </div>
    <p class="hint">Same input-sound engine as the Hammerspoon Spoon: a set is just a folder of WAVs.</p>
    <h2>ambient sounds</h2>
    <div class="chips" id="ambient-chips"></div>
    <p class="ambient-status" id="ambient-status">ambient off</p>
    <p class="hint">These are the same looping ambient sounds in Klonk's macOS menu. Pick one while you type above.</p>
    <p class="recorded"><strong>Recording credits:</strong> Cherry MX Blue and Brown by
      <a href="https://github.com/hainguyents13">Hải Nguyễn</a>; Holy Panda by
      <a href="https://github.com/tplai/kbsim">Thomas Lai</a>, adapted for Mechvibes by
      <a href="https://github.com/withinboredom">Rob Landers</a>.</p>
    <p class="recorded"><strong>New mechanism collection:</strong> the ten Cherry MX,
      Everglide, and Topre packs are converted from
      <a href="https://github.com/hainguyents13/mechvibes-dx/tree/main/soundpacks/keyboard">Mechvibes DX's keyboard recordings</a>
      by <a href="https://github.com/hainguyents13">Hải Nguyễn</a> (MIT). Each bundled
      set carries its pinned source commit and hashes in <code>SOURCE.txt</code>.</p>
    <p class="recorded">Want more real switch recordings? Start with the
      <a href="https://github.com/hainguyents13/mechvibes">Mechvibes packs on GitHub</a>,
      then follow Klonk's <a href="https://github.com/giantravens/klonk#real-recorded-keyboards">recorded-keyboard import guide</a>.</p>
    <p class="recorded"><strong>New ambient collection:</strong> ten sounds are from
      <a href="https://github.com/hainguyents13/mechvibes-dx/tree/main/assets/sounds">Mechvibes DX</a>
      by <a href="https://github.com/hainguyents13">Hải Nguyễn</a> (MIT). Detailed
      provenance and embedded metadata credits are in
      <a href="../Klonk.spoon/ambient/SOURCE.md">SOURCE.md</a>.</p>
  </div>
  <footer>Built by <code>tools/build_gallery.py</code> · synthesized sets are CC0 ·
    <a href="https://github.com/GiantRavens/klonk#readme">Klonk overview &amp; README</a></footer>
<script>
const SETS = __PAYLOAD__;
const LABELS = __LABELS__;
const AMBIENT_SOUNDS = __AMBIENT__;
let current = Object.keys(SETS)[0], vol = 0.7;
let ambientAudio = null;

function play(uri) {
  if (!uri) return;
  const a = new Audio(uri); a.volume = vol; a.play().catch(()=>{});
}
function rand(arr) { return arr && arr.length ? arr[Math.floor(Math.random()*arr.length)] : null; }

const chips = document.getElementById('keyboard-chips');
Object.keys(SETS).forEach(name => {
  const el = document.createElement('div');
  el.className = 'chip' + (name === current ? ' on' : '');
  el.innerHTML = name + (LABELS[name] ? ' <small>'+LABELS[name]+'</small>' : '');
  el.onclick = () => {
    current = name;
    [...chips.children].forEach(c => c.classList.remove('on'));
    el.classList.add('on');
    play(rand(SETS[name].down));   // preview
  };
  chips.appendChild(el);
});

const ambientChips = document.getElementById('ambient-chips');
const ambientStatus = document.getElementById('ambient-status');
const off = document.createElement('div');
off.className = 'chip on';
off.textContent = 'off';
off.onclick = () => selectAmbient(null, off);
ambientChips.appendChild(off);

function selectAmbient(name, chip) {
  if (ambientAudio) { ambientAudio.pause(); ambientAudio = null; }
  [...ambientChips.children].forEach(c => c.classList.remove('on'));
  chip.classList.add('on');
  ambientStatus.textContent = name ? `playing ${name}` : 'ambient off';
  if (!name) return;
  ambientAudio = new Audio(AMBIENT_SOUNDS[name]);
  ambientAudio.loop = true;
  ambientAudio.volume = vol;
  ambientAudio.play().catch(() => { ambientStatus.textContent = `click ${name} again to play`; });
}

Object.keys(AMBIENT_SOUNDS).forEach(name => {
  const el = document.createElement('div');
  el.className = 'chip';
  el.textContent = name;
  el.onclick = () => selectAmbient(name, el);
  ambientChips.appendChild(el);
});

const pad = document.getElementById('pad');
pad.addEventListener('keydown', e => {
  const s = SETS[current];
  if (e.key === ' ') play(s.space || rand(s.down));
  else if (e.key === 'Enter') play(s.enter || rand(s.down));
  else if (e.key === 'Backspace') play(s.backspace || rand(s.down));
  else if (e.key.length === 1 || e.key === 'Tab') play(rand(s.down));
});
pad.addEventListener('keyup', e => {
  if (e.key.length === 1 || e.key === ' ') play(rand(SETS[current].up));
});
document.getElementById('vol').addEventListener('input', e => {
  vol = parseFloat(e.target.value);
  if (ambientAudio) ambientAudio.volume = vol;
});
</script>
</body></html>
"""
html = (html.replace("__PAYLOAD__", payload)
            .replace("__LABELS__", labels)
            .replace("__AMBIENT__", ambient))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write(html)
kb = os.path.getsize(OUT) / 1024
print(f"wrote {os.path.relpath(OUT, ROOT)} ({kb:.0f} KB, "
      f"{len(sets)} keyboard sets embedded, {len(ambient_sounds)} ambient sounds linked)")
