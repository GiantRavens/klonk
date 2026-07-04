--- === Klonk ===
---
--- Mechanical keystroke sounds for macOS — in any voice you like.
---
--- A "sound set" is just a folder of WAVs, so the built-in synthesized sets,
--- real recorded keyboards, and anything you drop in all play the same way.
--- Every set rings a Return "ding" baked into its own `enter.wav`.
---
--- Mouse clicks and scrolling ring too: a click is just a down+up, so every set
--- gets mouse sounds for free from its `down`/`up` pool. A set can also ship
--- dedicated `click` / `clickup` / `rightclick` / `scroll` WAVs to voice the
--- mouse on its own.
---
--- The menu-bar shows a keyboard icon (dims + slashes when muted). Click it to
--- toggle sound, toggle mouse clicks, pick a set, or set the volume. Sets are
--- scanned from the bundled `sounds/` folder plus `~/.klonk/sounds` (your own).
---
--- Download: https://github.com/giantravens/klonk

local obj = {}
obj.__index = obj

obj.name = "Klonk"
obj.version = "1.0"
obj.author = "Skip Levens"
obj.homepage = "https://github.com/giantravens/klonk"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- Klonk.soundDirs
--- Variable
--- List of directories scanned for sound sets. Set before `:start()` to
--- customize. Defaults to the bundled `sounds/` plus `~/.klonk/sounds`. Earlier
--- directories win, so a set in your own dir overrides a bundled one of the
--- same name.
obj.soundDirs = nil

--- Klonk.voices
--- Variable
--- Maximum polyphony — the CAP on how many copies of a sound are loaded so fast
--- keystrokes overlap and ring out on top of each other. The actual count per
--- sound is ADAPTIVE: ~one voice per 0.1s of the sound's own length, capped
--- here. So short clacks (real recorded keyboards) stay crisp at a single voice,
--- while long-tailed samples (paper, splash, kalimba) fan out into a layered
--- wash. Drop a `voices` file (one integer) into a set folder to pin it. Set
--- before `:start()`. Default 6.
obj.voices = 6

--- Klonk.ambientDirs
--- Variable
--- List of directories scanned for ambient beds — single long, loopable audio
--- files (rain, wind, surf, a bridge hum) that play under your typing. Defaults
--- to the bundled `ambient/` plus `~/.klonk/ambient`. Each file's basename is a
--- bed's menu name.
obj.ambientDirs = nil

-- runtime state (underscore-prefixed → not part of the public API)
obj._menu  = nil
obj._tap   = nil
obj._pool  = {}
obj._set   = nil
obj._on    = true
obj._mouse = true
obj._vol   = 0.7
obj._lastScroll = 0
obj._bed      = nil     -- current ambient bed name (nil = none)
obj._bedSound = nil     -- the looping hs.sound object
obj._bedVol   = 0.5

-- Which dedicated file plays for which macOS key code.
local KEYFILE = { [49] = "space", [36] = "enter", [51] = "backspace" }

-- Generic pools bucketed by filename stem. The keyboard uses down/up; the mouse
-- uses click / clickup / rightclick / scroll — each falling back to a key pool
-- (see the play() chains in :start()), so a set needs zero new files to click.
local GENERIC = { up = true, down = true, click = true, clickup = true,
                  rightclick = true, scroll = true }
local VOLUMES = { 0.3, 0.5, 0.7, 1.0 }
local SCROLL_GAP = 0.05   -- min seconds between scroll ticks (trackpad throttle)

local function expand(p) return (p:gsub("^~", os.getenv("HOME"))) end

