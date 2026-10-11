// Klonk live performer: chamber music in a small salon (Versailles, or Vienna).
//
//   each keystroke   the first violin plays the next note of a real theme: the
//                    Minuet in G (BWV Anh. 114, attributed to Petzold) and the opening
//                    of Mozart's Eine kleine Nachtmusik, phrase by phrase
//   new bars         the cello takes the bass; then the viola fills the harmony, a
//                    second violin doubles a third below, and the harpsichord
//                    continuo rolls each chord, as the sentence grows
//   typing speed     phrasing: quick taps are crisp, slow typing sings
//   holding a key    the violin trills on the note
//   comma            the bow lifts
//   backspace        plays the previous note again
//   period / Return  a galant cadence: a trill over the dominant seventh, then the
//                    full ensemble resolves home; the next keystroke begins a new phrase
//
// Event-driven, like the orchestra: each keystroke schedules its own envelopes, so
// nothing depends on page timers. Strings are GeneralUser GS renders; the harpsichord
// is Klonk's physical model (chamber-samples.js).
(function (global) {
    'use strict';

    // ---- the conductor: keystrokes in, musical decisions out (no audio) ----
    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const SCALE = [0, 2, 4, 6, 7, 9, 11];                      // G major
    const CHORDS = {
        G: { bass: 43, inner: [59, 62], harp: [43, 55, 59, 62, 67] },
        C: { bass: 48, inner: [60, 64], harp: [48, 55, 60, 64, 67] },
        D: { bass: 50, inner: [54, 57], harp: [50, 54, 57, 62, 66] },
        D7: { bass: 50, inner: [57, 60], harp: [50, 54, 57, 60, 66] },
    };
    const N = (name) => {
        const m = /^([A-G])(#|b)?(\d)$/.exec(name);
        return 12 * (+m[3] + 1) + { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 }[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
    };
    const bars = (list) => list.map(([chord, notes]) => ({ chord, notes: notes.split(' ').map(N) }));
    const MINUET_A = bars([['G', 'D5 G4 A4 B4 C5'], ['G', 'D5 G4 G4'], ['C', 'E5 C5 D5 E5 F#5'], ['G', 'G5 G4 G4'],
        ['C', 'C5 D5 C5 B4 A4'], ['G', 'B4 C5 B4 A4 G4'], ['D', 'F#4 G4 A4 B4 G4'], ['D', 'A4']]);
    const MINUET_B = bars([['G', 'D5 G4 A4 B4 C5'], ['G', 'D5 G4 G4'], ['C', 'E5 C5 D5 E5 F#5'], ['G', 'G5 G4 G4'],
        ['C', 'C5 D5 C5 B4 A4'], ['G', 'B4 C5 B4 A4 G4'], ['D7', 'A4 B4 A4 G4 F#4'], ['G', 'G4']]);
    const NACHTMUSIK = bars([['G', 'G4 D4 G4 D4'], ['G', 'G4 D4 G4 B4 D5'], ['D7', 'C5 A4 C5 A4'], ['D7', 'C5 A4 F#4 A4 D4']]);
    const PHRASES = [
        { title: 'Minuet in G', bars: MINUET_A }, { title: 'Eine kleine Nachtmusik', bars: NACHTMUSIK },
        { title: 'Minuet in G', bars: MINUET_B }, { title: 'Eine kleine Nachtmusik', bars: NACHTMUSIK },
    ];
    const LEVELS = [0, 6, 14, 24];                              // cello, + viola, + second violin, + harpsichord

    function step(m, steps) {                                  // move along the G major scale
        const pcs = SCALE, oct = Math.floor(m / 12), pc = ((m % 12) + 12) % 12;
        let idx = pcs.indexOf(pc); if (idx < 0) return m + (steps > 0 ? 2 : -3);
        idx += steps;
        return 12 * (oct + Math.floor(idx / 7)) + pcs[((idx % 7) + 7) % 7];
    }
    function sequence(phrase) {
        const out = [];
        phrase.bars.forEach((b, bar) => b.notes.forEach((m, k) => out.push({ m, chord: b.chord, barStart: k === 0, bar })));
        return out;
    }

    class Conductor {
        constructor() { this.phrase = 0; this.pos = 0; this.keys = 0; this.last = null; }
        get intensity() { let i = 0; LEVELS.forEach((n, k) => { if (this.keys >= n) i = k; }); return i; }
        get title() { return PHRASES[this.phrase % PHRASES.length].title; }
        notes() { return sequence(PHRASES[this.phrase % PHRASES.length]); }
        play(n, I) {
            const out = [];
            if (n.barStart) out.push({ type: 'chord', chord: n.chord, intensity: I });
            out.push({ type: 'note', m: n.m, second: I >= 2 ? step(n.m, -2) : null, upper: step(n.m, 1) });
            this.last = n;
            return out;
        }
        key(code) {
            if (code === KEY.RETURN || code === KEY.PERIOD) {
                const I = this.intensity;
                this.phrase = (this.phrase + 1) % PHRASES.length; this.pos = 0; this.keys = 0; this.last = null;
                return [{ type: 'cadence', intensity: I }];
            }
            if (code === KEY.COMMA) return [{ type: 'lift' }];
            if (code === KEY.BACKSPACE) return this.last ? this.play(Object.assign({}, this.last, { barStart: false }), this.intensity) : [];
            this.keys++;
            let seq = this.notes();
            if (this.pos >= seq.length) { this.phrase = (this.phrase + 1) % PHRASES.length; this.pos = 0; seq = this.notes(); }
            return this.play(seq[this.pos++], this.intensity);
        }
    }
    global.ChamberConductor = { Conductor, PHRASES, CHORDS, LEVELS, step, N };
    if (!global.document) return;

    // ---- the renderer: a string quartet and harpsichord in a small, warm room ----
    const errors = [];
    global.addEventListener('error', (e) => errors.push(String(e.message)));
    global.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));
    const LEVEL = { violin: 0.55, second: 0.32, viola: 0.34, cello: 0.48, harpsichord: 0.42 };
    const BANK = { second: 'violin' };
    const P = { ctx: null, ready: false, error: '', buffers: {}, parts: {}, meter: null, master: null,
        lead: [], accomp: [], trill: [], conductor: new Conductor(), held: new Set(), ioi: 0.35, lastDown: 0, volume: 0.7, events: 0 };

    function salon(ctx) {                                      // a small panelled room: early reflections, ~1 s tail
        const seconds = 1.1, n = Math.floor(ctx.sampleRate * seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch); let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * 0.5 + (Math.random() * 2 - 1) * 0.5;
                d[i] = lp * 0.5 * Math.exp(-t * 6.9 / seconds) * (t < 0.008 ? 0 : 1);
            }
            [0.009, 0.014, 0.021, 0.027, 0.036, 0.043].forEach((t, k) => { const i = Math.floor((t + ch * 0.002) * ctx.sampleRate); d[i] += 0.6 / (k + 1); });
        }
        return ir;
    }

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            const jobs = [];
            for (const [part, notes] of Object.entries(global.CHAMBER)) {
                P.buffers[part] = {};
                for (const [m, b64] of Object.entries(notes)) {
                    const bin = atob(b64), buf = new Uint8Array(bin.length);
                    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
                    jobs.push(ctx.decodeAudioData(buf.buffer).then((b) => { P.buffers[part][m] = b; }));
                }
            }
            await Promise.all(jobs);
            P.master = ctx.createGain(); P.master.gain.value = P.volume; P.master.connect(ctx.destination);
            const room = ctx.createConvolver(); room.buffer = salon(ctx);
            const wet = ctx.createGain(); wet.gain.value = 0.3; room.connect(wet); wet.connect(P.master);
            const bus = ctx.createGain(); bus.connect(P.master); bus.connect(room);
            P.meter = ctx.createAnalyser(); P.meter.fftSize = 2048; bus.connect(P.meter);
            for (const p of Object.keys(LEVEL)) { const g = ctx.createGain(); g.gain.value = LEVEL[p]; g.connect(bus); P.parts[p] = g; }
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function note(part, m, when, gain, attack) {
        const bank = P.buffers[BANK[part] || part], roots = Object.keys(bank).map(Number);
        const root = roots.reduce((a, b) => Math.abs(b - m) < Math.abs(a - m) ? b : a);
        const src = P.ctx.createBufferSource(); src.buffer = bank[root];
        src.playbackRate.value = Math.pow(2, (m - root) / 12);
        const env = P.ctx.createGain();
        env.gain.setValueAtTime(0, when); env.gain.linearRampToValueAtTime(gain, when + attack);
        src.connect(env); env.connect(P.parts[part]); src.start(when);
        return { src, env };
    }
    function release(v, when, seconds) {
        const g = v.env.gain;
        g.cancelScheduledValues(when); g.setValueAtTime(g.value, when); g.setTargetAtTime(0, when, Math.max(0.01, seconds / 3));
        try { v.src.stop(when + seconds * 1.8 + 0.05); } catch (e) {}
    }
    const releaseAll = (list, when, seconds) => { list.forEach((v) => release(v, when, seconds)); return []; };
    const phrasing = () => Math.min(0.6, Math.max(0.08, P.ioi * 0.8));

    function stopTrill(now) { P.trill.forEach((v) => { try { v.src.stop(now); } catch (e) {} }); P.trill = []; }

    // Held keys trill: alternating with the upper neighbour, pre-scheduled and cancelled on release.
    function scheduleTrill(m, upper, start) {
        const rate = 0.075;
        for (let k = 0; k < 24; k++) P.trill.push(note('violin', k % 2 ? m : upper, start + k * rate, 0.85, 0.008));
        P.trill.forEach((v, k) => { const t = start + k * rate; v.env.gain.setTargetAtTime(0, t + rate * 0.9, 0.02); try { v.src.stop(t + rate * 2); } catch (e) {} });
    }

    function chord(a, now) {
        P.accomp = releaseAll(P.accomp, now, 0.25);
        const c = CHORDS[a.chord];
        P.accomp.push(note('cello', c.bass, now, 0.9, 0.04));
        if (a.intensity >= 1) c.inner.forEach((m) => P.accomp.push(note('viola', m, now, 0.7, 0.06)));
        if (a.intensity >= 3) c.harp.forEach((m, k) => P.accomp.push(note('harpsichord', m, now + k * 0.028, 0.8, 0.003)));
        P.accomp.forEach((v) => v.env.gain.setTargetAtTime(0, now + 2.0, 0.25));      // ring, then let go
    }

    function lead(a, now) {
        stopTrill(now);
        P.lead = releaseAll(P.lead, now, 0.06);                 // legato hand-off
        P.lead.push(note('violin', a.m, now, 0.9, 0.025));
        if (a.second !== null) P.lead.push(note('second', a.second, now, 0.8, 0.03));
        P.leadNote = a;
        if (!P.held.size) P.lead = releaseAll(P.lead, now + phrasing(), phrasing());
        else scheduleTrill(a.m, a.upper, now + 0.42);
    }

    function cadence(a, now) {
        stopTrill(now);
        P.lead = releaseAll(P.lead, now, 0.08); P.accomp = releaseAll(P.accomp, now, 0.15);
        const t1 = now + 0.02, t2 = now + 0.95, ring = [];
        const D7 = CHORDS.D7, G = CHORDS.G;
        ring.push(note('cello', D7.bass, t1, 0.9, 0.04));
        D7.inner.forEach((m) => ring.push(note('viola', m, t1, 0.75, 0.05)));
        D7.harp.forEach((m, k) => ring.push(note('harpsichord', m, t1 + k * 0.03, 0.8, 0.003)));
        ring.push(note('second', 66, t1, 0.75, 0.03));
        P.trill = []; scheduleTrill(69, 71, t1 + 0.12);         // the cadential trill on A over D7
        ring.forEach((v) => release(v, t2, 0.12));
        const fin = [note('cello', G.bass, t2, 1.0, 0.03), note('cello', 55, t2, 0.6, 0.03), note('violin', 67, t2, 1.0, 0.03),
            note('second', 59, t2, 0.8, 0.03)];
        G.inner.forEach((m) => fin.push(note('viola', m, t2, 0.8, 0.04)));
        if (a.intensity >= 1) G.harp.forEach((m, k) => fin.push(note('harpsichord', m, t2 + k * 0.035, 0.85, 0.003)));
        fin.forEach((v) => { v.env.gain.setTargetAtTime(0, t2 + 1.4, 0.35); try { v.src.stop(t2 + 3.2); } catch (e) {} });
        P.trill.forEach((v) => { try { v.src.stop(t2); } catch (e) {} });
        P.trill = [];
    }

    function handle(list) {
        for (const [type, code, ms, repeat] of list) {
            const now = P.ctx.currentTime + 0.01;
            if (type === 'd') {
                if (repeat) continue;
                P.held.add(code);
                const dt = (ms - P.lastDown) / 1000;
                if (P.lastDown && dt < 2.5) P.ioi = P.ioi * 0.7 + Math.min(1.2, Math.max(0.08, dt)) * 0.3;
                P.lastDown = ms;
                for (const a of P.conductor.key(code)) {
                    if (a.type === 'chord') chord(a, now);
                    else if (a.type === 'note') lead(a, now);
                    else if (a.type === 'cadence') cadence(a, now);
                    else if (a.type === 'lift') { stopTrill(now); P.lead = releaseAll(P.lead, now, 0.05); }
                }
            } else {
                P.held.delete(code);
                if (!P.held.size) { stopTrill(now); P.lead = releaseAll(P.lead, now, phrasing()); }
            }
        }
    }

    global.K = {
        events(list) {
            if (!P.ready) return 'not-ready';
            P.events += list.length;
            try { handle(list); } catch (e) { errors.push(String(e && e.stack || e)); }   // injected calls hide messages
            return 'ok';
        },
        volume(v) { P.volume = v; if (P.master) P.master.gain.setTargetAtTime(v, P.ctx.currentTime, 0.05); },
        stop() {
            P.held.clear(); P.conductor = new Conductor();
            if (!P.ready) return;
            const now = P.ctx.currentTime;
            stopTrill(now); P.lead = releaseAll(P.lead, now, 0.1); P.accomp = releaseAll(P.accomp, now, 0.2);
        },
        level() {
            if (!P.meter) return -Infinity;
            const a = new Float32Array(P.meter.fftSize); P.meter.getFloatTimeDomainData(a);
            let e = 0; for (const x of a) e += x * x;
            return +(10 * Math.log10(e / a.length + 1e-12)).toFixed(1);
        },
        status() {
            const c = P.conductor;
            return JSON.stringify({ ready: P.ready, error: P.error, errors: errors.slice(-5), state: P.ctx && P.ctx.state,
                events: P.events, piece: c.title, phrase: c.phrase, position: c.pos, keys: c.keys, intensity: c.intensity });
        },
    };
    init();
})(typeof window !== 'undefined' ? window : globalThis);
