// Klonk khoomei performer: Mongolian throat singing, synthesized in the audio thread.
//
// Sygyt, the whistled overtone melody: one bright glottal source drives both a soft
// vowel body (the drone you hear as the sung note) and a very narrow resonance
// parked on a single harmonic of that drone. Moving the resonance from harmonic to
// harmonic plays a melody while the fundamental never changes: one voice, two lines.
// With the drone on C3, harmonics 6 8 9 10 12 (and 13 15 16 at full strength) give
// a pentatonic scale. Kargyraa (period doubling, an octave below) is the deep layer;
// a morin khuur bows a fifth drone; hooves gallop. No samples.
const F0 = 130.81;                                     // C3: the drone the whole song rests on
const MELODY = [8, 9, 10, 9, 8, 6, 8, 9, 10, 12, 10, 9, 8, 9, 6, 8];   // harmonic numbers
const HIGH = [12, 13, 12, 10, 12, 15, 16, 15, 12, 10];               // the soaring line at full strength
const LEVELS = [0, 6, 14, 22, 30];
const WHISTLE_GAIN = 220;                             // measured: the whistle sits about 1.1x the fundamental, neighbours ~100x down
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const noise = () => Math.random() * 2 - 1;

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

class Throat {                                          // one singer: drone body plus the sygyt whistle
    constructor() {
        this.ph = 0; this.jit = 1; this.t = 0; this.f0 = F0;
        this.body = [[400, 80, 1.0], [800, 100, 0.35], [2500, 160, 0.08]].map(([f, bw, g]) => { const s = new SVF(); s.set(f, f / bw); return [s, g]; });
        this.chest = new SVF(); this.chest.set(240, 0.8);                       // the drone's floor: the sung pitch itself
        this.whistle = new SVF(); this.whistle2 = new SVF();
        this.harm = 8; this.fc = F0 * 8; this.target = F0 * 8; this.tick = 0;
        this.drone = 0; this.droneTarget = 0; this.wg = 0; this.wgTarget = 0;
    }
    sample(dt) {
        this.t += dt;
        const vib = 1 + 0.0025 * Math.sin(this.t * 2 * Math.PI * 5.1);
        this.ph += this.f0 * vib * this.jit * dt;
        if (this.ph >= 1) { this.ph -= 1; this.jit = 1 + (Math.random() - 0.5) * 0.004; }
        const open = this.ph < 0.38 ? Math.sin(Math.PI * this.ph / 0.38) : 0;   // a pressed, bright source
        const src = open * open * open - 0.2 + noise() * 0.01;
        if ((this.tick++ & 15) === 0) {                                          // the whistle glides between harmonics
            this.fc += (this.target - this.fc) * 0.06;
            this.whistle.set(this.fc, 55); this.whistle2.set(this.fc, 55);
        }
        this.drone += (this.droneTarget - this.drone) * 0.0015;
        this.wg += (this.wgTarget - this.wg) * 0.002;
        let body = this.chest.run(src).low * 2.4; for (const [s, g] of this.body) body += s.run(src).band * g;
        // Two narrow stages (Q 55), each normalized to unity gain at its centre: a pure, piercing tone.
        const w = this.whistle2.run(this.whistle.run(src).band / 55).band / 55;
        return (body * 0.9 * this.drone + w * WHISTLE_GAIN * this.wg) * (this.drone > 0.001 || this.wg > 0.001 ? 1 : 0);
    }
}

class Growl {                                           // kargyraa: period doubling an octave below the drone
    constructor() { this.ph = 0; this.odd = false; this.g = 0; this.target = 0; this.f = [new SVF(), new SVF()]; this.f[0].set(380, 4); this.f[1].set(720, 6); }
    sample(dt) {
        this.g += (this.target - this.g) * 0.001;
        if (this.g < 1e-4 && this.target === 0) return 0;
        this.ph += F0 * dt; if (this.ph >= 1) { this.ph -= 1; this.odd = !this.odd; }
        const open = this.ph < 0.55 ? Math.sin(Math.PI * this.ph / 0.55) : 0;
        const src = open * open * (this.odd ? 0.45 : 1) - 0.3;
        return (this.f[0].run(src).band + this.f[1].run(src).band * 0.5) * this.g;
    }
}

class Khuur {                                           // morin khuur: two bowed strings a fifth apart
    constructor() { this.f0 = F0; this.a = 0; this.b = 0; this.g = 0; this.target = 0; this.body = new SVF(); this.body.set(700, 1.2); this.bow = new SVF(); this.bow.set(2500, 0.8); this.t = 0; }
    sample(dt) {
        this.g += (this.target - this.g) * 0.0008;
        if (this.g < 1e-4 && this.target === 0) return 0;
        this.t += dt;
        const wob = 1 + 0.003 * Math.sin(this.t * 2 * Math.PI * 4.3);
        this.a = (this.a + this.f0 / 2 * wob * dt) % 1; this.b = (this.b + this.f0 * 0.75 * wob * dt) % 1;
        const saw = (this.a * 2 - 1) + (this.b * 2 - 1) * 0.7;
        return (this.body.run(saw).band + this.bow.run(noise()).band * 0.06) * this.g;
    }
}

