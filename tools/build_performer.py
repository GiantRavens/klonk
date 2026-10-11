#!/usr/bin/env python3
"""Assemble Klonk's live chant performer from a pinned Synth_Gregorian commit.

The performer is a hidden Web Audio page (Klonk.spoon/performer/) that turns
typing into a sung phrase. Its voice and repertoire come from Brendan James
Lynskey's Synth_Gregorian (MIT): the vocal-voices.js library is copied verbatim,
the chant repertoire is lifted note-for-note out of gregorian-engine.js, and the
male VocalSet loops (CC BY 4.0) are packed into voices.js so the page can load
them from file:// (WKWebView blocks fetch() of local files; <script> is fine).

    python3 tools/build_performer.py

Prints a manifest first (what will be fetched and written), then builds.
"""
import base64, json, os, sys, urllib.request

COMMIT = "5a46c905b19738683d419c89360ea186f38d85d3"
RAW = f"https://raw.githubusercontent.com/BrendanJamesLynskey/Synth_Gregorian/{COMMIT}/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Klonk.spoon", "performer")
CACHE = os.path.expanduser("~/.cache/klonk/synth-gregorian")


def fetch(path):
    local = os.path.join(CACHE, path)
    if not os.path.exists(local):
        os.makedirs(os.path.dirname(local), exist_ok=True)
        urllib.request.urlretrieve(RAW + path, local)
    with open(local, "rb") as f:
        return f.read()


def chant_block(engine_js):
    """Return the `this.chants = { ... }` object literal, braces balanced."""
    start = engine_js.index("this.chants = {") + len("this.chants = ")
    depth = 0
    for i in range(start, len(engine_js)):
        c = engine_js[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return engine_js[start:i + 1]
    raise SystemExit("unbalanced chants block in gregorian-engine.js")


def main():
    grid = json.loads(fetch("voices/grid.json"))
    male = [g for g in grid if g["part"] == "m"]
    print(json.dumps({"commit": COMMIT, "out": os.path.normpath(OUT),
                      "copy": ["vocal-voices.js"], "extract": "gregorian-engine.js chants",
                      "pack": f"{len(male)} male VocalSet loops"}, indent=1))
    os.makedirs(OUT, exist_ok=True)

    with open(os.path.join(OUT, "vocal-voices.js"), "wb") as f:
        f.write(b"// Copied verbatim from Synth_Gregorian " + COMMIT.encode() + b" (MIT, Brendan James Lynskey).\n")
        f.write(fetch("vocal-voices.js"))

    engine = fetch("gregorian-engine.js").decode("utf-8")
    with open(os.path.join(OUT, "chants.js"), "w", encoding="utf-8") as f:
        f.write("// Chant repertoire extracted verbatim from Synth_Gregorian gregorian-engine.js\n"
                f"// ({COMMIT}, MIT). Each syllable: {{ syl, v (sung vowel), n: [note names] }};\n"
                "// a multi-note n is a neume sung legato on one vowel.\n")
        f.write("window.CHANTS = " + chant_block(engine) + ";\n")

    packed = {g["file"]: base64.b64encode(fetch("voices/" + g["file"])).decode() for g in male}
    with open(os.path.join(OUT, "voices.js"), "w") as f:
        f.write("// Male VocalSet loops (Wilkins, Seetharaman, Wahl, Pardo, ISMIR 2018; CC BY 4.0),\n"
                f"// as prepared by Synth_Gregorian {COMMIT}. Base64 so file:// pages can load them.\n")
        f.write("window.VOICE_GRID = " + json.dumps(male) + ";\n")
        f.write("window.VOICE_DATA = " + json.dumps(packed) + ";\n")
    size = sum(os.path.getsize(os.path.join(OUT, n)) for n in ("vocal-voices.js", "chants.js", "voices.js"))
    print(f"built performer assets: {size / 1e6:.1f} MB in {os.path.normpath(OUT)}")


if __name__ == "__main__":
    sys.exit(main())
