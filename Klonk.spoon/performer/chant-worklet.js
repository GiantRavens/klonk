// Klonk war-chant performer: a synthesized throat-singing choir in the audio thread.
//
// The growl is kargyraa-style period doubling: every other glottal pulse is weaker
// and slightly late, which puts a subharmonic an octave below the sung pitch. Each
// voice is a pulse source through three male-bass formant filters (a, o, u); the
// choir is several such voices, detuned and jittered. Drums, metal hits and the sub
// boom are synthesized too. Timing counts samples, because hidden pages throttle timers.
const LEVELS = [0, 5, 12, 20, 30];            // keystrokes in the sentence for each layer
const VOWELS = {                              // male bass formants (Hz) for a growled chant
    a: [[600, 90], [1040, 110], [2250, 140]],
    o: [[400, 80], [750, 90], [2400, 140]],
    u: [[340, 70], [620, 80], [2300, 140]],
};
const SYLLABLES = ['a', 'o', 'a', 'u'];       // HA - O - HA - OM
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const noise = () => Math.random() * 2 - 1;
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);

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

class Singer {                                 // one growling voice; the gate is shaped by the choir
    constructor(midi, cents, growl) {
        this.f0 = hz(midi) * Math.pow(2, cents / 1200); this.growl = growl;
        this.ph = 0; this.odd = false; this.jit = 1; this.drift = Math.random() * 6.28;
        this.formants = [new SVF(), new SVF(), new SVF()]; this.cur = VOWELS.o.map((f) => f.slice()); this.target = VOWELS.o;
        this.tilt = new SVF(); this.tilt.set(1400, 0.6); this.tick = 0;
    }
    vowel(v) { this.target = VOWELS[v] || VOWELS.o; }
    sample(dt, t) {
        const vib = 1 + 0.004 * Math.sin(this.drift + t * 2 * Math.PI * 4.7);
        this.ph += this.f0 * vib * this.jit * dt;
        if (this.ph >= 1) {                                       // a new glottal period
            this.ph -= 1; this.odd = !this.odd;
            this.jit = 1 + (Math.random() - 0.5) * 0.012;           // roughness
        }
        const open = this.ph < 0.55 ? Math.sin(Math.PI * this.ph / 0.55) : 0;
        const pulse = open * open * (this.odd ? 1 - 0.5 * this.growl : 1) + noise() * 0.035;   // period doubling
        const src = this.tilt.run(pulse - 0.3).low;
        if ((this.tick++ & 63) === 0) {                            // glide formants toward the vowel
            for (let k = 0; k < 3; k++) {
                this.cur[k][0] += (this.target[k][0] - this.cur[k][0]) * 0.25;
                this.formants[k].set(this.cur[k][0], this.cur[k][0] / this.cur[k][1]);
            }
        }
        return this.formants[0].run(src).band * 1.0 + this.formants[1].run(src).band * 0.55 + this.formants[2].run(src).band * 0.22;
    }
}

class Section {                                // a choir section: voices plus one shared gate
    constructor(midis, growl) {
        this.voices = []; midis.forEach((m) => [-7, 3, 9].forEach((c) => this.voices.push(new Singer(m, c + (Math.random() - 0.5) * 4, growl))));
        this.gate = 0; this.target = 0; this.rate = 0.002;
    }
    sing(v, level) { this.voices.forEach((s) => s.vowel(v)); this.target = level; this.rate = 0.004; }
    release(seconds) { this.target = 0; this.rate = 1 / Math.max(1, seconds * sampleRate) * 5; }
    sample(dt, t) {
        this.gate += (this.target - this.gate) * this.rate;
        if (this.gate < 1e-4 && this.target === 0) return 0;
        let s = 0; for (const v of this.voices) s += v.sample(dt, t);
        return s * this.gate / this.voices.length;
    }
}

