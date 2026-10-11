// Instrument scenes: each instrument set performed as a phrase in a style, not one
// note per key. Data only; performer/scene.js plays them. Written themes are public
// domain and encoded note for note; the jazz, soul, lounge, mbira and bossa scenes
// generate their lines from chord-aware rules with a fixed seed.
//
// A scene:
//   phrases     written melody: [[chord, 'note note ...'], ...] per bar, or
//   generate    { style, perBar, range, progression } for a generated line
//   chords      name -> { root, pcs, voicing }        (root: bass MIDI, pcs: pitch classes)
//   scale       pitch classes for stepwise motion and thirds
//   parts       lead / double / bass / chord / drone / perc, each on a bank section
//   layers      keystroke counts at which each layer's parts join
//   cadence     what period or Return plays
//   room        a small convolution room
(function (global) {
    'use strict';
    const S = {};

    S.harpsichord = {
        title: 'Prelude', room: { seconds: 1.3, wet: 0.26, dark: 0.55 },
        // J. S. Bach, Prelude in C major, BWV 846: each bar's five notes arpeggiated twice.
        phrases: [
            [['C', 'C4 E4 G4 C5 E5'], ['Dm7/C', 'C4 D4 A4 D5 F5'], ['G7/B', 'B3 D4 G4 D5 F5'], ['C', 'C4 E4 G4 C5 E5']],
            [['Am/C', 'C4 E4 A4 E5 A5'], ['D7/C', 'C4 D4 F#4 A4 D5'], ['G/B', 'B3 D4 G4 D5 G5'], ['Cmaj7/B', 'B3 C4 E4 G4 C5']],
            [['Am7', 'A3 C4 E4 G4 C5'], ['D7', 'D3 A3 D4 F#4 C5'], ['G', 'G3 B3 D4 G4 B4'], ['C', 'C4 E4 G4 C5 E5']],
        ],
        figure: [0, 1, 2, 3, 4, 2, 3, 4, 0, 1, 2, 3, 4, 2, 3, 4],
        scale: [0, 2, 4, 5, 7, 9, 11],
        chords: { C: { root: 36 }, 'Dm7/C': { root: 36 }, 'G7/B': { root: 35 }, 'Am/C': { root: 36 }, 'D7/C': { root: 36 },
            'G/B': { root: 35 }, 'Cmaj7/B': { root: 35 }, Am7: { root: 45 }, D7: { root: 38 }, G: { root: 43 }, G7: { root: 43 } },
        parts: { lead: { section: 'harp', gain: 0.85, ring: true }, bass: { section: 'harp', gain: 0.6, mode: 'bar' },
            double: { section: 'harp', interval: 12, gain: 0.32 } },
        layers: [[0, ['lead']], [8, ['lead', 'bass']], [40, ['lead', 'bass', 'double']]],
        cadence: { steps: [['G7', ['G3', 'B3', 'D4', 'F4', 'B4']], ['C', ['C3', 'G3', 'C4', 'E4', 'G4', 'C5']]], roll: 0.045, hold: 2.4 },
    };

    S['hard-drive-music-box'] = {
        title: 'Lullaby', room: { seconds: 1.0, wet: 0.2, dark: 0.4 },
        // Johannes Brahms, Wiegenlied, Op. 49 No. 4, in A-flat to suit the music box's comb.
        phrases: [
            [['Ab', 'C5 C5'], ['Ab', 'Eb5 C5 C5'], ['Ab', 'Eb5 C5 Eb5'], ['Db', 'Ab5 G5 F5'], ['Eb', 'F5 Eb5 Bb4'],
                ['Eb', 'C5 Db5 Bb4'], ['Eb', 'Bb4 C5 Db5'], ['Eb', 'Bb4 Db5 G5'], ['Ab', 'F5 Eb5 G5'], ['Ab', 'Ab5']],
            [['Ab', 'Ab4 Ab4'], ['Db', 'Ab5 F5 Db5'], ['Ab', 'Eb5 C5 Ab4'], ['Db', 'Db5 Eb5 F5'], ['Ab', 'Eb5'],
                ['Ab', 'Ab4 Ab4'], ['Db', 'Ab5 F5 Db5'], ['Ab', 'Eb5 C5 Ab4'], ['Eb', 'Db5 C5 Bb4'], ['Ab', 'Ab4']],
        ],
        scale: [8, 10, 0, 1, 3, 5, 7],
        chords: { Ab: { root: 56 }, Db: { root: 61 }, Eb: { root: 63 } },
        parts: { lead: { section: ['box', 'box2'], gain: 0.85, exact: true }, double: { section: 'box', interval: 'third-below', gain: 0.35, exact: true } },
        layers: [[0, ['lead']], [12, ['lead', 'double']]],
        cadence: { steps: [['Eb', ['Bb4']], ['Ab', ['Ab4']]], winddown: true, hold: 2.0 },
    };

    S.bagpipe = {
        title: 'Highland', room: { seconds: 2.4, wet: 0.3, dark: 0.5 },
        // Scotland the Brave (traditional), from The Session setting 31611 (thesession.org/tunes/4960),
        // transposed from D up a fourth to G so it lies on the chanter over the G drones.
        phrases: [
            [['G', 'G4 G4 A4'], ['G', 'B4 G4 B4 D5'], ['G', 'G5 G5 F#5'], ['G', 'G5 D5 B4 G4'], ['C', 'C5 E5 C5'], ['G', 'B4 D5 B4 G4'], ['D', 'A4 D5 E5'], ['D', 'D5 C5 B4 A4']],
            [['G', 'G4 G4 A4'], ['G', 'B4 G4 B4 D5'], ['G', 'G5 G5 F#5'], ['G', 'G5 D5 B4 G4'], ['C', 'C5 E5 C5'], ['G', 'B4 D5 B4 G4'], ['D', 'A4 G4 A4'], ['G', 'G4']],
            [['D', 'A5 A5 G5'], ['D', 'A5 F#5 D5'], ['G', 'G5 B5 A5'], ['G', 'G5 D5 B4 D5'], ['G', 'G5 G5 G5'], ['D', 'F#5 G5 F#5'], ['C', 'E5 G5 F#5 E5'], ['D', 'D5 C5 B4 A4']],
            [['G', 'G4 G4 A4'], ['G', 'B4 G4 B4 D5'], ['G', 'G5 G5 F#5'], ['G', 'G5 D5 B4 G4'], ['C', 'C5 E5 C5'], ['G', 'B4 D5 G5 B5'], ['D', 'A5 D5 E5 F#5'], ['G', 'G5']],
        ],
        scale: [7, 9, 11, 0, 2, 4, 6],
        chords: { G: { root: 43 }, C: { root: 43 }, D: { root: 43 } },
        parts: { lead: { section: 'pipe', gain: 0.8, grace: 79 }, drone: { section: 'drone', gain: 0.5 },
            perc: { section: 'kit', bar: [[36, 0.7]], key: [[38, 0.18]], keyFrom: 2 } },
        layers: [[0, ['lead', 'drone']], [10, ['lead', 'drone', 'bass-drum']], [20, ['lead', 'drone', 'perc']]],
        cadence: { steps: [['D', ['A4']], ['G', ['G4']]], hold: 2.4 },
    };

    S['jazz-piano'] = {
        title: 'After Hours', room: { seconds: 1.2, wet: 0.24, dark: 0.6 },
        generate: { style: 'bebop', perBar: 8, range: [60, 81], progression: ['Dm7', 'G7', 'Cmaj7', 'A7'] },
        scale: [0, 2, 4, 5, 7, 9, 11],
        chords: { Dm7: { root: 38, pcs: [2, 5, 9, 0], voicing: [53, 57, 60, 64] }, G7: { root: 43, pcs: [7, 11, 2, 5], voicing: [53, 57, 59, 64] },
            Cmaj7: { root: 36, pcs: [0, 4, 7, 11], voicing: [52, 55, 59, 62] }, A7: { root: 45, pcs: [9, 1, 4, 7], voicing: [55, 58, 61, 66] },
            C69: { root: 36, pcs: [0, 4, 7, 9, 2], voicing: [52, 57, 62, 67] } },
        parts: { lead: { section: 'piano', gain: 0.75 }, bass: { section: 'bass', gain: 0.8, mode: 'walk' },
            chord: { section: 'piano', gain: 0.32, style: 'stab' }, perc: { section: 'kit', key: [[51, 0.12]] } },
        layers: [[0, ['lead']], [6, ['lead', 'bass']], [14, ['lead', 'bass', 'chord']], [24, ['lead', 'bass', 'chord', 'perc']]],
        cadence: { steps: [['Dm7', ['F5']], ['G7', ['E5']], ['C69', ['D5', 'G5']]], hold: 2.6 },
    };

    S.wurlitzer = {
        title: 'Soul Kitchen', room: { seconds: 1.4, wet: 0.24, dark: 0.55 },
        generate: { style: 'lyrical', perBar: 6, range: [60, 79], progression: ['Cm9', 'Fm9', 'Ab', 'Bb'] },
        scale: [0, 2, 3, 5, 7, 10],
        chords: { Cm9: { root: 36, pcs: [0, 3, 7, 10, 2], voicing: [51, 55, 58, 62] }, Fm9: { root: 41, pcs: [5, 8, 0, 3, 7], voicing: [51, 56, 60, 63] },
            Ab: { root: 44, pcs: [8, 0, 3], voicing: [51, 56, 60] }, Bb: { root: 46, pcs: [10, 2, 5], voicing: [50, 53, 58] } },
        parts: { lead: { section: 'wurli', gain: 0.8 }, bass: { section: 'bass', gain: 0.8, mode: 'bar' }, chord: { section: 'wurli', gain: 0.38, style: 'stab' } },
        layers: [[0, ['lead']], [6, ['lead', 'chord']], [14, ['lead', 'chord', 'bass']]],
        cadence: { steps: [['Fm9', ['Ab4', 'C5']], ['Cm9', ['G4', 'C5', 'Eb5']]], hold: 2.6 },          // the amen
    };

    S.vibraphone = {
        title: 'Late Lounge', room: { seconds: 1.8, wet: 0.3, dark: 0.5 },
        generate: { style: 'lyrical', perBar: 5, range: [62, 84], progression: ['Fmaj7', 'Dm7', 'Gm7', 'C7'] },
        scale: [5, 7, 9, 10, 0, 2, 4],
        chords: { Fmaj7: { root: 41, pcs: [5, 9, 0, 4], voicing: [57, 60, 64, 65] }, Dm7: { root: 38, pcs: [2, 5, 9, 0], voicing: [57, 60, 62, 65] },
            Gm7: { root: 43, pcs: [7, 10, 2, 5], voicing: [58, 62, 65, 67] }, C7: { root: 36, pcs: [0, 4, 7, 10], voicing: [58, 60, 64, 67] } },
        parts: { lead: { section: 'vibes', gain: 0.8 }, bass: { section: 'bass', gain: 0.75, mode: 'bar' }, chord: { section: 'vibes', gain: 0.28, style: 'roll' } },
        layers: [[0, ['lead']], [6, ['lead', 'bass']], [14, ['lead', 'bass', 'chord']]],
        cadence: { steps: [['Gm7', ['D5']], ['C7', ['E5']], ['Fmaj7', ['A5', 'F5']]], hold: 2.8 },
    };

    S.kalimba = {
        title: 'Mbira Circle', room: { seconds: 1.1, wet: 0.2, dark: 0.45 },
        generate: { style: 'riff', perBar: 8, range: [55, 86], progression: ['G', 'Em', 'C', 'D'], figure: [0, 4, 2, 5, 1, 4, 3, 5] },
        scale: [7, 9, 11, 2, 4],
        chords: { G: { root: 55, pcs: [7, 11, 2] }, Em: { root: 52, pcs: [4, 7, 11] }, C: { root: 48, pcs: [0, 4, 7] }, D: { root: 50, pcs: [2, 6, 9] } },
        parts: { lead: { section: 'kalimba', gain: 0.8 }, double: { section: 'kalimba', interval: -12, gain: 0.4, echo: true },
            perc: { section: 'kit', key: [[70, 0.25]] } },
        layers: [[0, ['lead']], [8, ['lead', 'perc']], [16, ['lead', 'perc', 'double']]],
        cadence: { steps: [['D', ['F#5', 'A5']], ['G', ['G4', 'B4', 'D5', 'G5']]], roll: 0.06, hold: 2.2 },
    };

    S['slap-bass'] = {
        title: 'Funk Groove', room: { seconds: 0.7, wet: 0.15, dark: 0.5 },
        // A two-bar slap riff in E: ^ pops a string, ~ is a ghost note.
        phrases: [
            [['E7', 'E2 E2~ E3^ E2 G2 A2 E3^ D3^'], ['E7', 'E2 E2~ E3^ G2 A2 B2 D3^ E3^']],
            [['A7', 'A2 A2~ A3^ A2 C3 D3 A3^ G3^'], ['E7', 'E2 E2~ E3^ G2 A2 B2 D3^ E3^']],
        ],
        scale: [4, 7, 9, 11, 2],
        chords: { E7: { root: 40 }, A7: { root: 45 } },
        parts: { lead: { section: 'slap', pop: 'pop', gain: 0.9 },
            perc: { section: 'kit', key: [[42, 0.25]], backbeat: [[38, 0.6]], bar: [[36, 0.8]] } },
        layers: [[0, ['lead']], [4, ['lead', 'hats']], [10, ['lead', 'perc']]],
        cadence: { steps: [['E7', ['G2', 'A2', 'B2']], ['E7', ['E2', 'E3^']]], fast: true, hit: [[36, 0.9], [38, 0.7]], hold: 1.6 },
    };

    S['schmoove-guitar'] = {
        title: 'Rio', room: { seconds: 1.2, wet: 0.24, dark: 0.5 },
        // Bossa nova comping: thumb on the root and fifth, fingers on syncopated chords.
        generate: { style: 'bossa', perBar: 8, progression: ['Dm9', 'G13', 'Cmaj9', 'A7b13'], pattern: ['B', 'C', 'b', 'C', 'C', 'B', 'C', 'b'] },
        scale: [0, 2, 4, 5, 7, 9, 11],
        chords: { Dm9: { root: 50, fifth: 45, voicing: [53, 60, 64] }, G13: { root: 43, fifth: 50, voicing: [53, 59, 64] },
            Cmaj9: { root: 48, fifth: 43, voicing: [52, 59, 62] }, A7b13: { root: 45, fifth: 52, voicing: [55, 61, 65] } },
        parts: { lead: { section: 'guitar', gain: 0.8 }, perc: { section: 'kit', key: [[70, 0.2]] }, bass: { section: 'bass', gain: 0.6, mode: 'bar' } },
        layers: [[0, ['lead']], [8, ['lead', 'perc']], [16, ['lead', 'perc', 'bass']]],
        cadence: { steps: [['G13', ['G13']], ['Cmaj9', ['Cmaj9']]], strum: 0.05, hold: 2.6 },
    };

    global.SCENES = S;
})(typeof window !== 'undefined' ? window : globalThis);
