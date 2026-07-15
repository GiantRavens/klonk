#!/usr/bin/env python3
"""Turn a folder of one-shot samples into a klonk sound set.

Where `import_pack.py` slices Mechvibes keyboard sprites, this generalizes to
ANY pile of short recordings — paper crinkles, ping-pong bounces, sparks, splashes,
Star Trek console blips — and maps them onto klonk's filename convention, mouse
voices included:

    down1..N   the samples themselves (a random one plays per key)
    up1..2     quiet, truncated release ticks derived from them
    space / enter / backspace   picked from the pool (enter = the fullest; add
                                a service bell with --bell)
    click1..N / clickup / rightclick / scroll1..2   the mouse, from the same pool

Observe-before-act: it first prints a MANIFEST (each input's duration + peak) and
the role assignment, so you see its decisions before trusting the audio. Imported
audio lands in ~/Music/Klonk/Sounds (never the repo) — override with $KLONK_SOUNDS.

    python3 tools/make_set.py <source_dir> <set_name> [--bell] [--maxdown N]

Needs ffmpeg (brew install ffmpeg). Handles any format/rate/bit-depth ffmpeg reads.
"""
import math, os, struct, subprocess, sys, tempfile, wave

SR = 44100
AUDIO_EXT = (".wav", ".mp3", ".aif", ".aiff", ".m4a", ".mov", ".flac", ".ogg", ".caf")

base = os.path.abspath(os.environ.get("KLONK_SOUNDS", os.path.expanduser("~/Music/Klonk/Sounds")))


def decode(path):
    """Any audio file -> list of mono float samples at 44.1 kHz."""
    with tempfile.TemporaryDirectory() as t:
        w = os.path.join(t, "d.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path,
                        "-ac", "1", "-ar", str(SR), "-sample_fmt", "s16", w], check=True)
        with wave.open(w, "rb") as f:
            n = f.getnframes()
            return [x / 32768.0 for x in struct.unpack("<%dh" % n, f.readframes(n))]


def trim(s, thresh=0.02, pre=0.004, tail=0.03):
    """Cut leading/trailing near-silence so every sample starts on its transient."""
    peak = max((abs(x) for x in s), default=0.0)
    if peak == 0:
        return s
    th = thresh * peak
    lo = next((i for i, x in enumerate(s) if abs(x) > th), 0)
    hi = next((i for i in range(len(s) - 1, -1, -1) if abs(s[i]) > th), len(s) - 1)
    return s[max(0, lo - int(pre * SR)): min(len(s), hi + int(tail * SR))]


def fade_norm(chunk, level=0.9, maxdur_ms=None):
    """Cap length, fade both edges (kills clicks), peak-normalize to `level`."""
    if maxdur_ms:
        chunk = chunk[:int(maxdur_ms / 1000 * SR)]
    chunk = list(chunk)
    n = len(chunk)
    fa, fo = int(0.003 * SR), int(0.008 * SR)
    for i in range(n):
        k = 1.0
        if i < fa: k = i / fa
        if n - i < fo: k = min(k, (n - i) / fo)
        chunk[i] *= k
    peak = max((abs(x) for x in chunk), default=1.0) or 1.0
    return [x * level / peak for x in chunk]


def write_wav(out, name, s):
    with wave.open(os.path.join(out, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in s))


def synth_bell(f0=784, dur=0.6, level=0.30):
    """Compact inharmonic struck-bell — an optional Return ding (shared with import_pack)."""
    import random
    random.seed(1)
    parts = [(1, .30, .60), (2, .45, .50), (2.40, .35, .42), (3, .22, .34), (4.05, .30, .30)]
    n = int(SR * dur); o = []
    for i in range(n):
        t = i / SR; v = 0.0
        for r, a, dec in parts:
            v += a * math.sin(2 * math.pi * f0 * r * t) * math.exp(-t / dec)
        v += 0.4 * (random.random() * 2 - 1) * math.exp(-t / 0.005)
        if t < 0.001: v *= t / 0.001
        if n - i < SR * 0.01: v *= (n - i) / (SR * 0.01)
        o.append(v)
    peak = max((abs(x) for x in o), default=1.0) or 1.0
    return [x * level / peak for x in o]


def mix(a, b):
    n = max(len(a), len(b)); buf = [0.0] * n
    for tr in (a, b):
        for i, x in enumerate(tr): buf[i] += x
    peak = max((abs(x) for x in buf), default=1.0) or 1.0
    return [x * 0.9 / peak for x in buf]


def transient(s):
    """Peak amplitude in the first 30 ms — how 'clicky' a sample's attack is."""
    return max((abs(x) for x in s[:int(0.03 * SR)]), default=0.0)


