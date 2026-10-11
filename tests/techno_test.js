// Techno performer regressions, run headlessly against the real worklet code:
//   node tests/techno_test.js
// Drives the AudioWorkletProcessor with simulated typing and checks the build-up,
// tempo, drop, idle stop, and that the output never clips.
const fs = require('fs');
const path = require('path');
require(path.join(__dirname, '..', 'Klonk.spoon', 'performer', 'mini.js'));   // the worklet scope loads mini.js first
const src = fs.readFileSync(path.join(__dirname, '..', 'Klonk.spoon', 'performer', 'techno-worklet.js'), 'utf8');

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
function run(seconds) {
    for (let i = 0, n = Math.round(seconds / block); i < n; i++) {
        const L = new Float32Array(128), R = new Float32Array(128);
        p.process([], [[L, R]]);
        for (const x of L) { peak = Math.max(peak, Math.abs(x)); energy += x * x; frames++; }
    }
}
const status = () => { p.message({ type: 'status' }); return last; };
const levelDb = () => { const db = 10 * Math.log10(energy / Math.max(1, frames) + 1e-12); energy = 0; frames = 0; return db; };

run(0.5);
same(levelDb() < -100, true, 'silent before typing');
same(status().running, false, 'idle before typing');

let ms = 0;
const seen = new Set();
for (let i = 1; i <= 36; i++) {
    ms += 180; p.message({ type: 'key', ms }); run(0.18);
    seen.add(status().intensity);
}
for (const level of [1, 2, 3, 4]) truthy(seen.has(level), `build reaches layer ${level}`);
const s = status();
same(s.intensity, 4, 'a long sentence ends at the riser');
truthy(s.bpm >= 118 && s.bpm <= 128, `the tempo stays in the dance range (got ${s.bpm})`);

p.message({ type: 'pow' });
run(0.05);
same(status().dropBars, 2, 'POW starts a two-bar drop');
same(status().keys, 0, 'POW resets the sentence');
run(4.0);
same(status().dropBars, 0, 'the drop ends after two bars');
same(status().intensity, 0, 'after the drop the next sentence builds from the kick');

run(12);
same(status().running, false, 'four quiet bars stop the groove');
levelDb(); run(0.5);
same(levelDb() < -100, true, 'silent after stopping');

p.message({ type: 'key', ms: ms += 5000 });
run(0.3);
same(status().running, true, 'a new keystroke restarts the kick');
p.message({ type: 'break' }); run(3);
truthy(status().running, 'a comma break keeps the groove alive');
p.message({ type: 'stop' }); run(0.2);
same(status().running, false, 'stop silences immediately');

// The riser must not hang: typing on at full build, it fades within four bars.
const q = new Proc(); let t2 = 0;
const runQ = (sec) => { for (let i = 0, n = Math.round(sec / block); i < n; i++) { const L = new Float32Array(128), R = new Float32Array(128); q.process([], [[L, R]]); } };
for (let i = 1; i <= 40; i++) { t2 += 180; q.message({ type: 'key', ms: t2 }); runQ(0.18); }
truthy(q.riserGain > 0.03, `riser audible during the build (gain ${q.riserGain.toFixed(3)})`);
truthy(q.riserFc <= 6000.5, `riser stays below 6 kHz (got ${q.riserFc.toFixed(0)})`);
for (let i = 1; i <= 40; i++) { t2 += 180; q.message({ type: 'key', ms: t2 }); runQ(0.18); }
truthy(q.riserGain < 0.01, `riser eases away when no drop comes (gain ${q.riserGain.toFixed(3)})`);
truthy(peak < 1.0, `output never clips (peak ${peak.toFixed(2)})`);
// Patterns: record what fires, tagged with its bar, and count whole bars exactly.
function record(proc, bars) {
    const fired = [];
    const orig = proc.fire.bind(proc);
    proc.fire = (v) => { fired.push({ bar: proc.bar, v }); orig(v); };
    const len = 240 / proc.bpm;
    for (let i = 0, n = Math.ceil(bars * len / block); i < n; i++) { const L = new Float32Array(128), R = new Float32Array(128); proc.process([], [[L, R]]); }
    proc.fire = orig;
    return fired;
}
const count = (fired, bar, v) => fired.filter((e) => e.bar === bar && e.v === v).length;
const d = new Proc();
d.message({ type: 'key', ms: 100 });
let fired = record(d, 1.5);
same(count(fired, 0, 'bd'), 4, 'default pattern: four kicks in the first bar');
same(fired.some((e) => e.v === 'cp'), false, 'claps wait for their unlock');
for (let i = 0; i < 12; i++) d.message({ type: 'key', ms: 200 + i * 150 });
const next = d.bar + 1;
fired = record(d, 2);
same(count(fired, next, 'cp'), 2, 'claps join at ten keystrokes');
const c = new Proc();
c.message({ type: 'program', lines: globalThis.Mini.parseProgram('0 : bd(3,8)\n0 : cb*2').lines });
c.message({ type: 'key', ms: 100 });
fired = record(c, 1.5);
same(count(fired, 0, 'bd'), 3, 'a custom Euclidean kick replaces the groove');
same(count(fired, 0, 'cb'), 2, 'cowbell plays');
c.message({ type: 'key', ms: 300 }); c.message({ type: 'break' });
const breakBar = c.bar + 1;
fired = record(c, 2);
same(count(fired, breakBar, 'bd'), 0, 'a comma break drops the kick for a bar');
same(count(fired, breakBar, 'cb'), 2, 'the break keeps the rest of the groove');
console.log(`techno tests: ${checks} passed`);
