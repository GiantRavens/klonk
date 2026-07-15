#!/usr/bin/env python3
"""Procedural keystroke sound-set generator for the Hammerspoon klack engine.

A set = a folder of WAVs. The engine's filename convention:
  down1..N.wav   generic key-down variants (randomized per keystroke)
  up1..N.wav     generic key-up variants (quieter release tick)
  space.wav, enter.wav, backspace.wav   dedicated per-key sounds
  click1..N.wav  mouse-down (heavier sibling of down)
  clickup.wav    mouse-up release
  rightclick.wav secondary-click (a touch deeper than click)
  scroll1..N.wav wheel / trackpad-scroll detent tick (short + quiet)

Mouse voices are OPTIONAL — the engine falls back click->down, scroll->up — but
every built-in set ships them so the mouse feels purpose-made, not borrowed.
Regenerate just the mouse files (leaving landed key sounds untouched) with:
  python3 tools/generate.py Klonk.spoon/sounds --mouse

Each sound is synthesized as: a filtered noise burst (the "contact") plus a few
exponentially-decaying sine partials (the "body resonance"). Variants detune
frequencies +/-4% and jitter decay +/-15% so fast typing never sounds like a
machine gun. Rerun this script anytime; tweak the SETS table to taste.
"""
import math, os, random, struct, sys, wave

SR = 44100

def onepole_lp(xs, cutoff):
    a = math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for x in xs:
        y = (1 - a) * x + a * y
        out.append(y)
    return out

def synth(dur, noise, partials, gain=1.0):
    """noise=(amp, lp_cutoff_hz, decay_s); partials=[(freq, amp, decay_s), ...]"""
    n = int(SR * dur)
    namp, ncut, ndec = noise
    burst = [namp * (random.random() * 2 - 1) * math.exp(-i / SR / ndec) for i in range(n)]
    burst = onepole_lp(burst, ncut)
    out = []
    for i in range(n):
        t = i / SR
        s = burst[i]
        for f, a, d in partials:
            s += a * math.sin(2 * math.pi * f * t) * math.exp(-t / d)
        if t < 0.0005: s *= t / 0.0005                     # de-pop attack
        if n - i < SR * 0.005: s *= (n - i) / (SR * 0.005)  # de-pop tail
        out.append(s * gain)
    peak = max(abs(s) for s in out) or 1.0
    return [s * 0.6 / peak * min(1.0, gain) for s in out]

def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767))
                               for s in samples))

def jitter(partials, rng):
    return [(f * rng.uniform(0.96, 1.04), a * rng.uniform(0.9, 1.1),
             d * rng.uniform(0.85, 1.15)) for f, a, d in partials]

