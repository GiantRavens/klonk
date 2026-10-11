// Klonk live performer: techno build-up. A sentence is a build, Return is the drop.
//
//   first keystroke  starts the kick ("mmm")
//   more keystrokes  add layers: off-beat hats ("tss"), claps and sixteenths,
//                    a rolling bass, then a snare roll and noise riser
//   typing speed     sets the tempo (118-140 BPM), eased in at each bar line
//   holding keys     opens the bass filter
//   comma            a break: the kick drops out for a bar
//   backspace        a scratch
//   period / Return  POW: an impact on a fresh downbeat, then the full groove
//                    for two bars; the next sentence builds again from the kick
//   silence          layers fall away a bar at a time; four quiet bars stop it
//
// Hidden WKWebView pages throttle timers to about one per second, so nothing here
// runs on setInterval: the sequencer and every drum voice live in an AudioWorklet
// and count samples. The page only forwards key events to the worklet's port.
(function () {
    'use strict';
    const errors = [];
    window.addEventListener('error', (e) => errors.push(String(e.message)));
    window.addEventListener('unhandledrejection', (e) => errors.push(String(e.reason)));


    const KEY = { RETURN: 36, PERIOD: 47, COMMA: 43, BACKSPACE: 51 };
    const P = { ctx: null, node: null, meter: null, ready: false, error: '', held: new Set(), events: 0, last: null, volume: 0.7 };

    async function init() {
        try {
            const ctx = P.ctx = new AudioContext({ latencyHint: 'interactive' });
            await ctx.resume();
            await ctx.audioWorklet.addModule('mini.js');          // the worklet parses nothing; it evaluates
            await ctx.audioWorklet.addModule('techno-worklet.js');
            P.node = new AudioWorkletNode(ctx, 'klonk-techno', { outputChannelCount: [2] });
            P.meter = ctx.createAnalyser(); P.meter.fftSize = 2048;
            P.node.connect(P.meter); P.node.connect(ctx.destination);
            P.node.port.onmessage = (e) => { if (e.data.type === 'status') P.last = e.data; };
            P.node.port.postMessage({ type: 'volume', v: P.volume });
            if (P.pattern) P.node.port.postMessage({ type: 'program', lines: P.pattern });
            P.ready = true;
        } catch (e) { P.error = String(e && e.message || e); }
    }

    function keyDown(code, ms, repeat) {
        if (repeat) return;
        P.held.add(code);
        const port = P.node.port;
        if (code === KEY.RETURN || code === KEY.PERIOD) return port.postMessage({ type: 'pow' });
        if (code === KEY.COMMA) port.postMessage({ type: 'break' });
        if (code === KEY.BACKSPACE) port.postMessage({ type: 'scratch' });
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
        // Replace the groove with a mini-notation program; takes effect at the next bar.
        pattern(text) {
            const prog = window.Mini.parseProgram(text);
            if (prog.errors.length) return JSON.stringify({ ok: false, errors: prog.errors });
            P.pattern = prog.lines;
            if (P.node) P.node.port.postMessage({ type: 'program', lines: prog.lines });
            return JSON.stringify({ ok: true, lines: prog.lines.length });
        },
        stop() { P.held.clear(); if (P.node) P.node.port.postMessage({ type: 'stop' }); },
        level() { return P.last ? P.last.levelDb : -Infinity; },   // pre-volume, from the worklet, like the other worklet moods
        status() {
            if (P.node) P.node.port.postMessage({ type: 'status' });
            return JSON.stringify({ ready: P.ready, error: P.error, errors: errors.slice(-5), state: P.ctx && P.ctx.state,
                outputLatency: P.ctx && P.ctx.outputLatency, events: P.events, worklet: P.last });
        },
    };
    init();
})();
