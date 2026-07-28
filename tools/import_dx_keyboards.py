#!/usr/bin/env python3
"""Convert Mechvibes DX v2 keyboard sprites into bundled Klonk sets.

The tool observes every requested pack first and prints a JSON manifest before
starting ffmpeg. It then decodes each source sprite once and slices representative
presses, authentic releases, and dedicated large keys into Klonk's WAV contract.

    python3 tools/import_dx_keyboards.py --source /path/to/mechvibes-dx
    python3 tools/import_dx_keyboards.py --source /path/to/mechvibes-dx pack-name
"""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "Klonk.spoon" / "sounds"
SOURCE_COMMIT = "fa3da3a46985687696bc335714fc7679ea4fe07f"
PRESS_KEYS = ("KeyA", "KeyS", "KeyD", "KeyF", "KeyJ", "KeyK", "KeyL", "Semicolon")
RELEASE_KEYS = PRESS_KEYS[:4]
SPECIAL_KEYS = {"Space": "space.wav", "Enter": "enter.wav", "Backspace": "backspace.wav"}


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def observe(pack_dir):
    config_path = pack_dir / "config.json"
    config = json.loads(config_path.read_text())
    audio = pack_dir / config["audio_file"]
    definitions = config.get("definitions", {})
    required = set(PRESS_KEYS) | set(RELEASE_KEYS) | set(SPECIAL_KEYS)
    missing = sorted(required - set(definitions))
    malformed = sorted(
        key for key in required & set(definitions)
        if len(definitions[key].get("timing", [])) != 2
        or any(len(segment) != 2 for segment in definitions[key]["timing"])
    )
    supported = (config.get("config_version") == "2"
                 and config.get("definition_method") == "single"
                 and audio.is_file() and not missing and not malformed)
    return {
        "pack": pack_dir.name,
        "strategy": "dx-v2-sprite",
        "config_version": config.get("config_version"),
        "definition_method": config.get("definition_method"),
        "definitions": len(definitions),
        "audio": audio.name,
        "source_bytes": audio.stat().st_size if audio.is_file() else 0,
        "predicted_wavs": len(PRESS_KEYS) + len(RELEASE_KEYS) + len(SPECIAL_KEYS),
        "missing_keys": missing,
        "malformed_keys": malformed,
        "supported": supported,
        "_config": config,
        "_config_path": config_path,
        "_audio_path": audio,
    }


def load_pcm(audio_path, tmp):
    decoded = tmp / "sprite.wav"
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(audio_path),
        "-ac", "1", "-ar", "44100", "-sample_fmt", "s16", str(decoded),
    ], check=True)
    with wave.open(str(decoded), "rb") as w:
        rate = w.getframerate()
        count = w.getnframes()
        samples = struct.unpack(f"<{count}h", w.readframes(count))
    return rate, samples


def slice_samples(samples, rate, segment):
    start_ms, end_ms = segment
    start = max(0, round(start_ms * rate / 1000))
    end = min(len(samples), round(end_ms * rate / 1000))
    if end <= start:
        raise ValueError(f"empty timing segment {segment}")
    clip = [sample / 32768.0 for sample in samples[start:end]]
    fade = min(round(rate * 0.002), len(clip) // 2)
    for i in range(fade):
        gain = i / max(1, fade)
        clip[i] *= gain
        clip[-1 - i] *= gain
    peak = max(abs(sample) for sample in clip) or 1.0
    return [sample * 0.88 / peak for sample in clip]


def write_wav(path, samples, rate):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", round(sample * 32767)) for sample in samples))


def convert(item, out_root):
    pack = item["pack"]
    out = out_root / pack
    out.mkdir(parents=True, exist_ok=True)
    for stale in out.glob("*.wav"):
        stale.unlink()
    with tempfile.TemporaryDirectory(prefix=f"klonk-{pack}-") as temp:
        rate, samples = load_pcm(item["_audio_path"], Path(temp))
        definitions = item["_config"]["definitions"]
        for index, key in enumerate(PRESS_KEYS, 1):
            write_wav(out / f"down{index}.wav",
                      slice_samples(samples, rate, definitions[key]["timing"][0]), rate)
        for index, key in enumerate(RELEASE_KEYS, 1):
            write_wav(out / f"up{index}.wav",
                      slice_samples(samples, rate, definitions[key]["timing"][1]), rate)
        for key, filename in SPECIAL_KEYS.items():
            write_wav(out / filename,
                      slice_samples(samples, rate, definitions[key]["timing"][0]), rate)

    (out / "category").write_text("keyboard\n")
    (out / "voices").write_text("1\n")
    (out / "SOURCE.txt").write_text(
        f"Mechvibes DX keyboard pack: {pack}\n"
        f"Author in pack config: {item['_config'].get('author', 'unknown')}\n"
        f"Source: https://github.com/hainguyents13/mechvibes-dx/tree/main/soundpacks/keyboard/{pack}\n"
        f"Pinned source commit: {SOURCE_COMMIT}\n"
        "License: MIT — https://github.com/hainguyents13/mechvibes-dx/blob/main/LICENSE\n"
        f"Source audio SHA-256: {sha256(item['_audio_path'])}\n"
        f"Source config SHA-256: {sha256(item['_config_path'])}\n"
        "Conversion: eight representative key presses, four authentic key releases, "
        "and dedicated Space/Enter/Backspace slices; mono 44.1 kHz 16-bit WAV.\n"
    )
    actual = len(list(out.glob("*.wav")))
    return {"pack": pack, "predicted_wavs": item["predicted_wavs"],
            "actual_wavs": actual, "status": "ok" if actual == item["predicted_wavs"] else "count-mismatch"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packs", nargs="*", help="pack folder names (default: all)")
    parser.add_argument("--source", required=True, type=Path,
                        help="Mechvibes DX checkout or its soundpacks/keyboard directory")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    source = args.source.resolve()
    pack_root = source / "soundpacks" / "keyboard" if (source / "soundpacks" / "keyboard").is_dir() else source
    names = args.packs or sorted(p.name for p in pack_root.iterdir() if p.is_dir())
    items = [observe(pack_root / name) for name in names]

    public_manifest = [{k: v for k, v in item.items() if not k.startswith("_")} for item in items]
    print("MANIFEST")
    print(json.dumps(public_manifest, indent=2))
    unsupported = [item["pack"] for item in items if not item["supported"]]
    if unsupported:
        print(f"ABORT unsupported inputs: {', '.join(unsupported)}", file=sys.stderr)
        return 2
    if not shutil.which("ffmpeg"):
        print("ABORT ffmpeg not found", file=sys.stderr)
        return 2

    results, failures = [], []
    for item in items:
        try:
            result = convert(item, args.out.resolve())
            results.append(result)
            if result["status"] != "ok":
                failures.append({"pack": item["pack"], "class": "silent-output-drift", "detail": result})
        except Exception as exc:
            failures.append({"pack": item["pack"], "class": type(exc).__name__, "detail": str(exc)})
    print("TELEMETRY")
    print(json.dumps({"succeeded": len(results) - sum(r["status"] != "ok" for r in results),
                      "requested": len(items), "results": results, "failures": failures}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
