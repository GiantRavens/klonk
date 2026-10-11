// Instrument-scene regressions (no audio): node tests/scenes_test.js
// Every scene must load, walk its line, bring in its layers, and cadence; written
// themes must match their sources note for note; generated lines must stay in range,
// in key, and reproducible.
require('../Klonk.spoon/performer/scenes.js');
require('../Klonk.spoon/performer/scene.js');
const { Conductor, parseNote } = globalThis.SceneEngine;
const SCENES = globalThis.SCENES;
let checks = 0;
const same = (a, b, label) => { checks++; const x = JSON.stringify(a), y = JSON.stringify(b); if (x !== y) throw new Error(`${label}: expected ${y}, got ${x}`); };
const truthy = (a, label) => same(!!a, true, label);
const N = (t) => parseNote(t).m;
const notesOf = (c, n) => { const out = []; for (let i = 0; i < n; i++) for (const a of c.key(0)) if (a.type === 'note') out.push(a); return out; };

same(Object.keys(SCENES).sort(), ['bagpipe', 'hard-drive-music-box', 'harpsichord', 'jazz-piano', 'kalimba', 'schmoove-guitar', 'slap-bass', 'vibraphone', 'wurlitzer'], 'nine scenes');

// Written themes, note for note.
const prelude = notesOf(new Conductor(SCENES.harpsichord), 16).map((a) => a.note.m);
same(prelude, ['C4', 'E4', 'G4', 'C5', 'E5', 'G4', 'C5', 'E5', 'C4', 'E4', 'G4', 'C5', 'E5', 'G4', 'C5', 'E5'].map(N), 'Bach BWV 846, bar 1');
same(notesOf(new Conductor(SCENES.harpsichord), 17)[16].note.m, N('C4'), 'bar 2 begins');
same(notesOf(new Conductor(SCENES.harpsichord), 18)[17].note.m, N('D4'), 'bar 2 is Dm7 over C');
const lullaby = notesOf(new Conductor(SCENES['hard-drive-music-box']), 13).map((a) => a.note.m);
same(lullaby, 'C5 C5 Eb5 C5 C5 Eb5 C5 Eb5 Ab5 G5 F5 F5 Eb5'.split(' ').map(N), 'Brahms Wiegenlied opening, in A-flat');
same(SCENES.harpsichord.parts.lead.ring, true, 'the Prelude rings through each bar');
const brave = notesOf(new Conductor(SCENES.bagpipe), 10).map((a) => a.note.m);
same(brave, 'G4 G4 A4 B4 G4 B4 D5 G5 G5 F#5'.split(' ').map(N), 'Scotland the Brave opening, in G');
const funk = notesOf(new Conductor(SCENES['slap-bass']), 3).map((a) => a.note.mark);
same(funk, ['', '~', '^'], 'the slap riff marks ghost and pop');

for (const [name, sc] of Object.entries(SCENES)) {
    const c = new Conductor(sc);
    const notes = notesOf(c, 60);
    same(notes.length, 60, `${name}: sixty keystrokes play sixty notes`);
    same(c.intensity, sc.layers.length - 1, `${name}: a long sentence reaches the last layer`);
    truthy(notes.some((a) => a.barStart && a.index === 0), `${name}: bars start`);
    if (sc.generate && sc.generate.style !== 'bossa') {
        const [lo, hi] = sc.generate.range;
        const melody = notes.map((a) => a.note.m);
        truthy(melody.every((m) => m >= lo - 2 && m <= hi + 2), `${name}: the generated line stays in range`);
        const inKey = melody.filter((m) => sc.scale.includes(m % 12)).length / melody.length;
        truthy(inKey > 0.75, `${name}: the line stays mostly in key (${(inKey * 100) | 0}%)`);
        const again = notesOf(new Conductor(sc), 60).map((a) => a.note.m);
        same(again, melody, `${name}: the line is reproducible`);
    }
    const cad = c.key(36);
    same(cad[0].type, 'cadence', `${name}: Return cadences`);
    same(c.keys, 0, `${name}: the cadence starts a new phrase`);
    same(c.key(43), [{ type: 'lift' }], `${name}: comma lifts`);
    truthy(c.key(0)[0].type === 'note' && c.key(51)[0].type === 'note', `${name}: backspace replays a note`);
    for (const [chord] of sc.cadence.steps) truthy(sc.chords[chord], `${name}: cadence chord ${chord} is defined`);
}
console.log(`scene tests: ${checks} passed`);
