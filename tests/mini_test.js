// Mini-notation regressions: node tests/mini_test.js
require('../Klonk.spoon/performer/mini.js');
const { parsePattern, cycleEvents, parseProgram, noteToMidi } = globalThis.Mini;
let checks = 0;
const same = (a, b, label) => { checks++; const x = JSON.stringify(a), y = JSON.stringify(b); if (x !== y) throw new Error(`${label}: expected ${y}, got ${x}`); };
const at = (p, cycle = 0) => cycleEvents(parsePattern(p), cycle, () => 0.9).map((e) => [+e.start.toFixed(4), e.v]);

same(at('bd sd'), [[0, 'bd'], [0.5, 'sd']], 'a sequence shares the bar');
same(at('bd*4').map((e) => e[0]), [0, 0.25, 0.5, 0.75], 'bd*4 is four kicks');
same(at('~ cp ~ cp'), [[0.25, 'cp'], [0.75, 'cp']], 'rests');
same(at('[~ oh]*4').map((e) => e[0]), [0.125, 0.375, 0.625, 0.875], 'off-beat open hats');
same(at('bd [sd sd]'), [[0, 'bd'], [0.5, 'sd'], [0.75, 'sd']], 'groups squeeze into one step');
same(at('bd!3 sd').map((e) => e[1]), ['bd', 'bd', 'bd', 'sd'], 'copies are separate steps');
same(at('<bd sd cp>', 0)[0][1], 'bd', 'alternation: bar 1');
same(at('<bd sd cp>', 1)[0][1], 'sd', 'alternation: bar 2');
same(at('<bd sd cp>', 3)[0][1], 'bd', 'alternation wraps');
same(at('bd(3,8)').map((e) => e[0]), [0, 0.375, 0.75], 'Euclid (3,8) is x..x..x.');
same(at('bd(3,8,2)').length, 3, 'rotated Euclid keeps its hits');
same(cycleEvents(parsePattern('hh?*8'), 0, () => 0.1).length, 0, 'maybe drops on low rolls');
same(cycleEvents(parsePattern('hh?*8'), 0, () => 0.9).length, 8, 'maybe keeps on high rolls');
same(noteToMidi('a1'), 33, 'a1 is MIDI 33'); same(noteToMidi('cs2'), 37, 'cs2 is C#2'); same(noteToMidi('bb1'), 34, 'bb1 is B-flat 1');
same(cycleEvents(parsePattern('bd*32*32'), 0, () => 0.9).length, 256, 'event count is capped');

const prog = parseProgram('# comment\n0 : bd*4\n10 : ~ cp ~ cp   # claps\n\nhh*8');
same(prog.lines.map((l) => l.unlock), [0, 10, 0], 'unlock counts, default 0');
same(prog.errors, [], 'a good program has no errors');
const bad = parseProgram('0 : bd*4\n4 : xx yy\n6 : [bd sd\n8 : bd(9,4)');
same(bad.errors.map((e) => e.line), [2, 3, 4], 'errors name their lines');
same(/unknown sound 'xx'/.test(bad.errors[0].message), true, 'unknown sounds are named');
same(/missing '\]'/.test(bad.errors[1].message), true, 'unclosed groups are caught');
same(parseProgram('').errors[0].message, 'no patterns', 'empty programs are refused');
console.log(`mini tests: ${checks} passed`);
