// Klonk live performer: action film score. A sentence builds a four-bar phrase in
// D minor; Return is THE HIT.
//
//   first keystroke  pulse: low strings drive sixteenths in 3-3-2, timpani on the bar
//   keep typing      theme: the horns state the theme (an original call, D-A-D, that
//                    sighs down and answers itself a step higher); violas join the ostinato
//                    answer: horns call, strings answer an octave up; one braam marks it,
//                    taiko on the accents
//                    tutti: horns and strings together, choir, low brass, snare, tom fills
//                    lift: a snare roll and riser, then the whole score rises a whole step
//                    to E minor on the next phrase, with one more braam
//   typing speed     sets the tempo (112-132 BPM), eased in at each bar
//   holding keys     crescendo
//   comma            the trailer gap: the next bar is silent
//   backspace        a reverse-cymbal whoosh
//   Return           everything stops, a beat of silence, then the trailer cadence:
//                    B-flat, C, D major (short-short-long) with the whole orchestra, a sub
//                    boom and a growl; after a short sentence, one hit
//   period           a beat of silence, then one D minor hit: the end of a line, not the film
//   silence          sections fall away a bar at a time; four quiet bars end it
//
// Every note is a few milliseconds late and a little uneven, as players are.
// The sequencer and sampler run in an AudioWorklet (cinematic-worklet.js), because
// hidden pages throttle timers. The orchestra bank (cinematic-samples.js, GeneralUser
// GS renders) is decoded here and transferred to the worklet as raw sample arrays.
(function () {
    'use strict';
    const errors = [];
    window.addEventListener('error', (e) => errors.push(String(e.message)));
    window.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));

    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const P = { ctx: null, node: null, ready: false, error: '', held: new Set(), events: 0, last: null, volume: 0.7 };

    function hall(ctx, seconds) {
        const n = Math.floor(ctx.sampleRate * seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch); let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * 0.72 + (Math.random() * 2 - 1) * 0.28;
                d[i] = lp * Math.exp(-t * 6.9 / seconds) * (t < 0.03 ? t / 0.03 : 1);
            }
        }
        return ir;
    }

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            await ctx.audioWorklet.addModule('cinematic-worklet.js');
            const bank = {}, transfer = [], jobs = [];
            for (const [section, notes] of Object.entries(window.CINEMATIC)) {
                bank[section] = {};
                for (const [m, b64] of Object.entries(notes)) {
                    const bin = atob(b64), buf = new Uint8Array(bin.length);
                    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
                    jobs.push(ctx.decodeAudioData(buf.buffer).then((b) => {
                        const data = new Float32Array(b.getChannelData(0));
                        bank[section][m] = data; transfer.push(data.buffer);
                    }));
                }
            }
            await Promise.all(jobs);
            P.node = new AudioWorkletNode(ctx, 'klonk-cinematic', { outputChannelCount: [2] });
            P.node.port.onmessage = (e) => { if (e.data.type === 'status') P.last = e.data; };
            P.node.port.postMessage({ type: 'bank', bank }, transfer);
            P.node.port.postMessage({ type: 'volume', v: P.volume });
            const verb = ctx.createConvolver(); verb.buffer = hall(ctx, 3.8);
            const wet = ctx.createGain(); wet.gain.value = 0.45;
            const dry = ctx.createGain(); dry.gain.value = 0.8;
            P.node.connect(dry); dry.connect(ctx.destination);
            P.node.connect(verb); verb.connect(wet); wet.connect(ctx.destination);
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function keyDown(code, ms, repeat) {
        if (repeat) return;
        P.held.add(code);
        const port = P.node.port;
        if (code === KEY.RETURN) return port.postMessage({ type: 'hit' });
        if (code === KEY.PERIOD) return port.postMessage({ type: 'end' });
        if (code === KEY.COMMA) port.postMessage({ type: 'gap' });
        if (code === KEY.BACKSPACE) port.postMessage({ type: 'whoosh' });
        port.postMessage({ type: 'key', ms });
        port.postMessage({ type: 'held', on: true });
    }
    function keyUp(code) {
        P.held.delete(code);
        if (!P.held.size) P.node.port.postMessage({ type: 'held', on: false });
    }

    window.K = {
        events(list) {
            if (!P.ready) return 'not-ready';
            P.events += list.length;
            try { for (const [type, code, ms, repeat] of list) { if (type === 'd') keyDown(code, ms, repeat); else keyUp(code); } }
            catch (e) { errors.push(String(e && e.stack || e)); }   // injected calls hide messages
            return 'ok';
        },
        volume(v) { P.volume = v; if (P.node) P.node.port.postMessage({ type: 'volume', v }); },
        stop() { P.held.clear(); if (P.node) P.node.port.postMessage({ type: 'stop' }); },
        level() { return P.last ? P.last.levelDb : -Infinity; },
        status() {
            if (P.node) P.node.port.postMessage({ type: 'status' });
            return JSON.stringify({ ready: P.ready, error: P.error, errors: errors.slice(-5), state: P.ctx && P.ctx.state,
                events: P.events, worklet: P.last });
        },
    };
    init();
})();
