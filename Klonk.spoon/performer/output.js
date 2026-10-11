// Klonk's shared output stage, loaded first by every performer page.
//
// Each page builds its own mix and ends with connect(ctx.destination). This file
// catches that last connection and routes it through one stage per audio context:
//
//   page mix -> trim (this mood's loudness match) -> limiter -> soft clip -> speaker
//
// The trim brings every mood to the same loudness (about -16 dBFS RMS while typing at
// full volume), the limiter holds cadences and hits under -3 dBFS, and the soft clip
// guarantees nothing reaches full scale, so no mood can overdrive the speakers.
// Trims come from tests/loudness_moods.lua; remeasure there after changing a mood's mix.
(function () {
    'use strict';
    const TRIM_DB = {                          // keyed by page, or scene#<set> for instrument scenes
        'chamber': -1.5, 'cinematic': -3.0, 'gregorian': -2.0, 'khoomei': -7.0, 'orchestra': -7.5,
        'techno': -4.5, 'warchant': -7.0,
        'scene#bagpipe': -6.0, 'scene#hard-drive-music-box': -3.5, 'scene#harpsichord': -4.5,
        'scene#jazz-piano': -4.5, 'scene#kalimba': -5.0, 'scene#schmoove-guitar': 1.5,
        'scene#slap-bass': -1.5, 'scene#vibraphone': -5.0, 'scene#wurlitzer': -6.5,
    };
    const page = location.pathname.split('/').pop().replace(/\.html$/, '');
    const key = page === 'scene' ? 'scene#' + decodeURIComponent(location.hash.slice(1)) : page;
    const trimDb = TRIM_DB[key] || 0;

    function softClip() {                      // linear to -6 dBFS, then bends smoothly toward (never past) 0.98
        const n = 4096, curve = new Float32Array(n), knee = 0.5, ceil = 0.98;
        for (let i = 0; i < n; i++) {
            const x = (i / (n - 1)) * 2 - 1, a = Math.abs(x);
            const y = a <= knee ? a : knee + (ceil - knee) * Math.tanh((a - knee) / (ceil - knee));
            curve[i] = Math.sign(x) * y;
        }
        return curve;
    }

    const connect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (target, ...rest) {
        if (!(target instanceof AudioDestinationNode)) return connect.call(this, target, ...rest);
        const ctx = target.context;
        if (!ctx.__klonkOut) {
            const trim = ctx.createGain(), limit = ctx.createDynamicsCompressor(), clip = ctx.createWaveShaper();
            trim.gain.value = Math.pow(10, trimDb / 20);
            limit.threshold.value = -6; limit.knee.value = 3; limit.ratio.value = 20;
            limit.attack.value = 0.002; limit.release.value = 0.2;
            clip.curve = softClip(); clip.oversample = '2x';
            connect.call(trim, limit); connect.call(limit, clip); connect.call(clip, target);
            ctx.__klonkOut = { trim, limit, key, trimDb };
        }
        return connect.call(this, ctx.__klonkOut.trim, ...rest);
    };
    window.KLONK_OUTPUT = { key, trimDb };
})();
