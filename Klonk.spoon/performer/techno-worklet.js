// Klonk techno groovebox: the sequencer and every drum voice, running in the audio
// thread (AudioWorkletProcessor) so timing counts samples, not page timers.
const LEVELS = [0, 4, 10, 18, 28];          // keystrokes in the sentence for each layer (the riser starts at the last)

// The groove is a mini-notation program (mini.js, loaded into this scope first):
// one bar per line, each line unlocked by that many keystrokes in the sentence.
// This default reproduces the original groove; the settings editor can replace it.
const DEFAULT_PATTERN = [
    '0  : bd*4',
    '4  : [~ oh]*4',
    '10 : ~ cp ~ cp',
    '10 : [~ hh]*8',
    '18 : [~ a1 a1 a1] [~ a1 <a1 c2> a1] [~ a1 a1 a1] [~ a1 a2 a1]',
].join('\n');
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const noise = () => Math.random() * 2 - 1;

class SVF {                                    // Zavalishin TPT state-variable filter
    constructor() { this.ic1 = 0; this.ic2 = 0; this.set(1000, 0.7); }
    set(fc, q) {
        const g = Math.tan(Math.PI * clamp(fc, 20, sampleRate * 0.45) / sampleRate), k = 1 / q;
        this.k = k; this.a1 = 1 / (1 + g * (g + k)); this.a2 = g * this.a1; this.a3 = g * this.a2;
    }
    run(x) {
        const v3 = x - this.ic2, v1 = this.a1 * this.ic1 + this.a2 * v3, v2 = this.ic2 + this.a2 * this.ic1 + this.a3 * v3;
        this.ic1 = 2 * v1 - this.ic1; this.ic2 = 2 * v2 - this.ic2;
        this.low = v2; this.band = v1; this.high = x - this.k * v1 - v2;
        return this;
    }
}

