// Film-score performer regressions, headless against the real worklet code:
//   node tests/cinematic_test.js
// The AAC bank needs a browser to decode, so the test supplies a synthetic bank
// (decaying tones at each grid pitch) and checks the sequencer, the sections, the
// theme and its answer, braams, the lift, the silence before the hit, the cadence,
// the trailer gap, idle stop, humanized timing, voice housekeeping, and clipping.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'Klonk.spoon', 'performer', 'cinematic-worklet.js'), 'utf8');
global.sampleRate = 44100;
let last, Proc;
global.AudioWorkletProcessor = class { constructor() { this.port = { postMessage: (m) => { last = m; } }; } };
global.registerProcessor = (_, cls) => { Proc = cls; };
eval(src);

let checks = 0;
const same = (a, b, label) => { checks++; if (a !== b) throw new Error(`${label}: expected ${b}, got ${a}`); };
const truthy = (a, label) => same(!!a, true, label);
const list = (a) => JSON.stringify(a);

const tone = (m, seconds) => {
    const f = 440 * Math.pow(2, (m - 69) / 12), n = Math.floor(seconds * sampleRate), d = new Float32Array(n);
    for (let i = 0; i < n; i++) d[i] = 0.6 * Math.sin(2 * Math.PI * f * i / sampleRate) * Math.exp(-i / sampleRate / (seconds / 3));
    return d;
};
const grid = { viola: [50, 62, 74], cello: [33, 45, 54], pizz: [36, 60, 78], brass: [30, 42, 54], horns: [60, 66, 72, 75],
    strings: [67, 76, 85, 88], timp: [38, 45, 50], choir: [62, 74], taiko: [36, 43], toms: [43, 58], kit: [36, 38, 49, 57] };
const bank = {};
for (const [s, ms] of Object.entries(grid)) { bank[s] = {}; for (const m of ms) bank[s][m] = tone(m, ['brass', 'choir', 'horns', 'strings'].includes(s) ? 3 : 0.6); }

const p = new Proc();
p.message({ type: 'bank', bank });
same(last.type, 'loaded', 'bank loads');
truthy(p.bank.whoosh, 'reverse crash prepared for backspace');

// Every note the score plays, with the bar and sixteenth it was written for.
let log = [];
p.onPlay = (section, m, gain, seconds) => log.push({ section, m, gain, seconds, bar: p.bar, pb: p.phraseBar, step: p.step, at: p.now });

const block = 128 / sampleRate;
let peak = 0, maxVoices = 0;
const run = (sec) => { for (let i = 0, n = Math.round(sec / block); i < n; i++) {
    const L = new Float32Array(128), R = new Float32Array(128); p.process([], [[L, R]]);
    for (const x of L) peak = Math.max(peak, Math.abs(x)); maxVoices = Math.max(maxVoices, p.voices.length); } };
const status = () => { p.message({ type: 'status' }); return last; };

run(0.5);
same(status().running, false, 'silent until the first keystroke');

// A long sentence typed every 200 ms: long enough for every section and the lift.
let ms = 0;
const seen = new Set(), chords = new Set(), sections = [];
for (let i = 1; i <= 100; i++) {
    ms += 200; p.message({ type: 'key', ms }); run(0.2);
    const s = status(); seen.add(s.intensity); chords.add(s.chord);
    if (sections[sections.length - 1] !== s.section) sections.push(s.section);
}
same(list(sections), list(['pulse', 'theme', 'answer', 'tutti', 'lift']), 'the build passes through every section in order');
for (const level of [0, 1, 2, 3, 4]) truthy(seen.has(level), `the build reaches section ${level}`);
same(chords.size, 4, 'the harmony cycles all four chords');
truthy(Math.abs(status().bpm - (138 - 0.2 * 60)) < 3, `typing every 200 ms settles near 126 BPM (got ${status().bpm})`);
truthy(status().levelDb > -30, `the full build is loud (${status().levelDb} dB)`);

// The theme: the horns' first phrase is the written call, on the written sixteenths.
const horns = log.filter((n) => n.section === 'horns');
same(horns[0].step, 0, 'the horns enter on a bar line');
same(horns[0].pb, 0, 'the theme enters at the top of its phrase');
const firstBar = horns.filter((n) => n.bar === horns[0].bar);
same(list(firstBar.map((n) => n.m)), list([62, 69, 74, 72]), 'the horns open with the theme, D-A-D-C');
same(list(firstBar.map((n) => n.step)), list([0, 6, 8, 14]), 'the theme sits on its written sixteenths');
const strings = log.filter((n) => n.section === 'strings');
truthy(strings.length > 0, 'the strings answer');
const answerBars = strings.filter((n) => !horns.some((h) => h.bar === n.bar)).map((n) => n.pb);
truthy(answerBars.length > 0 && answerBars.every((b) => b >= 2), 'in the answer section the strings take bars 3-4 alone');
truthy(strings.every((n) => n.m >= 74), 'the answer sounds an octave above the horn call');

