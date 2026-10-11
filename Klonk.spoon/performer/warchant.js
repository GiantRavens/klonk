// Klonk live performer: war chant. Throat-singing choir, drums, and the shout.
//
//   first keystroke  a low growled drone begins
//   each keystroke   the choir chants a syllable (HA - O - HA - OM) on the next
//                    sixteenth, so ragged typing becomes a disciplined ritual
//   keep typing      war drums on the strong beats, then a higher answering choir,
//                    then metal hits and doubled drums, then the frenzy
//   typing speed     the ritual's tempo (66-100 BPM)
//   holding keys     holds the syllable
//   comma            a breath: the choir falls silent for a beat
//   backspace        the undertone swells into a growl
//   period / Return  the SHOUT: the whole choir HA! with drum, gong and sub, then silence
//
// Everything is synthesized in an AudioWorklet (chant-worklet.js): kargyraa-style
// period doubling through male formant filters. No samples.
(function () {
    'use strict';
    const errors = [];
    window.addEventListener('error', (e) => errors.push(String(e.message)));
    window.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));
    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const P = { ctx: null, node: null, ready: false, error: '', held: new Set(), events: 0, last: null, volume: 0.7 };

    function hall(ctx, seconds) {               // a dark stone hall
        const n = Math.floor(ctx.sampleRate * seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch); let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * 0.86 + (Math.random() * 2 - 1) * 0.14;
                d[i] = lp * Math.exp(-t * 6.9 / seconds) * (t < 0.04 ? t / 0.04 : 1);
            }
        }
        return ir;
    }

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            await ctx.audioWorklet.addModule('chant-worklet.js');
            P.node = new AudioWorkletNode(ctx, 'klonk-war-chant', { outputChannelCount: [2] });
            P.node.port.onmessage = (e) => { if (e.data.type === 'status') P.last = e.data; };
            P.node.port.postMessage({ type: 'volume', v: P.volume });
            const verb = ctx.createConvolver(); verb.buffer = hall(ctx, 4.5);
            const wet = ctx.createGain(); wet.gain.value = 0.5;
            const dry = ctx.createGain(); dry.gain.value = 0.75;
            P.node.connect(dry); dry.connect(ctx.destination);
            P.node.connect(verb); verb.connect(wet); wet.connect(ctx.destination);
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function keyDown(code, ms, repeat) {
        if (repeat) return;
        P.held.add(code);
        const port = P.node.port;
        if (code === KEY.RETURN || code === KEY.PERIOD) return port.postMessage({ type: 'shout' });
        if (code === KEY.COMMA) return port.postMessage({ type: 'breath' });
        if (code === KEY.BACKSPACE) port.postMessage({ type: 'growl' });
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