class Kick {
    constructor(vel, big) { this.t = 0; this.ph = 0; this.vel = vel; this.len = big ? 0.9 : 0.56; this.lo = big ? 38 : 44; }   // deep and round: thump
    tick(dt) {
        const t = this.t; this.t += dt;
        const f = this.lo + 110 * Math.exp(-t / 0.028);
        this.ph += 2 * Math.PI * f * dt;
        const click = t < 0.003 ? noise() * 0.5 * (1 - t / 0.003) : 0;
        return this.vel * (Math.sin(this.ph) * Math.exp(-t / (this.len * 0.42)) + click);
    }
    get done() { return this.t > this.len * 2.2; }
}
class Hat {
    constructor(vel, open) { this.t = 0; this.vel = vel; this.dec = open ? 0.09 : 0.018; this.f = new SVF(); this.f.set(8200, 0.8); }
    tick(dt) { this.t += dt; return this.vel * this.f.run(noise()).high * Math.exp(-this.t / this.dec); }
    get done() { return this.t > this.dec * 6; }
}
class Clap {
    constructor(vel) { this.t = 0; this.vel = vel; this.f = new SVF(); this.f.set(1250, 1.4); }
    tick(dt) {
        const t = this.t; this.t += dt;
        let env = Math.exp(-t / 0.11);
        for (const b of [0, 0.011, 0.022]) if (t >= b && t < b + 0.008) env = Math.max(env, Math.exp(-(t - b) / 0.004) * 1.4);
        return this.vel * this.f.run(noise()).band * env * 2.2;
    }
    get done() { return this.t > 0.6; }
}
class Snare {
    constructor(vel) { this.t = 0; this.ph = 0; this.vel = vel; this.f = new SVF(); this.f.set(1900, 0.9); }
    tick(dt) {
        const t = this.t; this.t += dt; this.ph += 2 * Math.PI * 190 * dt;
        return this.vel * (this.f.run(noise()).band * 1.6 * Math.exp(-t / 0.06) + Math.sin(this.ph) * 0.5 * Math.exp(-t / 0.03));
    }
    get done() { return this.t > 0.35; }
}
class Shaker {
    constructor(vel) { this.t = 0; this.vel = vel; this.f = new SVF(); this.f.set(6500 + Math.random() * 2500, 0.9); }
    tick(dt) { this.t += dt; return this.vel * this.f.run(noise()).high * Math.exp(-this.t / 0.012); }
    get done() { return this.t > 0.08; }
}
class Rim {
    constructor(vel) { this.t = 0; this.ph = 0; this.vel = vel; this.f = new SVF(); this.f.set(2400, 4); }
    tick(dt) { const t = this.t; this.t += dt; this.ph += 2 * Math.PI * 1700 * dt; return this.vel * (this.f.run(noise()).band * 2 + Math.sin(this.ph) * 0.4) * Math.exp(-t / 0.012); }
    get done() { return this.t > 0.08; }
}
class Cowbell {
    constructor(vel) { this.t = 0; this.a = 0; this.b = 0; this.vel = vel; this.f = new SVF(); this.f.set(2600, 2); }
    tick(dt) {
        const t = this.t; this.t += dt; this.a = (this.a + 540 * dt) % 1; this.b = (this.b + 800 * dt) % 1;
        const sq = (this.a < 0.5 ? 1 : -1) + (this.b < 0.5 ? 1 : -1);
        return this.vel * this.f.run(sq).band * Math.exp(-t / 0.09) * 1.5;
    }
    get done() { return this.t > 0.5; }
}
class Bass {
    constructor(hz, vel, filter) { this.t = 0; this.ph = 0; this.hz = hz; this.vel = vel; this.f = filter; }
    tick(dt) {
        const t = this.t; this.t += dt; this.ph = (this.ph + this.hz * dt) % 1;
        const saw = this.ph * 2 - 1;
        const env = Math.min(1, t / 0.003) * Math.exp(-t / 0.13);
        return this.vel * env * this.f.run(saw).low;
    }
    get done() { return this.t > 0.6; }
}
class Impact {                                  // POW: crash, sub drop, and a big kick
    constructor(vel) { this.t = 0; this.ph = 0; this.vel = vel; this.f = new SVF(); this.f.set(5200, 0.6); this.kick = new Kick(1, true); }
    tick(dt) {
        const t = this.t; this.t += dt;
        this.ph += 2 * Math.PI * (34 + 30 * Math.exp(-t / 0.25)) * dt;
        const crash = this.f.run(noise()).high * Math.exp(-t / 0.75) * 0.55;
        const sub = Math.sin(this.ph) * Math.exp(-t / 0.7) * 0.8;
        return this.vel * (crash + sub + this.kick.tick(dt));
    }
    get done() { return this.t > 3.5; }
}
class Scratch {
    constructor() { this.t = 0; this.f = new SVF(); }
    tick(dt) {
        const t = this.t; this.t += dt;
        this.f.set(700 + 1600 * Math.abs(Math.sin(t * 2 * Math.PI * 9)), 3);
        return this.f.run(noise()).band * 0.9 * Math.sin(Math.PI * clamp(t / 0.2, 0, 1));
    }
    get done() { return this.t > 0.2; }
}

