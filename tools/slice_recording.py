#!/usr/bin/env python3
"""Slice ONE continuous recording into one-shots, then build a klonk set.

`make_set.py` wants a folder of already-cut samples. But the natural way to
harvest new material is one long capture — Piezo recording an app's output
(pick Safari, a video, a game as the source), a field recording of a real
typewriter, a phone memo of tapping on things. This tool bridges the two:
transient detection over the whole recording, each hit cut into its own
one-shot, then the slices are handed to make_set.py for trim/normalize and
role assignment (down/up/space/enter/backspace + the mouse voices).

Observe-before-act, like its siblings: it prints a MANIFEST of every detected
hit (time, duration, peak, attack) BEFORE writing anything. Run --dry-run,
read the manifest, tune --thresh / --gap-ms until the hit count looks like
what you heard, then run for real.

    python3 tools/slice_recording.py <recording> <set_name> [--bell] [--maxdown N]
        [--thresh 0.10]     onset threshold, fraction of the loudest hit
        [--gap-ms 120]      quiet time that separates two hits
        [--max-hits 24]     keep the N loudest (dropped ones are LOGGED)
        [--keep-slices DIR] also keep the raw one-shots for hand-curation
        [--dry-run]         manifest only, write nothing

Piezo notes: set Piezo's source to the APP making the sound (Safari for a web
page, Hammerspoon for live klonk playback), not a microphone. Any format Piezo
saves works — decoding goes through ffmpeg (brew install ffmpeg). Recordings
land in ~/Music/Piezo by default. The set lands in ~/Music/Klonk/Sounds/<set_name>
(override with $KLONK_SOUNDS), never in the repo.
"""
import os
import subprocess
import sys
import tempfile

import make_set  # decode / write_wav / SR — same contract, same ffmpeg path

SR = make_set.SR
HOP = int(0.005 * SR)     # envelope resolution: 5 ms
WIN = int(0.010 * SR)     # rms window: 10 ms
PRE_S = 0.006             # keep a little pre-transient air
TAIL_S = 0.040            # and a little tail past the release
MAX_HIT_S = 1.2           # a "keystroke-ish" one-shot is never longer than this
MIN_HIT_S = 0.015         # shorter than this is a crackle, not a hit
SUSTAIN_HOPS = 10         # env must stay below release this long to end a hit (50 ms)


def envelope(s):
    """Short-window RMS per hop, via prefix sums (recordings can be minutes)."""
    sq = [0.0] * (len(s) + 1)
    for i, x in enumerate(s):
        sq[i + 1] = sq[i] + x * x
    env = []
    for start in range(0, max(1, len(s) - WIN), HOP):
        env.append(((sq[start + WIN] - sq[start]) / WIN) ** 0.5)
    return env


def detect_hits(s, thresh_frac, gap_ms):
    """State-machine onset detection over the envelope. Returns [(start, end)]
    in samples. Threshold is relative to the loudest moment but floored at 4x
    the noise floor (median), so a quiet recording still slices and a hissy
    one doesn't slice its own hiss."""
    env = envelope(s)
    if not env:
        return []
    floor = sorted(env)[len(env) // 2]
    thr = max(thresh_frac * max(env), 4 * floor)
    release = 0.35 * thr
    gap_hops = max(1, int(gap_ms / 1000 * SR / HOP))

    hits, i, last_end_hop = [], 0, -gap_hops
    while i < len(env):
        if env[i] >= thr and i - last_end_hop >= gap_hops:
            start_hop = i
            quiet = 0
            while i < len(env):
                i += 1
                if i - start_hop >= MAX_HIT_S * SR / HOP:
                    break
                quiet = quiet + 1 if i < len(env) and env[i] < release else 0
                if quiet >= SUSTAIN_HOPS:
                    i -= SUSTAIN_HOPS - 1   # end where quiet began, not after it
                    break
            a = max(0, int(start_hop * HOP - PRE_S * SR))
            b = min(len(s), int(i * HOP + TAIL_S * SR))
            if (b - a) / SR >= MIN_HIT_S:
                hits.append((a, b))
            last_end_hop = i
        i += 1
    return hits


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    argv = [a for a in argv if a != "--dry-run"]
    passthrough = ["--bell"] if "--bell" in argv else []
    argv = [a for a in argv if a != "--bell"]
    thresh, gap_ms, max_hits, keep = 0.10, 120, 24, None
    for opt in ("--thresh", "--gap-ms", "--max-hits", "--keep-slices", "--maxdown"):
        if opt in argv:
            i = argv.index(opt)
            v = argv[i + 1]
            if opt == "--thresh": thresh = float(v)
            elif opt == "--gap-ms": gap_ms = int(v)
            elif opt == "--max-hits": max_hits = int(v)
            elif opt == "--keep-slices": keep = v
            else: passthrough += ["--maxdown", v]
            del argv[i:i + 2]
    if len(argv) < 2:
        sys.exit(__doc__.split("\n\n")[2])   # the usage block
    rec, name = argv[0], argv[1]

    s = make_set.decode(rec)
    dur = len(s) / SR
    hits = detect_hits(s, thresh, gap_ms)
    print(f"\n  {os.path.basename(rec)}: {dur:.1f}s, {len(hits)} hits "
          f"(thresh {thresh}, gap {gap_ms}ms)")
    for n, (a, b) in enumerate(hits, 1):
        chunk = s[a:b]
        peak = max((abs(x) for x in chunk), default=0.0)
        print(f"    hit{n:02d}  t={a / SR:7.2f}s  {len(chunk) / SR:5.2f}s"
              f"  peak={peak:.2f}  attack={make_set.transient(chunk):.2f}")
    if not hits:
        sys.exit("  no hits detected — lower --thresh, or is this the right recording?")
    if len(hits) > max_hits:
        ranked = sorted(hits, key=lambda h: -max(abs(x) for x in s[h[0]:h[1]]))
        kept = sorted(ranked[:max_hits])
        print(f"  keeping the {max_hits} loudest, dropping {len(hits) - max_hits} "
              f"(raise --max-hits to keep more)")
        hits = kept
    if dry:
        print("  --dry-run: nothing written")
        return

    def emit_slices(slice_dir):
        for n, (a, b) in enumerate(hits, 1):
            make_set.write_wav(slice_dir, f"hit{n:02d}.wav", s[a:b])
        subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                          "make_set.py"), slice_dir, name] + passthrough,
            check=True)
        # make_set only saw the temp slice dir; record the REAL provenance.
        with open(os.path.join(make_set.base, name, "SOURCE.txt"), "a") as f:
            f.write(f"\nSliced by slice_recording.py from: {os.path.abspath(rec)}\n")

    if keep:
        os.makedirs(keep, exist_ok=True)
        emit_slices(keep)
        print(f"  raw slices kept in {keep}")
    else:
        with tempfile.TemporaryDirectory() as t:
            emit_slices(t)


if __name__ == "__main__":
    main()
