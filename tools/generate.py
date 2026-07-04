#!/usr/bin/env python3
"""Procedural keystroke sound-set generator for the Hammerspoon klack engine.

A set = a folder of WAVs. The engine's filename convention:
  down1..N.wav   generic key-down variants (randomized per keystroke)
  up1..N.wav     generic key-up variants (quieter release tick)
  space.wav, enter.wav, backspace.wav   dedicated per-key sounds

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
    },
    "clicky": {  # bright, tactile — MX Blue energy
        "down":      (0.06, (0.7, 5500, 0.008), [(2300, .45, .018), (3600, .3, .012), (1200, .2, .02)], 0.9),
        "up":        (0.04, (0.5, 6500, 0.005), [(3000, .25, .01)], 0.35),
        "space":     (0.08, (0.8, 3500, 0.012), [(1700, .5, .02), (900, .3, .025)], 1.0),
        "enter":     (0.07, (0.8, 4500, 0.010), [(2000, .5, .02), (3100, .25, .012)], 1.0),
        "backspace": (0.06, (0.7, 6000, 0.007), [(2600, .4, .015), (4000, .25, .01)], 0.85),
    },
    "typewriter": {  # inharmonic metal — Selectric energy, bell on Enter
        "down":      (0.14, (0.8, 4000, 0.012), [(1250, .4, .05), (2650, .35, .035), (4150, .25, .02), (600, .2, .03)], 0.95),
        "up":        (0.05, (0.5, 5000, 0.006), [(1800, .2, .012)], 0.35),
        "space":     (0.18, (1.0, 500, 0.030),  [(180, .7, .06), (90, .4, .08)], 1.1),
        "enter":     (0.45, (0.7, 3000, 0.015), [(1250, .3, .04), (3135, .3, .30), (4700, .15, .22)], 1.0),  # ding!
        "backspace": (0.12, (0.8, 4500, 0.010), [(1500, .4, .04), (3000, .25, .025)], 0.9),
    },
}
VARIANTS = {"down": 5, "up": 3}   # everything else renders once

# Per-set Return ding, baked INTO that set's enter.wav (no universal overlay).
# (f0, dur, level) for a struck bell mixed over the enter keystroke; None means
# the set's enter is already its own flourish (typewriter bell / tonal / music).
DINGS = {
    "thock":      (523, 1.10, 0.45),   # soft low bell — matches the creamy body
    "clicky":     (880, 0.90, 0.45),   # bright ping
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
    },
    "water": {  # drip-drop — fast UPWARD pitch bend is the whole illusion
        "down":      (glide, dict(f0=430, f1=1150, dur=0.11, shape="sine", dec=0.045, level=0.55)),
        "up":        (glide, dict(f0=900, f1=1500, dur=0.05, shape="sine", dec=0.02,  level=0.25)),
        "space":     (glide, dict(f0=300, f1=820,  dur=0.16, shape="sine", dec=0.07,  level=0.6)),   # fat plop
        "enter":     (glide, dict(f0=240, f1=680,  dur=0.20, shape="sine", dec=0.09,  level=0.6)),   # deep plunk
        "backspace": (glide, dict(f0=520, f1=1050, dur=0.09, shape="sine", dec=0.035, level=0.5)),
    },
}

def render_themed(base):
    for set_name, keys in THEMED.items():
        d = os.path.join(base, set_name)
        os.makedirs(d, exist_ok=True)
        for key, (fn, kw) in keys.items():
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

def render_musical(base):
    for name, inst in INSTRUMENTS.items():
        d = os.path.join(base, name)
        os.makedirs(d, exist_ok=True)
        # down variants ARE the scale — random pick → pentatonic improvisation
        for i, off in enumerate(SCALE, start=1):
            write_wav(os.path.join(d, f"down{i}.wav"), inst(midi(off)))
        # up: two soft high grace notes (quiet, so release doesn't muddy melody)
        for i in range(1, 3):
            write_wav(os.path.join(d, f"up{i}.wav"),
                      inst(midi(SCALE[-1] + i * 2), dur=0.18, level=0.20))
        write_wav(os.path.join(d, "space.wav"), inst(midi(-5), dur=0.6, level=0.55))     # low root
        write_wav(os.path.join(d, "enter.wav"),                                          # flourish!
                  gliss(inst, [midi(o) for o in SCALE]))
        write_wav(os.path.join(d, "backspace.wav"), inst(midi(SCALE[1]), dur=0.3, level=0.45))
        print(f"  {name}: {len(os.listdir(d))} files")

# --- MECHANICAL sets: rendered by synth_mech, not the sine-stack synth --------
# Each key is synth_mech kwargs. "ding" (f0,dur,level) bakes a bell into enter.
MECH = {
    "telegraph": {   # sounder armature slamming brass — a solid low KATHUNK
        "ding": (880, 0.55, 0.38),   # small office bell on Return
        "keys": {
            "down":      dict(dur=0.14, thump=(230,140,0.95,0.055), impact=(1.0,2600,0.006),
                              ring=[(680,.45,.05),(1350,.28,.03),(2050,.15,.02)], sat=3.0, level=0.82),
            "up":        dict(dur=0.10, thump=(370,270,0.6,0.030), impact=(0.8,3400,0.005),
                              ring=[(1150,.4,.03),(2200,.2,.018)], sat=2.5, level=0.60),   # lighter release clack
            "space":     dict(dur=0.16, thump=(185,120,1.05,0.070), impact=(1.0,2200,0.007),
                              ring=[(560,.4,.05),(1080,.22,.03)], sat=3.0, level=0.88),     # deepest thunk
            "enter":     dict(dur=0.14, thump=(230,140,0.9,0.050), impact=(0.95,2600,0.006),
                              ring=[(700,.4,.05),(1400,.24,.03)], sat=3.0, level=0.80),
            "backspace": dict(dur=0.12, thump=(280,175,0.85,0.040), impact=(0.9,3000,0.006),
                              ring=[(900,.4,.04),(1800,.2,.02)], sat=2.8, level=0.72),
        },
    },
    "manual": {   # heavy manual typewriter — type-bar SLAP then hammer (ka-thunk)
        "ding": (700, 1.10, 0.5),    # hearty carriage return bell
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
        },
    },
}

def render_mech(base):
    for set_name, spec in MECH.items():
        d = os.path.join(base, set_name)
        os.makedirs(d, exist_ok=True)
        ding = spec.get("ding")
        for key, kw in spec["keys"].items():
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

def main():
    base = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 \
        else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(base, exist_ok=True)
    for set_name, keys in SETS.items():
        d = os.path.join(base, set_name)
        os.makedirs(d, exist_ok=True)
        for key, (dur, noise, partials, gain) in keys.items():
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
    render_mech(base)
    render_themed(base)
    render_musical(base)
    print("  (each set's Return ding is baked into its own enter.wav)")

if __name__ == "__main__":
    main()