SETS = {
    "thock": {   # deep, creamy — lubed Topre energy
        "down":      (0.10, (0.9, 700, 0.018),  [(140, .6, .045), (210, .35, .03), (390, .15, .02)], 1.0),
        "up":        (0.045, (0.4, 900, 0.008), [(180, .2, .015)], 0.4),
        "space":     (0.13, (1.0, 500, 0.022),  [(98, .7, .055), (150, .4, .035)], 1.1),
        "enter":     (0.12, (0.9, 600, 0.020),  [(115, .65, .05), (175, .35, .03)], 1.05),
        "backspace": (0.09, (0.9, 800, 0.016),  [(165, .55, .04), (245, .3, .025)], 0.95),
        "click":      (0.11, (1.0, 600, 0.020),  [(120, .7, .05), (180, .4, .032), (330, .16, .02)], 1.05),  # fat round button
        "clickup":    (0.05, (0.4, 850, 0.008),  [(160, .22, .016)], 0.38),
        "rightclick": (0.12, (1.0, 520, 0.022),  [(105, .72, .055), (160, .4, .035)], 1.05),                # deeper
        "scroll":     (0.03, (0.5, 1200, 0.004), [(300, .15, .006)], 0.30),                                 # tiny detent
    },
    "crystal": {  # bright glass/crystal tings — precise, resonant, jewel-like
        "down":      (0.06, (0.7, 5500, 0.008), [(2300, .45, .018), (3600, .3, .012), (1200, .2, .02)], 0.9),
        "up":        (0.04, (0.5, 6500, 0.005), [(3000, .25, .01)], 0.35),
        "space":     (0.08, (0.8, 3500, 0.012), [(1700, .5, .02), (900, .3, .025)], 1.0),
        "enter":     (0.07, (0.8, 4500, 0.010), [(2000, .5, .02), (3100, .25, .012)], 1.0),
        "backspace": (0.06, (0.7, 6000, 0.007), [(2600, .4, .015), (4000, .25, .01)], 0.85),
        "click":      (0.07,  (0.8, 5000, 0.009), [(2000, .45, .02), (3200, .3, .013), (1000, .22, .022)], 0.95),
        "clickup":    (0.04,  (0.5, 6500, 0.005), [(2800, .25, .01)], 0.35),
        "rightclick": (0.08,  (0.85, 4200, 0.011),[(1700, .5, .022), (2700, .28, .014)], 0.95),
        "scroll":     (0.025, (0.6, 7000, 0.004), [(4000, .18, .005)], 0.30),
    },
    "typewriter": {  # inharmonic metal — Selectric energy, bell on Enter
        "down":      (0.14, (0.8, 4000, 0.012), [(1250, .4, .05), (2650, .35, .035), (4150, .25, .02), (600, .2, .03)], 0.95),
        "up":        (0.05, (0.5, 5000, 0.006), [(1800, .2, .012)], 0.35),
        "space":     (0.18, (1.0, 500, 0.030),  [(180, .7, .06), (90, .4, .08)], 1.1),
        "enter":     (0.45, (0.7, 3000, 0.015), [(1250, .3, .04), (3135, .3, .30), (4700, .15, .22)], 1.0),  # ding!
        "backspace": (0.12, (0.8, 4500, 0.010), [(1500, .4, .04), (3000, .25, .025)], 0.9),
        "click":      (0.10, (0.9, 3000, 0.011), [(900, .4, .03), (1800, .3, .02), (450, .25, .03)], 0.95),  # lever chunk
        "clickup":    (0.05, (0.5, 4500, 0.006), [(1500, .2, .012)], 0.35),
        "rightclick": (0.12, (0.9, 2500, 0.013), [(700, .4, .035), (1400, .25, .02)], 0.95),
        "scroll":     (0.03, (0.6, 5000, 0.005), [(2000, .18, .006)], 0.30),
    },
}
# click/scroll get randomized variants (they repeat a lot); clickup/rightclick
# render once. MOUSE_KEYS drives the additive `--mouse` regen.
VARIANTS = {"down": 5, "up": 3, "click": 3, "scroll": 2}
MOUSE_KEYS = {"click", "clickup", "rightclick", "scroll"}

# Per-set Return ding, baked INTO that set's enter.wav (no universal overlay).
# (f0, dur, level) for a struck bell mixed over the enter keystroke; None means
# the set's enter is already its own flourish (typewriter bell / tonal / music).
DINGS = {
    "thock":      (523, 1.10, 0.45),   # soft low bell — matches the creamy body
    "crystal":    (880, 0.90, 0.45),   # bright crystal flourish
    "typewriter": None,                # its enter already rings
}

# --- OUR ding: a struck service bell -----------------------------------------
# A real bell is INHARMONIC — its partials aren't integer multiples, which is
# exactly what the ear reads as "metal" instead of "organ". These ratios are
# measured from a small hemispherical bell (hum, prime, tierce, quint, nominal).
# Bright strike transient up front, long shimmering decay, faint beating between
# close partials for that live-metal warble. This is 100% ours — no samples.
BELL_PARTIALS = [   # (freq_ratio, amp, decay_s)
    (1.00, 0.30, 1.10),   # hum
    (2.00, 0.45, 0.95),   # prime
    (2.40, 0.35, 0.80),   # minor-third tierce — the metallic color
    (3.00, 0.22, 0.65),   # quint
    (4.05, 0.30, 0.55),   # nominal (slightly sharp → shimmer)
    (5.43, 0.18, 0.40),   # upper inharmonic
    (6.80, 0.12, 0.30),   # air/strike ring
]
def synth_bell(f0=660.0, dur=1.4, gain=1.0):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for ratio, a, d in BELL_PARTIALS:
            f = f0 * ratio
            # tiny per-partial detune pair → slow beating (live metal warble)
            s += a * (math.sin(2*math.pi*f*t) + 0.5*math.sin(2*math.pi*f*1.003*t)) \
                   * math.exp(-t / d)
        strike = (random.random()*2 - 1) * math.exp(-t / 0.006)   # bright ping
        s += 0.5 * strike
        if t < 0.0008: s *= t / 0.0008
        if n - i < SR*0.01: s *= (n - i)/(SR*0.01)
        out.append(s * gain)
    peak = max(abs(s) for s in out) or 1.0
    return [s * 0.7 / peak for s in out]

