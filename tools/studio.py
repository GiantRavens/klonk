#!/usr/bin/env python3
"""klonk studio — a local web UI to see, audition, and organize your sound world.

Serves tools/studio.html on localhost and exposes a small JSON API over the same
filesystem contract the Spoon reads: sets are folders of WAVs in soundDirs,
ambient sounds are loopable files in ambientDirs, earlier directories win. The studio is
a VIEW plus (later) a compiler over that contract — it holds no private state.

Observe-before-act: every set gets an analysis manifest (per-file duration,
attack ratio, ring time, derived voice-bank size) computed with the same
definitions the engine and make_set.py use. The manifest drives both the UI's
chunky↔flowy character meter and, later, suggested `voices` values.

    python3 tools/studio.py [--port 8801]

Live apply needs the Hammerspoon CLI (`hs.ipc.cliInstall()` once from the HS
console); without it the studio still browses and auditions — apply is disabled.
"""
import json, os, shutil, struct, subprocess, sys, wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML = os.path.join(ROOT, "tools", "studio.html")

def expand(p): return os.path.expanduser(p)

# Same scan lists and precedence as Klonk.spoon/init.lua — earlier dirs win.
SOUND_DIRS = [
    (os.path.join(ROOT, "Klonk.spoon", "sounds"), "bundled"),
    (expand("~/Music/Klonk/keyboard"), "user"),
    (expand("~/Music/Klonk/Sounds"), "legacy"),
    (expand("~/.klonk/sounds"), "legacy"),
]
AMBIENT_DIRS = [
    (os.path.join(ROOT, "Klonk.spoon", "ambient"), "bundled"),
    (expand("~/Music/Klonk/ambient"), "user"),
    (expand("~/Music/Klonk/Ambience"), "legacy"),
    (expand("~/.klonk/ambient"), "legacy"),
]

AUDIO_RE_EXT = (".wav", ".aif", ".aiff", ".mp3")          # what the engine loads
AMBIENT_EXT = (".wav", ".mp3", ".aif", ".aiff", ".m4a")
GENERIC = {"down", "up", "click", "clickup", "rightclick", "scroll"}
DEDICATED = {"space", "enter", "backspace"}
CATEGORIES = [
    "environment", "keyboard", "percussive", "mechanical", "musical", "themed", "other",
]
VOICE_CAP = 6                                              # Klonk.voices default

# Fallback chains, exactly as the play() calls in init.lua:start().
FALLBACK = {
    "space": ["down"], "enter": ["down"], "backspace": ["down"],
    "click": ["down"], "rightclick": ["click", "down"],
    "clickup": ["up"], "scroll": ["up"],
}

MIME = {".wav": "audio/wav", ".mp3": "audio/mpeg", ".m4a": "audio/mp4",
        ".aif": "audio/aiff", ".aiff": "audio/aiff", ".html": "text/html"}

_analysis_cache = {}   # path -> (mtime, dict)


# ---------------------------------------------------------------- analysis

def analyze_wav(path):
    """Duration, attack ratio, ring time, straight from the samples.

    attack = peak in the first 30 ms over overall peak (make_set.py's transient(),
    normalized so un-normalized user files score the same as bundled ones).
    ring   = time until the 10 ms peak-envelope last exceeds 15% of peak — the
    audible tail, immune to trailing silence.
    """
    try:
        st = os.stat(path)
        hit = _analysis_cache.get(path)
        if hit and hit[0] == st.st_mtime:
            return hit[1]
        with wave.open(path, "rb") as w:
            sr, n, ch, sw = w.getframerate(), w.getnframes(), w.getnchannels(), w.getsampwidth()
            dur = n / sr if sr else 0.0
            if sw != 2 or n == 0:
                out = {"dur": round(dur, 3), "analyzed": False}
            else:
                raw = struct.unpack("<%dh" % (n * ch), w.readframes(n))
                mono = raw[::ch]  # left channel is plenty for an envelope
                peak = max(abs(x) for x in mono) or 1
                a30 = mono[:max(1, int(0.03 * sr))]
                attack = max(abs(x) for x in a30) / peak
                win = max(1, sr // 100)  # 10 ms windows
                ring = 0.0
                thresh = 0.15 * peak
                for i in range(0, len(mono), win):
                    if max(abs(x) for x in mono[i:i + win]) > thresh:
                        ring = min(dur, (i + win) / sr)
                out = {"dur": round(dur, 3), "attack": round(attack, 3),
                       "ring": round(ring, 3), "analyzed": True}
        _analysis_cache[path] = (st.st_mtime, out)
        return out
    except Exception:
        return {"dur": None, "analyzed": False}


def probe_duration(path):
    """Non-WAV fallback: ffprobe if present, else unknown."""
    if not shutil.which("ffprobe"):
        return None
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                            "format=duration", "-of", "csv=p=0", path],
                           capture_output=True, text=True, timeout=10)
        return round(float(r.stdout.strip()), 3)
    except Exception:
        return None