class Techno extends AudioWorkletProcessor {
    constructor() {
        super();
        this.dt = 1 / sampleRate;
        this.voices = []; this.bassVoices = [];
        this.running = false; this.bpm = 124; this.target = 124;
        this.step = 0; this.toStep = 0; this.bar = 0;
        this.keys = 0; this.ioi = 0.3; this.lastKeyMs = 0; this.lastKeyAt = 0; this.now = 0;
        this.idleBars = 0; this.dropBars = 0; this.breakBars = 0; this.breakPending = false; this.riseBars = 0; this.fresh = true;
        this.held = false; this.volume = 0.7; this.duck = 0; this.energy = 0;
        this.bassFilter = new SVF(); this.cutoff = 300; this.cutoffTarget = 300;
        this.riser = new SVF(); this.riserGain = 0; this.riserFc = 300; this.riserTime = 0;
        this.program = globalThis.Mini ? globalThis.Mini.parseProgram(DEFAULT_PATTERN).lines : [];
        this.queue = []; this.barPos = 0;
        this.port.onmessage = (e) => this.message(e.data);
    }
    get intensity() {
        if (this.dropBars > 0) return 4;
        let i = 0; for (let k = 0; k < LEVELS.length; k++) if (this.keys >= LEVELS[k]) i = k;
        return i;
    }
    message(m) {
        if (m.type === 'program') { this.program = m.lines; this.port.postMessage({ type: 'program', lines: m.lines.length }); }
        else if (m.type === 'key') {
            const dt = (m.ms - this.lastKeyMs) / 1000;
            if (this.lastKeyMs && dt < 2.5) this.ioi = this.ioi * 0.75 + clamp(dt, 0.08, 0.8) * 0.25;
            this.lastKeyMs = m.ms; this.lastKeyAt = this.now; this.idleBars = 0;
            this.target = clamp(131 - this.ioi * 30, 118, 128);          // a dance pulse, not a caffeine rush
            this.keys++;
            this.voices.push(new Shaker(0.16 + Math.random() * 0.08));
            if (!this.running) { this.running = true; this.step = 0; this.toStep = 0; this.bar = 0; this.fresh = true; this.bpm = this.target; }
        } else if (m.type === 'pow') {
            const size = 0.55 + 0.45 * (this.intensity / 4);
            this.voices.push(new Impact(size));
            this.dropBars = this.intensity >= 2 ? 2 : 1;
            this.keys = 0; this.riseBars = 0; this.idleBars = 0; this.lastKeyAt = this.now;
            this.running = true; this.bar = 0; this.fresh = false;            // POW is the new downbeat (step 0)
            this.step = 1; this.toStep = this.samplesPerStep(); this.startBar(true);
            this.duck = 1;
        } else if (m.type === 'break') { this.breakPending = true; this.lastKeyAt = this.now; }
        else if (m.type === 'scratch') { this.voices.push(new Scratch()); this.lastKeyAt = this.now; }
        else if (m.type === 'held') { this.held = m.on; }
        else if (m.type === 'volume') { this.volume = m.v; }
        else if (m.type === 'stop') { this.running = false; this.voices = []; this.bassVoices = []; this.keys = 0; this.dropBars = 0; this.riserGain = 0; }
        else if (m.type === 'status') {
            this.port.postMessage({ type: 'status', running: this.running, bpm: +this.bpm.toFixed(1), intensity: this.intensity,
                keys: this.keys, bar: this.bar, step: this.step, dropBars: this.dropBars, voices: this.voices.length + this.bassVoices.length,
                levelDb: +(10 * Math.log10(this.energy + 1e-12)).toFixed(1) });
        }
    }
    samplesPerStep() { return sampleRate * 60 / this.bpm / 4; }
    barLine() {
        this.bar++;
        this.bpm += (this.target - this.bpm) * 0.25;              // ease tempo changes in gently at the bar
        if (this.dropBars > 0) { this.dropBars--; if (this.dropBars === 0) this.keys = 0; }
        this.breakBars = this.breakPending ? 1 : 0; this.breakPending = false;   // comma: the next bar drops the kick
        if (this.intensity === 4 && this.dropBars === 0) this.riseBars++; else this.riseBars = 0;
        const quietBars = (this.now - this.lastKeyAt) * this.bpm / 240;
        if (quietBars >= 1 && this.dropBars === 0) {
            this.idleBars++;
            const lvl = Math.max(0, this.intensity - 1);
            this.keys = Math.min(this.keys, LEVELS[lvl]);
            if (this.idleBars >= 4) this.running = false;
        }
    }
    // Lay out this bar's pattern events, in samples from the bar line.
    startBar(skipDownbeat) {
        const bar = this.samplesPerStep() * 16, drop = this.dropBars > 0, brk = this.breakBars > 0;
        this.queue = []; this.barPos = 0;
        for (const line of this.program) {
            if (!drop && this.keys < line.unlock) continue;
            for (const e of globalThis.Mini.cycleEvents(line.tree, this.bar)) {
                if (skipDownbeat && e.start === 0 && e.v === 'bd') continue;   // POW's impact is the downbeat kick
                if (brk && (e.v === 'bd' || globalThis.Mini.noteToMidi(e.v) !== null)) continue;   // a break drops kick and bass
                this.queue.push({ at: e.start * bar, v: e.v });
            }
        }
        this.queue.sort((x, y) => x.at - y.at);
    }
    fire(v) {
        switch (v) {
            case 'bd': this.voices.push(new Kick(0.95, false)); this.duck = 1; break;
            case 'sd': case 'sn': this.voices.push(new Snare(0.3)); break;
            case 'cp': this.voices.push(new Clap(0.5)); break;
            case 'hh': this.voices.push(new Hat(0.14, false)); break;
            case 'oh': this.voices.push(new Hat(0.32, true)); break;
            case 'sh': this.voices.push(new Shaker(0.2)); break;
            case 'rim': this.voices.push(new Rim(0.3)); break;
            case 'cb': this.voices.push(new Cowbell(0.22)); break;
            default: {
                const m = globalThis.Mini.noteToMidi(v);
                if (m !== null) this.bassVoices.push(new Bass(440 * Math.pow(2, (m - 69) / 12), 0.55, this.bassFilter));
            }
        }
    }
    trigger(s) {
        if (s === 0) {
            if (this.fresh) this.fresh = false; else this.barLine();
            if (this.running) this.startBar(false);
        }
        if (!this.running) return;
        const I = this.intensity, drop = this.dropBars > 0;
        if (I === 4 && !drop) {                                     // the build: snare roll under the riser
            const every = this.riseBars >= 2 ? 1 : this.riseBars === 1 ? 2 : 4;
            if (s % every === 0) this.voices.push(new Snare(0.18 + 0.06 * Math.min(3, this.riseBars) + s * 0.006));
        }
    }
    process(inputs, outputs) {
        const out = outputs[0], L = out[0], R = out[1] || out[0];
        const I = this.intensity;
        this.cutoffTarget = 260 + 260 * I + (this.held ? 1400 : 0) + (this.dropBars > 0 ? 900 : 0);
        this.cutoff += (this.cutoffTarget - this.cutoff) * 0.08;
        this.bassFilter.set(this.cutoff, 5);
        // The riser is a broad low-passed noise whoosh: 300 Hz to 6 kHz over two bars,
        // then, if no drop comes, it eases away by bar four instead of hanging there.
        const rising = I === 4 && this.dropBars === 0 && this.running;
        this.riserTime = rising ? this.riserTime + L.length / sampleRate : 0;
        const bar = 240 / this.bpm, sweep = Math.min(1, this.riserTime / (2 * bar));
        const fadeAway = clamp((this.riserTime - 3 * bar) / bar, 0, 1);
        this.riserFc = 300 * Math.pow(20, sweep);
        this.riserGain += ((rising ? 0.11 * sweep * (1 - fadeAway) : 0) - this.riserGain) * 0.02;
        this.riser.set(this.riserFc, 0.7);
        for (let i = 0; i < L.length; i++) {
            this.now += this.dt;
            if (this.running) {
                this.toStep -= 1;
                if (this.toStep <= 0) { this.trigger(this.step); this.step = (this.step + 1) % 16; this.toStep += this.samplesPerStep(); }
                while (this.queue.length && this.queue[0].at <= this.barPos) this.fire(this.queue.shift().v);
                this.barPos += 1;
            }
            let mix = 0, bass = 0;
            for (let v = this.voices.length - 1; v >= 0; v--) { const x = this.voices[v]; mix += x.tick(this.dt); if (x.done) this.voices.splice(v, 1); }
            for (let v = this.bassVoices.length - 1; v >= 0; v--) { const x = this.bassVoices[v]; bass += x.tick(this.dt); if (x.done) this.bassVoices.splice(v, 1); }
            this.duck *= 0.9993;                                   // sidechain pump: bass ducks under each kick
            mix += bass * (1 - 0.8 * this.duck);
            if (this.riserGain > 0.001) mix += this.riser.run(noise()).low * this.riserGain;
            const pre = Math.tanh(mix * 0.9);
            this.energy = this.energy * 0.9995 + pre * pre * 0.0005;      // pre-volume level, ~50 ms window
            const y = pre * this.volume;
            L[i] = y; R[i] = y;
        }
        return true;
    }
}
registerProcessor('klonk-techno', Techno);
