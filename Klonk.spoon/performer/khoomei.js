// Klonk live performer: khoomei, Mongolian and Tuvan throat singing on the steppe.
//
//   each keystroke   the singer's next real sygyt note (Alfonso Perez, CC BY 4.0), in the
//                    order he sang them, over a soft drone tuned to his own fundamental;
//                    without the sample bank, a synthesized sygyt whistle takes over
//   keep typing      a galloping hoof rhythm, then a morin khuur bowing a fifth drone,
//                    then the deep kargyraa recordings beneath, then the soaring line
//   typing speed     the gallop's tempo
//   holding a key    lets the note ring
//   comma            a breath
//   backspace        sings the previous note again
//   period / Return  the singer's own ending: the final note of a take, then the steppe falls quiet
//
// Sequencer and voices run in an AudioWorklet (khoomei-worklet.js); timers in hidden
// pages are throttled. The recordings are decoded here and transferred to it.
(function () {
    'use strict';
    const errors = [];
    window.addEventListener('error', (e) => errors.push(String(e.message)));
    window.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));
    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const P = { ctx: null, node: null, ready: false, error: '', held: new Set(), events: 0, last: null, volume: 0.7 };

    function steppe(ctx, seconds) {             // open air: a faint, wide echo rather than a hall
        const n = Math.floor(ctx.sampleRate * seconds), ir = ctx.createBuffer(2, n, ctx.sampleRate);
        for (let ch = 0; ch < 2; ch++) {
            const d = ir.getChannelData(ch); let lp = 0;
            for (let i = 0; i < n; i++) {
                const t = i / ctx.sampleRate;
                lp = lp * 0.8 + (Math.random() * 2 - 1) * 0.2;
                d[i] = lp * 0.35 * Math.exp(-t * 6.9 / seconds);
            }
            [0.11, 0.23].forEach((t, k) => { const i = Math.floor((t + ch * 0.013) * ctx.sampleRate); d[i] += 0.25 / (k + 1); });
        }
        return ir;
    }
    async function decode(ctx, b64) {
        const bin = atob(b64), buf = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
        const b = await ctx.decodeAudioData(buf.buffer);
        return new Float32Array(b.getChannelData(0));
    }

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            await ctx.audioWorklet.addModule('khoomei-worklet.js');
            P.node = new AudioWorkletNode(ctx, 'klonk-khoomei', { outputChannelCount: [2] });
            P.node.port.onmessage = (e) => { if (e.data.type === 'status') P.last = e.data; };
            P.node.port.postMessage({ type: 'volume', v: P.volume });
            const src = window.KHOOMEI;
            if (src && src.sygyt && src.sygyt.length) {
                const transfer = [];
                const sygyt = await Promise.all(src.sygyt.map(async (n) => { const data = await decode(ctx, n.data); transfer.push(data.buffer); return { f0: n.f0, harmonic: n.harmonic, final: n.final, data }; }));
                const deep = await Promise.all(src.deep.map(async (n) => { const data = await decode(ctx, n.data); transfer.push(data.buffer); return data; }));
                P.node.port.postMessage({ type: 'bank', bank: { sygyt, deep } }, transfer);
            }
            const verb = ctx.createConvolver(); verb.buffer = steppe(ctx, 2.2);
            const wet = ctx.createGain(); wet.gain.value = 0.3;
            P.node.connect(ctx.destination); P.node.connect(verb); verb.connect(wet); wet.connect(ctx.destination);
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function keyDown(code, ms, repeat) {
        if (repeat) return;
        P.held.add(code);
        const port = P.node.port;
        if (code === KEY.RETURN || code === KEY.PERIOD) return port.postMessage({ type: 'cadence' });
        if (code === KEY.COMMA) return port.postMessage({ type: 'breath' });
        if (code === KEY.BACKSPACE) return port.postMessage({ type: 'slide' });
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