def mix(*tracks):
    """Overlay tracks (sum, pad to longest, renormalize) — bakes a bell into a key."""
    n = max(len(t) for t in tracks)
    buf = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            buf[i] += s
    peak = max((abs(s) for s in buf), default=1.0) or 1.0
    return [s * 0.8 / peak for s in buf]

# --- MECHANICAL impact synth: what makes a sound "physical" not "digital" -----
# Three ingredients clean sine partials can't fake:
#   1. IMPACT — a broadband noise burst (~5ms), low-passed: the contact itself.
#   2. THUMP — a low body tone (~120-230 Hz) whose pitch DROPS as it decays;
#      real struck objects sag in pitch as energy leaves them. This is the
#      "weight" your ear reads as mass hitting mass.
#   3. SATURATION — soft-clip (tanh) the sum for grit/nonlinearity, the way a
#      real transient overdrives whatever's listening. Sine stacks stay polite;
#      mechanical sounds don't.
# strike2 adds a second offset impact — the type-bar slap THEN hammer, or the
# armature travel THEN stop: "ka-THUNK". Ring = inharmonic metal overtones.
def synth_mech(dur, thump, impact, ring, strike2=None, sat=2.5, level=0.72):
    """thump=(f0,f1,amp,decay); impact=(amp,lp_hz,decay); ring=[(f,a,d)]."""
    n = int(SR * dur)
    tf0, tf1, tamp, tdec = thump
    iamp, ilp, idec = impact
    noise = onepole_lp([iamp*(random.random()*2-1)*math.exp(-i/SR/idec)
                        for i in range(n)], ilp)
    out, phase = [], 0.0
    for i in range(n):
        t = i / SR
        f = tf0 * (tf1 / tf0) ** (t / dur)          # thump pitch sags f0→f1
        phase += 2 * math.pi * f / SR
        s = noise[i] + tamp * math.sin(phase) * math.exp(-t / tdec)
        for rf, ra, rd in ring:
            s += ra * math.sin(2*math.pi*rf*t) * math.exp(-t / rd)
        out.append(s)
    if strike2:                                     # ka-THUNK: second impact
        d2, g2 = strike2
        off = int(SR * d2)
        n2 = onepole_lp([g2*iamp*(random.random()*2-1)*math.exp(-j/SR/idec)
                         for j in range(n-off)], ilp)
        for j, v in enumerate(n2):
            out[off+j] += v
    d = math.tanh(sat)
    out = [math.tanh(sat * s) / d for s in out]      # soft-saturate for grit
    for i in range(n):                               # de-pop edges
        t = i / SR
        if t < 0.0004: out[i] *= t / 0.0004
        if n - i < SR*0.004: out[i] *= (n - i)/(SR*0.004)
    peak = max((abs(s) for s in out), default=1.0) or 1.0
    return [s * level / peak for s in out]

# --- tonal sets (Trek blips, water drops) ------------------------------------
# These are PITCHED, not percussive, so they get their own synth. Phase is
# accumulated (not f*t) so a pitch glide bends smoothly with no click.
def _wave(phase, shape):
    if shape == "tri":  return 2/math.pi * math.asin(math.sin(phase))
    if shape == "sqr":  return 0.9 if math.sin(phase) >= 0 else -0.9
    return math.sin(phase)                                   # default sine

def finish(out, level, ta=0.0008, td=0.005):
    n = len(out)
    for i in range(n):
        t = i / SR
        k = 1.0
        if t < ta: k = t / ta                                # de-pop attack
        if n - i < SR * td: k = min(k, (n - i) / (SR * td))  # de-pop tail
        out[i] *= k
    peak = max((abs(s) for s in out), default=1.0) or 1.0
    return [s * level / peak for s in out]

def glide(f0, f1, dur, shape="sine", dec=None, level=0.6):
    dec, n, phase, out = dec or dur * 0.5, int(SR * dur), 0.0, []
    for i in range(n):
        t = i / SR
        f = f0 * (f1 / f0) ** (t / dur)                      # exp glide f0→f1
        phase += 2 * math.pi * f / SR
        out.append(_wave(phase, shape) * math.exp(-t / dec))
    return finish(out, level)

