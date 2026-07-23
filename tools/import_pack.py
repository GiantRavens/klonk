#!/usr/bin/env python3
"""Import a REAL recorded mechanical-keyboard pack into a klack sound set.

Source: github.com/hainguyents13/mechvibes (MIT). Packs are "sprites": one audio
file per pack + a config.json mapping each key's iohook keycode to a
[start_ms, duration_ms] slice. This tool downloads a pack, cuts the segments we
need into our WAV convention, and (because these packs are keydown-only)
synthesizes quiet 'up' ticks from truncated slices and bakes a soft service bell
into enter.wav so Return still dings.

    python3 _import_pack.py [pack] [set_name]
        pack     default: cherrymx-blue-pbt   (any dir under src/audio/ in the repo)
        set_name default: klonk

Rerun with a different pack name to add more real sets (cherrymx-brown-pbt,
holy-pandas, topre-purple-hybrid-pbt, nk-cream, …).
"""
import json, math, os, re, struct, subprocess, sys, tempfile, wave, random

SR = 44100
REPO = "https://raw.githubusercontent.com/hainguyents13/mechvibes/main/src/audio"
BELL_URL = "https://bigsoundbank.com/UPLOAD/bwf-en/2844.wav"   # CC0 Hermes Precisa 305
PACK_CREDITS = {
    "cherrymx-blue-pbt": (
        "Recording/pack creator: Hải Nguyễn (@hainguyents13)\n"
        "https://github.com/hainguyents13\n"
    ),
    "cherrymx-brown-pbt": (
        "Recording/pack creator: Hải Nguyễn (@hainguyents13)\n"
        "https://github.com/hainguyents13\n"
    ),
    "holy-pandas": (
        "Recording creator: Thomas Lai (@tplai), from kbsim\n"
        "https://github.com/tplai/kbsim\n"
        "Mechvibes adaptation: Rob Landers (@withinboredom)\n"
        "https://github.com/withinboredom\n"
    ),
}
pack = sys.argv[1] if len(sys.argv) > 1 else "cherrymx-blue-pbt"
setname = sys.argv[2] if len(sys.argv) > 2 else "blues"
# imported sets land in your personal klonk dir (not the shipped Spoon), so
# third-party recordings never end up in the repo. Override with $KLONK_SOUNDS.
base = os.path.abspath(os.environ.get("KLONK_SOUNDS", os.path.expanduser("~/Music/Klonk/keyboard")))
out = os.path.join(base, setname)
os.makedirs(out, exist_ok=True)
# Imported packs are real keyboard recordings — declare the family so the
# menu groups them under "Keyboard samples" (see tools/generate.py tag()).
with open(os.path.join(out, "category"), "w") as f:
    f.write("samples\n")

def curl(url, dest):
    subprocess.run(["curl", "-sSfL", "-m", "30", "-o", dest, url], check=True)

def ensure_bell():
    """Download + trim the CC0 typewriter bell into <base>/_bell.wav once, so
    imported sets ring a real bell on Return (load_bell picks it up)."""
    bp = os.path.join(base, "_bell.wav")
    if os.path.exists(bp):
        return
    with tempfile.TemporaryDirectory() as t:
        raw = os.path.join(t, "bell.wav")
        curl(BELL_URL, raw)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw,
            "-af", "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,"
                   "atrim=0:1.6,afade=t=out:st=1.3:d=0.3,loudnorm=I=-15:TP=-1.5",
            "-ac", "1", "-ar", str(SR), "-sample_fmt", "s16", bp], check=True)

ensure_bell()

def write_wav(name, s):
    with wave.open(os.path.join(out, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in s))

def synth_bell(f0=784, dur=0.6, level=0.30):
    # compact struck-bell (inharmonic partials) — mixed onto enter for the ding
    parts = [(1, .30, .60), (2, .45, .50), (2.40, .35, .42), (3, .22, .34), (4.05, .30, .30)]
    n = int(SR * dur); o = []
    for i in range(n):
        t = i / SR; s = 0.0
        for r, a, dec in parts:
            s += a * math.sin(2*math.pi*f0*r*t) * math.exp(-t/dec)
        s += 0.4 * (random.random()*2 - 1) * math.exp(-t/0.005)
        if t < 0.001: s *= t/0.001
        if n - i < SR*0.01: s *= (n - i)/(SR*0.01)
        o.append(s)
    peak = max(abs(x) for x in o) or 1.0
    return [x * level / peak for x in o]

def mix(a, b):
    n = max(len(a), len(b)); buf = [0.0]*n
    for tr in (a, b):
        for i, x in enumerate(tr): buf[i] += x
    peak = max((abs(x) for x in buf), default=1.0) or 1.0
    return [x * 0.85 / peak for x in buf]

def fade_norm(chunk, level=0.9, maxdur_ms=None):
    if maxdur_ms:
        chunk = chunk[:int(maxdur_ms / 1000 * SR)]
    n = len(chunk)
    fa, fo = int(0.003*SR), int(0.008*SR)                 # fades kill edge clicks
    for i in range(n):
        k = 1.0
        if i < fa: k = i / fa
        if n - i < fo: k = min(k, (n - i) / fo)
        chunk[i] *= k
    peak = max((abs(x) for x in chunk), default=1.0) or 1.0
    return [x * level / peak for x in chunk]

