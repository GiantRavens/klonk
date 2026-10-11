// Klonk instrument scenes: one engine plays every scene in scenes.js.
//
//   each keystroke   the next note of the scene's line: a written theme note for note,
//                    or a generated line (bebop, lyrical, mbira riff, bossa comping)
//   new bars         bass, chords, doubling, drones and percussion join by layer as the
//                    sentence grows, per the scene's data
//   typing speed     phrasing: quick taps are crisp, slow typing sings
//   holding a key    sustains the note
//   comma            lifts the hands
//   backspace        plays the last note again
//   period / Return  the scene's cadence, then the next keystroke starts a new phrase
//
// Event-driven like the salon: each keystroke schedules its own envelopes, so hidden-page
// timer throttling never matters. Which scene: the page's #fragment (the set name).
(function (global) {
    'use strict';
    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const PC = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

    // A written note: 'F#4', 'E3^' (pop), 'E2~' (ghost), or a chord name for comping.
    function parseNote(tok) {
        const m = /^([A-G])(#|b)?(-?\d)([\^~]?)$/.exec(tok);
        if (!m) return null;
        return { m: 12 * (+m[3] + 1) + PC[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0), mark: m[4] || '' };
    }
    function mulberry(seed) {                                   // small deterministic RNG
        let a = seed >>> 0;
        return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    }
    const hash = (s) => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return h >>> 0; };
    function inScale(m, scale) { return scale.includes(((m % 12) + 12) % 12); }
    function scaleStep(m, steps, scale) {
        let x = m, n = Math.abs(steps), dir = Math.sign(steps);
        while (n > 0) { x += dir; if (inScale(x, scale)) n--; }
        return x;
    }
    function chordTones(c, lo, hi) {
        const out = [];
        for (let m = lo; m <= hi; m++) if ((c.pcs || []).includes(((m % 12) + 12) % 12)) out.push(m);
        return out;
    }
    const nearest = (list, m) => list.reduce((a, b) => Math.abs(b - m) < Math.abs(a - m) ? b : a);

    // Generated lines: one bar at a time, seeded by scene and bar so they are reproducible.
    function generateBar(scene, bar, prev, nextChordName) {
        const g = scene.generate, name = g.progression[bar % g.progression.length], c = scene.chords[name];
        const rng = mulberry(hash(scene.title) + bar * 7919);
        const [lo, hi] = g.range || [55, 84];
        const notes = [];
        if (g.style === 'bossa') {
            for (const s of g.pattern) notes.push(s === 'B' ? { m: c.root } : s === 'b' ? { m: c.fifth } : { chord: c.voicing });
            return { chord: name, notes };
        }
        if (g.style === 'riff') {
            const tones = chordTones(c, lo, hi);
            const base = tones.indexOf(nearest(tones, prev || (lo + hi) / 2 | 0));
            const start = Math.max(0, Math.min(tones.length - 6, base - 2));
            for (const k of g.figure) notes.push({ m: tones[Math.min(tones.length - 1, start + k)] });
            return { chord: name, notes };
        }
        const tones = chordTones(c, lo, hi);
        let cur = nearest(tones, prev || ((lo + hi) / 2 | 0));
        notes.push({ m: cur });
        for (let i = 1; i < g.perBar; i++) {
            const leap = g.style === 'lyrical' ? 0.35 : 0.2;
            let step = (rng() < leap ? 2 : 1) * (rng() < 0.5 ? 1 : -1);
            if (cur > hi - 3) step = -Math.abs(step); else if (cur < lo + 3) step = Math.abs(step);
            cur = scaleStep(cur, step, scene.scale);
            if (g.style === 'bebop' && i === g.perBar - 1 && nextChordName) {
                const target = nearest(chordTones(scene.chords[nextChordName], lo, hi), cur);
                cur = target - 1;                                  // approach the next chord from a half step below
            }
            notes.push({ m: cur });
        }
        return { chord: name, notes };
    }

    function writtenBar(scene, phrase, bar) {
        const [chord, text] = scene.phrases[phrase][bar];
        let notes = text.split(/\s+/).map(parseNote);
        if (scene.figure) notes = scene.figure.map((k) => notes[k]);   // the prelude's arpeggio figure
        return { chord, notes };
    }

    class Conductor {
        constructor(scene) { this.scene = scene; this.reset(); }
        reset() { this.phrase = 0; this.bar = 0; this.pos = 0; this.keys = 0; this.genBar = 0; this.prev = null; this.last = null; this.current = null; }
        get intensity() { let i = 0; this.scene.layers.forEach(([n], k) => { if (this.keys >= n) i = k; }); return i; }
        get parts() { return this.scene.layers[this.intensity][1]; }
        barNotes() {
            const sc = this.scene;
            if (sc.generate) {
                const prog = sc.generate.progression;
                return generateBar(sc, this.genBar, this.prev, prog[(this.genBar + 1) % prog.length]);
            }
            return writtenBar(sc, this.phrase, this.bar);
        }
        advanceBar() {
            const sc = this.scene;
            this.pos = 0;
            if (sc.generate) { this.genBar++; return; }
            this.bar++;
            if (this.bar >= sc.phrases[this.phrase].length) { this.bar = 0; this.phrase = (this.phrase + 1) % sc.phrases.length; }
        }
        key(code) {
            const sc = this.scene;
            if (code === KEY.RETURN || code === KEY.PERIOD) {
                const I = this.intensity, parts = this.parts;
                if (!sc.generate) { this.phrase = (this.phrase + 1) % sc.phrases.length; this.bar = 0; }
                else this.genBar = (Math.floor(this.genBar / sc.generate.progression.length) + 1) * sc.generate.progression.length;
                this.pos = 0; this.keys = 0; this.current = null;
                return [{ type: 'cadence', intensity: I, parts }];
            }
            if (code === KEY.COMMA) return [{ type: 'lift' }];
            if (code === KEY.BACKSPACE) return this.last ? [Object.assign({}, this.last, { barStart: false })] : [];
            this.keys++;
            if (!this.current) this.current = this.barNotes();
            if (this.pos >= this.current.notes.length) { this.advanceBar(); this.current = this.barNotes(); }
            const n = this.current.notes[this.pos], barStart = this.pos === 0;
            const out = { type: 'note', chord: this.current.chord, note: n, barStart, index: this.pos, keys: this.keys, parts: this.parts, intensity: this.intensity };
            this.pos++;
            if (n && n.m !== undefined) this.prev = n.m;
            this.last = out;
            return [out];
        }
    }
    global.SceneEngine = { Conductor, parseNote, generateBar, scaleStep, mulberry };
    if (!global.document) return;

    // ---- the renderer ----
    const errors = [];
    global.addEventListener('error', (e) => errors.push(String(e.message)));
    global.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));
    const NAME = decodeURIComponent((location.hash || '#').slice(1));
    const SCENE = global.SCENES[NAME];
    const P = { ctx: null, ready: false, error: '', buffers: {}, bus: null, master: null, meter: null,
        lead: [], accomp: [], drone: null, conductor: SCENE ? new Conductor(SCENE) : null,
        held: new Set(), ioi: 0.35, lastDown: 0, volume: 0.7, events: 0, alt: 0 };

    function room(ctx, r) {
        const n = Math.floor(ctx.sampleRate * r.seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch); let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * r.dark + (Math.random() * 2 - 1) * (1 - r.dark);
                d[i] = lp * Math.exp(-t * 6.9 / r.seconds) * (t < 0.006 ? 0 : 1);
            }
            [0.011, 0.017, 0.026, 0.034].forEach((t, k) => { const i = Math.floor((t + ch * 0.002) * ctx.sampleRate); d[i] += 0.4 / (k + 1); });
        }
        return ir;
    }

    function loadBank() {
        return new Promise((resolve, reject) => {
            const s = document.createElement('script');
            s.src = 'scenes/' + encodeURIComponent(NAME) + '.js';
            s.onload = () => resolve(global.SCENE_BANK); s.onerror = () => reject(new Error('no note bank for ' + NAME));
            document.head.appendChild(s);
        });
    }

    async function init() {
        try {
            if (!SCENE) throw new Error('unknown scene ' + NAME);
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            const bank = await loadBank(), jobs = [];
            for (const [section, notes] of Object.entries(bank)) {
                P.buffers[section] = {};
                for (const [m, b64] of Object.entries(notes)) {
                    const bin = atob(b64), buf = new Uint8Array(bin.length);
                    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
                    jobs.push(ctx.decodeAudioData(buf.buffer).then((b) => { P.buffers[section][m] = b; }));
                }
            }
            await Promise.all(jobs);
            P.master = ctx.createGain(); P.master.gain.value = P.volume; P.master.connect(ctx.destination);
            const verb = ctx.createConvolver(); verb.buffer = room(ctx, SCENE.room);
            const wet = ctx.createGain(); wet.gain.value = SCENE.room.wet; verb.connect(wet); wet.connect(P.master);
            P.bus = ctx.createGain(); P.bus.connect(P.master); P.bus.connect(verb);
            P.meter = ctx.createAnalyser(); P.meter.fftSize = 2048; P.bus.connect(P.meter);
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function play(section, m, when, gain, opts) {
        opts = opts || {};
        const bank = P.buffers[section];
        if (!bank) return null;
        const roots = Object.keys(bank).map(Number);
        const root = roots.reduce((a, b) => Math.abs(b - m) < Math.abs(a - m) ? b : a);
        if (opts.exact && Math.abs(root - m) > 2) return null;   // a music box has only its own comb
        const src = P.ctx.createBufferSource(); src.buffer = bank[root];
        src.playbackRate.value = Math.pow(2, (m - root) / 12);
        if (opts.loop) src.loop = true;
        const env = P.ctx.createGain();
        env.gain.setValueAtTime(0, when); env.gain.linearRampToValueAtTime(gain, when + (opts.attack || 0.006));
        src.connect(env); env.connect(P.bus); src.start(when);
        return { src, env, m };
    }
    function release(v, when, seconds) {
        if (!v) return;
        const g = v.env.gain;
        g.cancelScheduledValues(when); g.setValueAtTime(g.value, when); g.setTargetAtTime(0, when, Math.max(0.01, seconds / 3));
        try { v.src.stop(when + seconds * 1.8 + 0.05); } catch (e) {}
    }
    const releaseAll = (list, when, s) => { list.forEach((v) => release(v, when, s)); return []; };
    const phrasing = () => Math.min(0.7, Math.max(0.08, P.ioi * 0.9));
    const has = (parts, p) => parts.includes(p);

    function leadNote(n, a, now) {
        const lead = SCENE.parts.lead;
        if (n.chord) {                                            // a strummed chord (bossa fingers)
            n.chord.forEach((m, k) => P.lead.push(play(lead.section, m, now + k * 0.012, lead.gain * 0.75)));
            return;
        }
        let section = Array.isArray(lead.section) ? lead.section[P.alt++ % lead.section.length] : lead.section;
        let gain = lead.gain;
        if (n.mark === '^' && lead.pop) section = lead.pop;
        if (n.mark === '~') gain *= 0.3;
        if (lead.grace) P.lead.push(play(section, lead.grace, now, gain * 0.7, { exact: lead.exact }));
        const t = lead.grace ? now + 0.035 : now;
        const v = play(section, n.m, t, gain, { exact: lead.exact });
        if (v) P.lead.push(v);
        const dbl = SCENE.parts.double;
        if (dbl && has(a.parts, 'double')) {
            const m2 = dbl.interval === 'third-below' ? scaleStep(n.m, -2, SCENE.scale) : n.m + dbl.interval;
            P.lead.push(play(dbl.section, m2, t + (dbl.echo ? Math.min(0.3, P.ioi * 0.5) : 0), dbl.gain, { exact: dbl.exact }));
        }
    }

    function barStart(a, now) {
        P.accomp = releaseAll(P.accomp, now, 0.2);
        const c = SCENE.chords[a.chord] || {}, parts = SCENE.parts;
        if (parts.bass && has(a.parts, 'bass') && parts.bass.mode === 'bar' && c.root) P.accomp.push(play(parts.bass.section, c.root, now, parts.bass.gain));
        if (parts.chord && has(a.parts, 'chord') && c.voicing) {
            const roll = parts.chord.style === 'roll' ? 0.03 : 0;
            c.voicing.forEach((m, k) => P.accomp.push(play(parts.chord.section, m, now + k * roll, parts.chord.gain)));
        }
        const perc = parts.perc;
        if (perc && (has(a.parts, 'perc') || has(a.parts, 'bass-drum')) && perc.bar) perc.bar.forEach(([m, g]) => play(perc.section, m, now, g));
        P.accomp.forEach((v) => v && v.env.gain.setTargetAtTime(0, now + 1.8, 0.3));
    }

    function eachKey(a, now) {
        const parts = SCENE.parts, c = SCENE.chords[a.chord] || {};
        if (parts.bass && has(a.parts, 'bass') && parts.bass.mode === 'walk' && a.index % 2 === 0) {
            const prog = SCENE.generate.progression, next = SCENE.chords[prog[(prog.indexOf(a.chord) + 1) % prog.length]];
            const step = (a.index / 2) % 4;
            const m = step === 0 ? c.root : step === 3 ? next.root - 1 : c.root + (step === 1 ? (c.pcs.includes((c.root + 3) % 12) ? 3 : 4) : 7);
            P.accomp.push(play(parts.bass.section, m, now, parts.bass.gain));
        }
        const perc = parts.perc;
        if (perc && perc.key && (has(a.parts, 'perc') || has(a.parts, 'hats')) && a.keys >= (perc.keyFrom || 0)) perc.key.forEach(([m, g]) => play(perc.section, m, now, g * (0.8 + 0.4 * Math.random())));
        if (perc && perc.backbeat && has(a.parts, 'perc') && a.index % 4 === 2) perc.backbeat.forEach(([m, g]) => play(perc.section, m, now, g));
    }

    function drone(a, now) {
        const d = SCENE.parts.drone;
        if (!d || !has(a.parts, 'drone')) return;
        if (P.drone && now - P.drone.born < 7.2) {               // keep it breathing while you type
            const g = P.drone.env.gain; g.cancelScheduledValues(now); g.setValueAtTime(g.value, now);
            g.linearRampToValueAtTime(d.gain, now + 0.2); g.setTargetAtTime(0, now + 3.5, 0.8);
            return;
        }
        if (P.drone) release(P.drone, now, 0.4);
        const root = Object.keys(P.buffers[d.section] || {})[0];
        P.drone = play(d.section, +root, now, d.gain, { attack: 0.4 });
        if (P.drone) { P.drone.born = now; P.drone.env.gain.setTargetAtTime(0, now + 3.5, 0.8); }
    }

    // A ringing lead (lead.ring) plays the way the Prelude is fingered: each note rings
    // on through the bar and the dampers drop when the harmony changes. Plucking a note
    // that is still ringing damps that string first, as the jack does.
    function note(a, now) {
        const ring = SCENE.parts.lead.ring;
        if (ring && a.barStart) P.lead = releaseAll(P.lead, now, 0.12);
        else if (ring) P.lead = P.lead.filter((v) => {
            if (v && (v.m === a.note.m || v.m === a.note.m + 12)) { release(v, now, 0.04); return false; }
            return !!v;
        });
        else P.lead = releaseAll(P.lead, now, 0.05);
        if (a.barStart) barStart(a, now);
        leadNote(a.note, a, now);
        eachKey(a, now);
        drone(a, now);
        if (!P.held.size && !ring) P.lead = releaseAll(P.lead, now + phrasing(), phrasing());
    }

    function cadence(a, now) {
        const cad = SCENE.cadence, parts = SCENE.parts;
        P.lead = releaseAll(P.lead, now, 0.08); P.accomp = releaseAll(P.accomp, now, 0.15);
        const gap = cad.fast ? 0.11 : cad.winddown ? 0.55 : 0.5, ring = [];
        let t = now + 0.01;
        cad.steps.forEach(([chord, notes], k) => {
            const c = SCENE.chords[chord] || {}, last = k === cad.steps.length - 1;
            if (parts.bass && has(a.parts, 'bass') && c.root) ring.push(play(parts.bass.section, c.root, t, parts.bass.gain));
            if (parts.chord && has(a.parts, 'chord') && c.voicing) c.voicing.forEach((m, j) => ring.push(play(parts.chord.section, m, t + j * 0.02, parts.chord.gain)));
            const lead = parts.lead;
            notes.forEach((tok, j) => {
                const chordVoicing = SCENE.chords[tok] && SCENE.chords[tok].voicing;
                if (chordVoicing) { [SCENE.chords[tok].root].concat(chordVoicing).forEach((m, i) => ring.push(play(lead.section, m, t + i * (cad.strum || 0.02), lead.gain))); return; }
                const n = parseNote(tok);
                const section = Array.isArray(lead.section) ? lead.section[0] : (n.mark === '^' && lead.pop ? lead.pop : lead.section);
                ring.push(play(section, n.m, t + j * (cad.fast ? gap : (cad.roll || 0)), lead.gain, { exact: lead.exact }));
            });
            if (last && cad.hit && parts.perc) cad.hit.forEach(([m, g]) => ring.push(play(parts.perc.section, m, t, g)));
            if (!last) t += (cad.fast ? gap * notes.length : gap) * (cad.winddown ? 1.6 : 1);
        });
        ring.forEach((v) => { if (!v) return; v.env.gain.setTargetAtTime(0, t + cad.hold, 0.4); try { v.src.stop(t + cad.hold + 2.5); } catch (e) {} });
        if (P.drone) { P.drone.env.gain.cancelScheduledValues(now); P.drone.env.gain.setTargetAtTime(0, t + cad.hold, 0.6); }
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
                    if (a.type === 'note') note(a, now);
                    else if (a.type === 'cadence') cadence(a, now);
                    else if (a.type === 'lift') P.lead = releaseAll(P.lead, now, 0.05);
                }
            } else {
                P.held.delete(code);
                if (!P.held.size && !SCENE.parts.lead.ring) P.lead = releaseAll(P.lead, now, phrasing());
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
            P.held.clear(); if (P.conductor) P.conductor.reset();
            if (!P.ready) return;
            const now = P.ctx.currentTime;
            P.lead = releaseAll(P.lead, now, 0.1); P.accomp = releaseAll(P.accomp, now, 0.2);
            if (P.drone) { release(P.drone, now, 0.4); P.drone = null; }
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
                scene: NAME, title: SCENE && SCENE.title, events: P.events, sounding: P.lead.length, keys: c && c.keys, intensity: c && c.intensity,
                phrase: c && c.phrase, bar: c && (SCENE.generate ? c.genBar : c.bar) });
        },
    };
    init();
})(typeof window !== 'undefined' ? window : globalThis);
