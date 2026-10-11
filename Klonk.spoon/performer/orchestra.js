// Klonk live performer: orchestral build-up. A sentence builds, Return lands it.
//
//   type             pizzicato strings pick out the current chord, a string pad beneath
//   keep typing      the harmony walks Dm, Bb, F, C, Dm, Bb, Gm and parks on A (the
//                    dominant); cellos, then horns, then brass join, and timpani strokes
//                    follow your keystrokes, so typing becomes the roll
//   hold keys        the orchestra swells
//   comma            a breath
//   backspace        steps back a chord
//   period / Return  the cadence: full orchestra, timpani, bass drum and crash, in
//                    D major if you built all the way to the dominant, else D minor
//   stop typing      every keystroke schedules its own fade, so silence fades it out
//
// Hidden pages throttle timers, so nothing here runs on setInterval: each keystroke
// schedules the envelopes it needs on the audio clock. Notes are GeneralUser GS
// renders (orchestra-samples.js), repitched from the nearest of a 3-semitone grid.
(function (global) {
    'use strict';

    // ---- the conductor: keystrokes in, musical decisions out (no audio here) ----
    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const CHORDS = {
        Dm: { root: 38, pcs: [2, 5, 9] }, Bb: { root: 46, pcs: [10, 2, 5] }, F: { root: 41, pcs: [5, 9, 0] },
        C: { root: 48, pcs: [0, 4, 7] }, Gm: { root: 43, pcs: [7, 10, 2] }, A: { root: 45, pcs: [9, 1, 4] },
        D: { root: 38, pcs: [2, 6, 9] },
    };
    const PROGRESSION = ['Dm', 'Bb', 'F', 'C', 'Dm', 'Bb', 'Gm', 'A'];   // the last chord is held: the dominant
    const KEYS_PER_CHORD = 5;
    const LEVELS = [0, 6, 14, 24, 34];                                    // keystrokes for each layer
    const SECTIONS_AT = [['strings'], ['strings', 'low'], ['strings', 'low', 'horns'],
        ['strings', 'low', 'horns', 'brass'], ['strings', 'low', 'horns', 'brass', 'high']];

    function voicing(pcs, lo, count) {
        const out = [];
        for (let m = lo; out.length < count && m < lo + 36; m++) if (pcs.includes(((m % 12) + 12) % 12)) out.push(m);
        return out;
    }

    class Conductor {
        constructor() { this.reset(); }
        reset() { this.keys = 0; this.chord = 0; this.arp = 0; }
        get intensity() { let i = 0; LEVELS.forEach((n, k) => { if (this.keys >= n) i = k; }); return i; }
        get chordName() { return PROGRESSION[Math.min(this.chord, PROGRESSION.length - 1)]; }
        chordAction() {
            const name = this.chordName, I = this.intensity;
            return { type: 'chord', name, sections: SECTIONS_AT[I], intensity: I };
        }
        key(code) {
            if (code === KEY.RETURN || code === KEY.PERIOD) {
                const I = this.intensity, home = this.chordName === 'A' ? 'D' : 'Dm';
                this.reset();
                return [{ type: 'cadence', name: home, intensity: I }];
            }
            if (code === KEY.COMMA) return [{ type: 'breath' }];
            if (code === KEY.BACKSPACE) {
                this.chord = Math.max(0, Math.min(this.chord, PROGRESSION.length - 1) - 1);
                this.keys = Math.min(this.keys, this.chord * KEYS_PER_CHORD + 1);
                return [this.chordAction(), { type: 'hold' }];
            }
            const before = this.keys === 0 ? -1 : this.chord, layersBefore = this.intensity;
            this.keys++;
            this.chord = Math.min(PROGRESSION.length - 1, Math.floor((this.keys - 1) / KEYS_PER_CHORD));
            const out = [];
            if (this.chord !== before || this.intensity !== layersBefore) out.push(this.chordAction());
            const c = CHORDS[this.chordName], arp = voicing(c.pcs, 62, 6), I = this.intensity;
            const pattern = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1];
            out.push({ type: 'pizz', note: arp[pattern[this.arp++ % pattern.length]], velocity: 0.45 + 0.1 * I });
            if (I >= 3) out.push({ type: 'timp', note: voicing([c.pcs[0]], 38, 1)[0], velocity: 0.25 + 0.12 * (I - 3) + Math.random() * 0.08 });
            out.push({ type: 'hold' });
            return out;
        }
    }
    global.OrchestraConductor = { Conductor, CHORDS, PROGRESSION, KEYS_PER_CHORD, LEVELS, voicing };
    if (!global.document) return;   // loaded headlessly for tests: the conductor is all there is

    // ---- the renderer: sampled orchestra, scheduled on the audio clock ----
    const errors = [];
    global.addEventListener('error', (e) => errors.push(String(e.message)));
    global.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));

    const LEVEL = { strings: 0.42, high: 0.3, low: 0.5, horns: 0.36, brass: 0.34, pizz: 0.5, timp: 0.55, kit: 0.7 };
    const ATTACK = { strings: 0.35, high: 0.4, low: 0.3, horns: 0.45, brass: 0.25 };
    const SAMPLE = { high: 'strings', timp: 'timpani' };
    const P = { ctx: null, ready: false, error: '', buffers: {}, master: null, expr: null, sections: {}, meter: null,
        pads: [], chord: '', conductor: new Conductor(), held: new Set(), volume: 0.7, events: 0 };

    function hall(ctx, seconds) {
        const n = Math.floor(ctx.sampleRate * seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch); let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * 0.7 + (Math.random() * 2 - 1) * 0.3;
                d[i] = lp * Math.exp(-t * 6.9 / seconds) * (t < 0.03 ? t / 0.03 : 1);
            }
        }
        return ir;
    }

    async function decode(b64) {
        const bin = atob(b64), buf = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
        return P.ctx.decodeAudioData(buf.buffer);
    }

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            const jobs = [];
            for (const [section, notes] of Object.entries(global.ORCHESTRA)) {
                P.buffers[section] = {};
                for (const [m, b64] of Object.entries(notes)) jobs.push(decode(b64).then((b) => { P.buffers[section][m] = b; }));
            }
            await Promise.all(jobs);
            P.master = ctx.createGain(); P.master.gain.value = P.volume; P.master.connect(ctx.destination);
            const verb = ctx.createConvolver(); verb.buffer = hall(ctx, 3.2);
            const wet = ctx.createGain(); wet.gain.value = 0.38; verb.connect(wet); wet.connect(P.master);
            const bus = ctx.createGain(); bus.connect(P.master); bus.connect(verb);
            P.meter = ctx.createAnalyser(); P.meter.fftSize = 2048; bus.connect(P.meter);
            P.expr = ctx.createGain(); P.expr.gain.value = 1; P.expr.connect(bus);
            for (const s of Object.keys(LEVEL)) { const g = ctx.createGain(); g.gain.value = LEVEL[s]; g.connect(P.expr); P.sections[s] = g; }
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function note(section, m, when, gain, attack) {
        const bank = P.buffers[SAMPLE[section] || section], roots = Object.keys(bank).map(Number);
        const root = roots.reduce((a, b) => Math.abs(b - m) < Math.abs(a - m) ? b : a);
        const src = P.ctx.createBufferSource(); src.buffer = bank[root];
        src.playbackRate.value = Math.pow(2, (m - root) / 12);
        const env = P.ctx.createGain();
        env.gain.setValueAtTime(0, when);
        env.gain.linearRampToValueAtTime(gain, when + (attack || 0.005));
        src.connect(env); env.connect(P.sections[section]);
        src.start(when);
        return { src, env, section, m, gain, born: when, attack: attack || 0.005 };
    }

    function release(pad, when, seconds) {
        const g = pad.env.gain;
        g.cancelScheduledValues(when); g.setValueAtTime(g.value, when); g.setTargetAtTime(0, when, seconds / 3);
        try { pad.src.stop(when + seconds * 1.6); } catch (e) {}
    }

    // Every keystroke keeps the pads alive a little longer, then lets them fade;
    // pads older than their samples are re-sounded with a crossfade.
    function hold(now) {
        const fresh = [];
        for (const pad of P.pads) {
            if (now - pad.born > 4.2) { release(pad, now, 0.6); fresh.push(note(pad.section, pad.m, now, pad.gain, 0.6)); continue; }
            const g = pad.env.gain;
            g.cancelScheduledValues(now); g.setValueAtTime(Math.max(g.value, 0.0001), now);
            g.linearRampToValueAtTime(pad.gain, now + Math.min(pad.attack, 0.3));
            g.setTargetAtTime(0, now + 2.2, 1.1);
            fresh.push(pad);
        }
        P.pads = fresh;
    }

    function voices(section, c) {
        if (section === 'strings') return voicing(c.pcs, 62, 3);
        if (section === 'high') return voicing(c.pcs, 74, 3);
        if (section === 'low') return [c.root, c.root + 12].map((m) => m < 33 ? m + 12 : m);
        if (section === 'horns') return voicing(c.pcs, 53, 3);
        if (section === 'brass') return voicing(c.pcs, 57, 3);
        return [];
    }

    function chord(a, now) {
        const c = CHORDS[a.name];
        if (a.name !== P.chord) { P.pads.forEach((pad) => release(pad, now, 0.7)); P.pads = []; P.chord = a.name; }
        const have = new Set(P.pads.map((p) => p.section));
        for (const s of a.sections) {
            if (have.has(s)) continue;
            const gain = s === 'brass' ? (a.intensity >= 4 ? 0.9 : 0.5) : 0.85;
            for (const m of voices(s, c)) P.pads.push(note(s, m, now, gain, ATTACK[s]));
        }
    }

    function cadence(a, now) {
        P.pads.forEach((pad) => release(pad, now, 0.12)); P.pads = []; P.chord = '';
        const c = CHORDS[a.name], size = 0.55 + 0.45 * (a.intensity / 4), t = now + 0.02;
        const tutti = [];
        for (const s of ['strings', 'high', 'low', 'horns', 'brass']) for (const m of voices(s, c)) tutti.push(note(s, m, t, size * 0.95, 0.02));
        tutti.push(note('timp', voicing([c.pcs[0]], 38, 1)[0], t, size, 0.003));
        tutti.push(note('kit', 36, t, size * 0.9, 0.003));
        if (a.intensity >= 2) tutti.push(note('kit', 49, t, size * 0.7, 0.003));
        for (const pad of tutti) { const g = pad.env.gain; g.setTargetAtTime(0, t + 2.4, 0.9); try { pad.src.stop(t + 7); } catch (e) {} }
        const e = P.expr.gain; e.cancelScheduledValues(now); e.setTargetAtTime(1, now, 0.05);
    }

    function perform(actions) {
        const now = P.ctx.currentTime + 0.01;
        for (const a of actions) {
            if (a.type === 'chord') chord(a, now);
            else if (a.type === 'pizz') note('pizz', a.note, now, a.velocity, 0.003);
            else if (a.type === 'timp') note('timp', a.note, now, a.velocity, 0.003);
            else if (a.type === 'hold') hold(now);
            else if (a.type === 'cadence') cadence(a, now);
            else if (a.type === 'breath') {
                const e = P.expr.gain; e.cancelScheduledValues(now);
                e.setTargetAtTime(0.15, now, 0.08); e.setTargetAtTime(1, now + 0.6, 0.15);
            }
        }
    }

    function swell(on) {
        const e = P.expr.gain, now = P.ctx.currentTime;
        e.cancelScheduledValues(now); e.setTargetAtTime(on ? 1.3 : 1, now, on ? 0.6 : 0.4);
    }

    function handle(list) {
        for (const [type, code, ms, repeat] of list) {
            if (type === 'd') {
                if (repeat) continue;
                P.held.add(code);
                perform(P.conductor.key(code));
                if (code !== KEY.RETURN && code !== KEY.PERIOD) swell(true);
            } else {
                P.held.delete(code);
                if (!P.held.size) swell(false);
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
            P.held.clear(); P.conductor.reset();
            if (!P.ready) return;
            const now = P.ctx.currentTime;
            P.pads.forEach((pad) => release(pad, now, 0.2)); P.pads = []; P.chord = '';
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
                events: P.events, keys: c.keys, chord: c.chordName, intensity: c.intensity, pads: P.pads.length });
        },
    };
    init();
})(typeof window !== 'undefined' ? window : globalThis);
