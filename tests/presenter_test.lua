-- Dependency-free presenter-mode regression tests.
-- Run from the repository root: lua tests/presenter_test.lua

hs = {
  keycodes = {
    map = {
      [0] = "a",
      [1] = "s",
      [2] = "d",
      [8] = "c",
      [36] = "return",
    },
  },
  timer = {},
}

local klonk = dofile("Klonk.spoon/init.lua")

local function event(keyCode, characters, flags)
  return {
    getKeyCode = function() return keyCode end,
    getCharacters = function() return characters end,
    getFlags = function() return flags or {} end,
  }
end

local function same(actual, expected, message)
  if actual ~= expected then
    error(("%s\nexpected: %q\nactual:   %q"):format(message, expected, actual), 2)
  end
end

local function reset(specialOnly)
  klonk._presenterKeys = {}
  klonk._presenterFlags = {}
  klonk._presenterModifierChord = nil
  klonk._presenterSpecialOnly = specialOnly or false
end

-- Rendering is throttled, not debounced: a dense key burst cannot repeatedly
-- cancel the one next-frame render and leave the HUD apparently deaf.
local scheduled, stopped = 0, 0
hs.timer.secondsSinceEpoch = function() return 1 end
hs.timer.doAfter = function()
  scheduled = scheduled + 1
  return { stop = function() stopped = stopped + 1 end }
end
reset()
klonk._presenterRenderTimer = nil
klonk:_showPresenterKey("s")
klonk:_showPresenterKey("d")
klonk:_showPresenterKey("a")
same(scheduled, 1, "A dense key burst schedules one next-frame render")
same(stopped, 0, "Later burst keys never cancel the pending render")
same(table.concat(klonk._presenterKeys, "|"), "s|d|a",
  "Every burst key is present in the scheduled render state")
klonk._presenterRenderTimer = nil

-- Replace the visual sink with the history semantics the canvas normally uses.
function klonk:_showPresenterKey(label, replaceLast)
  if replaceLast and #self._presenterKeys > 0 then table.remove(self._presenterKeys) end
  self._presenterKeys[#self._presenterKeys + 1] = label
end

local function history()
  return table.concat(klonk._presenterKeys, "|")
end

-- A modifier chord evolves in place as more special keys are held.
reset()
klonk:_presenterFlagsChanged(event(0, "", { cmd = true }))
same(history(), "⌘", "Command starts a modifier chord")
klonk:_presenterFlagsChanged(event(0, "", { cmd = true, alt = true }))
same(history(), "⌘+⌥", "Option joins Command with a plus")
klonk:_presenterFlagsChanged(event(0, "", { cmd = true, alt = true, fn = true }))
same(history(), "⌘+⌥+fn", "Fn joins the existing modifier chord")

-- A regular shortcut key can complete the displayed modifier chord.
reset()
klonk:_presenterFlagsChanged(event(0, "", { cmd = true }))
klonk:_presenterKeyDown(event(8, "c", { cmd = true }))
same(history(), "⌘+c", "Command-C replaces the standalone Command token")

-- Ordinary keys never acquire plus signs, even if keyDown events overlap.
reset()
klonk:_presenterKeyDown(event(0, "a", {}))
klonk:_presenterKeyDown(event(1, "s", {}))
same(history(), "a|s", "Overlapping ordinary letters remain separate elements")

-- Captain specimen: s+d overlap must not disable later presenter response.
reset()
klonk:_presenterKeyDown(event(1, "s", {}))
klonk:_presenterKeyDown(event(2, "d", {}))
klonk:_presenterKeyDown(event(0, "a", {}))
same(history(), "s|d|a", "s+d overlap stays responsive for the following key")

-- Auto-repeat never accumulates into a delayed presenter burst.
reset()
klonk:_presenterKeyDown(event(1, "s", {}), false)
klonk:_presenterKeyDown(event(1, "s", {}), true)
klonk:_presenterKeyDown(event(1, "s", {}), true)
klonk:_presenterKeyDown(event(2, "d", {}), false)
same(history(), "s|d", "Auto-repeat events are absent from presenter history")

-- Releasing modifiers closes one chord; the next press starts a new element.
reset()
klonk:_presenterFlagsChanged(event(0, "", { cmd = true, alt = true }))
klonk:_presenterFlagsChanged(event(0, "", { cmd = true }))
klonk:_presenterFlagsChanged(event(0, "", { cmd = true, fn = true }))
same(history(), "⌘+⌥|⌘+fn", "A release creates a chord boundary")

-- Special-only still hides ordinary characters while retaining editing keys.
reset(true)
klonk:_presenterKeyDown(event(0, "a", {}))
klonk:_presenterKeyDown(event(36, "\r", {}))
same(history(), "Return", "Special-only suppresses letters but keeps Return")

print("presenter tests: 9 passed")