def main():
    argv = sys.argv[1:]
    bell = "--bell" in argv
    argv = [a for a in argv if a != "--bell"]
    maxdown = 8
    role_override = {}          # role -> source basename, for semantic sets (e.g. LCARS)
    for opt in ("--maxdown", "--enter", "--space"):
        if opt in argv:
            i = argv.index(opt)
            if opt == "--maxdown":
                maxdown = int(argv[i + 1])
            else:
                role_override[opt[2:]] = argv[i + 1]
            del argv[i:i + 2]
    if len(argv) < 2:
        sys.exit("usage: make_set.py <source_dir> <set_name> [--bell] [--maxdown N] "
                 "[--enter FILE] [--space FILE]")
    src, name = argv[0], argv[1]

    files = sorted(os.path.join(src, f) for f in os.listdir(src)
                   if f.lower().endswith(AUDIO_EXT) and not f.startswith("."))
    if not files:
        sys.exit(f"no audio files in {src}")

    # OBSERVE: decode + trim everything, then print a manifest before assigning.
    samples = []
    print(f"\n  {name}: manifest ({len(files)} inputs)")
    for p in files:
        s = trim(decode(p))
        dur = len(s) / SR
        samples.append((os.path.basename(p), s, dur, transient(s)))
        print(f"    {os.path.basename(p):32s} {dur:5.2f}s  attack={s and transient(s):.2f}")

    # short samples make the best keys/clicks; long ones make the fullest space/enter.
    by_len = sorted(range(len(samples)), key=lambda i: samples[i][2])
    by_attack = sorted(range(len(samples)), key=lambda i: -samples[i][3])

    def find(basename):
        for i, (nm, *_ ) in enumerate(samples):
            if nm == basename or os.path.splitext(nm)[0] == os.path.splitext(basename)[0]:
                return i
        sys.exit(f"--role file '{basename}' not found among inputs")

    enter_idx = find(role_override["enter"]) if "enter" in role_override else by_len[-1]
    space_idx = find(role_override["space"]) if "space" in role_override else by_len[-1]
    # keep an explicitly-chosen enter/space OUT of the random key pool, so a
    # semantic sound (a door chime) doesn't fire on ordinary keystrokes.
    reserved = {enter_idx, space_idx} if role_override else set()
    key_pool = [i for i in by_len if i not in reserved] or by_len

    out = os.path.join(base, name)
    os.makedirs(out, exist_ok=True)

    def emit(fname, idx, level=0.9, maxdur_ms=None):
        write_wav(out, fname, fade_norm(samples[idx][1], level, maxdur_ms))
        return samples[idx][0]

    log = {}
    # down = the samples themselves (a random one plays per keystroke), capped
    # short so fast typing stays crisp instead of smearing long tails together.
    downs = key_pool[:maxdown]
    for i, idx in enumerate(downs, 1):
        log[f"down{i}"] = emit(f"down{i}.wav", idx, 0.9, maxdur_ms=260)
    # up = two quiet truncated release ticks
    for i, idx in enumerate(key_pool[:2], 1):
        log[f"up{i}"] = emit(f"up{i}.wav", idx, 0.4, maxdur_ms=60)
    # dedicated keys
    log["space"] = emit("space.wav", space_idx, 0.92)
    log["backspace"] = emit("backspace.wav", key_pool[len(key_pool) // 2], 0.85)
    if bell:
        write_wav(out, "enter.wav", mix(fade_norm(samples[enter_idx][1], 0.85), synth_bell()))
        log["enter"] = samples[enter_idx][0] + " + bell"
    else:
        log["enter"] = emit("enter.wav", enter_idx, 0.95)
    # mouse: click = the punchiest attack (heavier sibling of a key); scroll = a
    # very short quiet tick; rightclick = a different-flavored sample. Draw from
    # the attack pool minus reserved, so a semantic enter/space sound doesn't
    # fire on clicks either.
    attack_pool = [i for i in by_attack if i not in reserved] or by_attack
    click_idxs = attack_pool[:3]
    for i, idx in enumerate(click_idxs, 1):
        log[f"click{i}"] = emit(f"click{i}.wav", idx, 0.95, maxdur_ms=200)
    log["clickup"] = emit("clickup.wav", attack_pool[0], 0.4, maxdur_ms=60)
    log["rightclick"] = emit("rightclick.wav", attack_pool[min(1, len(attack_pool) - 1)], 0.9, maxdur_ms=220)
    for i, idx in enumerate((key_pool[:2] or downs), 1):
        log[f"scroll{i}"] = emit(f"scroll{i}.wav", idx, 0.3, maxdur_ms=40)

    with open(os.path.join(out, "SOURCE.txt"), "w") as f:
        f.write(f"Set '{name}' built by make_set.py from: {os.path.abspath(src)}\n")
        f.write("Provenance of the source audio is the user's to track; not redistributed.\n\n")
        for role, srcname in log.items():
            f.write(f"  {role:12s} <- {srcname}\n")

    print(f"  -> {len([x for x in os.listdir(out) if x.endswith('.wav')])} WAVs in {out}")
    print("     assignment:")
    for role, srcname in log.items():
        print(f"       {role:12s} <- {srcname}")


if __name__ == "__main__":
    main()
