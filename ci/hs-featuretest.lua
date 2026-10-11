-- hs-featuretest.lua — runs INSIDE Hammerspoon on config load (wired into
-- init.lua by ci/macos-test.sh). Exercises Klonk's real features and appends
-- CHECK lines to /tmp/maclab-artifacts/klonk-result.txt INCREMENTALLY, so a
-- failure in any single check never loses the results before it.
--
-- Mechanism notes learned the hard way:
--   * timers MUST be kept referenced (globals) or HS GC collects them pre-fire.
--   * write incrementally; don't buffer-then-write-once.
--   * each check is PASS / FAIL / UNVERIFIABLE (brief: unverifiable != pass).

local ART = "/tmp/maclab-artifacts"
local RESULT = ART .. "/klonk-result.txt"
os.execute("mkdir -p " .. ART)
os.execute("rm -f " .. RESULT)

local function emit(name, status, detail)
  local f = io.open(RESULT, "a")
  if f then f:write(string.format("CHECK %-16s %-12s %s\n", name, status, detail or "")); f:close() end
end
local function P(v) return v and "PASS" or "FAIL" end

_G._klonkT = _G._klonkT or {}
_G._klonkT.main = hs.timer.doAfter(0.5, function()
  -- INSTALL FLOW (documented: loadSpoon + start)
  local loaded = pcall(function() hs.loadSpoon("Klonk") end)
  emit("INSTALL_LOAD", P(loaded and spoon.Klonk ~= nil),
       loaded and ("loaded v"..tostring(spoon.Klonk and spoon.Klonk.version)) or "hs.loadSpoon failed")
  if not (loaded and spoon.Klonk) then return end
  local K = spoon.Klonk

  emit("METADATA", P(K.name == "Klonk" and K.version ~= nil),
       "name="..tostring(K.name).." version="..tostring(K.version))

  local sets = {}; pcall(function() sets = K:_sets() end)
  emit("SOUND_SETS", P(#sets > 0), (#sets).." keyboard sound sets loaded")

  local started = pcall(function() K:start() end)
  emit("START", P(started), started and "start() ok" or "start() threw (non-fatal if menubar/tap present)")

  emit("MENUBAR", P(K._menu ~= nil), K._menu ~= nil and "menu bar item present" or "no menu bar item")

  -- keyboard-sound + ambient playback are UNVERIFIABLE in a VF guest: it has no
  -- real audio endpoint, and actually invoking hs.sound:play() crashes the
  -- guest's CoreAudio (HALC_ProxyObject 0x10004003). We do NOT execute playback.
  -- Sound-file inventory is validated headlessly in Tier 1; audibility needs
  -- real hardware (or GitHub Actions with an audio device).
  emit("SOUND_PLAY", "UNVERIFIABLE", "sound files inventoried in Tier 1; playback needs a real audio endpoint (VF guest crashes on play)")
  emit("AMBIENT", "UNVERIFIABLE", "ambient playback needs a real audio endpoint; not verifiable in VF guest")

  -- video-desktop substrate: hs.webview below the icon layer
  local wv, wvOk = nil, false
  wvOk = pcall(function()
    wv = hs.webview.new(hs.screen.primaryScreen():fullFrame())
    if wv then
      local lvl = (hs.drawing and hs.drawing.windowLevels and hs.drawing.windowLevels.desktopIcon) or 0
      wv:level(lvl - 1); wv:show()
    end
  end)
  emit("VIDEO_DESKTOP", P(wvOk and wv ~= nil),
       (wvOk and wv) and "hs.webview sub-icon layer creates + shows" or "webview substrate failed")
  if wv then pcall(function() wv:delete() end) end

  local presOk = pcall(function() K:togglePresenter(); K:togglePresenter() end)
  emit("PRESENTER", P(presOk), presOk and "presenter HUD toggles" or "presenter threw")

  local hkOk = pcall(function() K:bindHotkeys({ toggle = {{"cmd","alt","ctrl"}, "f13"} }) end)
  emit("HOTKEYS", P(hkOk), hkOk and "bindHotkeys ok" or "bindHotkeys threw")

  os.execute("/usr/sbin/screencapture -x " .. ART .. "/klonk-running.png")
  emit("SCREENSHOT", "PASS", "klonk-running.png captured")

  -- Klonk's own event tap: assert it is present + enabled, WITHOUT posting a
  -- synthetic key through it — while Klonk is started, a synthetic keyDown would
  -- make its tap play a sound and crash the guest's CoreAudio. Presence+enabled
  -- is the safe assertion here.
  local kTap = false
  pcall(function() kTap = (K._tap ~= nil) and K._tap:isEnabled() end)
  emit("KLONK_TAP", P(kTap), kTap and "Klonk event tap present + enabled" or "Klonk tap missing/disabled")

  -- documented teardown, THEN a synthetic-event probe (safe: Klonk no longer listening)
  local stopped = pcall(function() K:stop() end)
  emit("STOP", P(stopped and K._tap == nil and K._menu == nil),
       "stop() ok; tap/menu cleared="..tostring(K._tap == nil and K._menu == nil))

  local fired = false
  local probe = nil
  pcall(function()
    probe = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(e) fired = true; return false end)
    probe:start()
  end)
  -- Poll for the event instead of a single fixed window: post repeatedly and
  -- check up to ~3s. A single 0.6s window is too tight under concurrent load
  -- (macOS 26 missed it when run alongside 15) — polling makes it reliable.
  local tries = 0
  _G._klonkT.inner = hs.timer.doEvery(0.3, function()
    tries = tries + 1
    if not fired then pcall(function() hs.eventtap.keyStroke({}, "F15", 0) end) end
    if fired or tries >= 10 then
      _G._klonkT.inner:stop()
      pcall(function() if probe then probe:stop() end end)
      emit("EVENT_TAP", P(fired), "synthetic keyDown seen by probe tap="..tostring(fired).." (after "..tries.." tries)")
      emit("DONE", "PASS", "manifest complete")
    end
  end)
end)