def bank_size(dur, override):
    """The engine's adaptive polyphony: ~one voice per 0.1s, capped, override wins."""
    if override:
        return max(1, min(VOICE_CAP, override))
    if not dur:
        return VOICE_CAP
    import math
    return max(1, min(VOICE_CAP, math.ceil(dur / 0.1)))


# ---------------------------------------------------------------- scanning

def read_sidecar(setdir, name):
    try:
        with open(os.path.join(setdir, name)) as f:
            return f.read().strip()
    except OSError:
        return None


def scan_sets():
    """Unique set names across soundDirs, first dir wins — mirrors obj:_sets()."""
    out = {}
    for dirpath, source in SOUND_DIRS:
        if not os.path.isdir(dirpath):
            continue
        for d in sorted(os.listdir(dirpath)):
            full = os.path.join(dirpath, d)
            if d.startswith((".", "_")) or not os.path.isdir(full) or d in out:
                continue
            out[d] = (full, source)
    return out


def describe_set(name, setdir, source):
    cat_raw = read_sidecar(setdir, "category") or ""
    cat = cat_raw.split()[0].lower() if cat_raw.split() else "other"
    if cat == "samples":  # compatibility with personal sets created before 2.3
        cat = "keyboard"
    if cat not in CATEGORIES:
        cat = "other"
    voices_raw = read_sidecar(setdir, "voices")
    override = None
    if voices_raw:
        digits = "".join(c for c in voices_raw if c.isdigit())
        override = int(digits) if digits else None

    roles = {}
    for f in sorted(os.listdir(setdir)):
        ext = os.path.splitext(f)[1].lower()
        if ext not in AUDIO_RE_EXT:
            continue
        stem = os.path.splitext(f)[0].rstrip("0123456789")
        if stem not in GENERIC and stem not in DEDICATED:
            continue
        path = os.path.join(setdir, f)
        info = analyze_wav(path) if ext == ".wav" else \
            {"dur": probe_duration(path), "analyzed": False}
        info["file"] = f
        info["bank"] = bank_size(info.get("dur"), override)
        roles.setdefault(stem, []).append(info)

    # which roles resolve through a fallback chain (and to what), or go silent
    fallbacks, silent = {}, []
    for role, chain in FALLBACK.items():
        if role in roles:
            continue
        target = next((t for t in chain if t in roles), None)
        if target:
            fallbacks[role] = target
        else:
            silent.append(role)

    # chunky ↔ flowy: ring time carries 70%, softness of attack 30%
    downs = [i for i in roles.get("down", []) if i.get("analyzed")]
    flow = None
    if downs:
        mean_ring = sum(i["ring"] for i in downs) / len(downs)
        mean_attack = sum(i["attack"] for i in downs) / len(downs)
        r = max(0.0, min(1.0, (mean_ring - 0.05) / 0.55))
        flow = round(0.7 * r + 0.3 * (1.0 - mean_attack), 3)
    label = None
    if flow is not None:
        label = "chunky" if flow < 0.35 else ("flowy" if flow > 0.65 else "balanced")

    # an environment is a compiled set carrying its own recipe
    environment = None
    envpath = os.path.join(setdir, "environment.json")
    if os.path.isfile(envpath):
        try:
            with open(envpath) as f:
                environment = json.load(f)
        except (OSError, ValueError):
            environment = {"error": "unreadable environment.json"}

    return {
        "name": name, "source": source, "category": cat,
        "voicesOverride": override, "roles": roles, "environment": environment,
        "fallbacks": fallbacks, "silent": silent,
        "character": {
            "flow": flow, "label": label,
            "meanRing": round(sum(i["ring"] for i in downs) / len(downs), 3) if downs else None,
            "meanAttack": round(sum(i["attack"] for i in downs) / len(downs), 3) if downs else None,
            "meanDur": round(sum(i["dur"] for i in downs) / len(downs), 3) if downs else None,
        },
    }


