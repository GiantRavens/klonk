#!/usr/bin/env python3
"""Slice real throat singing into notes for the khoomei performer.

Source: Freesound packs "Alfonso - Sygyt" (1190) and "Alfonso - Kargyraa" (1189),
uploaded by Bram (Freesound user 2) from an MTG (Universitat Pompeu Fabra) session
with Alfonso Perez, who learnt both styles in Tuva. CC BY 4.0. The public HQ
previews are used, pinned by sound ID.

Sygyt takes are pitch-tracked: the drone is the strongest peak in 80-300 Hz, the
whistle the strongest prominent peak in 600-2600 Hz. A new note starts wherever the
whistle moves more than about 70 cents and holds there; each note becomes one
segment, in the order he sang them, so typing performs his melody. Kargyraa takes
give steady chunks for the deep layer. Everything is printed (observe) before it is
packed into Klonk.spoon/performer/khoomei-samples.js.

    python3 tools/build_khoomei.py [--dry-run]
"""
import base64, json, os, subprocess, sys, tempfile, urllib.request, wave
import numpy as np

SR = 44100
SYGYT = [19528, 19529, 19530, 19531, 19532, 19533, 19534, 19535, 19536, 19545]
KARGYRAA = [19517, 19518, 19519, 19520, 19521, 19522, 19523, 19524, 19525, 19526, 19527]
CACHE = os.path.expanduser("~/.cache/klonk/freesound")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Klonk.spoon", "performer", "khoomei-samples.js")
CREDIT = ('Throat singing by Alfonso Perez, recorded at MTG (Universitat Pompeu Fabra), uploaded to Freesound by Bram, '
          'packs "Alfonso - Sygyt" and "Alfonso - Kargyraa", CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).')


def load(sound_id):
    os.makedirs(CACHE, exist_ok=True)
    mp3, wav = os.path.join(CACHE, f"{sound_id}.mp3"), os.path.join(CACHE, f"{sound_id}.wav")
    if not os.path.exists(wav):
        urllib.request.urlretrieve(f"https://cdn.freesound.org/previews/{sound_id // 1000}/{sound_id}_2-hq.mp3", mp3)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", mp3, wav], check=True)
    with wave.open(wav) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768


def track(x, n=4096, hop=512):
    win = np.hanning(n)
    frames = range(0, len(x) - n, hop)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    lo, hi = (freqs > 80) & (freqs < 300), (freqs > 600) & (freqs < 2600)
    drone, whistle, rms = [], [], []
    for i in frames:
        seg = x[i:i + n]
        spec = np.abs(np.fft.rfft(seg * win)) + 1e-9
        db = 20 * np.log10(spec)
        drone.append(freqs[lo][np.argmax(spec[lo])])
        band = db[hi]
        k = np.argmax(band)
        whistle.append(freqs[hi][k] if band[k] - np.median(band) > 22 else 0.0)   # a prominent, pure peak
        rms.append(float(np.sqrt(np.mean(seg ** 2))))
    return np.array(drone), np.array(whistle), np.array(rms), hop


def notes(x):
    drone, whistle, rms, hop = track(x)
    med = np.array([np.median(whistle[max(0, i - 2):i + 3]) for i in range(len(whistle))])   # smooth
    segs, start = [], None
    for i in range(1, len(med)):
        cur, prev = med[i], med[i - 1]
        moved = cur == 0 or prev == 0 or abs(np.log2(cur / prev)) > 0.06
        if start is None and cur > 0:
            start = i
        elif start is not None and moved:
            seg = (start, i)
            if (i - start) * hop / SR >= 0.18:
                segs.append(seg)
            start = i if cur > 0 else None
    out = []
    for a, b in segs:
        a_s, b_s = a * hop, min(len(x), b * hop + 4096)
        b_s = min(b_s, a_s + int(1.6 * SR))
        f0 = float(np.median(drone[a:b])); fw = float(np.median(med[a:b]))
        out.append({"a": a_s, "b": b_s, "f0": round(f0, 1), "hz": round(fw, 1), "harmonic": int(round(fw / f0)) if f0 else 0})
    return out


def chunks(x, seconds=3.0, count=2):
    _, _, rms, hop = track(x)
    n = int(seconds * SR / hop)
    if len(rms) < n + 10:
        return []
    scores = [(float(np.mean(rms[i:i + n])), i) for i in range(5, len(rms) - n, n // 2)]
    best = sorted(scores, reverse=True)[:count]
    return [{"a": i * hop, "b": i * hop + int(seconds * SR)} for _, i in sorted(best, key=lambda s: s[1])]


def aac(samples):
    fade = int(0.012 * SR)
    s = samples.copy()
    s[:fade] *= np.linspace(0, 1, fade); s[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(s)) or 1.0
    s = s * (0.8 / peak)
    with tempfile.TemporaryDirectory() as tmp:
        wav, m4a = os.path.join(tmp, "n.wav"), os.path.join(tmp, "n.m4a")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(s, -1, 1) * 32767).astype("<i2").tobytes())
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", wav, m4a], check=True)   # voice holds up at 64 kbps
        with open(m4a, "rb") as f:
            return base64.b64encode(f.read()).decode()


def main():
    dry = "--dry-run" in sys.argv
    sygyt, deep, report = [], [], []
    for sid in SYGYT:
        x = load(sid)
        ns = notes(x)
        if ns:
            ns[-1]["final"] = True                     # the take's last note: its own cadence
        report.append({"id": sid, "seconds": round(len(x) / SR, 1), "notes": len(ns),
                       "harmonics": [n["harmonic"] for n in ns][:24], "drone_hz": sorted({round(n["f0"]) for n in ns})[:6]})
        for n in ns:
            sygyt.append(dict(n, id=sid, data=None if dry else aac(x[n["a"]:n["b"]])))
    for sid in KARGYRAA:
        x = load(sid)
        for c in chunks(x):
            deep.append({"id": sid, "data": None if dry else aac(x[c["a"]:c["b"]])})
    print(json.dumps({"sygyt_takes": report, "sygyt_notes": len(sygyt), "kargyraa_chunks": len(deep),
                      "note_seconds": round(sum((n["b"] - n["a"]) / SR for n in sygyt), 1)}, indent=1))
    if dry:
        return
    bank = {"credit": CREDIT,
            "sygyt": [{k: n[k] for k in ("id", "f0", "hz", "harmonic", "data")} | {"final": n.get("final", False)} for n in sygyt],
            "deep": deep}
    with open(OUT, "w") as f:
        f.write("// Real throat singing for the khoomei performer, sliced by tools/build_khoomei.py.\n// " + CREDIT + "\n")
        f.write("window.KHOOMEI = " + json.dumps(bank) + ";\n")
    print(f"wrote {os.path.normpath(OUT)} ({os.path.getsize(OUT) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
