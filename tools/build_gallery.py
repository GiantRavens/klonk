#!/usr/bin/env python3
"""Build a self-contained HTML demo of the klonk sound sets.

Reads the bundled sets plus preview-only recorded keyboards, base64-embeds every
WAV, and emits previews/gallery.html
— a page with a "type here" box that plays the selected set as you type, entirely
client-side (no server, no external files). Rerun after regenerating sounds.

    python3 tools/build_gallery.py
"""
import base64, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUND_DIRS = [
    os.path.join(ROOT, "previews", "recorded-keyboards"),
    os.path.join(ROOT, "Klonk.spoon", "sounds"),
]
OUT = os.path.join(ROOT, "previews", "gallery.html")

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

# rough per-family labels for the chips
FAMILY = {
    "thock": "synth · deep", "crystal": "synth · glass tings",
    "telegraph": "recorded · sounder", "console": "synth · 8-bit",
    "ping-pong": "recorded · sports", "tennis": "recorded · sports",
    "blues": "recorded · Cherry MX Blue", "browns": "recorded · Cherry MX Brown",
    "pandas": "recorded · Holy Panda",
    "vibraphone": "musical · pentatonic", "kalimba": "musical · pentatonic",
    "harpsichord": "musical · pentatonic", "jazzy": "musical · pentatonic",
}

payload = json.dumps(sets)
labels = json.dumps(FAMILY)

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
    <p class="scope"><strong>This page previews one part of Klonk:</strong> its interactive
      input-sound sets. Pick a voice, click the box, and type. Explore ambient audio,
      video desktops, installation, and customization in the
      <a href="https://github.com/GiantRavens/klonk#readme">main Klonk README</a>.</p>
    <div class="chips" id="chips"></div>
    <textarea id="pad" placeholder="type here — every key makes a sound…" autofocus></textarea>
    <div class="row">
      <label>volume</label>
      <input type="range" id="vol" min="0" max="1" step="0.05" value="0.7">
    </div>
    <p class="hint">Same input-sound engine as the Hammerspoon Spoon: a set is just a folder of WAVs.</p>
    <p class="recorded"><strong>Recording credits:</strong> Cherry MX Blue and Brown by
      <a href="https://github.com/hainguyents13">Hải Nguyễn</a>; Holy Panda by
      <a href="https://github.com/tplai/kbsim">Thomas Lai</a>, adapted for Mechvibes by
      <a href="https://github.com/withinboredom">Rob Landers</a>.</p>
    <p class="recorded">Want more real switch recordings? Start with the
      <a href="https://github.com/hainguyents13/mechvibes">Mechvibes packs on GitHub</a>,
      then follow Klonk's <a href="https://github.com/giantravens/klonk#real-recorded-keyboards">recorded-keyboard import guide</a>.</p>
  </div>
  <footer>Built by <code>tools/build_gallery.py</code> · synthesized sets are CC0 ·
    <a href="https://github.com/GiantRavens/klonk#readme">Klonk overview &amp; README</a></footer>
<script>
const SETS = __PAYLOAD__;
const LABELS = __LABELS__;
let current = Object.keys(SETS)[0], vol = 0.7;

function play(uri) {
  if (!uri) return;
  const a = new Audio(uri); a.volume = vol; a.play().catch(()=>{});
}
function rand(arr) { return arr && arr.length ? arr[Math.floor(Math.random()*arr.length)] : null; }

const chips = document.getElementById('chips');
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
document.getElementById('vol').addEventListener('input', e => vol = parseFloat(e.target.value));
</script>
</body></html>
"""
html = html.replace("__PAYLOAD__", payload).replace("__LABELS__", labels)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write(html)
kb = os.path.getsize(OUT) / 1024
print(f"wrote {os.path.relpath(OUT, ROOT)} ({kb:.0f} KB, {len(sets)} sets embedded)")
