// Klonk film-score performer: the sequencer, a sampler for the orchestra bank, and
// the synthesized layers (sub boom, braam growl, riser), all in the audio thread so
// the ostinato keeps sample-accurate time in a hidden page.
//
// The score is a four-bar phrase in D minor that repeats while you type, written the
// way big action cues are: one theme you can hum, stated by horns and answered by
// strings; a low string ostinato in 3-3-2 under it; braams only where the structure
// changes; a whole-step lift for the last section; and a beat of silence before the hit.
const LEVELS = [0, 6, 14, 24, 34];            // keystrokes in the sentence for each section
const SECTIONS = ['pulse', 'theme', 'answer', 'tutti', 'lift'];
const PROG = [                                // one chord per bar: i - VI - iv - V
    { name: 'Dm', root: 38, pcs: [2, 5, 9] },
    { name: 'Bb', root: 34, pcs: [10, 2, 5] },
    { name: 'Gm', root: 31, pcs: [7, 10, 2] },
    { name: 'A', root: 33, pcs: [9, 1, 4] },
];
// The theme, original to Klonk: a horn call that climbs a fifth and a fourth (D-A-D),
// sighs down over B-flat, answers itself a step higher over G minor, and takes a breath
// on the dominant. Per bar: [sixteenth, length in sixteenths, MIDI note].
const THEME = [
    [[0, 6, 62], [6, 2, 69], [8, 6, 74], [14, 2, 72]],
    [[0, 4, 70], [4, 4, 69], [8, 8, 65]],
    [[0, 6, 67], [6, 2, 70], [8, 6, 74], [14, 2, 76]],
    [[0, 8, 73], [8, 4, 69]],
];
const OSTINATO = [0, 0, 1, 0, 2, 0, 1, 0, 0, 0, 1, 0, 2, 1, 0, 1];   // chord-tone index per sixteenth
const ACCENT = new Set([0, 3, 6, 8, 11, 14]);                       // the 3-3-2 film-score pulse
const SWELL = [0.82, 0.9, 0.96, 1.06];                              // dynamics across the phrase
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const noise = () => Math.random() * 2 - 1;
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);

function voicing(pcs, lo, count) {
    const out = [];
    for (let m = lo; out.length < count && m < lo + 36; m++) if (pcs.includes(((m % 12) + 12) % 12)) out.push(m);
    return out;
}
const major = (root) => [root % 12, (root + 4) % 12, (root + 7) % 12];
const minor = (root) => [root % 12, (root + 3) % 12, (root + 7) % 12];

class SVF {
    constructor() { this.ic1 = 0; this.ic2 = 0; this.set(1000, 0.7); }
    set(fc, q) {
        const g = Math.tan(Math.PI * clamp(fc, 20, sampleRate * 0.45) / sampleRate), k = 1 / q;
        this.k = k; this.a1 = 1 / (1 + g * (g + k)); this.a2 = g * this.a1; this.a3 = g * this.a2;
    }
    run(x) {
        const v3 = x - this.ic2, v1 = this.a1 * this.ic1 + this.a2 * v3, v2 = this.ic2 + this.a2 * this.ic1 + this.a3 * v3;
        this.ic1 = 2 * v1 - this.ic1; this.ic2 = 2 * v2 - this.ic2;
        this.low = v2; this.band = v1;
        return this;
    }
}

class Sample {                                 // one bank note, repitched, with a late start and a soft attack
    constructor(data, rate, gain, seconds, wait, attack) {
        this.d = data; this.pos = 0; this.rate = rate; this.gain = gain; this.wait = wait | 0;
        this.end = seconds ? Math.min(data.length - 2, seconds * sampleRate * rate) : data.length - 2;
        this.fade = 0.06 * sampleRate * rate; this.attack = (attack || 0) * sampleRate * rate;
    }
    tick() {
        if (this.wait > 0) { this.wait--; return 0; }
        const p = this.pos, i = p | 0, f = p - i, d = this.d;
        if (i >= this.end) { this.pos = Infinity; return 0; }
        const tail = this.end - p, env = (tail < this.fade ? tail / this.fade : 1) * (p < this.attack ? p / this.attack : 1);
        this.pos += this.rate;
        return (d[i] + (d[i + 1] - d[i]) * f) * this.gain * env;
    }
    choke() { this.wait = 0; this.fade = 0.03 * sampleRate * this.rate; this.end = Math.min(this.end, this.pos + this.fade); }
    get done() { return this.pos >= this.end; }
}
class Sub {                                    // the trailer boom: a sine dropping into the floor
    constructor(gain) { this.t = 0; this.ph = 0; this.gain = gain; }
    tick(dt) {
        const t = this.t; this.t += dt;
        this.ph += 2 * Math.PI * (30 + 45 * Math.exp(-t / 0.18)) * dt;
        return Math.sin(this.ph) * Math.exp(-t / 1.1) * this.gain;
    }
    choke() { this.t = 4; }
    get done() { return this.t > 4; }
}
class Growl {                                  // the braam's synthetic edge: detuned saws, closing filter, drive
    constructor(f, gain, seconds) { this.t = 0; this.a = 0; this.b = 0; this.f = f; this.gain = gain; this.len = seconds; this.svf = new SVF(); }
    tick(dt) {
        const t = this.t; this.t += dt;
        this.a = (this.a + this.f * dt) % 1; this.b = (this.b + this.f * 1.007 * dt) % 1;
        if (((t * sampleRate) | 0) % 64 === 0) this.svf.set(220 + 2600 * Math.exp(-t / 0.35), 1.2);
        const env = Math.min(1, t / 0.04) * (t < this.len ? 1 : Math.max(0, 1 - (t - this.len) / 0.5));
        return Math.tanh(this.svf.run((this.a + this.b - 1) * 1.6).low * 2) * env * this.gain;
    }
    choke() { this.t = this.len + 0.5; }
    get done() { return this.t > this.len + 0.5; }
}