def scan_ambient():
    out = {}
    for dirpath, source in AMBIENT_DIRS:
        if not os.path.isdir(dirpath):
            continue
        for f in sorted(os.listdir(dirpath)):
            name, ext = os.path.splitext(f)
            if f.startswith((".", "_")) or ext.lower() not in AMBIENT_EXT or name in out:
                continue
            path = os.path.join(dirpath, f)
            dur = analyze_wav(path)["dur"] if ext.lower() == ".wav" else probe_duration(path)
            out[name] = {"name": name, "file": f, "source": source,
                         "dur": dur, "size": os.path.getsize(path), "_path": path}
    return out


# ---------------------------------------------------------------- environments

def scale_wav(src, dst, gain):
    """Bake a gain into a 16-bit WAV by scaling samples (clamped). The engine
    has no per-file volume knob, so per-sound volume becomes data, not config."""
    try:
        with wave.open(src, "rb") as w:
            params = w.getparams()
            if params.sampwidth != 2:
                return False
            frames = w.readframes(params.nframes)
        n = len(frames) // 2
        vals = struct.unpack("<%dh" % n, frames)
        out = struct.pack("<%dh" % n,
                          *(max(-32768, min(32767, int(v * gain))) for v in vals))
        with wave.open(dst, "wb") as w:
            w.setparams(params)
            w.writeframes(out)
        return True
    except Exception:
        return False


def ffmpeg_gain(src, dst, gain):
    if not shutil.which("ffmpeg"):
        return False
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src,
                        "-filter:a", "volume=%.3f" % gain, dst],
                       check=True, timeout=60)
        return True
    except Exception:
        return False


def pool_files(setdir, stem):
    """All audio files in a set folder whose stem matches (down -> down1..N)."""
    out = []
    for f in sorted(os.listdir(setdir)):
        ext = os.path.splitext(f)[1].lower()
        if ext in AUDIO_RE_EXT and os.path.splitext(f)[0].rstrip("0123456789") == stem:
            out.append(f)
    return out


