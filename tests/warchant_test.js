// War-chant performer regressions, headless against the real worklet code:
//   node tests/warchant_test.js
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'Klonk.spoon', 'performer', 'chant-worklet.js'), 'utf8');
global.sampleRate = 44100;
let last, Proc;
global.AudioWorkletProcessor = class { constructor() { this.port = { postMessage: (m) => { last = m; } }; } };
global.registerProcessor = (_, cls) => { Proc = cls; };
eval(src);

let checks = 0;
const same = (a, b, label) => { checks++; if (a !== b) throw new Error(`${label}: expected ${b}, got ${a}`); };
const truthy = (a, label) => same(!!a, true, label);
const p = new Proc();
const block = 128 / sampleRate;
let peak = 0, energy = 0, frames = 0;
const run = (sec) => { for (let i = 0, n = Math.round(sec / block); i < n; i++) {
    const L = new Float32Array(128), R = new Float32Array(128); p.process([], [[L, R]]);
    for (const x of L) { peak = Math.max(peak, Math.abs(x)); energy += x * x; frames++; } } };
const db = () => { const v = 10 * Math.log10(energy / Math.max(1, frames) + 1e-12); energy = 0; frames = 0; return v; };
const status = () => { p.message({ type: 'status' }); return last; };

run(0.5);
truthy(db() < -100, 'silent before the first keystroke');

// The growl: a sustained low syllable should carry energy an octave below the sung pitch.
const solo = new Proc();
solo.message({ type: 'key', ms: 1 }); solo.message({ type: 'held', on: true });
const buf = [];
for (let i = 0; i < Math.round(1.2 / block); i++) { const L = new Float32Array(128), R = new Float32Array(128); solo.process([], [[L, R]]); if (i * block > 0.4) buf.push(...L); }
const power = (f) => { let re = 0, im = 0; buf.forEach((x, n) => { re += x * Math.cos(2 * Math.PI * f * n / sampleRate); im += x * Math.sin(2 * Math.PI * f * n / sampleRate); }); return Math.hypot(re, im); };
const f0 = 440 * Math.pow(2, (38 - 69) / 12);
truthy(power(f0 / 2) > power(f0) * 0.15, `kargyraa undertone present (sub ${power(f0 / 2).toFixed(0)} vs f0 ${power(f0).toFixed(0)})`);

let ms = 0;
const seen = new Set();
for (let i = 1; i <= 34; i++) {
    ms += 260; p.message({ type: 'key', ms }); p.message({ type: 'held', on: true }); run(0.1);
    p.message({ type: 'held', on: false }); run(0.16); seen.add(status().intensity);
}
for (const level of [0, 1, 2, 3, 4]) truthy(seen.has(level), `the chant reaches layer ${level}`);
truthy(Math.abs(status().bpm - (104 - 0.26 * 60)) < 4, `tempo follows typing (got ${status().bpm})`);
db(); run(1); const building = db();
truthy(building > -40, `the chant is audible (${building.toFixed(1)} dB)`);

p.message({ type: 'shout' }); run(0.3);
same(status().running, false, 'the shout ends the chant');
truthy(db() > building - 6, 'the shout is loud');
run(6); db(); run(0.5);
truthy(db() < -60, 'silence after the shout rings out');

p.message({ type: 'key', ms: ms += 5000 }); run(0.4);
same(status().running, true, 'the next keystroke starts again');
p.message({ type: 'breath' }); p.message({ type: 'key', ms: ms += 200 }); run(0.3);
truthy(status().running, 'a breath keeps the ritual going');
p.message({ type: 'growl' }); run(0.2);
run(16);
same(status().running, false, 'four quiet bars end it');
truthy(peak < 1.0, `output never clips (peak ${peak.toFixed(2)})`);
console.log(`war chant tests: ${checks} passed`);
