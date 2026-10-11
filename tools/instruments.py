"""Physical instrument models for klonk's musical sets, plus the star-voyage console set.

The original musical sets were sine stacks, which read as "toy". These models
copy what makes each real instrument sound like itself:

  harpsichord     a quill plucks a bright brass string near its end. Two 8'
                  choirs a few cents apart plus a quieter 4' octave choir, a
                  plectrum tick on the attack, a soundboard, and the authentic
                  release: the felt damper landing and the jack dropping back.
                  Return plays a rolled chord, as harpsichordists voice them.
  jazz-piano      real recordings: the Open Samples "Dusty Upright Piano"
                  repitched from the nearest sampled A, with an upright bass
                  walking under the mouse. Notes come from a D dorian palette
                  with sixths and a crushed blue note; Return is G13→Cmaj9.
  schmoove-guitar a hollow-body jazz guitar on the neck pickup: plucked
                  strings, strummed extended voicings (m9, 13, maj9, 7b13),
                  short palm-muted comping stabs on keys and a slow arpeggiated
                  Cmaj9 on Return.

Plucked strings use Karplus-Strong with a fractional-delay allpass, so chords
stay in tune in the upper register. The harpsichord follows Valimaki et al.
(2004), whose parameters were fitted to a real instrument. Only jazz-piano uses
recorded samples, fetched from a pinned Open Samples commit and credited in the
set's SOURCE.txt.
Deterministic: seeds derive from crc32, never Python's randomized hash().
"""
import math, os, random, zlib
from generate import SR, write_wav, finish, tag, onepole_lp

AUDIO_EXTS = (".wav", ".aif", ".aiff", ".mp3", ".m4a")


def seeded(*parts):
    random.seed(zlib.crc32(repr(parts).encode()))


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def layer(parts, tail=0.0):
    """Overlap-add [(offset_seconds, samples)] into one buffer."""
    n = max(int(SR * off) + len(x) for off, x in parts) + int(SR * tail)
    buf = [0.0] * n
    for off, x in parts:
        o = int(SR * off)
        for i, v in enumerate(x):
            buf[o + i] += v
    return buf


def fade(x, start, length):
    """Cosine fade to silence beginning at `start` seconds."""
    a, b = int(SR * start), int(SR * (start + length))
    out = x[:b]
    for i in range(a, min(b, len(out))):
        out[i] *= 0.5 * (1 + math.cos(math.pi * (i - a) / (b - a)))
    return out


def resonate(x, bands):
    """Add parallel biquad band-pass resonances: [(freq, q, gain)] — a body."""
    out = x[:]
    for f, q, gain in bands:
        w = 2 * math.pi * f / SR
        alpha = math.sin(w) / (2 * q)
        a0 = 1 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2 * math.cos(w) / a0, (1 - alpha) / a0
        x1 = x2 = y1 = y2 = 0.0
        for i, v in enumerate(x):
            y = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, v, y1, y
            out[i] += gain * y
    return out


def noise_burst(dur, lp, decay, amp=1.0, hp=False):
    n = int(SR * dur)
    raw = [(random.random() * 2 - 1) * math.exp(-i / SR / decay) for i in range(n)]
    low = onepole_lp(raw, lp)
    return [amp * (r - l if hp else l) for r, l in zip(raw, low)]


def ks_string(f, dur, t60, pluck=0.13, bright=0.7, damp=0.5, amp=1.0):
    """Karplus-Strong plucked string.

    pluck  position along the string (0..0.5); a comb notch in the excitation,
           the nasal color of a string plucked near its end.
    bright excitation brightness (0 dark .. 1 raw noise).
    damp   loop-filter weight on the previous sample; higher loses treble faster.
    t60    seconds for the fundamental to fall 60 dB.
    """
    n = int(SR * dur)
    period = SR / f
    L = int(period - damp)
    frac = period - damp - L
    if frac < 0.2:                       # keep the allpass coefficient well-behaved
        L -= 1; frac += 1
    C = (1 - frac) / (1 + frac)
    g = 10 ** (-3 / (f * t60))
    burst = onepole_lp([random.random() * 2 - 1 for _ in range(L)], 400 + bright * 12000)
    P = max(1, int(pluck * L))
    exc = [burst[i] - (burst[i - P] if i >= P else 0.0) for i in range(L)]
    mean = sum(exc) / L
    buf = [e - mean for e in exc]
    out = [0.0] * n
    idx, prev, ax, ay = 0, 0.0, 0.0, 0.0
    for i in range(n):
        x = buf[idx]
        out[i] = x
        lp = (1 - damp) * x + damp * prev
        prev = x
        y = C * lp + ax - C * ay          # first-order allpass: fractional delay
        ax, ay = lp, y
        buf[idx] = y * g
        idx += 1
        if idx == L:
            idx = 0
    return [s * amp for s in out]


# --- harpsichord: Valimaki et al., "Model-based sound synthesis of the harpsichord" --
# Joint Baltic-Nordic Acoustics Meeting 2004. Parameters below are the paper's
# values, estimated from recordings of a two-manual Knif/Pelto harpsichord
# (8' back, 8' front, 4'): loop gain and one-pole loss coefficient per key
# (eqs. 3-4), plucking point moving from 12% of the string in the bass to 50% in
# the treble, a separate release sound on key-up, and the soundboard as an
# 8-branch feedback delay network (Table 1) behind a 350 Hz high-pass.
# Tuned to A4 = 415 Hz, the baroque pitch the paper's instrument used.
A415 = 415.0


def harpsi_hz(m):
    return A415 * 2 ** ((m - 69) / 12)