def two_tone(fa, fb, dur, shape="tri", gap=0.5, level=0.6):
    """Two stacked blips — LCARS 'confirm' feel. gap = fraction before 2nd."""
    a = glide(fa, fa, dur * gap, shape, dur * gap * 0.6, level)
    b = glide(fb, fb, dur * (1 - gap), shape, dur * (1 - gap) * 0.6, level)
    return a + b

# spec: key -> (callable, kwargs). down/up jitter freq per variant so repeats
# aren't identical. Frequencies chosen to sit in the "friendly UI chirp" band.
THEMED = {
    "trek": {   # LCARS console — soft triangle blips, tuned like TNG panels
        "down":      (glide, dict(f0=760, f1=880,  dur=0.075, shape="tri", level=0.5)),
        "up":        (glide, dict(f0=1180, f1=1180, dur=0.045, shape="sine", level=0.28)),
        "space":     (glide, dict(f0=540, f1=640,  dur=0.10,  shape="tri", level=0.55)),
        "enter":     (two_tone, dict(fa=680, fb=1020, dur=0.16, shape="tri", level=0.6)),
        "backspace": (glide, dict(f0=900, f1=560,  dur=0.09,  shape="tri", level=0.5)),  # falling = "undo"
        "click":      (glide, dict(f0=520, f1=600, dur=0.075, shape="tri", level=0.55)),          # button boop
        "clickup":    (glide, dict(f0=900, f1=900, dur=0.04, shape="sine", level=0.26)),
        "rightclick": (two_tone, dict(fa=600, fb=440, dur=0.12, shape="tri", gap=0.5, level=0.55)),  # menu (descending)
        "scroll":     (glide, dict(f0=1300, f1=1300, dur=0.03, shape="sine", dec=0.012, level=0.22)),
    },
}

def tag(d, cat):
    """Declare the set's family (a one-word `category` file in the set folder).
    The generator knows what it synthesized; the menu groups by reading this —
    no hardcoded name→group map to drift out of date."""
    with open(os.path.join(d, "category"), "w") as f:
        f.write(cat + "\n")

def render_themed(base, only=None):
    for set_name, keys in THEMED.items():
        d = os.path.join(base, set_name)
        os.makedirs(d, exist_ok=True)
        tag(d, "themed")
        for key, (fn, kw) in keys.items():
            if only and key not in only: continue
            for v in range(1, VARIANTS.get(key, 1) + 1):
                random.seed(hash((set_name, key, v)))
                k = dict(kw)
                jf = random.uniform(0.95, 1.05)              # ±5% per-variant pitch
                for fk in ("f0", "f1", "fa", "fb"):
                    if fk in k: k[fk] *= jf
                name = f"{key}{v}.wav" if key in VARIANTS else f"{key}.wav"
                write_wav(os.path.join(d, name), fn(**k))
        print(f"  {set_name}: {len(os.listdir(d))} files")

# --- MUSICAL sets: typing plays a melody --------------------------------------
# The trick: draw notes from a MINOR PENTATONIC scale. It has no minor-2nd or
# tritone, so ANY random sequence of its notes sounds intentional — which means
# the engine's random per-keystroke variant pick becomes a pleasant improvised
# line instead of noise. Each instrument is just a different partial recipe.
def midi(semis):                       # semitones from C4 → Hz
    return 261.63 * 2 ** (semis / 12.0)
SCALE = [0, 3, 5, 7, 10, 12, 15, 17]   # C minor pentatonic over ~1.5 octaves

def _instr(f, dur, partials, level, trem=0.0, pluck=0.0, td=0.02):
    """partials=[(ratio, amp, decay_s)]; trem=Hz amplitude shimmer;
       pluck=amount of bright attack noise (plucked/struck realism)."""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        amp = 1.0 + trem * math.sin(2 * math.pi * 5.5 * t) if trem else 1.0
        s = 0.0
        for r, a, d in partials:
            s += a * math.sin(2 * math.pi * f * r * t) * math.exp(-t / d)
        if pluck:
            s += pluck * (random.random() * 2 - 1) * math.exp(-t / 0.004)
        out.append(s * amp)
    return finish(out, level, td=td)