class Cinematic extends AudioWorkletProcessor {
    constructor() {
        super();
        this.dt = 1 / sampleRate; this.bank = null; this.roots = {};
        this.voices = []; this.running = false; this.bpm = 120; this.target = 120;
        this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true;
        this.keys = 0; this.ioi = 0.3; this.lastKeyMs = 0; this.lastKeyAt = 0; this.now = 0;
        this.idleBars = 0; this.gapBars = 0; this.gapPending = false;
        this.held = false; this.expr = 1; this.volume = 0.7; this.energy = 0;
        this.shift = 0; this.braamedAt = 0; this.barI = 0; this.themeAt = -1; this.pending = []; this.ending = null;
        this.riser = new SVF(); this.riserGain = 0; this.riserTime = 0;
        this.port.onmessage = (e) => this.message(e.data);
    }
    get intensity() { let i = 0; for (let k = 0; k < LEVELS.length; k++) if (this.keys >= LEVELS[k]) i = k; return i; }
    // The pulse is an intro on a D minor pedal; the four-bar phrase counts from the bar the
    // theme enters, so the theme is always heard from its first note.
    get phraseBar() { return this.themeAt < 0 ? 0 : (this.bar - this.themeAt) % 4; }
    get chord() { return PROG[this.phraseBar]; }
    // Players are a little late and a little uneven: up to 9 ms and +-12% for the orchestra,
    // up to 3 ms for drums. A machine-perfect grid is what makes a score sound generated.
    play(section, m, gain, seconds, opts) {
        const roots = this.roots[section];
        if (!roots || !roots.length) return;
        const root = roots.reduce((a, b) => Math.abs(b - m) < Math.abs(a - m) ? b : a);
        const drum = section === 'taiko' || section === 'toms' || section === 'kit' || section === 'timp';
        const wait = (opts && opts.exact) ? 0 : Math.random() * (drum ? 0.003 : 0.009) * sampleRate;
        const human = (opts && opts.exact) ? 1 : 0.88 + 0.24 * Math.random();
        this.voices.push(new Sample(this.bank[section][root], Math.pow(2, (m - root) / 12), gain * human, seconds, wait, opts && opts.attack));
        if (this.onPlay) this.onPlay(section, m, gain, seconds);
    }
    message(m) {
        if (m.type === 'bank') {
            this.bank = m.bank;
            for (const s of Object.keys(m.bank)) this.roots[s] = Object.keys(m.bank[s]).map(Number);
            const crash = m.bank.kit && m.bank.kit[49];
            if (crash) { this.bank.whoosh = { 49: Float32Array.from(crash).reverse() }; this.roots.whoosh = [49]; }
            this.port.postMessage({ type: 'loaded', sections: Object.keys(this.bank).length });
        } else if (m.type === 'key') {
            const dt = (m.ms - this.lastKeyMs) / 1000;
            if (this.lastKeyMs && dt < 2.5) this.ioi = this.ioi * 0.75 + clamp(dt, 0.08, 0.8) * 0.25;
            this.lastKeyMs = m.ms; this.lastKeyAt = this.now; this.idleBars = 0;
            this.target = clamp(138 - this.ioi * 60, 112, 132);
            this.keys++;
            if (!this.running && !this.ending) {
                this.running = true; this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true;
                this.shift = 0; this.braamedAt = 0; this.themeAt = -1; this.barI = 0; this.bpm = this.target;
            }
        } else if (m.type === 'hit') this.end(true);
        else if (m.type === 'end') this.end(false);
        else if (m.type === 'gap') { this.gapPending = true; this.lastKeyAt = this.now; }
        else if (m.type === 'whoosh') { this.play('whoosh', 49, 0.7, 0, { exact: true }); this.lastKeyAt = this.now; }
        else if (m.type === 'held') this.held = m.on;
        else if (m.type === 'volume') this.volume = m.v;
        else if (m.type === 'stop') { this.running = false; this.voices = []; this.pending = []; this.ending = null; this.keys = 0; this.riserGain = 0; }
        else if (m.type === 'status') {
            this.port.postMessage({ type: 'status', running: this.running, bpm: +this.bpm.toFixed(1), intensity: this.intensity,
                section: SECTIONS[this.barI], keys: this.keys, bar: this.bar, chord: this.chord.name, lift: this.shift,
                gap: this.gapBars > 0, voices: this.voices.length, ending: this.ending,
                levelDb: +(10 * Math.log10(this.energy + 1e-12)).toFixed(1), loaded: !!this.bank });
        }
    }
    // The ending. Everything stops dead, a beat of silence, then the hit. Return gives the
    // full trailer cadence, B-flat, C, D major (bVI - bVII - I, short-short-long) after a
    // real build, or one tonic hit after a short one; a period gives one D minor hit.
    end(full) {
        const beat = 60 / this.bpm, size = 0.6 + 0.4 * (this.intensity / 4), t = this.shift;
        for (const v of this.voices) v.choke();
        this.running = false; this.keys = 0; this.riserGain = 0; this.riserTime = 0; this.gapPending = false;
        this.pending = [];
        const at = (beats, fn) => this.pending.push({ at: this.now + beats * beat, fn });
        if (full && size >= 0.8) {
            at(1, () => this.chordHit(34 + t, major, size * 0.85, beat, false));
            at(1.5, () => this.chordHit(36 + t, major, size * 0.85, 0.5 * beat, false));
            at(2, () => this.chordHit(38 + t, major, size, 2.6, true));
            this.ending = 'cadence';
        } else {
            at(full ? 1 : 0.5, () => this.chordHit(38 + t, full ? major : minor, size, 2.4, true));
            this.ending = full ? 'hit' : 'end';
        }
    }
    chordHit(root, quality, size, seconds, last) {
        const pcs = quality(root);
        for (const m of [root, root + 7, root + 12]) this.play('brass', m, 0.7 * size, seconds);
        for (const m of voicing(pcs, 60, 3)) this.play('horns', m, 0.5 * size, seconds);
        for (const m of voicing(pcs, 67, 4)) this.play('strings', m, 0.32 * size, seconds + 0.4);
        this.play('timp', root + 12, 0.8 * size);
        this.play('taiko', 36, 0.9 * size); this.play('kit', 36, 0.8 * size);
        if (!last) return;
        for (const m of voicing(pcs, 62, 4)) this.play('choir', m, 0.42 * size, seconds + 0.4);
        this.play('taiko', 43, 0.7 * size); this.play('kit', 49, 0.7 * size); this.play('kit', 57, 0.45 * size);
        this.voices.push(new Sub(0.95 * size), new Growl(hz(root), 0.32 * size, 1.4));
    }
    braam(c) {                                 // only where the structure changes
        for (const m of [c.root, c.root + 7, c.root + 12].map((x) => x + this.shift)) this.play('brass', m, 0.6, 2.2);
        this.voices.push(new Growl(hz(c.root + 12 + this.shift), 0.2, 1.8));
        this.play('timp', 38 + this.shift, 0.7);
    }
    barLine() {
        this.bar++;
        this.bpm += (this.target - this.bpm) * 0.5;
        this.gapBars = this.gapPending ? 1 : 0; this.gapPending = false;
        const quietBars = (this.now - this.lastKeyAt) * this.bpm / 240;
        if (quietBars >= 1) {
            this.idleBars++;
            this.keys = Math.min(this.keys, LEVELS[Math.max(0, this.intensity - 1)]);
            if (this.idleBars >= 4) this.running = false;
        }
    }
    theme(section, pb, s, octave, gain) {
        for (const [at, len, m] of THEME[pb]) if (at === s) {
            const sixteenth = 15 / this.bpm;
            this.play(section, m + octave + this.shift, gain * SWELL[pb], len * sixteenth * 1.05, { attack: section === 'strings' ? 0.05 : 0.02 });
        }
    }
    trigger(s) {
        if (s === 0) { if (this.fresh) this.fresh = false; else this.barLine(); }
        if (s === 0 && this.running) {         // sections change on half-phrases, one at a time, as a cue is laid out
            const want = this.intensity;
            if (want < this.barI) this.barI = want;
            else if (want > this.barI && (this.barI === 0 || (this.bar - this.themeAt) % 2 === 0)) this.barI++;
            if (this.barI >= 1 && this.themeAt < 0) this.themeAt = this.bar;
        }
        if (!this.running || this.gapBars > 0) return;
        const I = this.barI, pb = this.phraseBar, acc = ACCENT.has(s), sw = SWELL[pb];
        const heard = this.themeAt >= 0 && this.bar - this.themeAt >= 4;                 // the whole theme, once, in D minor
        if (s === 0 && pb === 0 && I === 4 && heard && this.shift === 0) this.shift = 2;  // the lift lands on a phrase
        const c = PROG[pb], sh = this.shift, lifting = I === 4 && this.shift === 0;
        if (s === 0 && ((I >= 2 && this.braamedAt < 2) || (sh && this.braamedAt < 4))) { this.braam(c); this.braamedAt = sh ? 4 : 2; }
        const breath = pb === 3 && s >= 14 && I < 3;                                      // the phrase breathes
        const low = c.root + 12 + sh;
        if (!breath) this.play('cello', s % 4 === 0 ? low : low - 12 >= 33 ? low - 12 : low, (acc ? 0.46 : 0.24) * sw, 0.13);
        if (s === 0) this.play('timp', 38 + sh + (pb === 3 ? 7 : 0), (I >= 3 ? 0.6 : 0.4) * sw);
        if (I >= 1 && !breath) {
            const tones = voicing(c.pcs.map((p) => (p + sh) % 12), 62, 3), m = tones[OSTINATO[s]];
            this.play('viola', m, (acc ? 0.34 : 0.18) * sw, 0.16);
            if (acc && I >= 2) this.play('pizz', m, 0.14, 0.25);
        }
        if (I >= 1) {                                                                     // the theme: call and answer
            const horns = I === 2 ? pb < 2 : true, strings = I >= 3 || (I === 2 && pb >= 2);
            if (horns) this.theme('horns', pb, s, 0, I >= 3 ? 0.6 : 0.5);
            if (strings) this.theme('strings', pb, s, 12, I >= 3 ? 0.3 : 0.36);
        }
        if (I >= 2 && acc) this.play('taiko', s % 8 === 0 ? 36 : 43, (s === 0 ? 0.55 : 0.36) * sw);
        if (I >= 3) {
            if (s === 0) for (const m of voicing(c.pcs.map((p) => (p + sh) % 12), 62, 3)) this.play('choir', m, 0.24 * sw, 240 / this.bpm, { attack: 0.15 });
            if (s === 4 || s === 12) this.play('kit', 38, 0.26 * sw, 0.3);
            if (s === 0) for (const m of [c.root + sh, c.root + 7 + sh]) this.play('brass', m, 0.22, 240 / this.bpm, { attack: 0.08 });
            if (pb === 3 && s >= 12 && !lifting) this.play('toms', [58, 53, 48, 43][s - 12], 0.45);
        }
        if (lifting) this.play('kit', 38, 0.1 + 0.3 * ((pb * 16 + s) / 63), 0.2);       // the roll into the lift
    }
    process(inputs, outputs) {
        const out = outputs[0], L = out[0], R = out[1] || out[0];
        if (!this.bank) { L.fill(0); if (R !== L) R.fill(0); return true; }
        const rising = this.running && this.gapBars === 0 && this.barI === 4 && this.shift === 0;
        this.riserTime = rising ? this.riserTime + L.length / sampleRate : 0;
        const bar = 240 / this.bpm, sweep = Math.min(1, this.riserTime / (2 * bar));
        this.riserGain += ((rising ? 0.08 * sweep : 0) - this.riserGain) * 0.02;
        this.riser.set(300 * Math.pow(15, sweep), 0.7);
        const exprTarget = this.held ? 1.25 : 1;
        for (let i = 0; i < L.length; i++) {
            this.now += this.dt;
            if (this.pending.length && this.now >= this.pending[0].at) {
                this.pending.shift().fn();
                if (!this.pending.length) this.ending = null;
            }
            if (this.running) {
                this.toStep -= 1;
                if (this.toStep <= 0) { this.trigger(this.step); this.step = (this.step + 1) % 16; this.toStep += sampleRate * 60 / this.bpm / 4; }
            }
            this.expr += (exprTarget - this.expr) * 0.0002;
            let mix = 0;
            for (let v = this.voices.length - 1; v >= 0; v--) { const x = this.voices[v]; mix += x.tick(this.dt); if (x.done) this.voices.splice(v, 1); }
            if (this.riserGain > 0.001) mix += this.riser.run(noise()).low * this.riserGain;
            const pre = Math.tanh(mix * 0.8 * this.expr);
            this.energy = this.energy * 0.9995 + pre * pre * 0.0005;
            const y = pre * this.volume;
            L[i] = y; R[i] = y;
        }
        return true;
    }
}
registerProcessor('klonk-cinematic', Cinematic);