def load_bell():
    """Prefer the REAL typewriter bell at klack/_bell.wav (CC0 Hermes Precisa);
    fall back to the synthesized bell if it isn't there."""
    bp = os.path.join(base, "_bell.wav")
    if os.path.exists(bp):
        with wave.open(bp, "rb") as w:
            return [x/32768.0 for x in struct.unpack("<%dh"%w.getnframes(), w.readframes(w.getnframes()))]
    random.seed(1)
    return synth_bell()

def expand_glob(pattern):
    """'GENERIC_R{0-4}.mp3' -> ['GENERIC_R0.mp3', ... 'GENERIC_R4.mp3']."""
    m = re.match(r'^(.*)\{(\d+)-(\d+)\}(.*)$', pattern)
    if not m: return [pattern]
    pre, a, b, suf = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
    return [f"{pre}{i}{suf}" for i in range(a, b + 1)]

REAL_BELL = os.path.exists(os.path.join(base, "_bell.wav"))

with tempfile.TemporaryDirectory() as tmp:
    cfg_path = os.path.join(tmp, "config.json")
    curl(f"{REPO}/{pack}/config.json", cfg_path)
    cfg = json.load(open(cfg_path))
    d = cfg["defines"]
    dtype = cfg.get("key_define_type", "single")

    if dtype == "single":
        # SPRITE pack: one audio file, keys are [start_ms, dur_ms] slices of it
        sprite = cfg["sound"]
        curl(f"{REPO}/{pack}/{sprite}", os.path.join(tmp, sprite))
        wav = os.path.join(tmp, "sprite.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(tmp, sprite),
                        "-ac", "1", "-ar", str(SR), "-sample_fmt", "s16", wav], check=True)
        with wave.open(wav, "rb") as w:
            samples = list(struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes())))

        def key_samples(kc, level=0.9, maxdur=None):
            seg = d.get(str(kc))
            if not seg: return None
            start_ms, dur_ms = seg
            if maxdur: dur_ms = min(dur_ms, maxdur)
            a = max(0, int((start_ms - 6) / 1000 * SR))
            b = min(len(samples), int((start_ms + dur_ms) / 1000 * SR))
            return fade_norm([samples[i] / 32768.0 for i in range(a, b)], level)

        up_keys = (31, 19)
    else:
        # MULTI pack: each key is its own audio file (defines[kc] = filename);
        # generic keys use the sound-field glob, releases live under release/.
        _cache = {}
        def load_file(rel, level=0.9, maxdur=None):
            if rel not in _cache:
                safe = rel.replace("/", "_")
                curl(f"{REPO}/{pack}/{rel}", os.path.join(tmp, safe))
                cw = os.path.join(tmp, safe + ".wav")
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(tmp, safe),
                                "-ac", "1", "-ar", str(SR), "-sample_fmt", "s16", cw], check=True)
                with wave.open(cw, "rb") as w:
                    _cache[rel] = [x/32768.0 for x in struct.unpack("<%dh"%w.getnframes(), w.readframes(w.getnframes()))]
            return fade_norm(list(_cache[rel]), level, maxdur)

        def key_samples(kc, level=0.9, maxdur=None):
            f = d.get(str(kc))
            return load_file(f, level, maxdur) if f else None

        generics = expand_glob(cfg["sound"])            # generic key-down files
        di = 0
        for g in generics:
            try:
                di += 1; write_wav(f"down{di}.wav", load_file(g))
            except Exception:
                di -= 1
            if di >= 6: break
        up_keys = ()                                    # real releases handled below

    # --- shared: dedicated keys + enter with the (real) bell baked in ---
    if dtype == "single":
        di = 0
        for kc in (30, 31, 32, 33, 17, 18, 19, 20):     # A S D F W E R T
            s = key_samples(kc)
            if s:
                di += 1; write_wav(f"down{di}.wav", s)
            if di >= 6: break

    ui = 0
    for kc in up_keys:                                  # sprite packs: truncated slices
        s = key_samples(kc, level=0.4, maxdur=55)
        if s:
            ui += 1; write_wav(f"up{ui}.wav", s)
    if dtype == "multi":                                # multi packs: REAL release sounds
        for rel in expand_glob("release/" + cfg["sound"]) + \
                   ["release/SPACE.mp3", "release/BACKSPACE.mp3", "release/ENTER.mp3"]:
            try:
                write_wav(f"up{ui+1}.wav", load_file(rel, level=0.5, maxdur=90)); ui += 1
            except Exception:
                pass
            if ui >= 2: break

    for kc, name in ((57, "space.wav"), (14, "backspace.wav")):
        s = key_samples(kc)
        if s: write_wav(name, s)
    write_wav("enter.wav", mix(key_samples(28) or [], load_bell()))   # click + typewriter bell

    # Pin polyphony to a single voice: a real mechanical keyboard is crisp —
    # each keystroke a discrete clack, not a ringing sample that should layer
    # into a wash. This opts the set out of klonk's length-based voice heuristic.
    with open(os.path.join(out, "voices"), "w") as f:
        f.write("1\n")

    with open(os.path.join(out, "SOURCE.txt"), "w") as f:
        f.write(f"Set '{setname}' imported from Mechvibes pack '{pack}' ({dtype})\n"
                f"{REPO}/{pack}/\nLicense: MIT (github.com/hainguyents13/mechvibes)\n"
                f"{PACK_CREDITS.get(pack, '')}"
                f"enter.wav mixes in {'the REAL CC0 typewriter bell (_bell.wav)' if REAL_BELL else 'a synthesized bell'}.\n")

print(f"  {setname}: {len([x for x in os.listdir(out) if x.endswith('.wav')])} WAVs "
      f"from real '{cfg['name']}' recordings ({dtype} pack)")
