// Klonk mini-notation: a small, clean-room subset of TidalCycles' pattern language.
// Shared by the settings editor (live error checking), the performer page, and the
// techno AudioWorklet, so all three agree on what a pattern means.
//
// A pattern is one bar (a "cycle"):
//   bd sd          a sequence: steps share the bar equally
//   ~              a rest
//   [bd sd]        a group squeezed into one step
//   bd*4           repeat within the step (four kicks in the step's time)
//   bd!3           three copies as separate steps
//   <bd sd cp>     alternate: one per bar, in turn
//   hh?            sometimes (dropped about half the time)
//   bd(3,8)        Euclidean rhythm: 3 hits spread over 8 slots (optional rotation: (3,8,2))
// A program is one pattern per line, prefixed with the keystrokes that unlock it:
//   10 : ~ cp ~ cp       # comments run to the end of the line
(function (global) {
    'use strict';

    const SOUNDS = ['bd', 'sd', 'sn', 'cp', 'hh', 'oh', 'sh', 'rim', 'cb'];
    const NOTE = /^([a-g])(#|s|b)?(-?\d)$/;
    const LIMIT = 256;                                   // events per bar, so a pattern cannot run away

    function noteToMidi(word) {
        const m = NOTE.exec(word);
        if (!m) return null;
        const pc = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 }[m[1]] + (m[2] === '#' || m[2] === 's' ? 1 : m[2] === 'b' ? -1 : 0);
        return 12 * (parseInt(m[3], 10) + 1) + pc;
    }
    const valid = (w) => SOUNDS.includes(w) || noteToMidi(w) !== null;

    // ---- parser: text -> tree ----
    function parsePattern(text) {
        let i = 0;
        const src = text;
        const fail = (msg) => { throw new Error(`${msg} at column ${i + 1}`); };
        const ws = () => { while (i < src.length && /[\s.]/.test(src[i])) i++; };
        const number = () => {
            const m = /^\d+(\.\d+)?/.exec(src.slice(i));
            if (!m) fail('expected a number');
            i += m[0].length; return parseFloat(m[0]);
        };
        function sequence(close) {
            const items = [];
            for (;;) {
                ws();
                if (i >= src.length) { if (close) fail(`missing '${close}'`); break; }
                if (src[i] === close) { i++; break; }
                if (']>)'.includes(src[i])) fail(`unexpected '${src[i]}'`);
                const step = modifiers(atom());
                if (step.copies) { for (let k = 0; k < step.copies; k++) items.push(step.node); } else items.push(step.node);
            }
            return items;
        }
        function atom() {
            const c = src[i];
            if (c === '~') { i++; return { t: 'rest' }; }
            if (c === '[') { i++; const items = sequence(']'); if (!items.length) fail('empty group'); return { t: 'seq', items }; }
            if (c === '<') { i++; const items = sequence('>'); if (!items.length) fail('empty alternation'); return { t: 'alt', items }; }
            const m = /^[a-z][a-z0-9#]*/.exec(src.slice(i));
            if (!m) fail(`unexpected '${c}'`);
            i += m[0].length;
            if (!valid(m[0])) { i -= m[0].length; fail(`unknown sound '${m[0]}' (sounds: ${SOUNDS.join(' ')}, or a note like a1)`); }
            return { t: 'word', v: m[0] };
        }
        function modifiers(node) {
            let copies = 0;
            for (;;) {
                const c = src[i];
                if (c === '*') { i++; const n = number(); if (n < 1 || n > 32) fail('* takes 1 to 32'); node = { t: 'fast', n, node }; }
                else if (c === '!') { i++; const n = /\d/.test(src[i] || '') ? number() : 2; if (n < 1 || n > 32) fail('! takes 1 to 32'); copies = n; }
                else if (c === '?') { i++; node = { t: 'maybe', node }; }
                else if (c === '(') {
                    i++; ws(); const k = number(); ws(); if (src[i] !== ',') fail("expected ','"); i++; ws(); const n = number(); ws();
                    let r = 0; if (src[i] === ',') { i++; ws(); r = number(); ws(); }
                    if (src[i] !== ')') fail("expected ')'"); i++;
                    if (n < 1 || n > 32 || k < 0 || k > n) fail('Euclid needs 0 <= hits <= slots <= 32');
                    node = { t: 'euclid', k, n, r, node };
                } else break;
            }
            return { node, copies };
        }
        const items = sequence(null);
        return { t: 'seq', items };
    }

    // ---- evaluator: tree + bar number -> timed events within the bar (0..1) ----
    function events(node, cycle, start, dur, out, rand) {
        if (out.length >= LIMIT) return out;
        switch (node.t) {
            case 'rest': break;
            case 'word': out.push({ start, dur, v: node.v }); break;
            case 'seq': { const d = dur / node.items.length; node.items.forEach((n, k) => events(n, cycle, start + k * d, d, out, rand)); break; }
            case 'alt': events(node.items[((cycle % node.items.length) + node.items.length) % node.items.length], Math.floor(cycle / node.items.length), start, dur, out, rand); break;
            case 'fast': { const d = dur / node.n; for (let k = 0; k < node.n; k++) events(node.node, cycle * node.n + k, start + k * d, d, out, rand); break; }
            case 'maybe': if (rand() >= 0.5) events(node.node, cycle, start, dur, out, rand); break;
            case 'euclid': {
                const d = dur / node.n;
                for (let k = 0; k < node.n; k++) {
                    const j = (k + node.r) % node.n;
                    if ((j * node.k) % node.n < node.k) events(node.node, cycle, start + k * d, d, out, rand);
                }
                break;
            }
        }
        return out;
    }
    function cycleEvents(tree, cycle, rand) {
        return events(tree, cycle, 0, 1, [], rand || Math.random).sort((a, b) => a.start - b.start);
    }

    // ---- program: "keys : pattern" lines ----
    function parseProgram(text) {
        const lines = [], errors = [];
        String(text || '').split('\n').forEach((raw, k) => {
            const line = raw.replace(/#.*/, '').trim();
            if (!line) return;
            const m = /^(\d+)\s*:\s*(.*)$/.exec(line);
            const unlock = m ? parseInt(m[1], 10) : 0, body = m ? m[2] : line;
            try {
                const tree = parsePattern(body.toLowerCase());
                if (!tree.items.length) throw new Error('empty pattern');
                lines.push({ unlock, tree, src: body, line: k + 1 });
            } catch (e) { errors.push({ line: k + 1, message: e.message }); }
        });
        if (!lines.length && !errors.length) errors.push({ line: 0, message: 'no patterns' });
        return { lines, errors };
    }

    global.Mini = { SOUNDS, noteToMidi, parsePattern, cycleEvents, parseProgram };
})(typeof globalThis !== 'undefined' ? globalThis : this);
