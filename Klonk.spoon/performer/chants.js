// Chant repertoire extracted verbatim from Synth_Gregorian gregorian-engine.js
// (5a46c905b19738683d419c89360ea186f38d85d3, MIT). Each syllable: { syl, v (sung vowel), n: [note names] };
// a multi-note n is a neume sung legato on one vowel.
window.CHANTS = {
            // "Veni Creator Spiritus" — Vesper hymn for Pentecost, Mode 8
            // (Hypomixolydian): final G, reciting tone C. Syllabic, strophic.
            veni: {
                title: 'Veni Creator Spiritus',
                mode: 8, genre: 'hymn (syllabic)',
                phrases: [
                    [ { syl: 'Ve',   v: 'e', n: ['G3'] },
                      { syl: 'ni',   v: 'i', n: ['A3'] },
                      { syl: 'Cre',  v: 'e', n: ['G3','F3'] },
                      { syl: 'a',    v: 'a', n: ['G3'] },
                      { syl: 'tor',  v: 'o', n: ['A3','G3'] },
                      { syl: 'Spi',  v: 'i', n: ['C4'] },
                      { syl: 'ri',   v: 'i', n: ['D4'] },
                      { syl: 'tus',  v: 'u', n: ['C4'] } ],
                    [ { syl: 'Men',  v: 'e', n: ['C4'] },
                      { syl: 'tes',  v: 'e', n: ['G3'] },
                      { syl: 'tu',   v: 'u', n: ['A3'] },
                      { syl: 'o',    v: 'o', n: ['C4'] },
                      { syl: 'rum',  v: 'u', n: ['D4','C4'] },
                      { syl: 'vi',   v: 'i', n: ['D4'] },
                      { syl: 'si',   v: 'i', n: ['E4'] },
                      { syl: 'ta',   v: 'a', n: ['D4'] } ],
                    [ { syl: 'Im',   v: 'i', n: ['C4'] },
                      { syl: 'ple',  v: 'e', n: ['D4','E4'] },
                      { syl: 'su',   v: 'u', n: ['C4','B3'] },
                      { syl: 'per',  v: 'e', n: ['A3','G3'] },
                      { syl: 'na',   v: 'a', n: ['C4','D4'] },
                      { syl: 'gra',  v: 'a', n: ['G3'] },
                      { syl: 'ti',   v: 'i', n: ['A3'] },
                      { syl: 'a',    v: 'a', n: ['C4'] } ],
                    [ { syl: 'Quae', v: 'e', n: ['B3','C4'] },
                      { syl: 'tu',   v: 'u', n: ['A3'] },
                      { syl: 'cre',  v: 'e', n: ['G3','F3'] },
                      { syl: 'a',    v: 'a', n: ['A3'] },
                      { syl: 'sti',  v: 'i', n: ['A3','B3','A3'] },
                      { syl: 'pec',  v: 'e', n: ['G3'] },
                      { syl: 'to',   v: 'o', n: ['F3'] },
                      { syl: 'ra',   v: 'a', n: ['G3'] } ]
                ]
            },
            // "Viderunt omnes" — Christmas gradual (respond), Mode 5: final F,
            // reciting tone C. Decoded note-for-note from the GregoBase 1163
            // GABC (Graduale Romanum 1961 p. 33 / Liber Usualis p. 409, c3
            // clef: d=F3 e=G3 f=A3 g=B3 h=C4 i=D4 j=E4 k=F4; the "gx" flat in
            // "omnis" makes those g's B♭3). This is the respond Pérotin set as
            // four-voice organum — fully melismatic, the melisma on "(ter)ra"
            // running to sixteen notes.
            viderunt: {
                title: 'Viderunt omnes',
                mode: 5, genre: 'gradual (melismatic)',
                phrases: [
                    [ { syl: 'Vi',   v: 'i', n: ['F3'] },
                      { syl: 'dé',   v: 'e', n: ['F3'] },
                      { syl: 'runt', v: 'u', n: ['A3','C4'] },
                      { syl: 'o',    v: 'o', n: ['C4','D4','C4','A3','C4','C4','C4','E4','D4','C4'] },
                      { syl: 'mnes', v: 'e', n: ['C4'] } ],
                    [ { syl: 'fi',   v: 'i', n: ['C4','D4'] },
                      { syl: 'nes',  v: 'e', n: ['C4','A3'] },
                      { syl: 'ter',  v: 'e', n: ['C4','A3','C4','C4','A3'] },
                      { syl: 'rae',  v: 'e', n: ['A3','C4','C4','A3','C4','B3','C4','A3'] } ],
                    [ { syl: 'sa',   v: 'a', n: ['A3'] },
                      { syl: 'lu',   v: 'u', n: ['C4','B3'] },
                      { syl: 'tá',   v: 'a', n: ['C4','B3','D4'] },
                      { syl: 're',   v: 'e', n: ['D4','C4','B3','C4','A3'] } ],
                    [ { syl: 'De',   v: 'e', n: ['A3','G3','A3','B3','C4','D4','C4'] },
                      { syl: 'i',    v: 'i', n: ['C4','B3','D4','E4','F4'] },
                      { syl: 'no',   v: 'o', n: ['D4','C4'] },
                      { syl: 'stri', v: 'i', n: ['C4','B3','C4','A3'] } ],
                    [ { syl: 'ju',   v: 'u', n: ['A3'] },
                      { syl: 'bi',   v: 'i', n: ['C4','B3'] },
                      { syl: 'lá',   v: 'a', n: ['C4'] },
                      { syl: 'te',   v: 'e', n: ['C4','C4','C4'] },
                      { syl: 'De',   v: 'e', n: ['A3','C4','G3','G3','F3'] },
                      { syl: 'o',    v: 'o', n: ['F3','G3','A3','C4','A3','F3'] } ],
                    [ { syl: 'o',    v: 'o', n: ['F3','A3','C4','D4','E4','C4'] },
                      { syl: 'mnis', v: 'i', n: ['C4','A3','Bb3','C4','Bb3','G3','A3','Bb3','A3','G3'] },
                      { syl: 'ter',  v: 'e', n: ['F3','G3','F3'] },
                      { syl: 'ra',   v: 'a', n: ['F3','A3','C4','F3','A3','C4','C4','B3','G3','F3','A3','G3','A3','G3','G3','F3'] } ]
                ]
            },
            // "Dies irae" — sequence from the Requiem Mass, Mode 1: final D,
            // reciting tone A. Decoded from GregoBase 1198 (Graduale Romanum
            // 1961 p. 96* / LU p. 1810, c4 clef: a=A2 c=C3 d=D3 e=E3 f=F3
            // g=G3 h=A3 i=B3 j=C4). Strophic and syllabic — stanza I ("Dies
            // irae...") and stanza III ("Tuba mirum...", the higher second
            // melodic strain) are encoded, six phrases in all.
            dies: {
                title: 'Dies irae',
                mode: 1, genre: 'sequence (syllabic)',
                phrases: [
                    [ { syl: 'Di',   v: 'i', n: ['F3'] },
                      { syl: 'es',   v: 'e', n: ['E3'] },
                      { syl: 'i',    v: 'i', n: ['F3'] },
                      { syl: 'rae',  v: 'e', n: ['D3'] },
                      { syl: 'di',   v: 'i', n: ['E3'] },
                      { syl: 'es',   v: 'e', n: ['C3'] },
                      { syl: 'il',   v: 'i', n: ['D3'] },
                      { syl: 'la',   v: 'a', n: ['D3'] } ],
                    [ { syl: 'Sol',  v: 'o', n: ['F3'] },
                      { syl: 'vet',  v: 'e', n: ['F3','G3'] },
                      { syl: 'sae',  v: 'e', n: ['F3','E3'] },
                      { syl: 'clum', v: 'u', n: ['D3','C3'] },
                      { syl: 'in',   v: 'i', n: ['E3'] },
                      { syl: 'fa',   v: 'a', n: ['F3'] },
                      { syl: 'víl',  v: 'i', n: ['E3'] },
                      { syl: 'la',   v: 'a', n: ['D3'] } ],
                    [ { syl: 'Te',   v: 'e', n: ['A2'] },
                      { syl: 'ste',  v: 'e', n: ['C3','D3'] },
                      { syl: 'Da',   v: 'a', n: ['D3'] },
                      { syl: 'vid',  v: 'i', n: ['D3','C3'] },
                      { syl: 'cum',  v: 'u', n: ['E3'] },
                      { syl: 'Si',   v: 'i', n: ['F3'] },
                      { syl: 'býl',  v: 'i', n: ['E3'] },
                      { syl: 'la',   v: 'a', n: ['D3'] } ],
                    [ { syl: 'Tu',   v: 'u', n: ['A3'] },
                      { syl: 'ba',   v: 'a', n: ['C4'] },
                      { syl: 'mi',   v: 'i', n: ['C4'] },
                      { syl: 'rum',  v: 'u', n: ['B3','G3','A3'] },
                      { syl: 'spar', v: 'a', n: ['A3','G3','F3'] },
                      { syl: 'gens', v: 'e', n: ['G3'] },
                      { syl: 'so',   v: 'o', n: ['A3'] },
                      { syl: 'num',  v: 'u', n: ['A3','D3'] } ],
                    [ { syl: 'Per',  v: 'e', n: ['F3'] },
                      { syl: 'se',   v: 'e', n: ['E3'] },
                      { syl: 'púl',  v: 'u', n: ['F3'] },
                      { syl: 'cra',  v: 'a', n: ['D3'] },
                      { syl: 're',   v: 'e', n: ['E3'] },
                      { syl: 'gi',   v: 'i', n: ['C3'] },
                      { syl: 'ó',    v: 'o', n: ['D3'] },
                      { syl: 'num',  v: 'u', n: ['D3'] } ],
                    [ { syl: 'Co',   v: 'o', n: ['F3'] },
                      { syl: 'get',  v: 'e', n: ['G3','A3'] },
                      { syl: 'o',    v: 'o', n: ['A3','G3','F3'] },
                      { syl: 'mnes', v: 'e', n: ['E3','D3','C3'] },
                      { syl: 'an',   v: 'a', n: ['E3'] },
                      { syl: 'te',   v: 'e', n: ['F3'] },
                      { syl: 'thro', v: 'o', n: ['E3'] },
                      { syl: 'num',  v: 'u', n: ['D3'] } ]
                ]
            },
            // Kyrie XI "Orbis factor" — Mass Ordinary, Mode 1: final D.
            // Decoded from GregoBase 2982 (Graduale Romanum 1961 p. 38* / LU
            // p. 46, c4 clef; the "ix" flats make the i's B♭3). Melismatic:
            // each invocation carries the great nine-note "e(léison)" melisma
            // F G A B♭ A G F E D. Kyrie — Christe — final expanded Kyrie.
            kyrie: {
                title: 'Kyrie XI (Orbis factor)',
                mode: 1, genre: 'Kyrie (melismatic)',
                phrases: [
                    [ { syl: 'Ky',  v: 'i', n: ['A3','Bb3'] },
                      { syl: 'ri',  v: 'i', n: ['A3','G3'] },
                      { syl: 'e',   v: 'e', n: ['A3','D3'] },
                      { syl: 'e',   v: 'e', n: ['F3','G3','A3','Bb3','A3','G3','F3','E3','D3'] },
                      { syl: 'lé',  v: 'e', n: ['C3'] },
                      { syl: 'i',   v: 'i', n: ['D3'] },
                      { syl: 'son', v: 'o', n: ['D3'] } ],
                    [ { syl: 'Chri', v: 'i', n: ['A3','G3'] },
                      { syl: 'ste',  v: 'e', n: ['D4','C4','D4','C4','A3','G3','A3'] },
                      { syl: 'e',    v: 'e', n: ['F3','G3','A3','Bb3','A3','G3','F3','E3','D3'] },
                      { syl: 'lé',   v: 'e', n: ['C3'] },
                      { syl: 'i',    v: 'i', n: ['D3'] },
                      { syl: 'son',  v: 'o', n: ['D3'] } ],
                    [ { syl: 'Ký',  v: 'i', n: ['D3','F3','D3'] },
                      { syl: 'ri',  v: 'i', n: ['C3','D3'] },
                      { syl: 'e',   v: 'e', n: ['D3','G3','F3','G3','F3','D3','C3','D3'] },
                      { syl: 'e',   v: 'e', n: ['F3','G3','A3','Bb3','A3','G3','F3','E3','D3'] },
                      { syl: 'lé',  v: 'e', n: ['C3'] },
                      { syl: 'i',   v: 'i', n: ['D3'] },
                      { syl: 'son', v: 'o', n: ['D3'] } ]
                ]
            },
            // "Requiem aeternam" — introit of the Mass for the Dead, Mode 6:
            // final F, with the mode's characteristic B♭. Decoded from
            // GregoBase 7978 (Graduale Romanum 1974 p. 669, c4 clef).
            // Neumatic antiphon, then the psalm verse "Te decet hymnus" sung
            // to the Mode 6 INTROIT tone exactly as printed — so this piece
            // demonstrates introit psalmody (antiphon + verse) while the mode
            // buttons' psalm option demonstrates office psalmody.
            requiem: {
                title: 'Requiem aeternam',
                mode: 6, genre: 'introit + psalm verse (neumatic)',
                phrases: [
                    [ { syl: 'Re',   v: 'e', n: ['F3','F3','G3'] },
                      { syl: 'qui',  v: 'i', n: ['F3'] },
                      { syl: 'em',   v: 'e', n: ['F3'] },
                      { syl: 'ae',   v: 'e', n: ['F3','G3','A3'] },
                      { syl: 'tér',  v: 'e', n: ['A3','G3','G3','F3','G3'] },
                      { syl: 'nam',  v: 'a', n: ['G3','F3'] } ],
                    [ { syl: 'do',   v: 'o', n: ['F3','G3','A3'] },
                      { syl: 'na',   v: 'a', n: ['A3','G3'] },
                      { syl: 'e',    v: 'e', n: ['A3'] },
                      { syl: 'is',   v: 'i', n: ['A3','C4','A3','G3','A3','Bb3','A3','G3'] },
                      { syl: 'Dó',   v: 'o', n: ['F3'] },
                      { syl: 'mi',   v: 'i', n: ['F3','G3','A3','G3','F3','G3'] },
                      { syl: 'ne',   v: 'e', n: ['G3','F3'] } ],
                    [ { syl: 'et',   v: 'e', n: ['A3','G3'] },
                      { syl: 'lux',  v: 'u', n: ['A3','G3','F3'] },
                      { syl: 'per',  v: 'e', n: ['A3'] },
                      { syl: 'pé',   v: 'e', n: ['G3','A3'] },
                      { syl: 'tu',   v: 'u', n: ['G3','F3'] },
                      { syl: 'a',    v: 'a', n: ['F3'] } ],
                    [ { syl: 'lú',   v: 'u', n: ['A3','G3'] },
                      { syl: 'ce',   v: 'e', n: ['A3'] },
                      { syl: 'at',   v: 'a', n: ['A3','C4','A3','G3','A3','Bb3','A3','G3'] },
                      { syl: 'e',    v: 'e', n: ['F3','G3','A3','G3','F3','G3'] },
                      { syl: 'is',   v: 'i', n: ['G3','F3'] } ],
                    [ { syl: 'Te',   v: 'e', n: ['F3','G3'] },
                      { syl: 'de',   v: 'e', n: ['G3','F3'] },
                      { syl: 'cet',  v: 'e', n: ['G3','A3'] },
                      { syl: 'hym',  v: 'i', n: ['A3'] },
                      { syl: 'nus',  v: 'u', n: ['G3'] },
                      { syl: 'De',   v: 'e', n: ['Bb3'] },
                      { syl: 'us',   v: 'u', n: ['A3'] },
                      { syl: 'in',   v: 'i', n: ['A3'] },
                      { syl: 'Si',   v: 'i', n: ['G3'] },
                      { syl: 'on',   v: 'o', n: ['F3'] } ],
                    [ { syl: 'et',   v: 'e', n: ['A3'] },
                      { syl: 'ti',   v: 'i', n: ['A3','C4'] },
                      { syl: 'bi',   v: 'i', n: ['G3'] },
                      { syl: 'red',  v: 'e', n: ['F3'] },
                      { syl: 'dé',   v: 'e', n: ['F3'] },
                      { syl: 'tur',  v: 'u', n: ['F3'] },
                      { syl: 'vo',   v: 'o', n: ['F3'] },
                      { syl: 'tum',  v: 'u', n: ['G3'] },
                      { syl: 'in',   v: 'i', n: ['F3','D3'] },
                      { syl: 'Ie',   v: 'e', n: ['F3'] },
                      { syl: 'rú',   v: 'u', n: ['G3'] },
                      { syl: 'sa',   v: 'a', n: ['F3'] },
                      { syl: 'lem',  v: 'e', n: ['F3'] } ]
                ]
            }
        };
