// Chamber conductor regressions (no audio): node tests/chamber_test.js
require('../Klonk.spoon/performer/chamber.js');
const { Conductor, PHRASES, LEVELS, step, N } = globalThis.ChamberConductor;
let checks = 0;
const same = (a, b, label) => { checks++; const x = JSON.stringify(a), y = JSON.stringify(b); if (x !== y) throw new Error(`${label}: expected ${y}, got ${x}`); };
const KEY = 0, RETURN = 36, PERIOD = 47, COMMA = 43, BACKSPACE = 51;

same(N('G4'), 67, 'G4 is MIDI 67'); same(N('F#5'), 78, 'F#5 is MIDI 78');
same(step(N('B4'), -2), N('G4'), 'a third below B is G');
same(step(N('G4'), -2), N('E4'), 'a third below G is E');
same(step(N('D5'), 1), N('E5'), 'upper neighbour of D is E');
same(step(N('F#4'), 1), N('G4'), 'upper neighbour of F# is G');

const c = new Conductor();
const melody = [];
let first = c.key(KEY);
same(first[0], { type: 'chord', chord: 'G', intensity: 0 }, 'the first bar opens on G');
same(first[1].m, N('D5'), 'the minuet begins on D5');
same(first[1].second, null, 'no second violin yet');
melody.push(first[1].m);
for (let i = 0; i < 30; i++) for (const a of c.key(KEY)) if (a.type === 'note') melody.push(a.m);
same(melody.slice(0, 8), ['D5', 'G4', 'A4', 'B4', 'C5', 'D5', 'G4', 'G4'].map(N), 'the Minuet in G, note for note');
same(c.title, 'Minuet in G', 'still in the minuet');
same(c.key(KEY).find((a) => a.type === 'note').m, N('A4'), 'the first phrase ends on A, the half cadence');
same(c.intensity >= 3, true, 'a long phrase brings in the harpsichord layer');
const next = c.key(KEY);
same(c.title, 'Eine kleine Nachtmusik', 'the next phrase is Mozart');
same(next.find((a) => a.type === 'note').m, N('G4'), 'Nachtmusik begins on G4');
same(next.find((a) => a.type === 'note').second, N('E4'), 'the second violin doubles a third below');

same(c.key(BACKSPACE).find((a) => a.type === 'note').m, N('G4'), 'backspace replays the previous note');
same(c.key(COMMA), [{ type: 'lift' }], 'comma lifts the bow');
same(c.key(RETURN)[0].type, 'cadence', 'Return plays the cadence');
same(c.title, 'Minuet in G', 'after the cadence, the next phrase');
same(c.key(KEY).find((a) => a.type === 'note').m, N('D5'), 'a new phrase starts from its first note');
same(c.key(PERIOD)[0].type, 'cadence', 'period cadences too');
same(PHRASES.length, 4, 'four phrases alternate the two salons');
same(LEVELS, [0, 6, 14, 24], 'four layers');
console.log(`chamber tests: ${checks} passed`);