-- Unique set names across all soundDirs, sorted.
function obj:_sets()
  local seen, out = {}, {}
  for _, dir in ipairs(self.soundDirs) do
    dir = expand(dir)
    if hs.fs.attributes(dir) then
      for d in hs.fs.dir(dir) do
        if not d:match("^[._]") and not seen[d]
           and hs.fs.attributes(dir .. "/" .. d, "mode") == "directory" then
          seen[d] = true; out[#out + 1] = d
        end
      end
    end
  end
  table.sort(out)
  return out
end

-- Resolve a set name to a directory (first soundDir match wins).
function obj:_setDir(name)
  for _, dir in ipairs(self.soundDirs) do
    local p = expand(dir) .. "/" .. name
    if hs.fs.attributes(p, "mode") == "directory" then return p end
  end
end

-- Preload a set into hs.sound objects once, so keystroke playback is a table
-- lookup + play with no disk I/O on the hot path. Files follow the convention:
-- down1..N / up1..N (randomized variants) and space / enter / backspace.
-- Load a sound as a BANK of copies with a rotating index. Playing rotates to the
-- next copy, so retriggering before the tail dies lands on a fresh (idle) NSSound
-- instance — the copies overlap and decay instead of cutting each other off.
-- Bank size is ADAPTIVE: ~one voice per 0.1s of the sound's own length, capped at
-- Klonk.voices. A short clack resolves to ONE voice (crisp, exactly the old
-- behavior); a long sample fans out into a layering wash. An explicit per-set
-- `voices` file (self._voiceOverride) wins over the length heuristic.
function obj:_bank(path)
  local first = hs.sound.getByFile(path)
  if not first then return { copies = {}, i = 0 } end
  first:volume(self._vol)
  local cap = math.max(1, self.voices or 6)
  local n = self._voiceOverride and math.max(1, math.min(cap, self._voiceOverride)) or cap
  if not self._voiceOverride then
    local dur = first:duration()
    if type(dur) == "number" and dur > 0 then
      n = math.max(1, math.min(cap, math.ceil(dur / 0.1)))
    end
  end
  local copies = { first }
  for _ = 2, n do
    local s = hs.sound.getByFile(path)
    if s then s:volume(self._vol); copies[#copies + 1] = s end
  end
  return { copies = copies, i = 0 }
end

function obj:_load(name)
  self._set = name
  self._pool = {}
  local dir = self:_setDir(name)
  if not dir then return end
  -- optional per-set polyphony override: a `voices` file holding one integer
  self._voiceOverride = nil
  local vf = io.open(dir .. "/voices", "r")
  if vf then
    self._voiceOverride = tonumber((vf:read("*a") or ""):match("%d+"))
    vf:close()
  end
  for f in hs.fs.dir(dir) do
    if f:match("%.wav$") or f:match("%.aiff?$") or f:match("%.mp3$") then
      local stem = f:gsub("%.%w+$", ""):gsub("%d+$", "")
      if GENERIC[stem] then
        self._pool[stem] = self._pool[stem] or {}
        table.insert(self._pool[stem], self:_bank(dir .. "/" .. f))
      else
        for kc, want in pairs(KEYFILE) do
          if stem == want then self._pool[kc] = { self:_bank(dir .. "/" .. f) } end
        end
      end
    end
  end
end

-- Ambient beds are single loopable files (not folders). List their basenames
-- across all ambientDirs, de-duped and sorted, so the menu can offer them.
function obj:_beds()
  local seen, out = {}, {}
  for _, dir in ipairs(self.ambientDirs or {}) do
    dir = expand(dir)
    if hs.fs.attributes(dir) then
      for f in hs.fs.dir(dir) do
        local name, ext = f:match("^(.+)%.([^.]+)$")
        if name and not f:match("^[._]")
           and (ext == "wav" or ext == "mp3" or ext:match("^aif") or ext == "m4a")
           and not seen[name] then
          seen[name] = true; out[#out + 1] = name
        end
      end
    end
  end
  table.sort(out)
  return out
end

-- Resolve a bed name to a file path (first ambientDir match wins).
function obj:_bedFile(name)
  for _, dir in ipairs(self.ambientDirs or {}) do
    dir = expand(dir)
    if hs.fs.attributes(dir) then
      for f in hs.fs.dir(dir) do
        if f:match("^(.+)%.[^.]+$") == name then return dir .. "/" .. f end
      end
    end
  end
end

-- Swap the looping background bed. name=nil stops it. hs.sound loops natively,
-- so a bed is one long file played on repeat under everything else — it's fully
-- independent of the keystroke master switch.
function obj:_playBed(name)
  if self._bedSound then self._bedSound:stop(); self._bedSound = nil end
  self._bed = name
  if not name then return end
  local path = self:_bedFile(name)
  if not path then self._bed = nil; return end
  local s = hs.sound.getByFile(path)
  if s then
    s:loopSound(true); s:volume(self._bedVol); s:play()
    self._bedSound = s
  end
end

-- Menu-bar icon: a keyboard drawn as a MONOCHROME TEMPLATE, so macOS recolors
-- it for light/dark automatically. Muted state simply dims the whole icon
-- (lower alpha) — no slash.
local function icon(on)
  local a = on and 1 or 0.3
  local c = hs.canvas.new{ x = 0, y = 0, w = 22, h = 22 }
  c[1] = { type = "rectangle", action = "stroke", strokeWidth = 1.5,
           strokeColor = { white = 0, alpha = a }, roundedRectRadii = { xRadius = 3, yRadius = 3 },
           frame = { x = 2, y = 6, w = 18, h = 11 } }
  local function dot(x) return { type = "rectangle", action = "fill",
    fillColor = { white = 0, alpha = a }, frame = { x = x, y = 9, w = 2.2, h = 2.2 } } end
  c[2] = dot(5); c[3] = dot(9.9); c[4] = dot(14.8)
  c[5] = { type = "rectangle", action = "fill", fillColor = { white = 0, alpha = a },
           frame = { x = 6, y = 13, w = 10, h = 2 } }              -- spacebar
  local img = c:imageFromCanvas(); c:delete()
  return img:template(true)
end

function obj:_refresh()
  if self._menu then self._menu:setIcon(icon(self._on)) end
  if self._tap then
    if self._on then self._tap:start() else self._tap:stop() end
  end
  hs.settings.set("klonk.on", self._on)
  hs.settings.set("klonk.mouse", self._mouse)
  hs.settings.set("klonk.set", self._set)
  hs.settings.set("klonk.vol", self._vol)
  hs.settings.set("klonk.bed", self._bed)
  hs.settings.set("klonk.bedvol", self._bedVol)
end

function obj:_menuItems()
  local items = {
    { title = hs.styledtext.new("klonk", { font = { name = "Menlo-Bold", size = 11 },
        color = { white = 0.5 } }), disabled = true },
    { title = "-" },
    { title = self._on and "Sounds: on" or "Sounds: off",
      fn = function() self._on = not self._on; self:_refresh() end },
    { title = self._mouse and "Mouse clicks: on" or "Mouse clicks: off",
      fn = function() self._mouse = not self._mouse; self:_refresh() end },
    { title = "-" },
  }
  for _, s in ipairs(self:_sets()) do
    items[#items + 1] = { title = s, checked = (s == self._set),
      fn = function() self:_load(s); self:_refresh() end }
  end
  local vol = {}
  for _, v in ipairs(VOLUMES) do
    vol[#vol + 1] = { title = math.floor(v * 100 + 0.5) .. "%",
      checked = (math.abs(v - self._vol) < 0.01),
      fn = function()
        self._vol = v
        for _, pool in pairs(self._pool) do
          for _, bank in ipairs(pool) do
            for _, snd in ipairs(bank.copies) do snd:volume(v) end
          end
        end
        self:_refresh()
      end }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Volume", menu = vol }

  -- Ambient beds: a looping background soundscape under the typing.
  local beds = self:_beds()
  if #beds > 0 then
    local bmenu = { { title = "None", checked = (self._bed == nil),
      fn = function() self:_playBed(nil); self:_refresh() end }, { title = "-" } }
    for _, b in ipairs(beds) do
      bmenu[#bmenu + 1] = { title = b, checked = (b == self._bed),
        fn = function() self:_playBed(b); self:_refresh() end }
    end
    bmenu[#bmenu + 1] = { title = "-" }
    local bvol = {}
    for _, v in ipairs(VOLUMES) do
      bvol[#bvol + 1] = { title = math.floor(v * 100 + 0.5) .. "%",
        checked = (math.abs(v - self._bedVol) < 0.01),
        fn = function()
          self._bedVol = v
          if self._bedSound then self._bedSound:volume(v) end
          self:_refresh()
        end }
    end
    bmenu[#bmenu + 1] = { title = "Bed volume", menu = bvol }
    items[#items + 1] = { title = "Ambient", menu = bmenu }
  end

  items[#items + 1] = { title = "Add sound sets…", fn = function()
    local d = expand("~/.klonk/sounds")
    hs.fs.mkdir(d)
    hs.execute(("open '%s'"):format(d))
  end }
  items[#items + 1] = { title = "a set = folder of WAVs: down1..N, up1..N,",
    disabled = true, indent = 1 }
  items[#items + 1] = { title = "space, enter, backspace; optional click, scroll",
    disabled = true, indent = 1 }
  return items
end

--- Klonk:toggle()
--- Method
--- Toggles all sounds on/off (the master switch).
function obj:toggle()
  self._on = not self._on; self:_refresh(); return self
end

--- Klonk:toggleMouse()
--- Method
--- Toggles mouse-click and scroll sounds on/off, independent of keystrokes.
function obj:toggleMouse()
  self._mouse = not self._mouse; self:_refresh(); return self
end

--- Klonk:cycleSet(step)
--- Method
--- Switches to the next (step 1) or previous (step -1) sound set.
function obj:cycleSet(step)
  local sets = self:_sets()
  if #sets == 0 then return self end
  local i = 1
  for k, s in ipairs(sets) do if s == self._set then i = k end end
  i = ((i - 1 + (step or 1)) % #sets) + 1
  self:_load(sets[i]); self:_refresh()
  hs.alert.show("klonk: " .. sets[i], 0.7)
  return self
end

--- Klonk:init()
--- Method
--- Called automatically by `hs.loadSpoon`. Resolves the default sound dirs.
function obj:init()
  self.soundDirs = self.soundDirs or { hs.spoons.resourcePath("sounds"), "~/.klonk/sounds" }
  self.ambientDirs = self.ambientDirs or { hs.spoons.resourcePath("ambient"), "~/.klonk/ambient" }
  return self
end

--- Klonk:start()
--- Method
--- Installs the menu-bar item and the keystroke listener. Restores your last
--- set / volume / on-state from `hs.settings`.
function obj:start()
  self._on = hs.settings.get("klonk.on"); if self._on == nil then self._on = true end
  self._mouse = hs.settings.get("klonk.mouse"); if self._mouse == nil then self._mouse = true end
  self._vol = hs.settings.get("klonk.vol") or 0.7
  self._set = hs.settings.get("klonk.set") or (self:_sets()[1] or "thock")
  self._bedVol = hs.settings.get("klonk.bedvol") or 0.5

  local et = hs.eventtap.event.types
  local props = hs.eventtap.event.properties

  -- Play a random variant from the FIRST non-empty pool in a fallback chain,
  -- so click → down and scroll → up when a set ships no dedicated mouse WAVs.
  -- Rotate through the chosen variant's voice bank so repeats overlap + decay.
  local function play(...)
    for _, pool in ipairs({ ... }) do
      if pool and #pool > 0 then
        local bank = pool[math.random(#pool)]
        bank.i = bank.i % #bank.copies + 1        -- next voice (round-robin)
        local s = bank.copies[bank.i]
        s:stop(); s:play()                        -- stop() only resets THIS copy
        return
      end
    end
  end

  self._tap = hs.eventtap.new({
    et.keyDown, et.keyUp,
    et.leftMouseDown,  et.leftMouseUp,
    et.rightMouseDown, et.rightMouseUp,
    et.scrollWheel,
  }, function(e)
    local p, t = self._pool, e:getType()
    if t == et.keyDown then
      play(p[e:getKeyCode()], p.down)
    elseif t == et.keyUp then
      play(p.up)
    elseif not self._mouse then
      return false                       -- mouse sounds disabled
    elseif t == et.leftMouseDown then
      play(p.click, p.down)
    elseif t == et.rightMouseDown then
      play(p.rightclick, p.click, p.down)
    elseif t == et.leftMouseUp or t == et.rightMouseUp then
      play(p.clickup, p.up)
    elseif t == et.scrollWheel then
      -- Tick on wheel notches and active trackpad scroll, but stay SILENT during
      -- inertial "momentum" coasting (phase ~= 0). Throttle so a fast two-finger
      -- swipe is a gentle tick-tick, not a roar.
      if e:getProperty(props.scrollWheelEventMomentumPhase) == 0 then
        local now = hs.timer.secondsSinceEpoch()
        if now - self._lastScroll >= SCROLL_GAP then
          self._lastScroll = now
          play(p.scroll, p.up)
        end
      end
    end
    return false        -- observe only; never swallow the event
  end)

  self._menu = hs.menubar.new()
  self._menu:setMenu(function() return self:_menuItems() end)
  self:_load(self._set)
  self:_playBed(hs.settings.get("klonk.bed"))   -- resume last ambient bed, if any
  self:_refresh()
  return self
end

--- Klonk:stop()
--- Method
--- Removes the menu-bar item and stops listening.
function obj:stop()
  if self._tap then self._tap:stop(); self._tap = nil end
  if self._bedSound then self._bedSound:stop(); self._bedSound = nil end
  if self._menu then self._menu:delete(); self._menu = nil end
  return self
end

--- Klonk:bindHotkeys(mapping)
--- Method
--- Binds hotkeys. Keys: `toggle`, `toggleMouse`, `nextSet`, `prevSet`. Example:
--- `spoon.Klonk:bindHotkeys({ toggle = {{"cmd","alt"}, "k"} })`
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({
    toggle      = function() self:toggle() end,
    toggleMouse = function() self:toggleMouse() end,
    nextSet     = function() self:cycleSet(1) end,
    prevSet     = function() self:cycleSet(-1) end,
  }, mapping)
  return self
end

return obj
