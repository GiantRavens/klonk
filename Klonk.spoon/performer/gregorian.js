// Klonk live performer: typing performs a written chant instead of picking notes.
//
//   each keystroke   sings the next syllable; a neume flows at the current tempo
//   typing speed     sets the tempo (a smoothed inter-keystroke interval)
//   holding keys     sustains the voice; letting go releases it into the abbey
//   comma            a breath: broadens the syllable, then releases
//   backspace        steps back and sings the previous syllable again
//   period / Return  the cadence: the phrase's closing syllables, broadened, land
//                    on the final with an organum fifth beneath; next phrase follows
//
// Voices are Synth_Gregorian's VocalSet sampler (vocal-voices.js); the repertoire
// is its note-for-note chant encoding (chants.js). Klonk sends key events through
// K.events([[type, keyCode, ms, repeat], ...]).
(function () {
    'use strict';

    // WKWebView blocks fetch() of file:// URLs, so the voice library's sample
    // requests are answered from the packed base64 bank in voices.js.
    const nativeFetch = window.fetch ? window.fetch.bind(window) : null;
    window.fetch = async (url, opts) => {
        const name = String(url).split('/').pop();
        if (name === 'grid.json') return new Response(JSON.stringify(window.VOICE_GRID || []));
        const b64 = window.VOICE_DATA && window.VOICE_DATA[name];
        if (b64) {
            const bin = atob(b64), buf = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
            return new Response(buf.buffer);
        }
        return nativeFetch(url, opts);
    };

    const errors = [];
    window.addEventListener('error', (e) => errors.push(String(e.message)));
    window.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));

    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const ORDER = ['dies', 'kyrie', 'veni', 'requiem', 'viderunt'];
    const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));

    function hz(name) {
        const m = /^([A-G])(b|#)?(-?\d)$/.exec(name);
        const s = { C: -9, D: -7, E: -5, F: -4, G: -2, A: 0, B: 2 }[m[1]] + (m[2] === 'b' ? -1 : m[2] === '#' ? 1 : 0);
        return 440 * Math.pow(2, (s + (parseInt(m[3], 10) - 4) * 12) / 12);
    }

    const P = {
        ctx: null, ready: false, technique: '', error: '',
        master: null, gate: null, organum: null, organumGain: null, schola: [],
        piece: 0, phrase: 0, syl: 0,
        held: new Set(), ioi: 0.4, lastDown: 0, singingUntil: 0, sounding: false,
        volume: 0.7, events: 0, lastEventAt: 0,
    };

    function abbey(ctx, seconds) {
        // Stone-abbey impulse: sparse early reflections, then a long dark tail.
        const n = Math.floor(ctx.sampleRate * seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch);
            let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * 0.82 + (Math.random() * 2 - 1) * 0.18;           // darken the tail
                d[i] = lp * Math.exp(-t * 6.9 / seconds) * (t < 0.025 ? t / 0.025 : 1);
            }
            [0.019, 0.031, 0.047, 0.066, 0.083].forEach((t, k) => {
                const i = Math.floor((t + ch * 0.004) * ctx.sampleRate);
                if (i < n) d[i] += 0.5 / (k + 1);
            });
        }
        return ir;
    }

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            await VocalVoices.init(ctx);
            P.technique = VocalVoices.hasSamples(ctx) ? 'sampler' : 'additive';
            P.master = ctx.createGain(); P.master.gain.value = P.volume;
            P.master.connect(ctx.destination);
            const verb = ctx.createConvolver(); verb.buffer = abbey(ctx, 6.5);
            const wet = ctx.createGain(); wet.gain.value = 0.55;
            const dry = ctx.createGain(); dry.gain.value = 0.6;
            verb.connect(wet); wet.connect(P.master); dry.connect(P.master);
            const bus = ctx.createGain();
            bus.connect(dry); bus.connect(verb);
            P.meter = ctx.createAnalyser(); P.meter.fftSize = 2048; bus.connect(P.meter);   // pre-volume level
            // The phrase gate: voices stay voiced, the gate shapes attack and release.
            P.gate = ctx.createGain(); P.gate.gain.value = 0; P.gate.connect(bus);
            [-8, 0, 7].forEach((cents) => {
                const v = VocalVoices.create(ctx, { technique: P.technique, vowel: 'a', detuneCents: cents });
                const g = ctx.createGain(); g.gain.value = 0.36;
                v.output.connect(g); g.connect(P.gate);
                v.setFrequency(hz('D3'), ctx.currentTime, 0); v.setLevel(1, ctx.currentTime);
                P.schola.push(v);
            });
            P.organumGain = ctx.createGain(); P.organumGain.gain.value = 0; P.organumGain.connect(bus);
            P.organum = VocalVoices.create(ctx, { technique: P.technique, vowel: 'o', detuneCents: -3 });
            P.organum.output.connect(P.organumGain);
            P.organum.setFrequency(hz('A2'), ctx.currentTime, 0); P.organum.setLevel(1, ctx.currentTime);
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    const chant = () => window.CHANTS[ORDER[P.piece % ORDER.length]];
    const phrase = () => chant().phrases[P.phrase];

    function nextPhrase() {
        P.syl = 0; P.phrase++;
        if (P.phrase >= chant().phrases.length) { P.phrase = 0; P.piece = (P.piece + 1) % ORDER.length; }
    }

    // Sing one syllable starting at t; returns when its last note ends.
    function sing(s, t, per) {
        const notes = s.n.map(hz);
        const fresh = !P.sounding;
        P.schola.forEach((v) => {
            v.setVowel(s.v, t);
            notes.forEach((f, k) => v.setFrequency(f, t + k * per, fresh && k === 0 ? 0 : Math.min(0.07, per * 0.35)));
        });
        return t + notes.length * per;
    }

    function open(t) {
        const g = P.gate.gain;
        g.cancelScheduledValues(t); g.setValueAtTime(g.value, t); g.linearRampToValueAtTime(1, t + 0.05);
        P.sounding = true;
    }

    function release(seconds) {
        const t = Math.max(P.ctx.currentTime, P.singingUntil), g = P.gate.gain;
        g.cancelScheduledValues(t); g.setTargetAtTime(0, t, seconds / 3);
        P.sounding = false;
    }

    function step(broaden) {
        if (P.syl >= phrase().length) nextPhrase();
        const s = phrase()[P.syl++];
        const now = P.ctx.currentTime;
        const per = clamp(P.ioi * 0.85 / s.n.length, 0.07, 0.42) * (broaden || 1);
        const t = now + 0.005;
        if (!P.sounding) open(t); else { const g = P.gate.gain; g.cancelScheduledValues(t); g.setValueAtTime(g.value, t); g.linearRampToValueAtTime(1, t + 0.04); }
        P.singingUntil = sing(s, t, per);
    }

    function cadence() {
        const ph = phrase();
        let from = Math.max(P.syl, ph.length - 2);
        if (from >= ph.length) from = ph.length - 1;
        let t = P.ctx.currentTime + 0.005;
        open(t);
        for (let i = from; i < ph.length; i++) {
            const s = ph[i], last = i === ph.length - 1;
            const per = clamp(P.ioi * 1.3 / s.n.length, 0.16, 0.5);
            t = sing(s, t, per) + (last ? 1.2 : 0.05);
        }
        // the organum: a fifth below the final, swelling in under the last note
        const finalHz = hz(ph[ph.length - 1].n.slice(-1)[0]);
        const og = P.organumGain.gain, tf = t - 1.3;
        P.organum.setFrequency(finalHz * Math.pow(2, -7 / 12), tf, 0);
        og.cancelScheduledValues(tf); og.setValueAtTime(0, tf); og.linearRampToValueAtTime(0.32, tf + 0.5);
        og.setTargetAtTime(0, t, 0.9);
        P.singingUntil = t;
        release(2.8);
        P.syl = ph.length;          // the next keystroke begins the next phrase
    }

    function keyDown(code, ms, repeat) {
        if (repeat) return;
        P.held.add(code);
        const dt = (ms - P.lastDown) / 1000;
        if (P.lastDown && dt < 2.5) P.ioi = P.ioi * 0.7 + clamp(dt, 0.08, 1.2) * 0.3;
        P.lastDown = ms;
        if (code === KEY.RETURN || code === KEY.PERIOD) return cadence();
        if (code === KEY.BACKSPACE) {
            P.syl = Math.max(0, Math.min(P.syl, phrase().length) - 2);
            return step(1.2);
        }
        if (code === KEY.COMMA) { step(1.6); return release(0.5); }
        step(1);
    }

    function keyUp(code) {
        P.held.delete(code);
        if (!P.held.size && P.sounding) release(clamp(P.ioi * 1.4, 0.25, 1.4));
    }

    window.K = {
        events(list) {
            if (!P.ready) return 'not-ready';
            P.events += list.length; P.lastEventAt = Date.now();
            try { for (const [type, code, ms, repeat] of list) {
                if (type === 'd') keyDown(code, ms, repeat); else keyUp(code);
            } } catch (e) { errors.push(String(e && e.stack || e)); }   // injected calls hide messages
            return 'ok';
        },
        volume(v) { P.volume = v; if (P.master) P.master.gain.setTargetAtTime(v, P.ctx.currentTime, 0.05); },
        level() {   // RMS dBFS at the voice bus, before the volume control
            if (!P.meter) return -Infinity;
            const a = new Float32Array(P.meter.fftSize); P.meter.getFloatTimeDomainData(a);
            let e = 0; for (const x of a) e += x * x;
            return +(10 * Math.log10(e / a.length + 1e-12)).toFixed(1);
        },
        stop() {
            P.held.clear();
            if (!P.ready) return;
            const t = P.ctx.currentTime;
            [P.gate.gain, P.organumGain.gain].forEach((g) => { g.cancelScheduledValues(t); g.setTargetAtTime(0, t, 0.08); });
            P.sounding = false;
        },
        status() {
            const c = chant();
            return JSON.stringify({ ready: P.ready, error: P.error, errors: errors.slice(-5), technique: P.technique,
                state: P.ctx && P.ctx.state, baseLatency: P.ctx && P.ctx.baseLatency, outputLatency: P.ctx && P.ctx.outputLatency,
                piece: c && c.title, phrase: P.phrase, syllable: P.syl, ioi: +P.ioi.toFixed(3), events: P.events });
        },
    };
    init();
})();
