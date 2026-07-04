--- === Klonk ===
---
--- Mechanical keystroke sounds for macOS — in any voice you like.
---
--- A "sound set" is just a folder of WAVs, so the built-in synthesized sets,
--- real recorded keyboards, and anything you drop in all play the same way.
--- Every set rings a Return "ding" baked into its own `enter.wav`.
---
--- The menu-bar shows a keyboard icon (dims + slashes when muted). Click it to
--- toggle sound, pick a set, or set the volume. Sets are scanned from the
--- bundled `sounds/` folder plus `~/.klonk/sounds` (your own).
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

-- runtime state (underscore-prefixed → not part of the public API)
obj._menu = nil
obj._tap  = nil
obj._pool = { down = {}, up = {} }
obj._set  = nil
obj._on   = true
obj._vol  = 0.7

-- Which dedicated file plays for which macOS key code.
local KEYFILE = { [49] = "space", [36] = "enter", [51] = "backspace" }
local VOLUMES = { 0.3, 0.5, 0.7, 1.0 }

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
function obj:_load(name)
  self._set = name
  self._pool = { down = {}, up = {} }
  local dir = self:_setDir(name)
  if not dir then return end
  for f in hs.fs.dir(dir) do
    if f:match("%.wav$") or f:match("%.aiff?$") or f:match("%.mp3$") then
      local s = hs.sound.getByFile(dir .. "/" .. f)
      if s then
        s:volume(self._vol)
        local stem = f:gsub("%.%w+$", ""):gsub("%d+$", "")
        if stem == "up" then table.insert(self._pool.up, s)
        elseif stem == "down" then table.insert(self._pool.down, s)
        else
          for kc, want in pairs(KEYFILE) do
            if stem == want then self._pool[kc] = { s } end
          end
        end
      end
    end
  end
end

-- Menu-bar icon: a keyboard drawn as a MONOCHROME TEMPLATE, so macOS recolors
-- it for light/dark automatically. Muted state dims it and adds a slash.
local function icon(on)
  local a = on and 1 or 0.35
  local c = hs.canvas.new{ x = 0, y = 0, w = 22, h = 22 }
  c[1] = { type = "rectangle", action = "stroke", strokeWidth = 1.5,
           strokeColor = { white = 0, alpha = a }, roundedRectRadii = { xRadius = 3, yRadius = 3 },
           frame = { x = 2, y = 6, w = 18, h = 11 } }
  local function dot(x) return { type = "rectangle", action = "fill",
    fillColor = { white = 0, alpha = a }, frame = { x = x, y = 9, w = 2.2, h = 2.2 } } end
  c[2] = dot(5); c[3] = dot(9.9); c[4] = dot(14.8)
  c[5] = { type = "rectangle", action = "fill", fillColor = { white = 0, alpha = a },
           frame = { x = 6, y = 13, w = 10, h = 2 } }              -- spacebar
  if not on then
    c[6] = { type = "segments", action = "stroke", strokeWidth = 1.6,
             strokeColor = { white = 0, alpha = 0.7 }, coordinates = { { x = 3, y = 4 }, { x = 19, y = 19 } } }
  end
  local img = c:imageFromCanvas(); c:delete()
  return img:template(true)
end

function obj:_refresh()
  if self._menu then self._menu:setIcon(icon(self._on)) end
  if self._tap then
    if self._on then self._tap:start() else self._tap:stop() end
  end
  hs.settings.set("klonk.on", self._on)
  hs.settings.set("klonk.set", self._set)
  hs.settings.set("klonk.vol", self._vol)
end

function obj:_menuItems()
  local items = {
    { title = hs.styledtext.new("klonk", { font = { name = "Menlo-Bold", size = 11 },
        color = { white = 0.5 } }), disabled = true },
    { title = "-" },
    { title = self._on and "Sounds: on" or "Sounds: off",
      fn = function() self._on = not self._on; self:_refresh() end },
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
          for _, snd in ipairs(pool) do snd:volume(v) end
        end
        self:_refresh()
      end }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Volume", menu = vol }
  items[#items + 1] = { title = "Add sound sets…", fn = function()
    local d = expand("~/.klonk/sounds")
    hs.fs.mkdir(d)
    hs.execute(("open '%s'"):format(d))
  end }
  items[#items + 1] = { title = "a set = folder of WAVs: down1..N, up1..N,",
    disabled = true, indent = 1 }
  items[#items + 1] = { title = "space, enter, backspace", disabled = true, indent = 1 }
  return items
end

--- Klonk:toggle()
--- Method
--- Toggles keystroke sounds on/off.
function obj:toggle()
  self._on = not self._on; self:_refresh(); return self
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
  return self
end

--- Klonk:start()
--- Method
--- Installs the menu-bar item and the keystroke listener. Restores your last
--- set / volume / on-state from `hs.settings`.
function obj:start()
  self._on = hs.settings.get("klonk.on"); if self._on == nil then self._on = true end
  self._vol = hs.settings.get("klonk.vol") or 0.7
  self._set = hs.settings.get("klonk.set") or (self:_sets()[1] or "thock")

  local et = hs.eventtap.event.types
  self._tap = hs.eventtap.new({ et.keyDown, et.keyUp }, function(e)
    local pool
    if e:getType() == et.keyUp then pool = self._pool.up
    else pool = self._pool[e:getKeyCode()] or self._pool.down end
    local n = #pool
    if n > 0 then
      local s = pool[math.random(n)]
      s:stop(); s:play()
    end
    return false        -- observe only; never swallow the keystroke
  end)

  self._menu = hs.menubar.new()
  self._menu:setMenu(function() return self:_menuItems() end)
  self:_load(self._set)
  self:_refresh()
  return self
end

--- Klonk:stop()
--- Method
--- Removes the menu-bar item and stops listening.
function obj:stop()
  if self._tap then self._tap:stop(); self._tap = nil end
  if self._menu then self._menu:delete(); self._menu = nil end
  return self
end

--- Klonk:bindHotkeys(mapping)
--- Method
--- Binds hotkeys. Keys: `toggle`, `nextSet`, `prevSet`. Example:
--- `spoon.Klonk:bindHotkeys({ toggle = {{"cmd","alt"}, "k"} })`
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({
    toggle  = function() self:toggle() end,
    nextSet = function() self:cycleSet(1) end,
    prevSet = function() self:cycleSet(-1) end,
  }, mapping)
  return self
end

return obj