// Braams mark structure only: the answer, the lift, nowhere else.
const braams = new Set(log.filter((n) => n.section === 'brass' && n.seconds >= 2.2).map((n) => n.bar));
same(braams.size, 2, `two braams in the whole build (bars ${[...braams]})`);
truthy(log.filter((n) => n.section === 'cello').length > 100, 'the ostinato keeps driving');

// The lift: a whole step up, landing on the first bar of a phrase.
same(status().lift, 2, 'the last section lifts a whole step');
const lifted = log.find((n) => n.section === 'horns' && n.m === 64);
truthy(lifted, 'the lifted horns start the theme on E');
same(lifted.pb, 0, 'the lift lands on a phrase');
truthy(horns.some((n) => n.m === 62 && n.pb === 0), 'the theme is heard whole in D minor before the lift');
truthy(log.some((n) => n.section === 'kit' && n.m === 38 && n.bar < lifted.bar && n.bar >= lifted.bar - 4), 'a snare roll leads into the lift');

// Players are human: notes start a few milliseconds late, not on the grid.
const waits = new Set(p.voices.filter((v) => v.wait !== undefined).map((v) => Math.round(v.wait)));
p.message({ type: 'key', ms: ms += 200 }); run(0.05);
const fresh = p.voices.filter((v) => v.wait > 0).map((v) => v.wait);
truthy(fresh.length > 0 || waits.size > 1, 'notes are humanized off the grid');
truthy(fresh.every((w) => w < 0.01 * sampleRate), 'by less than 10 ms');

// Return: everything stops, a beat of silence, then B-flat, C, D major.
log = [];
const beat = 60 / status().bpm, hitAt = p.now;
p.message({ type: 'hit' });
run(0.06);
same(status().running, false, 'the hit stops the score');
same(status().ending, 'cadence', 'a full build ends with the trailer cadence');
run(beat * 0.8);
same(log.length, 0, 'a beat of silence before the hit');
truthy(status().levelDb < -25, `the silence is silent (${status().levelDb} dB)`);
run(beat * 1.6);
const brassRoots = log.filter((n) => n.section === 'brass').map((n) => n.m).filter((m, i, a) => a.indexOf(m) === i);
same(list(brassRoots.slice(0, 9).filter((_, i) => i % 3 === 0)), list([36, 38, 40]), 'the cadence climbs B-flat, C, D (lifted to C, D, E)');
const firstHit = Math.min(...log.map((n) => n.at)) - hitAt;
truthy(firstHit > beat * 0.9 && firstHit < beat * 1.2, `the first chord lands one beat after Return (${firstHit.toFixed(2)} s)`);
const finalChord = log.filter((n) => n.section === 'horns').slice(-3).map((n) => n.m % 12).sort((a, b) => a - b);
same(list(finalChord), list([4, 8, 11]), 'it ends on the major tonic (E major after the lift)');
truthy(status().voices >= 10, 'the hit sounds the whole orchestra');
run(3);
truthy(status().levelDb > -60, 'the hall rings after the hit');
run(4);
same(status().voices, 0, 'every voice finishes after the hit');
same(status().ending, null, 'the ending is over');

// A period is a line ending: a single minor hit, no cadence.
p.message({ type: 'key', ms: ms += 8000 }); run(0.3);
log = [];
p.message({ type: 'end' }); run(1.2);
same(log.filter((n) => n.section === 'horns').map((n) => n.m % 12).sort((a, b) => a - b).join(), '2,5,9', 'a period ends on one D minor hit');
run(4);

p.message({ type: 'key', ms: ms += 6000 }); run(0.3);
same(status().running, true, 'the next keystroke starts a new build');
same(status().lift, 0, 'a new sentence starts back in D minor');
p.message({ type: 'gap' }); run(240 / status().bpm + 0.2);
same(status().gap, true, 'a comma silences the next bar');
const v = status().voices; run(0.6);
truthy(status().voices <= v, 'nothing new sounds in the gap');
p.message({ type: 'whoosh' }); run(0.05);
truthy(status().voices >= 1, 'backspace whooshes');
run(14);
same(status().running, false, 'four quiet bars end it');
truthy(maxVoices < 200, `voices stay bounded (max ${maxVoices})`);
truthy(peak < 1.0, `output never clips (peak ${peak.toFixed(2)})`);
console.log(`cinematic tests: ${checks} passed`);