def harpsi_string(m, dur, choir="back", amp=1.0):
    k = min(56, max(1, m - 30))                        # key 1 = G1 … key 56 = D6
    f = harpsi_hz(m) * {"back": 2 ** (-1.2 / 1200), "front": 2 ** (1.2 / 1200), "four": 2.0}[choir]
    g = 0.9953 + 0.00005559 * k                        # eq. 3
    a = -0.1323 + 0.008276 * k if k <= 10 else -0.04713 + 0.000683 * k   # eq. 4
    b = g * (1 + a)
    pluck = 0.12 + 0.38 * (k - 1) / 55                 # 12% bass → 50% treble
    if choir == "front":
        pluck = min(0.5, pluck * 1.25)                 # front register plucks farther from the nut
    period = SR / f
    w = 2 * math.pi * f / SR
    loss_delay = math.atan2(-a * math.sin(w), 1 + a * math.cos(w)) / w
    L = int(period - loss_delay)
    frac = period - loss_delay - L
    if frac < 0.2:
        L -= 1; frac += 1
    C = (1 - frac) / (1 + frac)
    # Excitation: the quill scraping the string, comb-notched at the pluck point.
    burst = onepole_lp([random.random() * 2 - 1 for _ in range(L)], 9000)
    P = max(1, int(pluck * L))
    exc = [burst[i] - (burst[i - P] if i >= P else 0.0) for i in range(L)]
    mean = sum(exc) / L
    buf = [e - mean for e in exc]
    n = int(SR * dur)
    out = [0.0] * n
    idx, y1, ax, ay = 0, 0.0, 0.0, 0.0
    for i in range(n):
        x = buf[idx]
        out[i] = x
        y1 = b * x - a * y1                            # H(z) = b / (1 + a z^-1)
        y = C * y1 + ax - C * ay                       # allpass fractional delay
        ax, ay = y1, y
        buf[idx] = y
        idx += 1
        if idx == L:
            idx = 0
    return [v * amp for v in out]


FDN = [(1009, 0.971945, 0.094931, 81), (1109, 0.969209, 0.104272, 89), (1237, 0.965723, 0.116181, 99),
       (1373, 0.962024, 0.128829, 110), (1489, 0.958890, 0.139552, 119), (1609, 0.955641, 0.150669, 129),
       (1741, 0.952105, 0.162769, 139), (1999, 0.945195, 0.186397, 160)]   # paper Table 1


def soundboard(x, tail=1.2, g_fb=-0.25, a_ap=0.5):
    """The paper's soundboard reverb: 8 delay lines, each with a one-pole loss
    filter and a comb allpass. Each line feeds back its own output plus g_fb times
    the sum of all outputs; with g_fb = -2/8 that is a lossless Householder
    matrix, so the per-branch loss filters alone set the decay."""
    n = len(x) + int(SR * tail)
    lines = [[0.0] * P for P, _, _, _ in FDN]
    aps = [[0.0] * M for _, _, _, M in FDN]
    lp = [0.0] * 8
    pos = [0] * 8
    apos = [0] * 8
    signs = [-1, -1, 1, 1, -1, -1, 1, 1]
    fb = 0.0
    out = [0.0] * n
    for i in range(n):
        v = (x[i] if i < len(x) else 0.0) + g_fb * fb
        total = acc = 0.0
        for k in range(8):
            P, gh, ah, M = FDN[k]
            d = lines[k][pos[k]]
            lp[k] = gh * (1 - ah) * d + ah * lp[k]                  # eq. 5
            # comb allpass A(z) = (a + z^-M) / (1 + a z^-M), stored as its internal state
            w_old = aps[k][apos[k]]
            w_new = lp[k] - a_ap * w_old
            y = a_ap * w_new + w_old
            aps[k][apos[k]] = w_new
            apos[k] = (apos[k] + 1) % M
            lines[k][pos[k]] = v + y
            pos[k] = (pos[k] + 1) % P
            total += y
            acc += signs[k] * y
        fb = total
        out[i] = acc
    return out


def highpass(x, f, q=0.707):
    w = 2 * math.pi * f / SR
    alpha = math.sin(w) / (2 * q)
    a0 = 1 + alpha
    b0, b1, b2 = (1 + math.cos(w)) / 2 / a0, -(1 + math.cos(w)) / a0, (1 + math.cos(w)) / 2 / a0
    a1, a2 = -2 * math.cos(w) / a0, (1 - alpha) / a0
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for v in x:
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out.append(y)
    return out


def harpsichord(notes, dur=1.1, level=0.6, tick=True, board=0.22):
    """notes = [(offset_s, midi)]. Strings for every note, then ONE soundboard
    pass over the mix (the soundboard is linear, so this equals per-note)."""
    parts = []
    for off, m in notes:
        parts.append((off, harpsi_string(m, dur, "back")))
        parts.append((off + 0.002, harpsi_string(m, dur, "front", 0.85)))
        parts.append((off + 0.004, harpsi_string(m + 12, dur, "four", 0.3) if m < 74 else [0.0]))
        if tick:
            parts.append((off, noise_burst(0.006, 3000, 0.0012, amp=0.25, hp=True)))   # quill
    direct = layer(parts)
    body = highpass(highpass(soundboard(direct), 350), 350)                         # tone corrector
    peak_d = max(abs(v) for v in direct) or 1.0
    peak_b = max(abs(v) for v in body) or 1.0
    mixed = [v / peak_d + (body[i] / peak_b * board) for i, v in enumerate(direct + [0.0] * (len(body) - len(direct)))]
    total = len(mixed) / SR
    return finish(fade(mixed, total * 0.55, total * 0.45), level, td=0.03)


def harpsichord_release(level=0.10):
    """Key-up: the felt damper lands on the string, then the jack drops back."""
    thud = noise_burst(0.04, 500, 0.006)
    click = noise_burst(0.006, 3000, 0.0008, amp=0.5, hp=True)
    return finish(layer([(0.0, thud), (0.014, click)]), level)


def render_harpsichord(d):
    melody = [62, 65, 67, 69, 72, 74, 77, 81]          # D minor pentatonic, D4..A5
    files = {f"down{i}": harpsichord([(0, m)]) for i, m in enumerate(melody, 1)}
    files.update({f"up{i}": harpsichord_release(0.08 + 0.02 * i) for i in (1, 2)})
    files["space"] = harpsichord([(0, 50)], 1.3, 0.55)
    files["backspace"] = harpsichord([(0, 69), (0.055, 67), (0.11, 69)], 0.7, 0.5)            # mordent
    files["enter"] = harpsichord([(i * 0.045, m) for i, m in enumerate([50, 57, 62, 65, 69, 74])], 1.7, 0.62)  # rolled Dm
    files.update({f"click{i}": harpsichord([(0, m)], 0.9, 0.5) for i, m in enumerate([50, 45, 53], 1)})
    files["clickup"] = harpsichord_release(0.08)
    files["rightclick"] = harpsichord([(0, 38), (0.004, 50)], 1.1, 0.5)
    files.update({f"scroll{i}": harpsichord([(0, m)], 0.16, 0.14, board=0.0) for i, m in enumerate([81, 84], 1)})
    return files