def compile_environment(m):
    """Materialize an environment manifest as a plain set folder.

    Starts from the base set's files, replaces overridden roles with sounds
    referenced from ANY set (single file, or a whole stem pool), bakes each
    override's gain into the samples, and writes the manifest alongside as
    environment.json — the folder is self-describing and playable by the
    engine with zero engine changes. Raises ValueError with a reason on bad
    input; returns a report dict (files written + warnings).
    """
    name = (m.get("name") or "").strip()
    base = m.get("base")
    if not safe_name(name):
        raise ValueError("environment name: letters, digits, space . _ - only")
    sets = scan_sets()
    if base not in sets:
        raise ValueError("unknown base set %r" % base)
    if name == base:
        raise ValueError("an environment cannot be based on itself")

    user_dir = expand("~/Music/Klonk/keyboard")
    out_dir = os.path.join(user_dir, name)
    if name in sets:
        existing, src = sets[name]
        if src == "bundled":
            raise ValueError("%r is a bundled set — pick another name" % name)
        if os.path.realpath(existing) != os.path.realpath(out_dir):
            raise ValueError("%r already exists in %s" % (name, existing))
        if not os.path.isfile(os.path.join(existing, "environment.json")):
            raise ValueError("a hand-made set named %r exists — refusing to overwrite it" % name)

    base_dir = sets[base][0]
    overrides = m.get("roles") or {}
    warnings = []

    # PLAN before touching disk: out_filename -> (source_path, gain)
    plan = {}
    for f in sorted(os.listdir(base_dir)):
        ext = os.path.splitext(f)[1].lower()
        if ext not in AUDIO_RE_EXT:
            continue
        stem = os.path.splitext(f)[0].rstrip("0123456789")
        if (stem in GENERIC or stem in DEDICATED) and stem not in overrides:
            plan[f] = (os.path.join(base_dir, f), 1.0)

    clean_roles = {}
    for role, ov in overrides.items():
        if role not in GENERIC and role not in DEDICATED:
            raise ValueError("unknown role %r" % role)
        try:
            gain = max(0.0, min(2.0, float(ov.get("gain", 1.0))))
        except (TypeError, ValueError):
            raise ValueError("bad gain for role %r" % role)
        src_set = ov.get("set")
        if src_set not in sets:
            raise ValueError("role %r references unknown set %r" % (role, src_set))
        src_dir = sets[src_set][0]
        entry = {"set": src_set, "gain": gain}
        if ov.get("file"):
            f = ov["file"]
            if not safe_name(f) or "/" in f or not os.path.isfile(os.path.join(src_dir, f)):
                raise ValueError("role %r: file %r not found in %r" % (role, f, src_set))
            ext = os.path.splitext(f)[1].lower()
            out_name = role + ("1" if role in GENERIC else "") + ext
            plan[out_name] = (os.path.join(src_dir, f), gain)
            entry["file"] = f
        elif ov.get("pool"):
            stem = ov["pool"]
            files = pool_files(src_dir, stem)
            if not files:
                raise ValueError("role %r: set %r has no %r pool" % (role, src_set, stem))
            if role in DEDICATED:
                files = files[:1]
            for i, f in enumerate(files, 1):
                ext = os.path.splitext(f)[1].lower()
                out_name = role + (str(i) if role in GENERIC else "") + ext
                plan[out_name] = (os.path.join(src_dir, f), gain)
            entry["pool"] = stem
        else:
            raise ValueError("role %r override needs 'file' or 'pool'" % role)
        clean_roles[role] = entry

    # ACT: write the folder, clearing audio left over from a previous compile
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if os.path.splitext(f)[1].lower() in AUDIO_RE_EXT and f not in plan:
            os.remove(os.path.join(out_dir, f))
    written = []
    for out_name, (src, gain) in sorted(plan.items()):
        dst = os.path.join(out_dir, out_name)
        if abs(gain - 1.0) < 1e-3:
            shutil.copyfile(src, dst)
        elif src.lower().endswith(".wav") and scale_wav(src, dst, gain):
            pass
        elif ffmpeg_gain(src, dst, gain):
            pass
        else:
            shutil.copyfile(src, dst)
            warnings.append("%s: gain not baked (unsupported format, no ffmpeg)" % out_name)
        written.append(out_name)

    with open(os.path.join(out_dir, "category"), "w") as f:
        f.write("environment\n")
    voices = m.get("voices")
    vpath = os.path.join(out_dir, "voices")
    if voices:
        with open(vpath, "w") as f:
            f.write("%d\n" % int(voices))
    else:
        base_voices = read_sidecar(base_dir, "voices")
        if base_voices:
            with open(vpath, "w") as f:
                f.write(base_voices + "\n")
        elif os.path.exists(vpath):
            os.remove(vpath)

    ambient = m.get("ambient")
    if ambient and ambient not in scan_ambient():
        warnings.append("ambient sound %r not found — saved anyway" % ambient)
    manifest = {"name": name, "base": base, "roles": clean_roles,
                "ambient": ambient, "voices": int(voices) if voices else None}
    with open(os.path.join(out_dir, "environment.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    return {"ok": True, "folder": out_dir, "files": written, "warnings": warnings}


def delete_environment(name):
    sets = scan_sets()
    if name not in sets:
        raise ValueError("unknown set")
    setdir, src = sets[name]
    if not os.path.isfile(os.path.join(setdir, "environment.json")):
        raise ValueError("%r is not an environment — refusing to delete a real set" % name)
    shutil.rmtree(setdir)
    return {"ok": True, "deleted": setdir}


# ---------------------------------------------------------------- hammerspoon

def hs_cli():
    found = shutil.which("hs")
    if found:
        return found
    for path in ("/opt/homebrew/bin/hs", "/usr/local/bin/hs"):
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def hs_eval(lua):
    """Run Lua in the live Hammerspoon via the hs CLI. Returns (ok, output)."""
    cli = hs_cli()
    if not cli:
        return False, "hs CLI not installed (run hs.ipc.cliInstall() in the HS console)"
    try:
        command = [cli, "-c", lua]
        if os.path.isfile("/bin/launchctl"):
            command = ["/bin/launchctl", "asuser", str(os.getuid())] + command
        r = subprocess.run(command, capture_output=True, text=True, timeout=12)
        if r.returncode != 0:
            return False, (r.stderr or r.stdout).strip()
        return True, r.stdout.strip()
    except subprocess.TimeoutExpired:
        return False, "hs CLI timed out — is Hammerspoon running?"
    except Exception as e:
        return False, str(e)


def engine_state():
    ok, out = hs_eval(
        'local K = spoon and spoon.Klonk; if not K then return "null" end; '
        'return hs.json.encode({set=K._set, ambient=K._ambient, on=K._on, '
        'mouse=K._mouse, vol=K._vol, ambientvol=K._ambientVol})')
    if not ok:
        return None, out
    try:
        return json.loads(out), None
    except ValueError:
        return None, "unexpected hs output: " + out[:120]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


SAFE = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")


def safe_name(s):
    return isinstance(s, str) and 0 < len(s) < 120 and all(c in SAFE for c in s)


# ---------------------------------------------------------------- http

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store" if ctype.startswith("application") else "max-age=60")
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path):
        ext = os.path.splitext(path)[1].lower()
        try:
            with open(path, "rb") as f:
                self._send(200, f.read(), MIME.get(ext, "application/octet-stream"))
        except OSError:
            self._send(404, {"error": "not found"})

    def do_GET(self):
        parts = [unquote(p) for p in self.path.split("?")[0].split("/") if p]
        if not parts:
            return self._send_file(HTML)
        if parts == ["api", "state"]:
            return self._send(200, self.state())
        if len(parts) == 4 and parts[:2] == ["audio", "set"]:
            _, _, name, fname = parts
            sets = scan_sets()
            if name in sets and safe_name(fname) and "/" not in fname:
                return self._send_file(os.path.join(sets[name][0], fname))
        if len(parts) == 3 and parts[:2] == ["audio", "ambient"]:
            ambient = scan_ambient().get(parts[2])
            if ambient:
                return self._send_file(ambient["_path"])
        if parts == ["favicon.ico"]:
            return self._send(204, b"", "image/x-icon")
        self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        try:
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return self._send(400, {"error": "bad json"})

        if path == "/api/environment":
            try:
                return self._send(200, compile_environment(req))
            except ValueError as e:
                return self._send(400, {"error": str(e)})
        if path != "/api/apply":
            return self._send(404, {"error": "not found"})

        results = {}
        if "set" in req:
            name = req["set"]
            if not safe_name(name) or name not in scan_sets():
                return self._send(400, {"error": "unknown set"})
            ok, out = hs_eval(
                "spoon.Klonk:_load(%s); spoon.Klonk:_refresh(); "
                "hs.alert.show('klonk: ' .. %s, 0.7); return 'ok'"
                % (lua_str(name), lua_str(name)))
            results["set"] = {"ok": ok, "detail": out}
        if "ambient" in req:
            ambient = req["ambient"]
            if ambient is not None and (not safe_name(ambient) or ambient not in scan_ambient()):
                return self._send(400, {"error": "unknown ambient sound"})
            arg = lua_str(ambient) if ambient else "nil"
            ok, out = hs_eval(
                "spoon.Klonk:_playAmbient(%s); spoon.Klonk:_refresh(); return 'ok'" % arg)
            results["ambient"] = {"ok": ok, "detail": out}
        if not results:
            return self._send(400, {"error": "nothing to apply (send set and/or ambient)"})
        code = 200 if all(r["ok"] for r in results.values()) else 502
        self._send(code, results)

    def do_DELETE(self):
        parts = [unquote(p) for p in self.path.split("?")[0].split("/") if p]
        if len(parts) == 3 and parts[:2] == ["api", "environment"]:
            try:
                return self._send(200, delete_environment(parts[2]))
            except ValueError as e:
                return self._send(400, {"error": str(e)})
        self._send(404, {"error": "not found"})

    def state(self):
        sets = [describe_set(n, d, src) for n, (d, src) in scan_sets().items()]
        sets.sort(key=lambda s: (CATEGORIES.index(s["category"]), s["name"]))
        ambient = [{k: v for k, v in sound.items() if not k.startswith("_")}
                   for sound in scan_ambient().values()]
        engine, err = engine_state()
        return {
            "sets": sets, "ambient": ambient, "categories": CATEGORIES,
            "fallbackChains": FALLBACK, "voiceCap": VOICE_CAP,
            "hs": {"cli": bool(hs_cli()), "engine": engine, "error": err},
            "dirs": {"sounds": [d for d, _ in SOUND_DIRS],
                     "ambient": [d for d, _ in AMBIENT_DIRS]},
        }


def main():
    port = 8801
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    n_sets, n_ambient = len(scan_sets()), len(scan_ambient())
    print(f"klonk studio: http://127.0.0.1:{port}  "
          f"({n_sets} sets, {n_ambient} ambient sounds, hs CLI {'found' if hs_cli() else 'NOT found — apply disabled'})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