class Drum {                                   // war drum: a big low skin with a pitch drop
    constructor(vel, low) { this.t = 0; this.ph = 0; this.vel = vel; this.f = low ? 52 : 74; this.f2 = new SVF(); this.f2.set(900, 0.8); }
    tick(dt) {
        const t = this.t; this.t += dt;
        this.ph += 2 * Math.PI * (this.f + 40 * Math.exp(-t / 0.04)) * dt;
        return this.vel * (Math.sin(this.ph) * Math.exp(-t / 0.42) + this.f2.run(noise()).low * Math.exp(-t / 0.03) * 0.8);
    }
    get done() { return this.t > 1.6; }
}
class Metal {                                  // anvil and gong: inharmonic partials that ring
    constructor(vel, big) { this.t = 0; this.vel = vel; this.p = (big ? [83, 131, 197, 263, 351] : [523, 829, 1187, 1601]).map((f) => [f, Math.random() * 6]); this.len = big ? 3.2 : 1.1; }
    tick(dt) {
        const t = this.t; this.t += dt;
        let s = 0; for (const [f, ph] of this.p) s += Math.sin(2 * Math.PI * f * t + ph);
        return this.vel * s / this.p.length * Math.exp(-t / (this.len / 3)) * Math.min(1, t / 0.002);
    }
    get done() { return this.t > this.len; }
}
class Sub {
    constructor(gain) { this.t = 0; this.ph = 0; this.gain = gain; }
    tick(dt) { const t = this.t; this.t += dt; this.ph += 2 * Math.PI * (32 + 40 * Math.exp(-t / 0.2)) * dt; return Math.sin(this.ph) * Math.exp(-t / 1.0) * this.gain; }
    get done() { return this.t > 3.5; }
}
class Breath {                                 // the H of HA
    constructor(vel) { this.t = 0; this.vel = vel; this.f = new SVF(); this.f.set(1500, 0.8); }
    tick(dt) { const t = this.t; this.t += dt; return this.vel * this.f.run(noise()).band * Math.sin(Math.PI * clamp(t / 0.07, 0, 1)); }
    get done() { return this.t > 0.07; }
}