# --- sampled instruments: Open Samples (github.com/pumodi/open-samples) ---------------
# Real recordings, repitched from the nearest sampled note the way a sampler does.
# Downloads are pinned to one commit and cached; nothing is fetched at runtime.
OPEN_SAMPLES_COMMIT = "a7eab6788701ffaccf9790fbf91e0bbac2f2ef27"
OPEN_SAMPLES_CACHE = os.path.expanduser("~/.cache/klonk/open-samples")
UPRIGHT = {  # measured pitch of each source note (this upright runs a little sharp)
    45.06: "Pianos/Dusty Upright PIano/Samples/uprightPiano_A2.wav",
    57.14: "Pianos/Dusty Upright PIano/Samples/uprightPiano_A3.wav",
    69.17: "Pianos/Dusty Upright PIano/Samples/uprightPiano_A4.wav",
    81.17: "Pianos/Dusty Upright PIano/Samples/uprightPiano_A5.wav",
}
UPRIGHT_BASS = {26.61: "StringedInstruments/Bohemian Upright Bass/Samples/brokenUprightBass.wav"}
_loaded = {}


FREEPATS_BAGPIPE_COMMIT = "496f2f6e82f226d650e270c0f0ad5febbebec249"
SOURCES = {  # path prefix -> raw URL base, each pinned to one commit
    "freepats-bagpipe:": f"https://raw.githubusercontent.com/freepats/bagpipe/{FREEPATS_BAGPIPE_COMMIT}/",
    "": f"https://raw.githubusercontent.com/pumodi/open-samples/{OPEN_SAMPLES_COMMIT}/",
}


def open_sample(path):
    """Fetch (once) and decode a pinned sample (WAV or FLAC) to mono 44.1 kHz floats."""
    if path in _loaded:
        return _loaded[path]
    import subprocess, urllib.parse, urllib.request, wave as wavmod
    os.makedirs(OPEN_SAMPLES_CACHE, exist_ok=True)
    key = zlib.crc32(path.encode())
    raw = os.path.join(OPEN_SAMPLES_CACHE, f"{key:08x}.src.wav")
    mono = os.path.join(OPEN_SAMPLES_CACHE, f"{key:08x}.wav")
    if not os.path.exists(mono):
        prefix = next(p for p in SOURCES if path.startswith(p))
        url = SOURCES[prefix] + urllib.parse.quote(path[len(prefix):])
        urllib.request.urlretrieve(url, raw)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", raw, mono], check=True)
    with wavmod.open(mono) as w:
        frames = w.readframes(w.getnframes())
    data = [v / 32768 for v in memoryview(frames).cast("h")]
    start = next(i for i, v in enumerate(data) if abs(v) > 0.02)          # trim lead-in silence
    _loaded[path] = data[max(0, start - 64):]
    return _loaded[path]


def sampled(table, m, dur, vel=0.7, level=0.6, release=0.08):
    """Play MIDI note m from the nearest recorded note, resampled to pitch."""
    root = min(table, key=lambda r: abs(r - m))
    src = open_sample(table[root])
    ratio = 2 ** ((m - root) / 12)
    n = min(int(SR * dur), int((len(src) - 2) / ratio))
    out = []
    for i in range(n):
        p = i * ratio
        j = int(p)
        out.append(src[j] + (src[j + 1] - src[j]) * (p - j))
    if vel < 0.9:                                      # softer touch = darker tone
        out = onepole_lp(out, 1500 + vel * 9000)
    out = fade(out, max(0.0, n / SR - release), release)
    return finish(out, level * (0.55 + 0.45 * vel), td=0.005)


def upright(m, dur=1.0, vel=0.7, level=0.6):
    return sampled(UPRIGHT, m, dur, vel, level)


def chord(midis, dur, vel=0.55, roll=0.008, level=0.55, voice=None):
    voice = voice or upright
    return finish(layer([(i * roll, voice(m, dur, vel)) for i, m in enumerate(midis)]), level)


def render_jazz_piano(d):
    files = {}
    singles = [62, 65, 67, 69, 72, 74]                  # D dorian, with the blue note as a grace
    for i, m in enumerate(singles, 1):
        files[f"down{i}"] = upright(m, 0.9, vel=0.55 + 0.08 * (i % 3))
    files["down7"] = chord([65, 74], 0.9, vel=0.6, roll=0.0, level=0.6)     # sixth
    files["down8"] = chord([69, 77], 0.9, vel=0.55, roll=0.0, level=0.6)    # sixth
    files["down9"] = finish(layer([(0.0, upright(68, 0.1, 0.45)), (0.035, upright(69, 0.9, 0.65))]), 0.6)  # crushed blue note
    files.update({f"up{i}": harpsichord_release(0.04 + 0.01 * i) for i in (1, 2)})          # felt damper
    files["space"] = chord([53, 57, 60, 64], 1.1, vel=0.45, roll=0.01, level=0.5)           # rootless Dm9
    files["backspace"] = finish(layer([(0.0, upright(69, 0.2, 0.55)), (0.06, upright(68, 0.2, 0.5)),
                                       (0.12, upright(67, 0.6, 0.55))]), 0.5)
    files["enter"] = finish(layer([(0.0, chord([53, 59, 64, 69], 0.4, vel=0.6)),
                                   (0.34, chord([52, 55, 59, 62, 69], 1.6, vel=0.65, roll=0.012))]), 0.62)  # G13 → Cmaj9
    bass = lambda m, dur=0.9: sampled(UPRIGHT_BASS, m, dur, 0.9, 0.7, release=0.12)
    files.update({f"click{i}": bass(m) for i, m in enumerate([26, 29, 31], 1)})               # walking upright bass
    files["clickup"] = harpsichord_release(0.04)
    files["rightclick"] = bass(24, 1.1)
    files.update({f"scroll{i}": upright(m, 0.22, 0.35, 0.2) for i, m in enumerate([81, 84], 1)})
    return files