class Take {                                            // a slice of a real recording
    constructor(data, gain) { this.d = data; this.pos = 0; this.gain = gain; this.rel = 0; this.relStep = 0; }
    release(seconds) { this.relStep = 1 / Math.max(1, seconds * sampleRate); }
    tick() {
        if (this.pos >= this.d.length - 1) { this.pos = Infinity; return 0; }
        if (this.relStep) { this.rel += this.relStep; if (this.rel >= 1) { this.pos = Infinity; return 0; } }
        return this.d[this.pos++] * this.gain * (1 - this.rel);
    }
    get left() { return (this.d.length - this.pos) / sampleRate; }
    get done() { return this.pos >= this.d.length - 1; }
}

class Hoof {                                            // a hoof on hard steppe: a knock and a low thud
    constructor(vel) { this.t = 0; this.ph = 0; this.vel = vel; this.f = new SVF(); this.f.set(1100 + Math.random() * 400, 3); }
    tick(dt) {
        const t = this.t; this.t += dt; this.ph += 2 * Math.PI * (95 * Math.exp(-t / 0.05) + 55) * dt;
        return this.vel * (this.f.run(noise()).band * 1.4 * Math.exp(-t / 0.012) + Math.sin(this.ph) * 0.6 * Math.exp(-t / 0.07));
    }
    get done() { return this.t > 0.35; }
}

