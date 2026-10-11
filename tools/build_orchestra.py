#!/usr/bin/env python3
"""Render the orchestra performer's note bank from GeneralUser GS.

Each section is rendered with FluidSynth (via instruments.gm) on a grid of pitches
about every three semitones; the page repitches the nearest note by at most a
semitone and a half. Notes are AAC-compressed and packed as base64 into
Klonk.spoon/performer/orchestra-samples.js, because WKWebView pages opened from
file:// cannot fetch() their neighbours.

    python3 tools/build_orchestra.py              # both banks
    python3 tools/build_orchestra.py cinematic    # one bank

Prints the manifest (sections, programs, pitches, lengths) before rendering.
"""
import base64, json, os, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import instruments as I                                   # noqa: E402
from generate import write_wav                            # noqa: E402

PERFORMER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Klonk.spoon", "performer")

# section: (GM program, drum kit?, pitches, note seconds, velocity)
SECTIONS = {
    "strings": (48, False, [48, 51, 54, 57, 60, 63, 66, 69, 72, 75, 78], 5.5, 96),    # String Ensemble 1
    "pizz":    (45, False, [57, 60, 63, 66, 69, 72, 75, 78, 81], 0.9, 100),          # Pizzicato Strings
    "low":     (42, False, [33, 36, 39, 42, 45, 48, 51, 54], 5.5, 100),              # Cello (and bass octave)
    "horns":   (60, False, [48, 51, 54, 57, 60, 63, 66, 69, 72], 5.0, 96),           # French Horn
    "brass":   (61, False, [54, 57, 60, 63, 66, 69, 72, 75], 4.0, 104),              # Brass Section
    "timpani": (47, False, [36, 39, 42, 45, 48, 51], 3.0, 110),                      # Timpani
    "kit":     (48, True,  [35, 36, 49, 57], 3.5, 112),                              # Orchestra kit: bass drums, crashes
}

# The film-score bank: short bowed notes for ostinati, horns for the theme and
# sustained strings for its answer, low brass for braams, timpani, taiko and toms,
# choir, and the orchestra kit (bass drum, snare, crash).
CINEMATIC = {
    "viola":   (41, False, [50, 53, 56, 59, 62, 65, 68, 71, 74, 77, 80], 0.35, 112),  # fastest bowed attack
    "cello":   (42, False, [33, 36, 39, 42, 45, 48, 51, 54], 0.4, 112),
    "pizz":    (45, False, [36, 42, 48, 54, 60, 66, 72, 78], 0.4, 110),              # layered for bite
    "brass":   (61, False, [30, 33, 36, 39, 42, 45, 48, 51, 54], 3.0, 124),          # braams
    "horns":   (60, False, [48, 51, 54, 57, 60, 63, 66, 69, 72, 75], 3.0, 120),   # the theme, lifted to E
    "strings": (48, False, [55, 58, 61, 64, 67, 70, 73, 76, 79, 82, 85, 88], 3.0, 104),   # the answer, legato
    "timp":    (47, False, [38, 41, 45, 50], 2.5, 118),
    "choir":   (52, False, [50, 53, 56, 59, 62, 65, 68, 71, 74], 4.0, 100),
    "taiko":   (116, False, [36, 43, 50], 2.0, 120),
    "toms":    (117, False, [43, 48, 53, 58], 1.2, 112),
    "kit":     (48, True,  [36, 38, 49, 57], 3.5, 118),                              # bass drum, snare, crashes
}
# The salon bank: a string quartet from GeneralUser GS plus Klonk's own harpsichord
# model (instruments.harpsichord, after Valimaki et al.), retuned to A440 so it
# plays in tune with the strings.
CHAMBER = {
    "violin":      (40, False, [55, 58, 61, 64, 67, 70, 73, 76, 79, 82, 85, 88], 2.5, 96),
    "viola":       (41, False, [48, 51, 54, 57, 60, 63, 66, 69, 72], 2.5, 88),
    "cello":       (42, False, [33, 36, 39, 42, 45, 48, 51, 54, 57, 60], 2.5, 96),
    "harpsichord": ("model", False, [43, 46, 49, 52, 55, 58, 61, 64, 67, 70, 73, 76, 79], 1.6, 0),
}
BANKS = {"orchestra": (SECTIONS, "ORCHESTRA", "orchestra-samples.js"),
         "cinematic": (CINEMATIC, "CINEMATIC", "cinematic-samples.js"),
         "chamber": (CHAMBER, "CHAMBER", "chamber-samples.js")}


def aac_b64(samples):
    with tempfile.TemporaryDirectory() as tmp:
        wav, m4a = os.path.join(tmp, "n.wav"), os.path.join(tmp, "n.m4a")
        write_wav(wav, samples)
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", wav, m4a], check=True)
        with open(m4a, "rb") as f:
            return base64.b64encode(f.read()).decode()


def build(name):
    sections, var, filename = BANKS[name]
    manifest = {k: {"program": p, "drums": d, "pitches": n, "seconds": sec} for k, (p, d, n, sec, _) in sections.items()}
    print(json.dumps({"bank": name, "soundfont": "GeneralUser GS " + I.GUGS_COMMIT[:10], "sections": manifest}, indent=1))
    bank, total = {}, 0
    for section, (program, drums, pitches, seconds, vel) in sections.items():
        bank[section] = {}
        for m in pitches:
            if program == "model":
                I.A415 = 440.0                                # concert pitch for the ensemble
                I.seeded("chamber-harpsichord", m)
                samples = I.harpsichord([(0, m)], dur=seconds, level=0.8)
            else:
                samples = I.gm(program, [(0, m, seconds, vel)], level=0.8, drums=drums, tail=0.6, gain=0.8)
            bank[section][m] = aac_b64(samples)
            total += len(bank[section][m])
        print(f"  {section}: {len(pitches)} notes")
    out = os.path.join(PERFORMER, filename)
    with open(out, "w") as f:
        f.write(f"// {name.title()} note bank rendered by tools/build_orchestra.py with FluidSynth from\n"
                f"// GeneralUser GS v2.0.3 by S. Christian Collins (commit {I.GUGS_COMMIT[:10]}). AAC, base64.\n")
        f.write(f"window.{var} = " + json.dumps(bank) + ";\n")
    print(f"wrote {os.path.normpath(out)} ({total / 1e6:.1f} MB of audio)")


def main():
    for name in (sys.argv[1:] or list(BANKS)):
        build(name)


if __name__ == "__main__":
    main()
