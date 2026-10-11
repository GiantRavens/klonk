// Orchestra conductor regressions (no audio): node tests/orchestra_test.js
// Loads orchestra.js headlessly and checks how keystrokes become musical decisions.
const path = require('path');
require(path.join(__dirname, '..', 'Klonk.spoon', 'performer', 'orchestra.js'));
const { Conductor, CHORDS, PROGRESSION, KEYS_PER_CHORD, LEVELS, voicing } = globalThis.OrchestraConductor;

let checks = 0;
const same = (a, b, label) => { checks++; if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${label}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); };
const KEY = 0, RETURN = 36, PERIOD = 47, COMMA = 43, BACKSPACE = 51;

same(voicing([2, 5, 9], 62, 3), [62, 65, 69], 'D minor voiced from D4');
same(voicing([9, 1, 4], 62, 3), [64, 69, 73], 'A major voiced from D4');

const c = new Conductor();
let first = c.key(KEY);
same(first[0], { type: 'chord', name: 'Dm', sections: ['strings'], intensity: 0 }, 'first key opens Dm on strings');
same(first.some((a) => a.type === 'pizz'), true, 'every key plucks a pizzicato note');
same(first.some((a) => a.type === 'timp'), false, 'no timpani early in the build');

const chordsSeen = ['Dm'], sectionsSeen = new Set(['strings']);
for (let i = 2; i <= 40; i++) {
    for (const a of c.key(KEY)) {
        if (a.type === 'chord') { if (a.name !== chordsSeen[chordsSeen.length - 1]) chordsSeen.push(a.name); a.sections.forEach((s) => sectionsSeen.add(s)); }
    }
}
same(chordsSeen, PROGRESSION, 'the harmony walks the whole progression');
same(c.chordName, 'A', 'a long sentence parks on the dominant');
same(c.intensity, 4, 'a long sentence reaches the full orchestra');
same([...sectionsSeen].sort(), ['brass', 'high', 'horns', 'low', 'strings'], 'every section joins along the way');
same(c.key(KEY).some((a) => a.type === 'timp'), true, 'at full strength keystrokes roll the timpani');

const land = c.key(RETURN);
same(land, [{ type: 'cadence', name: 'D', intensity: 4 }], 'Return from the dominant lands in D major');
same(c.keys, 0, 'the cadence resets the sentence');

for (let i = 0; i < 7; i++) c.key(KEY);
same(c.key(PERIOD)[0].name, 'Dm', 'a short sentence lands in D minor');

for (let i = 0; i < 12; i++) c.key(KEY);
same(c.chordName, 'F', 'twelve keys reach the third chord');
same(c.key(BACKSPACE)[0].name, 'Bb', 'backspace steps back a chord');
same(c.key(COMMA), [{ type: 'breath' }], 'comma breathes');
same(LEVELS.length, 5, 'five layers');
same(KEYS_PER_CHORD, 5, 'five keys per chord');
same(Object.keys(CHORDS).includes('D'), true, 'D major exists for the Picardy cadence');
console.log(`orchestra tests: ${checks} passed`);
