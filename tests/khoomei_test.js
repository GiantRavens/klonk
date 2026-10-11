// Khoomei performer regressions, headless against the real worklet code:
//   node tests/khoomei_test.js
// The key check is spectral: the whistle must make its chosen harmonic of the
// drone stand out from its neighbours, or it is not sygyt.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'Klonk.spoon', 'performer', 'khoomei-worklet.js'), 'utf8');
global.sampleRate = 44100;
let last, Proc;
global.AudioWorkletProcessor = class { constructor() { this.port = { postMessage: (m) => { last = m; } }; } };
global.registerProcessor = (_, cls) => { Proc = cls; };
eval(src);
let checks = 0;
const same = (a, b, label) => { checks++; if (a !== b) throw new Error(`${label}: expected ${b}, got ${a}`); };
const truthy = (a, label) => same(!!a, true, label);
const block = 128 / sampleRate;
let peak = 0;
function capture(p, seconds) {
    const buf = [];
    for (let i = 0, n = Math.round(seconds / block); i < n; i++) {
        const L = new Float32Array(128), R = new Float32Array(128); p.process([], [[L, R]]);
        for (const x of L) { buf.push(x); peak = Math.max(peak, Math.abs(x)); }
    }
    return buf;
}
const power = (buf, f) => { let re = 0, im = 0; for (let n = 0; n < buf.length; n++) { const a = 2 * Math.PI * f * n / sampleRate; re += buf[n] * Math.cos(a); im += buf[n] * Math.sin(a); } return Math.hypot(re, im) / buf.length; };
const db = (buf) => 10 * Math.log10(buf.reduce((s, x) => s + x * x, 0) / buf.length + 1e-12);
const status = (p) => { p.message({ type: 'status' }); return last; };
const F0 = 130.81;

const p = new Proc();
truthy(db(capture(p, 0.3)) < -100, 'silent before the first keystroke');
p.message({ type: 'key', ms: 1 }); p.message({ type: 'held', on: true });
capture(p, 0.6);                                                   // let the whistle settle
let buf = capture(p, 0.5);
same(status(p).harmonic, 8, 'the first note is harmonic 8');
const h = (n) => power(buf, F0 * n);
truthy(h(8) > 3 * h(7) && h(8) > 3 * h(9), `sygyt: harmonic 8 stands out (h7 ${h(7).toExponential(1)}, h8 ${h(8).toExponential(1)}, h9 ${h(9).toExponential(1)})`);
truthy(h(1) > 0.25 * h(8), `the drone fundamental sounds underneath (h1 ${h(1).toExponential(1)})`);
p.message({ type: 'key', ms: 400 });
capture(p, 0.6); buf = capture(p, 0.5);
same(status(p).harmonic, 9, 'the next keystroke moves the whistle to harmonic 9');
truthy(h(9) > 3 * h(8) && h(9) > 3 * h(10), 'and harmonic 9 now stands out');
p.message({ type: 'held', on: false });

let ms = 400;
const seen = new Set();
for (let i = 0; i < 34; i++) { ms += 250; p.message({ type: 'key', ms }); capture(p, 0.25); seen.add(status(p).intensity); }
for (const level of [1, 2, 3, 4]) truthy(seen.has(level), `the song reaches layer ${level}`);
truthy(status(p).harmonic >= 10, 'at full strength the whistle soars higher');
p.message({ type: 'cadence' });
capture(p, 1.0);
same(status(p).harmonic, 6, 'the cadence settles the whistle down to harmonic 6');
capture(p, 5);
truthy(db(capture(p, 0.5)) < -50, 'silence after the cadence');
p.message({ type: 'key', ms: ms += 5000 }); capture(p, 0.3);
same(status(p).running, true, 'a new keystroke starts a new song');
p.message({ type: 'breath' }); capture(p, 0.2);
same(status(p).drone < 0.3, true, 'a comma breathes');
p.message({ type: 'slide' }); capture(p, 0.1);
truthy(status(p).harmonic >= 6, 'backspace slides the whistle down');
capture(p, 12);
same(status(p).running, false, 'quiet bars end the song');
truthy(peak < 1.0, `output never clips (peak ${peak.toFixed(2)})`);
// Sample mode: a stand-in bank of tones with known drone pitches and one final note.
const tone = (f, sec) => { const d = new Float32Array(Math.floor(sec * sampleRate)); for (let i = 0; i < d.length; i++) d[i] = 0.4 * Math.sin(2 * Math.PI * f * i / sampleRate); return d; };
const bankNotes = [
    { f0: 140, harmonic: 8, final: false, data: tone(1120, 0.4) },
    { f0: 140, harmonic: 9, final: false, data: tone(1260, 0.4) },
    { f0: 150, harmonic: 10, final: true, data: tone(1500, 0.6) },
    { f0: 150, harmonic: 8, final: false, data: tone(1200, 0.4) },
];
const s = new Proc();
s.message({ type: 'bank', bank: { sygyt: bankNotes, deep: [tone(70, 3), tone(72, 3)] } });
same(last.notes, 4, 'the bank loads');
s.message({ type: 'key', ms: 1 }); capture(s, 0.1);
same(status(s).mode, 'samples', 'real recordings take over');
same(status(s).note, 1, 'the first keystroke plays the first real note');
same(s.throat.f0, 140, 'the drone bed retunes to the recording');
same(s.throat.wgTarget, 0, 'no synthetic whistle over a real singer');
s.message({ type: 'key', ms: 300 }); capture(s, 0.1);
same(status(s).note, 2, 'the next keystroke plays the next real note');
s.message({ type: 'slide' }); capture(s, 0.05);
same(status(s).note, 1 + 1, 'backspace sings the previous note again');
s.message({ type: 'cadence' }); capture(s, 0.05);
same(s.seg, 3, 'the cadence finds the next final note');
same(s.throat.f0, 150, 'and retunes to its drone');
const d = new Proc();
d.message({ type: 'bank', bank: { sygyt: bankNotes, deep: [tone(70, 3)] } });
let t = 0; for (let i = 0; i < 24; i++) { t += 200; d.message({ type: 'key', ms: t }); capture(d, 0.2); }
truthy(d.deepTake, 'the deep kargyraa layer arrives as the song builds');
truthy(peak < 1.0, `sample mode never clips (peak ${peak.toFixed(2)})`);
console.log(`khoomei tests: ${checks} passed`);