# --- Wurlitzer 200A: the soul/jazz electric piano, real reed recordings -------
NOTE_PC = {"c": 0, "db": 1, "d": 2, "eb": 3, "e": 4, "f": 5, "gb": 6, "g": 7, "ab": 8, "a": 9, "bb": 10, "b": 11}
WURLI_DIR = "Keyboards/Electric Pianos/Samples/Wurlitzer 200A Electric Piano Samples/raw/"
WURLI_FILES = ("Ab3_f B2_f C2_f Db4_f E3_f F2_f a1_f a1_ff a1_mp a1_pp a2_mp ab2_pp ab3_ff ab3_mp ab3_pp "
               "ab4_f ab6_f ab6_mp b2_ff b4_mp c2_ff db4_ff db4_mp db4_pp db5_f db5_ff db5_mp db5_pp db6_f "
               "db6_mp e2_mp e3_ff e4_ff eb3_mp eb3_pp f2_ff g4_ff g4_pp g5_f g5_ff g5_mp gb4_mp").split()


def note_midi(name):
    """'db4' -> 61, 'A1' -> 33 (scientific pitch, as the Wurlitzer files are named)."""
    name = name.lower()
    pc = name.rstrip("0123456789")
    return 12 * (int(name[len(pc):]) + 1) + NOTE_PC[pc]


def wurli_table(dynamic):
    return {note_midi(f.split("_")[0]): WURLI_DIR + f + ".wav"
            for f in WURLI_FILES if f.split("_")[1] == dynamic}


def wurli(m, dur=0.9, dynamic="mp", level=0.6):
    # each dynamic is a different recording, not a filter: hard hits bark
    return sampled(wurli_table(dynamic), m, dur, 1.0, level, release=0.1)


def render_wurlitzer(d):
    files = {}
    melody = [60, 63, 65, 67, 70, 72, 74, 75]           # C minor pentatonic plus the 9th
    for i, m in enumerate(melody, 1):
        files[f"down{i}"] = wurli(m, 0.9, "mp")
    files.update({f"up{i}": harpsichord_release(0.03 + 0.01 * i) for i in (1, 2)})           # key thump
    files["space"] = chord([63, 67, 70, 74], 1.2, roll=0.012, level=0.55,
                           voice=lambda m, dur, vel: wurli(m, dur, "mp"))                    # rootless Cm9
    files["backspace"] = finish(layer([(0.0, wurli(75, 0.2)), (0.07, wurli(74, 0.2)), (0.14, wurli(72, 0.6))]), 0.5)
    pow_ = chord([46, 68, 74, 79], 0.45, roll=0.0, level=1.0, voice=lambda m, dur, vel: wurli(m, dur, "ff"))
    land = chord([48, 63, 67, 70, 74], 1.7, roll=0.015, level=1.0, voice=lambda m, dur, vel: wurli(m, dur, "f"))
    files["enter"] = finish(layer([(0.0, pow_), (0.38, land)]), 0.62)                        # Bb13 bark → Cm9
    files.update({f"click{i}": wurli(m, 0.8, "f", 0.6) for i, m in enumerate([36, 41, 43], 1)})   # low reeds
    files["clickup"] = harpsichord_release(0.03)
    files["rightclick"] = wurli(36, 1.0, "ff", 0.6)
    files.update({f"scroll{i}": wurli(m, 0.25, "pp", 0.2) for i, m in enumerate([85, 87], 1)})
    return files


# --- hard-drive music box: a paper-tape music box gaffer-taped to an empty hard
# drive case. G#/Ab major, every note recorded twice — both takes are used, so
# repeats alternate between two real strikes instead of one sample.
MUSICBOX_DIR = "MusicBoxes/Samples/hardDriveMusicBox/musicBox_"


def music_box(name, take=1, dur=1.6, level=0.6):
    return sampled({0: f"{MUSICBOX_DIR}{name}_L-00{take}.wav"}, 0, dur, 1.0, level, release=0.4)


def render_music_box(d):
    files = {}
    tune = ["C5", "Eb5", "F5", "Ab5", "Bb5", "C6", "Eb6", "F6"]   # Ab major pentatonic
    for i, n in enumerate(tune):
        for take in (1, 2):
            files[f"down{i * 2 + take}"] = music_box(n, take)
    files["space"] = music_box("Ab4", 1, 2.0)
    files["backspace"] = finish(layer([(0.0, music_box("G5", 1, 0.5)), (0.11, music_box("F5", 2, 1.4))]), 0.55)
    files["enter"] = finish(layer([(i * 0.075, music_box(n, 1 + i % 2, 2.4))
                                   for i, n in enumerate(["Ab4", "C5", "Eb5", "Ab5", "C6", "Eb6", "Ab6"])]), 0.62)
    files["click1"] = music_box("Ab4", 2, 1.2)
    files["click2"] = music_box("Bb4", 1, 1.2)
    files["rightclick"] = finish(layer([(0.0, music_box("Ab4", 1, 1.4)), (0.0, music_box("Eb5", 2, 1.4))]), 0.6)
    files.update({f"scroll{i}": music_box(n, i, 0.4, 0.2) for i, n in enumerate(["G6", "Ab6"], 1)})
    return files     # no up files: a music box is silent when you let go


# --- bagpipe in G: FreePats recordings (CC0), chanter plus separately recorded drones
# Thin bagpipe = chanter without drones. Every note here sits on both drones,
# opens with the high-G gracenote pipers put before melody notes, and Return
# plays a run to a held high G.
BAGPIPE = {note_midi(n.replace("#", "").lower()) + (1 if "#" in n else 0): f"freepats-bagpipe:samples/{n}_31.flac"
           for n in ["G4", "A4", "A#4", "B4", "C5", "C#5", "D5", "D#5", "E5", "F5", "F#5", "G5"]}


def drones(dur, level=1.0):
    g2 = sampled({43: "freepats-bagpipe:samples/drone_G2_1.flac"}, 43, dur, 1.0, 1.0, release=0.15)
    g3 = sampled({55: "freepats-bagpipe:samples/drone_G3_3.flac"}, 55, dur, 1.0, 1.0, release=0.15)
    return [level * (a + b) for a, b in zip(g2, g3)]


def xfade_join(a, b, xf):
    """Append b to a with an equal-power crossfade of xf samples."""
    out = a[:-xf]
    for i in range(xf):
        w = i / xf
        out.append(a[len(a) - xf + i] * math.cos(w * math.pi / 2) + b[i] * math.sin(w * math.pi / 2))
    return out + b[xf:]