class Khoomei extends AudioWorkletProcessor {
    constructor() {
        super();
        this.dt = 1 / sampleRate; this.now = 0;
        this.throat = new Throat(); this.growl = new Growl(); this.khuur = new Khuur(); this.hooves = [];
        this.running = false; this.bpm = 92; this.target = 92; this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true;
        this.keys = 0; this.note = 0; this.ioi = 0.35; this.lastKeyMs = 0; this.lastKeyAt = 0; this.idleBars = 0;
        this.held = false; this.volume = 0.7; this.energy = 0; this.releaseAt = 0; this.breathUntil = 0; this.endAt = 0;
        this.bank = null; this.seg = 0; this.take = null; this.deepTake = null; this.deepIdx = 0; this.takes = [];
        this.port.onmessage = (e) => this.message(e.data);
    }
    get intensity() { let i = 0; for (let k = 0; k < LEVELS.length; k++) if (this.keys >= LEVELS[k]) i = k; return i; }
    stepSamples() { return sampleRate * 60 / this.bpm / 3; }       // triplet eighths: the gallop's grid
    whistle(h) { this.throat.harm = h; this.throat.target = this.throat.f0 * h; }
    message(m) {
        if (m.type === 'bank') { this.bank = m.bank; this.port.postMessage({ type: 'bank', notes: m.bank.sygyt.length, deep: m.bank.deep.length }); }
        else if (m.type === 'key') {
            const dt = (m.ms - this.lastKeyMs) / 1000;
            if (this.lastKeyMs && dt < 2.5) this.ioi = this.ioi * 0.75 + clamp(dt, 0.08, 0.9) * 0.25;
            this.lastKeyMs = m.ms; this.lastKeyAt = this.now; this.idleBars = 0; this.endAt = 0;
            this.target = clamp(118 - this.ioi * 70, 72, 112);
            this.keys++;
            if (!this.running) { this.running = true; this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true; this.bpm = this.target; }
            const I = this.intensity;
            if (this.bank) this.sing(this.bank.sygyt[this.seg++ % this.bank.sygyt.length], 0.9);
            else {
                const line = I >= 4 ? HIGH : MELODY;
                this.whistle(line[this.note++ % line.length]);
                this.throat.droneTarget = 0.55; this.throat.wgTarget = 0.6 + 0.08 * I;
            }
            this.khuur.target = I >= 2 ? 0.22 : 0.1;
            this.growl.target = I >= 3 ? 0.35 : 0;
            this.releaseAt = this.held ? 0 : this.now + clamp(this.ioi * 0.9, 0.2, 0.9);
        } else if (m.type === 'held') { this.held = m.on; if (!m.on) this.releaseAt = this.now + clamp(this.ioi * 0.6, 0.12, 0.6); }
        else if (m.type === 'breath') { this.breathUntil = this.now + 0.45; this.throat.wgTarget = 0; this.throat.droneTarget = 0; if (this.take) this.take.release(0.08); }
        else if (m.type === 'slide') {
            if (this.bank) { this.seg = Math.max(0, this.seg - 1); this.sing(this.bank.sygyt[this.seg++ % this.bank.sygyt.length], 0.9); }
            else { this.whistle(Math.max(6, this.throat.harm - 2)); this.throat.wgTarget = 0.7; this.releaseAt = this.now + 0.5; }
        }
        else if (m.type === 'cadence') this.cadence();
        else if (m.type === 'volume') this.volume = m.v;
        else if (m.type === 'stop') this.end(0.3);
        else if (m.type === 'status') {
            this.port.postMessage({ type: 'status', running: this.running, bpm: +this.bpm.toFixed(1), intensity: this.intensity,
                keys: this.keys, harmonic: this.throat.harm, mode: this.bank ? 'samples' : 'synth', note: this.seg, takes: this.takes.length, whistle: +this.throat.wg.toFixed(3), drone: +this.throat.drone.toFixed(3),
                levelDb: +(10 * Math.log10(this.energy + 1e-12)).toFixed(1) });
        }
    }
    // Sample mode: the next real note, crossfaded from the last, with the synthesized
    // bed retuned to that recording's own drone so the two never clash.
    sing(n, gain) {
        if (this.take) this.take.release(0.04);
        this.take = new Take(n.data, gain); this.takes.push(this.take);
        this.throat.f0 = n.f0 || F0; this.khuur.f0 = n.f0 || F0;
        this.throat.wgTarget = 0; this.throat.droneTarget = 0.18;
    }
    cadence() {                                        // the line settles: down to the octave, then the fifth below it
        if (this.bank) {                               // the singer's own ending: the next take's final note
            const list = this.bank.sygyt;
            let k = this.seg; while (k < this.seg + list.length && !list[k % list.length].final) k++;
            const n = list[k % list.length]; this.seg = k + 1;
            this.sing(n, 1.0);
            this.endAt = this.now + n.data.length / sampleRate + 0.8;
        } else { this.whistle(8); this.throat.wgTarget = 0.75; this.throat.droneTarget = 0.6; this.cadenceStep = this.now + 0.6; this.endAt = this.now + 3.2; }
        this.hooves.push(new Hoof(0.9));
        this.running = false; this.keys = 0; this.releaseAt = 0;
    }
    end(seconds) {
        this.running = false; this.keys = 0;
        for (const t of this.takes) t.release(seconds || 0.3);
        this.throat.droneTarget = 0; this.throat.wgTarget = 0; this.khuur.target = 0; this.growl.target = 0;
    }
    barLine() {
        this.bar++;
        this.bpm += (this.target - this.bpm) * 0.5;
        const quietBars = (this.now - this.lastKeyAt) * this.bpm / 240;
        if (quietBars >= 1) {
            this.idleBars++;
            this.keys = Math.min(this.keys, LEVELS[Math.max(0, this.intensity - 1)]);
            if (this.idleBars >= 3) this.end(2);
        }
    }
    trigger(s) {
        if (s === 0) { if (this.fresh) this.fresh = false; else this.barLine(); }
        if (!this.running) return;
        const I = this.intensity, beat = s % 3;
        if (I >= 1) {                                   // the gallop: ta-ka-TUM on every beat
            const vel = beat === 2 ? 0.55 : 0.25 + 0.05 * beat;
            if (I >= 4 || beat !== 1 || s % 6 < 3) this.hooves.push(new Hoof(vel + (I >= 4 ? 0.1 : 0)));
        }
    }
    process(inputs, outputs) {
        const out = outputs[0], L = out[0], R = out[1] || out[0];
        for (let i = 0; i < L.length; i++) {
            this.now += this.dt;
            if (this.running) {
                this.toStep -= 1;
                if (this.toStep <= 0) { this.trigger(this.step); this.step = (this.step + 1) % 12; this.toStep += this.stepSamples(); }
            }
            if (this.releaseAt && this.now >= this.releaseAt && !this.held) { this.releaseAt = 0; this.throat.wgTarget = 0.12; }
            if (this.breathUntil && this.now >= this.breathUntil) { this.breathUntil = 0; if (this.running) this.throat.droneTarget = 0.55; }
            if (this.cadenceStep && this.now >= this.cadenceStep) { this.cadenceStep = 0; this.whistle(6); }
            if (this.endAt && this.now >= this.endAt) { this.endAt = 0; this.end(2); }
            if (this.bank && this.running && this.intensity >= 3 && (!this.deepTake || this.deepTake.left < 0.3)) {   // real kargyraa beneath
                const deep = this.bank.deep;
                if (deep.length) { this.deepTake = new Take(deep[this.deepIdx++ % deep.length], 0.45); this.takes.push(this.deepTake); }
            }
            let mix = this.throat.sample(this.dt) + (this.bank ? 0 : this.growl.sample(this.dt)) + this.khuur.sample(this.dt);
            for (let k = this.takes.length - 1; k >= 0; k--) { const t = this.takes[k]; mix += t.tick(); if (t.done || t.pos === Infinity) this.takes.splice(k, 1); }
            for (let h = this.hooves.length - 1; h >= 0; h--) { const x = this.hooves[h]; mix += x.tick(this.dt); if (x.done) this.hooves.splice(h, 1); }
            const pre = Math.tanh(mix * 1.2);
            this.energy = this.energy * 0.9995 + pre * pre * 0.0005;
            const y = pre * this.volume;
            L[i] = y; R[i] = y;
        }
        return true;
    }
}
registerProcessor('klonk-khoomei', Khoomei);