class WarChant extends AudioWorkletProcessor {
    constructor() {
        super();
        this.dt = 1 / sampleRate; this.now = 0;
        this.low = new Section([38], 0.85);            // D2 chanters, growling an octave below
        this.answer = new Section([45, 50], 0.35);     // A2 and D3 answer the call
        this.drone = new Section([26], 1.0);           // the undertone bed
        this.hits = [];
        this.running = false; this.bpm = 84; this.target = 84; this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true;
        this.keys = 0; this.syl = 0; this.ioi = 0.35; this.lastKeyMs = 0; this.lastKeyAt = 0;
        this.idleBars = 0; this.pending = []; this.held = false; this.volume = 0.7; this.energy = 0; this.breathUntil = 0;
        this.port.onmessage = (e) => this.message(e.data);
    }
    get intensity() { let i = 0; for (let k = 0; k < LEVELS.length; k++) if (this.keys >= LEVELS[k]) i = k; return i; }
    stepSamples() { return sampleRate * 60 / this.bpm / 4; }
    message(m) {
        if (m.type === 'key') {
            const dt = (m.ms - this.lastKeyMs) / 1000;
            if (this.lastKeyMs && dt < 2.5) this.ioi = this.ioi * 0.75 + clamp(dt, 0.08, 0.9) * 0.25;
            this.lastKeyMs = m.ms; this.lastKeyAt = this.now; this.idleBars = 0;
            this.target = clamp(104 - this.ioi * 60, 66, 100);
            this.keys++;
            if (!this.running) {
                this.running = true; this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true; this.bpm = this.target;
                this.drone.sing('u', 0.35);
            }
            this.pending.push('syllable');                     // sung on the next sixteenth: the ritual's grid
        } else if (m.type === 'shout') this.shout();
        else if (m.type === 'breath') { this.breathUntil = this.now + 60 / this.bpm; this.low.release(0.08); this.answer.release(0.08); }
        else if (m.type === 'growl') { this.drone.sing('a', 0.8); this.lastKeyAt = this.now; }
        else if (m.type === 'held') { this.held = m.on; if (!m.on) this.releaseSyllable(); }
        else if (m.type === 'volume') this.volume = m.v;
        else if (m.type === 'stop') this.halt(0.2);
        else if (m.type === 'status') {
            this.port.postMessage({ type: 'status', running: this.running, bpm: +this.bpm.toFixed(1), intensity: this.intensity,
                keys: this.keys, bar: this.bar, syllable: SYLLABLES[this.syl % SYLLABLES.length], hits: this.hits.length,
                levelDb: +(10 * Math.log10(this.energy + 1e-12)).toFixed(1) });
        }
    }
    releaseSyllable() {
        const r = clamp(this.ioi * 1.2, 0.15, 0.9);
        this.low.release(r); this.answer.release(r * 1.2);
    }
    syllable() {
        if (this.now < this.breathUntil) return;
        const v = SYLLABLES[this.syl++ % SYLLABLES.length], I = this.intensity;
        if (v === 'a') this.hits.push(new Breath(0.25 + 0.05 * I));
        this.low.sing(v, 0.55 + 0.1 * I);
        if (I >= 2) this.answerAt = this.now + 60 / this.bpm / 2, this.answerVowel = v;   // the answer, an eighth later
        if (!this.held) this.releaseAfter = this.now + Math.max(0.16, this.ioi * 0.6);
        this.drone.sing(I >= 4 ? 'a' : 'u', 0.3 + 0.06 * I);
    }
    shout() {                                              // HA!
        const size = 0.6 + 0.4 * (this.intensity / 4);
        this.hits.push(new Breath(0.6 * size), new Drum(1.0 * size, true), new Drum(0.7 * size, false),
            new Metal(0.5 * size, true), new Sub(0.9 * size));
        this.low.sing('a', 1.0 * size); this.answer.sing('a', 0.8 * size); this.drone.sing('a', 0.6 * size);
        this.releaseAfter = this.now + 0.55; this.answerAt = 0;
        this.running = false; this.keys = 0; this.pending = [];
        this.droneOffAt = this.now + 0.55;
    }
    halt(seconds) { this.running = false; this.keys = 0; this.pending = []; this.low.release(seconds); this.answer.release(seconds); this.drone.release(seconds); }
    barLine() {
        this.bar++;
        this.bpm += (this.target - this.bpm) * 0.5;
        const quietBars = (this.now - this.lastKeyAt) * this.bpm / 240;
        if (quietBars >= 1) {
            this.idleBars++;
            this.keys = Math.min(this.keys, LEVELS[Math.max(0, this.intensity - 1)]);
            if (this.idleBars >= 4) this.halt(2.5);
        }
    }
    trigger(s) {
        if (s === 0) { if (this.fresh) this.fresh = false; else this.barLine(); }
        if (!this.running) return;
        while (this.pending.length) { this.pending.shift(); this.syllable(); }
        const I = this.intensity;
        if (I >= 1 && (s === 0 || s === 8)) this.hits.push(new Drum(0.75, true));
        if (I >= 3 && s === 0 && this.bar % 2 === 0) this.hits.push(new Metal(0.3, this.bar % 4 === 0));
        if (I >= 3 && (s === 4 || s === 12)) this.hits.push(new Drum(0.5, false));
        if (I >= 4 && s % 2 === 0 && s % 8 !== 0) this.hits.push(new Drum(0.32 + s * 0.01, s % 4 === 2));
    }
    process(inputs, outputs) {
        const out = outputs[0], L = out[0], R = out[1] || out[0];
        for (let i = 0; i < L.length; i++) {
            this.now += this.dt;
            if (this.running) {
                this.toStep -= 1;
                if (this.toStep <= 0) { this.trigger(this.step); this.step = (this.step + 1) % 16; this.toStep += this.stepSamples(); }
            }
            if (this.releaseAfter && this.now >= this.releaseAfter) { this.releaseAfter = 0; this.releaseSyllable(); }
            if (this.answerAt && this.now >= this.answerAt) { this.answerAt = 0; this.answer.sing(this.answerVowel, 0.45); if (!this.held) this.answerOffAt = this.now + 0.25; }
            if (this.answerOffAt && this.now >= this.answerOffAt) { this.answerOffAt = 0; this.answer.release(0.3); }
            if (this.droneOffAt && this.now >= this.droneOffAt) { this.droneOffAt = 0; this.low.release(1.4); this.answer.release(1.4); this.drone.release(2.0); }
            let mix = this.low.sample(this.dt, this.now) * 1.3 + this.answer.sample(this.dt, this.now) + this.drone.sample(this.dt, this.now) * 0.9;
            for (let h = this.hits.length - 1; h >= 0; h--) { const x = this.hits[h]; mix += x.tick(this.dt); if (x.done) this.hits.splice(h, 1); }
            const pre = Math.tanh(mix * 1.1);
            this.energy = this.energy * 0.9995 + pre * pre * 0.0005;
            const y = pre * this.volume;
            L[i] = y; R[i] = y;
        }
        return true;
    }
}
registerProcessor('klonk-war-chant', WarChant);
