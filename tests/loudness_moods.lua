-- Loudness check: how hot does every Interactive mood get at the speaker?
--
-- Run inside Hammerspoon (silent: output is metered, then muted before the speaker):
--   hs -q -c 'dofile("/path/to/klonk/tests/loudness_moods.lua")'
--   ... about 9 seconds per mood, then:
--   hs -q -c 'return LOUDNESS_REPORT'
-- To recheck some moods only: set LOUDNESS_ONLY = { "wurlitzer" } before dofile.
--
-- A script injected before the page's own code reroutes every connection to the
-- speaker through a meter and a muted gain, so the reading is the page's real output
-- after its own volume stage, at full volume (1.0). Each mood is typed into for six
-- seconds at a brisk pace, then sent Return. Reported: the sample peak (dBFS) and the
-- loudest 0.75 s RMS, while typing and at the cadence. A peak at or above 0 dBFS
-- clips; anything far above the others will sound like overdrive at the same volume.
-- Klonk.spoon/performer/output.js holds each mood's trim; adjust it from this report.
local k = spoon.Klonk
LOUDNESS, LOUDNESS_KEEP, LOUDNESS_REPORT = {}, {}, "running"
local PEAK_LIMIT, RMS_LIMIT, CADENCE_LIMIT = -1.0, -12.0, -9.0   -- dBFS at full volume: no clipping,
                                               -- typing at one level, cadences louder but not startling

local METER = [[
(function () {
  const meters = [];
  const connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (target, ...rest) {
    if (target instanceof AudioDestinationNode) {
      const ctx = target.context;
      if (!ctx.__meter) {
        const sum = ctx.createGain(), an = ctx.createAnalyser(), mute = ctx.createGain();
        an.fftSize = 32768; mute.gain.value = 0;
        connect.call(sum, an); connect.call(an, mute); connect.call(mute, target);
        ctx.__meter = { sum, an, buf: new Float32Array(an.fftSize) };
        meters.push(ctx.__meter);
      }
      return connect.call(this, ctx.__meter.sum, ...rest);
    }
    return connect.call(this, target, ...rest);
  };
  window.__meter = function () {
    let peak = 0, e = 0, n = 0;
    for (const m of meters) {
      m.an.getFloatTimeDomainData(m.buf);
      for (const x of m.buf) { const a = Math.abs(x); if (a > peak) peak = a; e += x * x; n++; }
    }
    const db = (v) => +(20 * Math.log10(v + 1e-9)).toFixed(1);
    return JSON.stringify({ peak: db(peak), rms: db(Math.sqrt(e / Math.max(1, n))) });
  };
})();
]]

local function later(t, f) LOUDNESS_KEEP[#LOUDNESS_KEEP + 1] = hs.timer.doAfter(t, f) end

local moods = {}
for _, name in ipairs(k:_sets()) do
  local wanted = not LOUDNESS_ONLY or hs.fnutils.contains(LOUDNESS_ONLY, name)
  if k:_category(name) == "interactive" and k:_performerKind(k:_setDir(name)) and wanted then moods[#moods + 1] = name end
end

local function finish()
  table.sort(LOUDNESS, function(a, b) return a.peak > b.peak end)
  local lines, hot = { string.format("%-22s %8s %8s %8s %8s", "mood (full volume)", "peak", "rms", "cad.peak", "cad.rms") }, 0
  for _, r in ipairs(LOUDNESS) do
    local flag = (math.max(r.peak, r.cpeak) >= PEAK_LIMIT or r.rms >= RMS_LIMIT or r.crms >= CADENCE_LIMIT) and "HOT" or ""
    if flag ~= "" then hot = hot + 1 end
    lines[#lines + 1] = string.format("%-22s %8.1f %8.1f %8.1f %8.1f  %s", r.name, r.peak, r.rms, r.cpeak, r.crms, flag)
  end
  lines[#lines + 1] = string.format("%d moods, %d hot (peak >= %.0f, typing rms >= %.0f, or cadence rms >= %.0f dBFS)", #LOUDNESS, hot, PEAK_LIMIT, RMS_LIMIT, CADENCE_LIMIT)
  LOUDNESS_REPORT = table.concat(lines, "\n")
  hs.printf("klonk loudness %d checked, %d hot", #LOUDNESS, hot)
end

local function check(i)
  if i > #moods then return finish() end
  local name = moods[i]
  local kind = k:_performerKind(k:_setDir(name))
  local r = { name = name, peak = -99, rms = -99, cpeak = -99, crms = -99 }
  LOUDNESS[#LOUDNESS + 1] = r
  local uc = hs.webview.usercontent.new("klonkLoudness" .. i)
  uc:injectScript({ source = METER, mainFrame = true, injectionTime = "documentStart" })
  local view = hs.webview.new({ x = 0, y = 0, w = 10, h = 10 }, {}, uc):url(k:_performerURL(kind, name))
  LOUDNESS_KEEP[#LOUDNESS_KEEP + 1] = view; LOUDNESS_KEEP[#LOUDNESS_KEEP + 1] = uc
  local function sample(cadence)
    view:evaluateJavaScript("window.__meter ? __meter() : '{}'", function(s)
      local ok, m = pcall(hs.json.decode, s or "{}")
      if not ok or not m or not m.peak then return end
      if cadence then r.cpeak, r.crms = math.max(r.cpeak, m.peak), math.max(r.crms, m.rms)
      else r.peak, r.rms = math.max(r.peak, m.peak), math.max(r.rms, m.rms) end
    end)
  end
  later(4.0, function()
    view:evaluateJavaScript("window.K && K.volume(1)")
    for n = 1, 40 do
      later(n * 0.15, function()
        local ms = hs.timer.absoluteTime() / 1e6
        view:evaluateJavaScript("K.events(" .. hs.json.encode({ { "d", n % 30, ms, false }, { "u", n % 30, ms + 90 } }) .. ")")
      end)
    end
    for t = 1.0, 6.0, 0.5 do later(t, function() sample(false) end) end
    later(6.2, function()
      local ms = hs.timer.absoluteTime() / 1e6
      view:evaluateJavaScript("K.events(" .. hs.json.encode({ { "d", 36, ms, false }, { "u", 36, ms + 80 } }) .. ")")
    end)
    for t = 6.5, 9.0, 0.5 do later(t, function() sample(true) end) end
    later(9.3, function() view:delete(); later(0.3, function() check(i + 1) end) end)
  end)
end

check(1)
return string.format("measuring %d moods", #moods)