def vibraphone(f, dur=0.7, level=0.6):
    # metal bar: near-harmonic 4th partial, long sing, slow tremolo shimmer
    return _instr(f, dur, [(1, 1.0, dur*0.9), (3.98, 0.4, dur*0.5), (9.2, 0.12, dur*0.3)],
                  level, trem=0.22, td=0.03)

def kalimba(f, dur=0.45, level=0.6):
    # thumb-piano tine: inharmonic overtones, medium decay, slight buzz pluck
    return _instr(f, dur, [(1, 1.0, dur*0.8), (2.76, 0.45, dur*0.4), (5.40, 0.22, dur*0.2)],
                  level, pluck=0.25)

def harpsichord(f, dur=0.5, level=0.55):
    # plucked string: full harmonic stack, bright, quick decay, hard pluck
    return _instr(f, dur, [(h, 1.0/h, dur*0.4) for h in range(1, 10)],
                  level, pluck=0.35, td=0.01)

def jazzy(f, dur=0.6, level=0.55):
    # Rhodes-ish: fundamental + a struck 'bell' overtone that fades fast = e-piano
    return _instr(f, dur, [(1, 1.0, dur*0.6), (2, 0.3, dur*0.4), (14, 0.18, 0.05)],
                  level, td=0.02)

INSTRUMENTS = {"vibraphone": vibraphone, "kalimba": kalimba,
               "harpsichord": harpsichord, "jazzy": jazzy}

def gliss(inst, freqs, step=0.05, notedur=0.35, level=0.65):
    """Overlap-add a run up the scale — the harpsichord-style Enter flourish."""
    seg = int(SR * step)
    buf = [0.0] * (seg * len(freqs) + int(SR * notedur))
    for k, f in enumerate(freqs):
        note = inst(f, dur=notedur, level=0.5)
        for i, s in enumerate(note):
            buf[k * seg + i] += s
    return finish(buf, level, td=0.03)

def render_musical(base, only=None):
    def want(k): return only is None or k in only
    for name, inst in INSTRUMENTS.items():
        d = os.path.join(base, name)
        os.makedirs(d, exist_ok=True)
        tag(d, "musical")
        if want("down"):   # down variants ARE the scale — random pick improvises
            for i, off in enumerate(SCALE, start=1):
                write_wav(os.path.join(d, f"down{i}.wav"), inst(midi(off)))
        if want("up"):     # two soft high grace notes (quiet, so release stays out of the way)
            for i in range(1, 3):
                write_wav(os.path.join(d, f"up{i}.wav"),
                          inst(midi(SCALE[-1] + i * 2), dur=0.18, level=0.20))
        if want("space"):
            write_wav(os.path.join(d, "space.wav"), inst(midi(-5), dur=0.6, level=0.55))   # low root
        if want("enter"):
            write_wav(os.path.join(d, "enter.wav"), gliss(inst, [midi(o) for o in SCALE]))  # flourish!
        if want("backspace"):
            write_wav(os.path.join(d, "backspace.wav"), inst(midi(SCALE[1]), dur=0.3, level=0.45))
        # mouse = BASS + percussion an octave under the melody, so clicks lay down
        # a walking low line while the keys sing on top. rightclick = deep root.
        if want("click"):
            for i in range(1, VARIANTS.get("click", 1) + 1):
                write_wav(os.path.join(d, f"click{i}.wav"),
                          inst(midi(SCALE[(i - 1) % len(SCALE)] - 12), dur=0.5, level=0.5))
        if want("clickup"):
            write_wav(os.path.join(d, "clickup.wav"), inst(midi(SCALE[-1] + 2), dur=0.16, level=0.18))
        if want("rightclick"):
            write_wav(os.path.join(d, "rightclick.wav"), inst(midi(-17), dur=0.55, level=0.5))  # deep root
        if want("scroll"):
            for i in range(1, VARIANTS.get("scroll", 1) + 1):
                write_wav(os.path.join(d, f"scroll{i}.wav"),
                          inst(midi(SCALE[-1] + 4 + i * 2), dur=0.14, level=0.16))
        print(f"  {name}: {len(os.listdir(d))} files")