def seamless_loop(x, length, xf):
    """Tile x (equal-power joins) to length+xf, then fold the tail over the head
    so playback can loop with no seam."""
    buf = x[:]
    while len(buf) < length + xf:
        buf = xfade_join(buf, x, xf)
    out = buf[:length]
    for i in range(xf):
        w = i / xf
        out[i] = buf[length + i] * math.cos(w * math.pi / 2) + out[i] * math.sin(w * math.pi / 2)
    return out


def drone_loop(seconds=8.0):
    """Both drones as one seamless loop: the engine holds it from the first key
    until Return (the set's sustain.wav)."""
    trim = lambda x, a, b: x[int(SR * a):len(x) - int(SR * b)]
    g2 = trim(open_sample("freepats-bagpipe:samples/drone_G2_1.flac"), 0.15, 0.1)
    g3 = trim(open_sample("freepats-bagpipe:samples/drone_G3_3.flac"), 0.3, 0.2)
    n, xf = int(SR * seconds), int(SR * 0.4)
    a, b = seamless_loop(g2, n, xf), seamless_loop(g3, n, xf)
    return [u + v for u, v in zip(a, b)]


def pipe(m, dur=0.4, grace=True, drone=0.0, level=0.6):
    parts = []
    t = 0.0
    if grace:
        parts.append((0.0, sampled(BAGPIPE, 79, 0.035, 1.0, 0.8, release=0.01)))   # high-G gracenote
        t = 0.03
    parts.append((t, sampled(BAGPIPE, m, dur, 1.0, 1.0, release=0.08)))
    if drone:
        parts.append((0.0, drones(dur + t, drone)))
    return finish(layer(parts), level, td=0.02)


def render_bagpipe(d):
    files = {}
    tune = [67, 69, 71, 72, 74, 76, 77, 79]             # G mixolydian, the pipe's own scale
    for i, m in enumerate(tune, 1):
        files[f"down{i}"] = pipe(m)
    files["space"] = pipe(67, 0.5)                      # low G
    files["sustain"] = drone_loop()
    birl = [69, 67, 69, 67, 69]                         # the birl: a low-A flourish
    files["backspace"] = finish(layer([(i * 0.04, sampled(BAGPIPE, m, 0.06, 1.0, 1.0, release=0.01))
                                       for i, m in enumerate(birl)]), 0.55)
    run = [(i * 0.09, pipe(m, 0.12, grace=False, drone=0.0, level=1.0)) for i, m in enumerate([67, 71, 74])]
    hold = (0.27, pipe(79, 1.4, grace=True, drone=0.0, level=1.0))
    files["enter"] = finish(layer(run + [hold, (0.0, drones(1.7, 0.45))]), 0.62)
    files.update({f"click{i}": pipe(m, 0.25, grace=False) for i, m in enumerate([69, 67], 1)})
    files["rightclick"] = pipe(74, 0.4)
    files.update({f"scroll{i}": finish(sampled(BAGPIPE, m, 0.05, 1.0, 1.0, release=0.02), 0.15)
                  for i, m in enumerate([79, 81], 1)})
    return files     # no up files: release is silence


# --- General MIDI instruments: FluidSynth + GeneralUser GS (S. Christian Collins) -----
# One renderer opens the whole General MIDI orchestra: write a tiny MIDI file,
# render it dry (no reverb or chorus) through the pinned bank, decode to mono.
GUGS_COMMIT = "684543d5e5efaef08d02be50dcda8d552478fa60"
GUGS_SHA256 = "9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe"
SOUNDFONT = os.path.expanduser("~/.cache/klonk/soundfonts/GeneralUser-GS.sf2")
GUGS_CREDIT = ("Rendered with FluidSynth from GeneralUser GS v2.0.3 by S. Christian Collins\n"
               "(github.com/mrbumpy409/GeneralUser-GS, commit " + GUGS_COMMIT[:10] + "), which its license\n"
               "allows in software projects, private or commercial.\n")


def soundfont():
    import hashlib, urllib.request
    if not os.path.exists(SOUNDFONT):
        os.makedirs(os.path.dirname(SOUNDFONT), exist_ok=True)
        urllib.request.urlretrieve("https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/"
                                   f"{GUGS_COMMIT}/GeneralUser-GS.sf2", SOUNDFONT)
    with open(SOUNDFONT, "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != GUGS_SHA256:
            raise SystemExit(f"{SOUNDFONT} does not match the pinned GeneralUser GS checksum")
    return SOUNDFONT


def _vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, (n & 0x7F) | 0x80)
        n >>= 7
    return bytes(out)


