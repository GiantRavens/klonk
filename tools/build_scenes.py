#!/usr/bin/env python3
"""Render the note banks for the instrument scenes (performer/scene.js).

Each scene plays its instrument set as a phrase, not one note per key, so it needs
notes at known pitches. They are rendered with the voices Klonk already has
(generate.py sine recipes, instruments.py physical models and samplers, FluidSynth
for General MIDI), on a grid about every three semitones, AAC-compressed and packed
as base64 into Klonk.spoon/performer/scenes/<set>.js. The music box and bagpipe
keep their exact recorded pitches.

    python3 tools/build_scenes.py                 # every scene
    python3 tools/build_scenes.py harpsichord     # one scene

Prints the manifest (scene, sections, pitches) before rendering.
"""
import base64, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate as G                                       # noqa: E402
import instruments as I                                    # noqa: E402
from build_orchestra import aac_b64                        # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Klonk.spoon", "performer", "scenes")
grid = lambda lo, hi: list(range(lo, hi + 1, 3))


def harpsichord(m, dur=4.0):                               # long enough to ring through a bar
    I.A415 = 440.0
    I.seeded("scene-harpsichord", m)
    return I.harpsichord([(0, m)], dur=dur, level=0.8)


def gm(program, drums=False, seconds=1.5, vel=100):
    return lambda m: I.gm(program, [(0, m, seconds, vel)], level=0.8, drums=drums, tail=0.5, gain=0.8)


BASS = lambda m: I.sampled(I.UPRIGHT_BASS, m, 1.6, 0.9, 0.8, release=0.15)
BOX = {I.note_midi(n): n for n in ["Ab4", "Bb4", "C5", "Db5", "Eb5", "F5", "G5", "Ab5", "Bb5", "C6", "Db6", "Eb6", "F6", "G6", "Ab6"]}

# scene: {section: (renderer(m) -> samples, pitches)}
SCENES = {
    "harpsichord": {"harp": (harpsichord, grid(36, 84))},
    "hard-drive-music-box": {
        "box": (lambda m: I.music_box(BOX[m], 1, 1.8, 0.8), sorted(BOX)),
        "box2": (lambda m: I.music_box(BOX[m], 2, 1.8, 0.8), sorted(BOX)),
    },
    "bagpipe": {
        "pipe": (lambda m: I.sampled(I.BAGPIPE, m, 2.5, 1.0, 0.8, release=0.1), sorted(I.BAGPIPE)),
        "drone": (lambda m: I.drone_loop(), [43]),
        "kit": (gm(48, True, 1.2, 112), [36, 38]),             # pipe-band bass drum and snare
    },
    "jazz-piano": {
        "piano": (lambda m: I.upright(m, 1.6, 0.7, 0.8), grid(45, 84)),
        "bass": (BASS, grid(28, 52)),
        "kit": (gm(0, True, 0.6, 70), [42, 51]),                # brushed hat and ride
    },
    "wurlitzer": {
        "wurli": (lambda m: I.wurli(m, 1.6, "mp", 0.8), grid(36, 84)),
        "bass": (BASS, grid(28, 52)),
    },
    "vibraphone": {
        "vibes": (lambda m: G.vibraphone(I.hz(m), dur=1.8, level=0.8), grid(53, 89)),
        "bass": (BASS, grid(28, 52)),
    },
    "kalimba": {
        "kalimba": (lambda m: G.kalimba(I.hz(m), dur=1.2, level=0.8), grid(52, 91)),
        "kit": (gm(0, True, 0.4, 90), [70, 82]),                # maracas and shaker, the hosho
    },
    "slap-bass": {
        "slap": (gm(36, False, 0.5, 118), grid(28, 58)),
        "pop": (gm(37, False, 0.4, 120), grid(40, 64)),
        "kit": (gm(0, True, 0.6, 108), [36, 38, 42, 46]),
    },
    "schmoove-guitar": {
        "guitar": (lambda m: I.finish(I.guitar_string(m, 1.4, 1.4), 0.8), grid(40, 79)),
        "bass": (BASS, grid(28, 52)),
        "kit": (gm(0, True, 0.4, 80), [70, 75]),                # shaker and claves
    },
}


def build(name):
    sections = SCENES[name]
    print(json.dumps({"scene": name, "sections": {s: p for s, (_, p) in sections.items()}}))
    bank = {}
    for section, (render, pitches) in sections.items():
        bank[section] = {}
        for m in pitches:
            I.seeded(name, section, m)
            bank[section][m] = aac_b64(render(m))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.js")
    with open(path, "w") as f:
        f.write(f"// Note bank for the '{name}' scene, rendered by tools/build_scenes.py (see the set's SOURCE.txt).\n")
        f.write("window.SCENE_BANK = " + json.dumps(bank) + ";\n")
    print(f"  wrote {os.path.relpath(path)} ({os.path.getsize(path) / 1e6:.2f} MB)")


def main():
    for name in (sys.argv[1:] or list(SCENES)):
        build(name)


if __name__ == "__main__":
    main()