# --- MECHANICAL sets: rendered by synth_mech, not the sine-stack synth --------
# Each key is synth_mech kwargs. An optional "ding" bakes a bell into enter;
# Return behavior is an artistic choice per set, not a global convention.
MECH = {
    # Telegraph is a curated recorded set and is deliberately not regenerated.
    "console": {   # old-school console: chunky 8-bit-flavored beeps and bops
        "ding": None,  # Return keeps its drum-pad action without a bell overlay
        "keys": {
            "down":      dict(dur=0.16, thump=(190,120,0.9,0.050), impact=(1.0,2400,0.007),
                              ring=[(520,.4,.05),(1100,.3,.03),(1900,.16,.02)],
                              strike2=(0.008,0.5), sat=2.8, level=0.80),   # slap+hammer
            "up":        dict(dur=0.05, thump=(410,300,0.4,0.020), impact=(0.6,3500,0.005),
                              ring=[(1400,.25,.012)], sat=2.0, level=0.40),
            "space":     dict(dur=0.22, thump=(150,92,1.1,0.090), impact=(1.0,1800,0.008),
                              ring=[(300,.4,.06),(95,.5,.10)], sat=2.8, level=0.92),   # platen thunk
            "enter":     dict(dur=0.16, thump=(190,120,0.9,0.050), impact=(0.95,2400,0.007),
                              ring=[(520,.35,.05),(1100,.25,.03)], strike2=(0.008,0.5), sat=2.8, level=0.80),
            "backspace": dict(dur=0.13, thump=(240,150,0.8,0.040), impact=(0.9,2800,0.006),
                              ring=[(700,.4,.04),(1500,.2,.02)], sat=2.6, level=0.72),
            "click":      dict(dur=0.16, thump=(185,118,0.9,0.05), impact=(1.0,2300,0.007),
                               ring=[(500,.4,.05),(1050,.3,.03)], strike2=(0.008,0.5), sat=2.8, level=0.82),  # slap+hammer
            "clickup":    dict(dur=0.05, thump=(400,290,0.4,0.02), impact=(0.6,3500,0.005),
                               ring=[(1350,.25,.012)], sat=2.0, level=0.4),
            "rightclick": dict(dur=0.17, thump=(170,108,0.95,0.055), impact=(1.0,2100,0.008),
                               ring=[(460,.4,.055),(980,.25,.03)], strike2=(0.009,0.5), sat=2.8, level=0.82),
            "scroll":     dict(dur=0.05, thump=(520,400,0.35,0.015), impact=(0.6,3800,0.004),
                               ring=[(1500,.22,.01)], sat=2.0, level=0.4),
        },
    },
}

def render_mech(base, only=None):
    for set_name, spec in MECH.items():
        d = os.path.join(base, set_name)
        os.makedirs(d, exist_ok=True)
        tag(d, "mechanical")
        ding = spec.get("ding")
        for key, kw in spec["keys"].items():
            if only and key not in only: continue
            for v in range(1, VARIANTS.get(key, 1) + 1):
                random.seed(hash((set_name, key, v)))
                k = dict(kw)
                jf = random.uniform(0.97, 1.03)                 # ±3% per-variant thump pitch
                f0, f1, a, dec = k["thump"]; k["thump"] = (f0*jf, f1*jf, a, dec)
                s = synth_mech(**k)                             # consumes RNG for noise → varies
                if key == "enter" and ding:
                    f0b, bdur, blev = ding
                    random.seed(hash((set_name, "bell")))
                    s = mix(s, [x * blev for x in synth_bell(f0b, bdur)])
                name = f"{key}{v}.wav" if key in VARIANTS else f"{key}.wav"
                write_wav(os.path.join(d, name), s)
        print(f"  {set_name}: {len(os.listdir(d))} files (mechanical)")

# --- AMBIENT beds: looping background soundscapes -----------------------------
# A bed is a long, quiet, LOOPABLE noise texture that plays under the typing.
# The whole illusion is shaped filtered noise + slow modulation:
#   rain  = bright hiss (band-passed noise) + random droplet transients
#   wind  = dark noise whose level + cutoff swell on a slow, irregular gust LFO
#   surf  = low rumble with a ~0.08 Hz swell; hiss rides the crest = a wave break
# loopify() crossfades the tail back over the head so repeat playback has no seam.
def _noise_lp(dur, cutoff, seed):
    random.seed(seed)
    return onepole_lp([random.random() * 2 - 1 for _ in range(int(SR * dur))], cutoff)

