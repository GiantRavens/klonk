# Performer credits

Assembled by `tools/build_performer.py` from a pinned commit.

- **Synth_Gregorian** by Brendan James Lynskey —
  <https://github.com/BrendanJamesLynskey/Synth_Gregorian>, commit
  `5a46c905b19738683d419c89360ea186f38d85d3`, MIT license (as stated in its README).
  `vocal-voices.js` is copied verbatim; `chants.js` is its chant repertoire, extracted
  verbatim from `gregorian-engine.js`. The chants were encoded by the author from the
  Solesmes books (Graduale Romanum, Liber Usualis) via GregoBase transcriptions.
- **VocalSet** — Julia Wilkins, Prem Seetharaman, Alison Wahl, Bryan Pardo,
  "VocalSet: A Singing Voice Dataset," ISMIR 2018, <https://zenodo.org/records/1193957>,
  CC BY 4.0. `voices.js` packs the male vowel loops as prepared by Synth_Gregorian.
- `gregorian.js` (the typing-to-phrase chant engine and abbey reverb) and `techno.js` (the build-up groovebox, synthesized in an AudioWorklet) are Klonk's own, MIT.