def gm(program, notes, level=0.6, bank=0, drums=False, tail=0.3, gain=0.7, hall=False):
    """Render [(start_s, midi, length_s, velocity)] on a General MIDI program.
    drums=True plays channel 10 with `program` choosing the kit (25 = TR-808).
    hall=True renders with a large, slow reverb (cathedral) instead of dry."""
    import struct, subprocess, tempfile, wave as wavmod
    ch = 9 if drums else 0
    tick = lambda t: int(round(t * 960))            # 480 PPQ at 120 bpm: 960 ticks per second
    events = [(0, bytes([0xB0 | ch, 0, 128 if drums else bank])), (0, bytes([0xC0 | ch, program]))]
    for start, m, length, vel in notes:
        events.append((tick(start), bytes([0x90 | ch, m, vel])))
        events.append((tick(start + length), bytes([0x80 | ch, m, 0])))
    events.sort(key=lambda e: e[0])
    body, now = b"", 0
    for t, data in events:
        body += _vlq(t - now) + data
        now = t
    body += _vlq(tick(tail)) + b"\xFF\x2F\x00"
    midi = b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) + b"MTrk" + struct.pack(">I", len(body)) + body
    with tempfile.TemporaryDirectory() as tmp:
        mid, raw, mono = (os.path.join(tmp, n) for n in ("in.mid", "out.wav", "mono.wav"))
        open(mid, "wb").write(midi)
        room = ["-R", "1", "-o", "synth.reverb.room-size=0.95", "-o", "synth.reverb.damp=0.25",
                "-o", "synth.reverb.width=1.0", "-o", "synth.reverb.level=0.85"] if hall else ["-R", "0"]
        subprocess.run(["fluidsynth", "-ni", "-q", *room, "-C", "0", "-g", str(gain), "-r", str(SR),
                        "-F", raw, soundfont(), mid], check=True, capture_output=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", raw, mono], check=True)
        with wavmod.open(mono) as w:
            data = [v / 32768 for v in memoryview(w.readframes(w.getnframes())).cast("h")]
    start = next((i for i, v in enumerate(data) if abs(v) > 0.003), 0)
    end = max(notes, key=lambda n: n[0] + n[2])
    data = data[max(0, start - 32):max(0, start - 32) + int(SR * (end[0] + end[2] + tail))]
    return finish(fade(data, max(0.0, len(data) / SR - 0.06), 0.06), level, td=0.005)


# --- funk slap bass: thumb slaps, popped octaves, ghost notes on release -----------------
SLAP, POP = 36, 37                                 # GM Slap Bass 1 (thumb), Slap Bass 2 (pop)


def render_slap_bass(d):
    files = {}
    thumb = [40, 43, 45, 47, 50, 52]                   # E minor pentatonic, the funk home key
    for i, m in enumerate(thumb, 1):
        files[f"down{i}"] = gm(SLAP, [(0, m, 0.22, 118)])
    files["down7"] = gm(POP, [(0, 52, 0.18, 120)])      # popped octave
    files["down8"] = gm(POP, [(0, 57, 0.18, 120)])
    files.update({f"up{i}": gm(SLAP, [(0, m, 0.04, 34)], level=0.25, tail=0.08)        # ghost notes
                  for i, m in enumerate([40, 45], 1)})
    files["space"] = gm(SLAP, [(0, 40, 0.1, 124)] + [(0.09, 52, 0.2, 120)], level=0.6)  # slap low, pop octave
    files["backspace"] = gm(SLAP, [(0, 43, 0.07, 110), (0.07, 45, 0.25, 116)])        # hammer-on
    lick = [(0.0, 40, 0.1, 124), (0.11, 52, 0.08, 118), (0.2, 43, 0.08, 110), (0.27, 45, 0.08, 116),
            (0.36, 47, 0.08, 118), (0.47, 40, 0.6, 127), (0.47, 52, 0.6, 127)]
    files["enter"] = gm(SLAP, lick, level=0.62, tail=0.4)                              # ...POW
    files.update({f"click{i}": gm(SLAP, [(0, m, 0.05, 50)], level=0.35, tail=0.1)
                  for i, m in enumerate([40, 43, 45], 1)})
    files["clickup"] = gm(SLAP, [(0, 40, 0.03, 26)], level=0.15, tail=0.05)
    files["rightclick"] = gm(POP, [(0, 52, 0.2, 124)])
    files.update({f"scroll{i}": gm(SLAP, [(0, m, 0.03, 30)], level=0.12, tail=0.05)
                  for i, m in enumerate([55, 57], 1)})
    return files


# --- Gregorian chant: monks in D dorian over an organum drone, in a cathedral -------
CHOIR, OOH = 52, 53                                # GM Choir Aahs, Voice Oohs


def chant(notes, level=0.6, tail=1.6, voice=CHOIR):
    """notes = [(start_s, midi, length_s)] sung legato, in the hall."""
    return gm(voice, [(t, m, length, 88) for t, m, length in notes], level, tail=tail, hall=True, gain=0.6)


def render_gregorian(d):
    files = {}
    mode = [50, 52, 53, 55, 57, 60, 62]               # D dorian, D3-D4: the first mode
    for i, m in enumerate(mode, 1):
        files[f"down{i}"] = chant([(0, m, 0.45)])
    files["down8"] = chant([(0, 57, 0.22), (0.22, 55, 0.4)])           # a falling two-note neume
    files["space"] = chant([(0, 53, 0.25), (0.25, 55, 0.5)])           # podatus, rising
    files["backspace"] = chant([(0, 57, 0.2), (0.2, 55, 0.2), (0.4, 53, 0.4)])
    amen = [(0, 60, 0.35), (0.35, 57, 0.35), (0.7, 55, 0.4),          # melisma down...
            (1.1, 52, 0.55), (1.65, 50, 1.4), (1.65, 57, 1.4)]         # A-men: the final, in fifths
    files["enter"] = chant(amen, level=0.62, tail=2.2)
    files.update({f"click{i}": chant([(0, m, 0.35)], 0.5, voice=OOH) for i, m in enumerate([50, 45], 1)})
    files["rightclick"] = chant([(0, 38, 0.6), (0, 45, 0.6)], 0.5, voice=OOH)
    files.update({f"scroll{i}": chant([(0, m, 0.12)], 0.15, tail=0.6, voice=OOH) for i, m in enumerate([62, 64], 1)})
    # The held organum: low D and A in fifths, rendered long and looped seamlessly.
    drone = gm(OOH, [(0, 38, 11.0, 70), (0, 45, 11.0, 64)], 1.0, tail=0.5, hall=True, gain=0.6)
    files["sustain"] = seamless_loop(drone[int(SR * 1.5):int(SR * 10.5)], int(SR * 8.0), int(SR * 0.5))
    return files     # no up files: release is the cathedral's tail


# --- schmoove guitar -------------------------------------------------------------
def guitar_string(m, dur, t60=1.6, pick=0.22, amp=1.0):
    return ks_string(hz(m), dur, t60, pluck=pick, bright=0.4, damp=0.55, amp=amp)


def strum(midis, dur, gap=0.011, up=False, vel=1.0, mute_at=None, t60=1.6, level=0.55):
    order = list(reversed(midis)) if up else list(midis)
    parts = [(i * gap, guitar_string(m, dur, t60, amp=vel * random.uniform(0.85, 1.0)))
             for i, m in enumerate(order)]
    s = onepole_lp(layer(parts)[:int(SR * dur)], 2600)                      # neck pickup
    s = resonate(s, [(110, 3, 0.18), (230, 4, 0.14)])                        # hollow body
    if mute_at:
        s = fade(s, mute_at, 0.07)
    return finish(s, level, td=0.01)


def chuck(level=0.25):
    """Fretting hand lays across the strings: a percussive, pitchless scratch."""
    dead = [guitar_string(m, 0.06, t60=0.04, amp=0.6) for m in (45, 50, 55, 59)]
    scratch = noise_burst(0.03, 1800, 0.006, amp=0.7)
    return finish(layer([(i * 0.004, x) for i, x in enumerate(dead)] + [(0.0, scratch)]), level)


VOICINGS = {
    "Dm9":   [50, 53, 60, 64],
    "G13":   [43, 53, 59, 64],
    "Cmaj9": [48, 52, 59, 62],
    "A7b13": [45, 55, 61, 65],
    "Fmaj7": [41, 52, 57, 60],
    "Em9":   [52, 55, 62, 66],
}


def render_schmoove_guitar(d):
    files = {}
    for i, name in enumerate(VOICINGS, 1):
        files[f"down{i}"] = strum(VOICINGS[name], 0.5, vel=0.9, mute_at=0.2, level=0.5)
    files["down7"] = strum(VOICINGS["Dm9"], 0.45, up=True, gap=0.008, vel=0.7, mute_at=0.16, level=0.42)
    files["down8"] = strum(VOICINGS["Cmaj9"], 0.45, up=True, gap=0.008, vel=0.7, mute_at=0.16, level=0.42)
    files.update({f"up{i}": chuck(0.09 + 0.02 * i) for i in (1, 2)})
    files["space"] = strum([45], 0.7, t60=1.0, level=0.5)                     # thumb on the A string
    files["backspace"] = finish(layer([(0.0, strum([49, 53, 60, 63], 0.14, mute_at=0.08)),
                                       (0.09, strum([48, 52, 59, 62], 0.5, mute_at=0.3))]), 0.5)  # half-step slide
    files["enter"] = strum([48, 52, 59, 62, 67], 2.2, gap=0.055, t60=2.4, level=0.58)      # slow Cmaj9
    files.update({f"click{i}": chuck(0.22 + 0.03 * i) for i in (1, 2, 3)})
    files["clickup"] = chuck(0.06)
    files["rightclick"] = strum([40], 0.6, t60=1.0, level=0.5)                 # low E
    files.update({f"scroll{i}": finish(guitar_string(m, 0.3, 0.6, pick=0.5), 0.12)   # harmonic ping
                  for i, m in enumerate([76, 79], 1)})
    return files


OPEN_SAMPLES_CREDIT = (
    "Recorded samples from Open Samples (github.com/pumodi/open-samples, commit "
    + OPEN_SAMPLES_COMMIT[:10] + "), Jeffrey Brice and contributors, under the Open Samples\n"
    "Permissive Use Public License v2: royalty free for sound playback; not to be resold or\n"
    "repackaged for sale. Klonk is free and redistributes these derived sounds non-commercially.\n")

MODELS = {
    "harpsichord": (render_harpsichord,
        "Synthesized: a physical model of a two-manual harpsichord (8' back, 8' front, 4')\n"
        "after Valimaki, Penttinen, Laurson, Erkut, and Knif, \"Model-based sound synthesis of\n"
        "the harpsichord\", Joint Baltic-Nordic Acoustics Meeting 2004: per-key loop gain and\n"
        "loss filter (eqs. 3-4), 12%-50% plucking point, 8-branch soundboard network (Table 1)\n"
        "behind a 350 Hz high-pass, and a damper release on key-up. Tuned to A4 = 415 Hz.\n"
        "No samples.\n"),
    "jazz-piano": (render_jazz_piano,
        "Sampled: keys and chords play the Open Samples 'Dusty Upright Piano' (A2-A5,\n"
        "repitched to the nearest note and tuned against each sample's measured pitch);\n"
        "mouse clicks walk a bass line on the 'Bohemian Upright Bass'. Key-up is a synthesized\n"
        "felt damper.\n" + OPEN_SAMPLES_CREDIT),
    "wurlitzer": (render_wurlitzer,
        "Sampled: the Open Samples 'Wurlitzer 200A Electric Piano' raw reed recordings at four\n"
        "dynamics (pp, mp, f, ff). Keys play the mellow mp takes in C minor pentatonic; Space is\n"
        "a rootless Cm9; Return barks a hard-hit Bb13 into Cm9; clicks are low reeds. Key-up is\n"
        "a synthesized key thump.\n" + OPEN_SAMPLES_CREDIT),
    "hard-drive-music-box": (render_music_box,
        "Sampled: the Open Samples 'Hard Drive Music Box', a paper-tape music box gaffer-taped\n"
        "to an empty hard drive case, recorded in G#/Ab major with two takes per note; both\n"
        "takes are used. Return rolls an Ab major arpeggio. Played as recorded, not repitched.\n"
        + OPEN_SAMPLES_CREDIT),
    "bagpipe": (render_bagpipe,
        "Sampled: FreePats 'Bagpipe in G' (github.com/freepats/bagpipe, commit "
        + FREEPATS_BAGPIPE_COMMIT[:10] + "), recorded\n"
        "August 2020 by Gilles Sadowski on a bagpipe designed by Remy Dubois and built by Olle\n"
        "Geris. sustain.wav loops both drones (G2, G3): the first key or click starts them,\n"
        "they hold under every note, and Return ends them with a run to a held high G.\n"
        "Chanter notes open with a high-G gracenote; Backspace is a birl. CC0 public domain.\n"),
    "slap-bass": (render_slap_bass,
        "Funk slap bass: thumb slaps in E minor pentatonic on keys, popped octaves, ghost notes\n"
        "on key release, slap-pop octave on Space, a hammer-on on Backspace, a lick ending in a\n"
        "big octave on Return.\n" + GUGS_CREDIT),
    "gregorian": (render_gregorian,
        "Gregorian chant: choir voices singing D dorian (the first mode) in a cathedral\n"
        "reverb. sustain.wav holds an organum drone, low D and A in fifths, from the first key\n"
        "until Return, which sings a falling melisma to an Amen on the final. Neumes on Space,\n"
        "Backspace, and one key.\n" + GUGS_CREDIT),
    "schmoove-guitar": (render_schmoove_guitar,
        "Synthesized: a hollow-body jazz guitar on the neck pickup, modeled with\n"
        "Karplus-Strong plucked strings (fractional-delay tuned), strummed extended voicings,\n"
        "palm-muted comping stabs, and a slow Cmaj9 on Return. No samples.\n"),
}


def clear_audio(d, keep=()):
    for f in os.listdir(d):
        if f.lower().endswith(AUDIO_EXTS) and f not in keep:
            os.remove(os.path.join(d, f))


TARGET_DB = -14.5   # early RMS of key sounds; kalimba sits at -14.3, vibraphone at -12.9
SUSTAIN_DB = -5.0   # held loops (drones) sit this far under the key sounds


def match_loudness(files, target_db=TARGET_DB, ceiling=0.95):
    """Scale a whole set by one gain so its key sounds match the other musical
    sets in perceived level. Peak normalization alone leaves spiky plucks quiet."""
    def early_rms(x):
        head = x[:int(SR * 0.3)]
        return math.sqrt(sum(v * v for v in head) / max(1, len(head)))
    held = files.pop("sustain", None)
    downs = [early_rms(x) for stem, x in files.items() if stem.startswith("down")]
    current = 20 * math.log10(sum(downs) / len(downs))
    gain = 10 ** ((target_db - current) / 20)
    peak = max(max(abs(v) for v in x) for x in files.values())
    gain = min(gain, ceiling / peak)
    out = {stem: [v * gain for v in x] for stem, x in files.items()}
    if held:   # a held loop sits under the playing, SUSTAIN_DB below the keys
        rms = math.sqrt(sum(v * v for v in held) / len(held))
        g = min(10 ** ((target_db + SUSTAIN_DB) / 20) / rms, ceiling / max(abs(v) for v in held))
        out["sustain"] = [v * g for v in held]
    return out


def render_model(base, name):
    fn, about = MODELS[name]
    d = os.path.join(base, name)
    os.makedirs(d, exist_ok=True)
    clear_audio(d)
    seeded(name)
    files = match_loudness(fn(d))
    for stem, samples in files.items():
        write_wav(os.path.join(d, stem + ".wav"), samples)
    tag(d, "interactive")
    with open(os.path.join(d, "SOURCE.txt"), "w") as f:
        f.write(f"Set '{name}' built by tools/instruments.py.\n\n{about}\nRegenerate with: "
                f"python3 tools/generate.py Klonk.spoon/sounds --only={name}\n")
    print(f"  {name}: {len(files)} sounds")


# --- Star voyage ----------------------------------------------------------------------
# A starship console you can play. The typing keys are a tuned console instrument: a
# quick acknowledgement blip an octave up, then a glassy tone that rings about 1.5 s.
# All eight notes come from one open chord (D lydian, built in fifths), so whatever
# overlaps while you type sounds as a chord, not a clash. The short recorded effects
# from the personal LCARS backup keep the jobs short sounds suit: the door chime on
# Space, beeps on Backspace, clicks and scroll, and "Working" on Return.
VOYAGE_NOTES = [74, 76, 78, 81, 83, 85, 88, 90]          # D5 E5 F#5 A5 B5 C#6 E6 F#6


def console_tone(m, dur=1.6, level=0.3):
    """A tuned console note: a 22 ms blip an octave up, then two slightly detuned
    partial stacks (the shimmer) with a hard attack and a long, clean decay."""
    n = int(SR * dur)
    f = hz(m)
    out = []
    p1 = p2 = pb = 0.0
    for i in range(n):
        t = i / SR
        pb += 2 * math.pi * 2 * f / SR
        blip = math.sin(pb) * (1.0 if t < 0.022 else 0.0) * min(1.0, t / 0.002) * 0.6
        p1 += 2 * math.pi * f / SR
        p2 += 2 * math.pi * f * 1.0023 / SR                   # about 4 cents: glass, not chorus
        tone = sum(a * (math.sin(k * p1) + math.sin(k * p2)) for k, a in ((1, 0.5), (2, 0.12), (3, 0.05)))
        env = 0.0 if t < 0.02 else min(1.0, (t - 0.02) / 0.003) * math.exp(-(t - 0.02) / (dur * 0.28))
        out.append(blip + tone * env)
    return finish(out, level, td=0.02)


def read_wav(path, gain_db=0.0):
    """A recorded effect as mono floats at SR, scaled by gain_db."""
    import struct, wave
    with wave.open(path) as w:
        sr, ch, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if width != 2:
        raise SystemExit(f"{path}: expected 16-bit audio")
    x = [v / 32768 for v in struct.unpack(f"<{len(raw) // 2}h", raw)]
    if ch == 2:
        x = [(x[i] + x[i + 1]) / 2 for i in range(0, len(x) - 1, 2)]
    if sr != SR:
        x = [x[min(len(x) - 1, int(i * sr / SR))] for i in range(int(len(x) * SR / sr))]
    g = 10 ** (gain_db / 20)
    return [v * g for v in x]


def render_star_voyage(d, recordings):
    """Build the star-voyage set in d from the recorded console effects in
    `recordings` (the LCARS backup) plus the tuned console instrument."""
    for need in ("space.wav", "backspace.wav", "click1.wav", "click3.wav", "down4.wav", "scroll1.wav", "scroll2.wav"):
        if not os.path.isfile(os.path.join(recordings, need)):
            raise SystemExit(f"{recordings} has no {need}")
    if not os.path.isfile(os.path.join(d, "enter.wav")):
        raise SystemExit(f"{d} needs the recorded enter.wav ('Working')")
    rec = lambda name, db: read_wav(os.path.join(recordings, name), db)
    clear_audio(d, keep=("enter.wav", "signal-bosun.wav"))
    seeded("star-voyage")
    files = {f"down{i}": console_tone(m) for i, m in enumerate(VOYAGE_NOTES, 1)}
    files["space"] = rec("space.wav", -6)                  # door chime
    files["backspace"] = rec("backspace.wav", -12)         # a falling beep
    files["click1"], files["click2"] = rec("click1.wav", -12), rec("click3.wav", -12)
    files["rightclick"] = rec("down4.wav", -10)            # the computer's chirp
    files["scroll1"], files["scroll2"] = rec("scroll1.wav", -6), rec("scroll2.wav", -6)
    for stem, samples in files.items():
        write_wav(os.path.join(d, stem + ".wav"), samples)
    tag(d, "themed")
    with open(os.path.join(d, "SOURCE.txt"), "w") as f:
        f.write("Set 'star-voyage' (formerly lcars) built by tools/instruments.py\n"
                "(generate.py --star-voyage). Keys: a synthesized console instrument tuned to one\n"
                "open chord (D lydian in fifths), so overlapping notes form chords. Space, Backspace,\n"
                "clicks and scroll: recorded console effects from the retro-terminals asset library,\n"
                f"taken from {recordings}. enter.wav keeps the recorded 'Star Trek - Working'.\n"
                "Personal library only: the recordings are not redistributed.\n")
    print(f"  star-voyage: {len(VOYAGE_NOTES)} console notes + {len(files) - len(VOYAGE_NOTES)} recorded effects + enter.wav")