def loopify(x, xf=1.2):
    n = len(x); m = min(int(xf * SR), n // 2)
    out = list(x[:n - m])
    for i in range(m):                      # blend the tail back over the head
        w = i / m
        out[i] = x[i] * w + x[n - m + i] * (1 - w)
    peak = max((abs(s) for s in out), default=1.0) or 1.0
    return [s / peak for s in out]

def bed_rain(dur=12.0, level=0.5):
    hiss = _noise_lp(dur, 6500, seed=101)
    low  = onepole_lp(hiss, 900)
    x = [(h - l) * 0.9 for h, l in zip(hiss, low)]            # band-pass ≈ hiss
    random.seed(202)                                          # droplets
    n = len(x); i = 0
    while i < n:
        i += int(SR * random.uniform(0.02, 0.09))
        if i >= n: break
        f = random.uniform(1800, 5200); a = random.uniform(0.15, 0.5)
        for j in range(min(int(SR * 0.02), n - i)):
            t = j / SR
            x[i + j] += a * math.sin(2 * math.pi * f * t) * math.exp(-t / 0.004)
    return finish(loopify(x), level, ta=0.02, td=0.02)

def bed_wind(dur=14.0, level=0.5):
    base = _noise_lp(dur, 1100, seed=303)
    n = len(base); out = []
    for i in range(n):
        t = i / SR
        gust = 0.55 + 0.45 * math.sin(2*math.pi*0.05*t) * math.sin(2*math.pi*0.017*t + 1.3)
        out.append(base[i] * gust)
    return finish(loopify(out), level, ta=0.03, td=0.03)

def bed_surf(dur=14.0, level=0.5):
    rumble = _noise_lp(dur, 500, seed=404)
    hiss   = _noise_lp(dur, 7000, seed=505)
    n = len(rumble); out = []
    for i in range(n):
        t = i / SR
        swell = 0.5 + 0.5 * math.sin(2*math.pi*0.08*t - 1.2)   # ~12 s wave cycle
        crest = max(0.0, swell - 0.55) / 0.45                  # hiss only on the crest
        out.append(rumble[i] * (0.4 + 0.6*swell) + hiss[i] * 0.25 * crest)
    return finish(loopify(out), level, ta=0.03, td=0.03)

AMBIENT = {"rain": bed_rain, "wind": bed_wind, "surf": bed_surf}

def render_ambient(base):
    d = os.path.join(os.path.dirname(os.path.abspath(base)), "ambient")
    os.makedirs(d, exist_ok=True)
    for name, fn in AMBIENT.items():
        write_wav(os.path.join(d, f"{name}.wav"), fn())
    print(f"  ambient: {len(AMBIENT)} beds (rain, wind, surf) -> {d}")


def main():
    flags = sys.argv[1:]
    args = [a for a in flags if not a.startswith("-")]
    only = MOUSE_KEYS if "--mouse" in flags else None          # additive: only touch mouse files
    ambient_only = "--ambient" in flags                        # additive: only rebuild beds
    base = os.path.abspath(args[0]) if args \
        else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(base, exist_ok=True)
    if ambient_only:
        render_ambient(base)
        return
    if only:
        print("  --mouse: adding click/clickup/rightclick/scroll only (key sounds untouched)")
    for set_name, keys in SETS.items():
        d = os.path.join(base, set_name)
        os.makedirs(d, exist_ok=True)
        tag(d, "mechanical")
        for key, (dur, noise, partials, gain) in keys.items():
            if only and key not in only: continue
            for v in range(1, VARIANTS.get(key, 1) + 1):
                rng = random.Random(hash((set_name, key, v)))
                random.seed(hash((set_name, key, v, "noise")))
                s = synth(dur, noise, jitter(partials, rng), gain)
                if key == "enter" and DINGS.get(set_name):        # bake the bell in
                    f0, bdur, blev = DINGS[set_name]
                    random.seed(hash((set_name, "bell")))
                    s = mix(s, [x * blev for x in synth_bell(f0, bdur)])
                name = f"{key}{v}.wav" if key in VARIANTS else f"{key}.wav"
                write_wav(os.path.join(d, name), s)
        print(f"  {set_name}: {len(os.listdir(d))} files")
    render_mech(base, only)
    render_themed(base, only)
    render_musical(base, only)
    if not only:
        render_ambient(base)
        print("  (Return flourishes are defined independently by each set)")

if __name__ == "__main__":
    main()
