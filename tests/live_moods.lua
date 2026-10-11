-- Live check: does every Interactive moods set actually make sound?
--
-- Run inside Hammerspoon (it never touches your current set or volume):
--   hs -q -c 'dofile("/path/to/klonk/tests/live_moods.lua")'
--   ... about 10 seconds per mood, then:
--   hs -q -c 'return LIVE_MOODS_REPORT'
-- To recheck some moods only: set LIVE_MOODS_ONLY = { "techno-build" } before dofile.
--
-- Each performed mood is opened in its own private hidden page at zero volume, typed
-- into (24 keystrokes), then sent Return. Levels are read before the volume stage, so
-- zero volume cannot hide a silent engine. A mood passes when its page is ready, logs
-- no errors, and sounds both while typing and after the cadence. Per-key interactive
-- sets (no performer) pass when their key sounds load and have length.
local k = spoon.Klonk
local THRESHOLD = -45                          -- dB: clearly sounding, not noise
LIVE_MOODS, LIVE_MOODS_KEEP, LIVE_MOODS_REPORT = {}, {}, "running"

local function later(t, f) LIVE_MOODS_KEEP[#LIVE_MOODS_KEEP + 1] = hs.timer.doAfter(t, f) end

local moods = {}
for _, name in ipairs(k:_sets()) do
  local wanted = not LIVE_MOODS_ONLY or hs.fnutils.contains(LIVE_MOODS_ONLY, name)
  if k:_category(name) == "interactive" and wanted then moods[#moods + 1] = name end
end

-- Hammerspoon runs the code it loaded, not what is on disk: an edit without a reload
-- leaves the old code playing. Fail loudly instead of testing pages the spoon never opens.
local stale = {}
for file in hs.fs.dir(k.spoonPath) do
  if file:match("%.lua$") then
    local changed = hs.fs.attributes(k.spoonPath .. "/" .. file, "modification") or 0
    if not k._loadedAt or changed > k._loadedAt then stale[#stale + 1] = file end
  end
end

local function finish()
  local lines, failed = {}, 0
  if #stale > 0 then
    failed = failed + 1
    lines[#lines + 1] = "FAIL stale code: " .. table.concat(stale, ", ") .. " changed after Hammerspoon loaded Klonk; reload"
  end
  for _, r in ipairs(LIVE_MOODS) do
    if not r.ok then failed = failed + 1 end
    lines[#lines + 1] = string.format("%-4s %-22s %-8s typing %6s dB  cadence %6s dB  %s",
      r.ok and "PASS" or "FAIL", r.name, r.kind, tostring(r.typing), tostring(r.cadence), r.note or "")
  end
  lines[#lines + 1] = string.format("%d moods, %d failed", #LIVE_MOODS, failed)
  LIVE_MOODS_REPORT = table.concat(lines, "\n")
  hs.printf("klonk live-moods %d checked, %d failed", #LIVE_MOODS, failed)
  if k._perfView then                                             -- and the page actually running now
    k._perfView:evaluateJavaScript("typeof K==='undefined'?'{}':K.status()", function(st)
      local ok, s = pcall(hs.json.decode, st or "{}")
      if ok and s and not s.ready then
        LIVE_MOODS_REPORT = LIVE_MOODS_REPORT .. "\nFAIL the running set's page is not ready: " .. tostring(s.error)
      end
    end)
  end
end

local function level(view, cb)
  view:evaluateJavaScript("K.status()", function() end)        -- worklet moods refresh their level on status
  later(0.12, function()
    view:evaluateJavaScript("typeof K==='undefined'?-999:K.level()", function(v) cb(tonumber(v) or -999) end)
  end)
end

local function check(i)
  if i > #moods then return finish() end
  local name = moods[i]
  local dir = k:_setDir(name)
  local kind = k:_performerKind(dir)
  local r = { name = name, kind = kind or "per-key", typing = -999, cadence = -999 }
  LIVE_MOODS[#LIVE_MOODS + 1] = r
  if not kind then                                                -- a per-key set: its sounds must load
    local pool = k:_poolFor(dir)
    local n, longest = 0, 0
    for _, bank in ipairs(pool.down or {}) do
      local s = bank.copies[1]
      if s then n = n + 1; longest = math.max(longest, s:duration() or 0) end
    end
    r.ok = n > 0 and longest > 0
    r.note = string.format("%d key sounds, longest %.2fs", n, longest)
    r.typing, r.cadence = "-", "-"
    return later(0.1, function() check(i + 1) end)
  end
  local url = k:_performerURL(kind, name)                         -- the same page the spoon opens
  local view = hs.webview.new({ x = 0, y = 0, w = 10, h = 10 }):url(url)
  LIVE_MOODS_KEEP[#LIVE_MOODS_KEEP + 1] = view
  later(4.0, function()
    view:evaluateJavaScript("typeof K==='undefined'?'{}':K.status()", function(s)
      local ok, st = pcall(hs.json.decode, s or "{}")
      st = ok and st or {}
      if not st.ready then r.ok = false; r.note = "not ready: " .. tostring(st.error); view:delete(); return later(0.1, function() check(i + 1) end) end
      view:evaluateJavaScript("K.volume(0)")
      for n = 1, 24 do
        later(n * 0.15, function()
          local ms = hs.timer.absoluteTime() / 1e6
          view:evaluateJavaScript("K.events(" .. hs.json.encode({ { "d", 0, ms, false }, { "u", 0, ms + 90 } }) .. ")")
        end)
      end
      for _, t in ipairs({ 1.9, 3.0, 3.6 }) do later(t, function() level(view, function(v) r.typing = math.max(r.typing, v) end) end) end
      later(3.8, function()
        local ms = hs.timer.absoluteTime() / 1e6
        view:evaluateJavaScript("K.events(" .. hs.json.encode({ { "d", 36, ms, false }, { "u", 36, ms + 80 } }) .. ")")
      end)
      for _, t in ipairs({ 4.0, 4.4, 5.0 }) do later(t, function() level(view, function(v) r.cadence = math.max(r.cadence, v) end) end) end
      later(5.6, function()
        view:evaluateJavaScript("JSON.parse(K.status()).errors.length", function(e)
          local errs = tonumber(e) or 0
          r.ok = errs == 0 and r.typing > THRESHOLD and r.cadence > THRESHOLD
          r.note = errs > 0 and (errs .. " page errors") or nil
          view:delete()
          later(0.2, function() check(i + 1) end)
        end)
      end)
    end)
  end)
end

check(1)
return string.format("checking %d moods", #moods)
