--- === Klonk ===
---
--- Desktop ambiance for macOS — mechanical keystroke sounds, ambient sounds, and a
--- looping video desktop, all from one menu-bar icon.
---
--- Three groups share the same "folder is the config" idea: a keyboard sound set
--- is a folder of WAVs, an ambient sound is a loopable audio file, and a video
--- desktop is a clip you drop in (or an Apple Aerial symlinked in for free).
---
--- A "sound set" is just a folder of WAVs, so the built-in synthesized sets,
--- real recorded keyboards, and anything you drop in all play the same way.
--- Every set can give Return its own flourish through `enter.wav`.
---
--- Mouse clicks and scrolling ring too: a click is just a down+up, so every set
--- gets mouse sounds for free from its `down`/`up` pool. A set can also ship
--- dedicated `click` / `clickup` / `rightclick` / `scroll` WAVs to voice the
--- mouse on its own.
---
--- The menu-bar shows a keyboard icon (dims + slashes when muted). Click it to
--- toggle sound, toggle mouse clicks, pick a set, or set the volume. Sets are
--- scanned from the bundled `sounds/` folder plus `~/Music/Klonk/keyboard`.
---
--- Download: https://github.com/giantravens/klonk

local obj = {}
obj.__index = obj

obj.name = "Klonk"
obj.version = "2.4"
obj.author = "Skip Levens"
obj.homepage = "https://github.com/giantravens/klonk"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- Klonk.soundDirs
--- Variable
--- List of directories scanned for sound sets. Set before `:start()` to
--- customize. Defaults to the bundled `sounds/`, unified user library at
--- `~/Music/Klonk/keyboard`, and legacy fallbacks. Earlier directories win.
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
--- List of directories scanned for ambient sounds — single long, loopable audio
--- files (rain, wind, surf, a bridge hum) that play under your typing. Defaults
--- to the bundled `ambient/`, unified user library at `~/Music/Klonk/ambient`,
--- and legacy fallbacks. Each file's basename is an ambient sound's menu name.
obj.ambientDirs = nil

--- Klonk.wallpaperDirs
--- Variable
--- List of directories scanned for video-desktop clips — `.mp4/.mov/.m4v` files
--- that loop behind the desktop icons. Both work: drop your OWN clips in, or let
--- `_syncAerials()` symlink Apple's downloaded Aerials in for free. Defaults to
--- `~/Music/Klonk/livedesktop`. Each file's basename (minus extension) is a
--- pick's menu name. Set before `:start()`.
obj.wallpaperDirs = nil

-- runtime state (underscore-prefixed → not part of the public API)
obj._menu  = nil
obj._tap   = nil
obj._pool  = {}
obj._set   = nil
obj._on    = true
obj._mouse = true
obj._vol   = 0.7
obj._lastScroll = 0
obj._ambient      = nil -- current ambient sound name (nil = none)
obj._ambientSound = nil -- the looping hs.sound object
obj._ambientVol   = 0.5
obj._recentSets = {}
obj._recentAmbient = {}
obj._recentWallpapers = {}
obj._audioMuted = false -- one master mute over keyboard/mouse + ambient audio
obj._wpViews  = {}      -- one webview per screen while a video desktop is active
obj._wpBackdrops = {}   -- persistent black canvases beneath webviews during swaps
obj._wp       = nil     -- current video-desktop clip basename (nil = off)
obj._wpPauseBattery = false
obj._wpSpeed  = 1.0     -- video-desktop playback rate (1.0 = normal, <1 = slow motion)
obj._wpChangeMinutes = 0 -- 0 loops the selected clip; otherwise shuffle on this cadence
obj._wpChangeTimer = nil
obj._wpApplyGeneration = 0 -- invalidates a pending fade/rebuild when state changes again
obj._wpFadeTimer = nil
obj._presenter = false     -- intentionally session-only: never reveal keys after a restart
obj._presenterSpecialOnly = false
obj._presenterHUD = nil
obj._presenterHUDTimer = nil
obj._presenterRenderTimer = nil
obj._presenterKeys = {}
obj._presenterLastKey = 0
obj._presenterFlags = {}
obj._presenterModifierChord = nil
obj._presenterRings = {}
obj._presenterClickQueue = {}
obj._presenterTapWatchTimer = nil
obj._presenterTapRecoveries = 0
obj._eventTapMaxSeconds = 0
obj._eventTapEvents = 0
obj._audioQueue = {}
obj._audioDrainTimer = nil
obj._audioQueueDrops = 0

-- Which dedicated file plays for which macOS key code.
local KEYFILE = { [49] = "space", [36] = "enter", [51] = "backspace" }

-- Generic pools bucketed by filename stem. The keyboard uses down/up; the mouse
-- uses click / clickup / rightclick / scroll — each falling back to a key pool
-- (see the play() chains in :start()), so a set needs zero new files to click.
local GENERIC = { up = true, down = true, click = true, clickup = true,
                  rightclick = true, scroll = true }
local VOLUMES = { 0.3, 0.5, 0.7, 1.0 }
local SET_ALIASES = { clicky = "crystal", manual = "console",
                      paper = "calligraph", water = "splash" }
local SCROLL_GAP = 0.05   -- min seconds between scroll ticks (trackpad throttle)
local RECENT_LIMIT = 5
local STUDIO_LABEL = "com.giantravens.klonk-studio"
local PRESENTER_KEY_GAP = 1.4
local PRESENTER_KEY_LIMIT = 6
local AUDIO_QUEUE_LIMIT = 32

local function expand(p) return (p:gsub("^~", os.getenv("HOME"))) end

local function listContains(items, wanted)
  for _, item in ipairs(items) do if item == wanted then return true end end
  return false
end

local function settingsList(key)
  local value = hs.settings.get(key)
  return type(value) == "table" and value or {}
end

-- Keep a short MRU list for each large media library. Missing files are filtered
-- when the menu is built, so removable/user-edited libraries need no migration.
function obj:_rememberRecent(field, settingsKey, value)
  if not value then return end
  local previous, nextItems = self[field] or {}, { value }
  for _, item in ipairs(previous) do
    if item ~= value and #nextItems < RECENT_LIMIT then nextItems[#nextItems + 1] = item end
  end
  self[field] = nextItems
  hs.settings.set(settingsKey, nextItems)
end

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

-- A set's family comes from an optional one-word `category` file in its folder
-- (same pattern as the `voices` override), written by tools/generate.py — the
-- generator knows what it synthesized — and tools/import_pack.py (recordings
-- of real switches). The menu groups by reading it, so there's no hardcoded
-- name→family map to drift; untagged or unknown sets land in "More sets".
local CATEGORIES = {
  { key = "environment", label = "Environments"          },
  { key = "keyboard",    label = "Recorded keyboards"    },
  { key = "percussive",  label = "Percussive objects"    },
  { key = "mechanical",  label = "Machines & mechanisms" },
  { key = "musical",     label = "Musical instruments"   },
  { key = "themed",      label = "Playful effects"       },
  { key = "other",       label = "More sets"             },
}

function obj:_category(name)
  local dir = self:_setDir(name)
  local f = dir and io.open(dir .. "/category", "r")
  if not f then return "other" end
  local c = ((f:read("*a") or ""):match("%a+") or ""):lower()
  f:close()
  if c == "samples" then c = "keyboard" end -- pre-2.3 compatibility
  for _, cat in ipairs(CATEGORIES) do if cat.key == c then return c end end
  return "other"
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
  self:_rememberRecent("_recentSets", "klonk.recentsets", name)
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

-- Ambient sounds are single loopable files (not folders). List their basenames
-- across all ambientDirs, de-duped and sorted, so the menu can offer them.
function obj:_ambientSounds()
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

-- Resolve an ambient sound name to a file path (first ambientDir match wins).
function obj:_ambientFile(name)
  for _, dir in ipairs(self.ambientDirs or {}) do
    dir = expand(dir)
    if hs.fs.attributes(dir) then
      for f in hs.fs.dir(dir) do
        if f:match("^(.+)%.[^.]+$") == name then return dir .. "/" .. f end
      end
    end
  end
end

-- Swap the looping ambient sound. name=nil stops it. hs.sound loops natively,
-- so the sound plays on repeat under everything else — it's fully
-- independent of the keyboard switch, but covered by the top-level audio mute.
function obj:_playAmbient(name)
  if self._ambientSound then self._ambientSound:stop(); self._ambientSound = nil end
  self._ambient = name
  self:_rememberRecent("_recentAmbient", "klonk.recentambient", name)
  if not name or self._audioMuted then return end
  local path = self:_ambientFile(name)
  if not path then self._ambient = nil; return end
  local s = hs.sound.getByFile(path)
  if s then
    s:loopSound(true); s:volume(self._ambientVol); s:play()
    self._ambientSound = s
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

-- ===========================================================================
-- Video desktop — loop a scenic clip behind the desktop icons. Same "folder is
-- the config" idea as sound sets: drop .mp4/.mov/.m4v into wallpaperDirs[1], OR
-- symlink Apple's downloaded Aerials in via _syncAerials() — the picker scans
-- for both. Rendered in one hs.webview per screen, pinned below the desktop-icon
-- layer, muted and looped. WKWebView only reads siblings of the HTML that loads
-- it, so the wrapper is written INTO the folder and video.src is a RELATIVE
-- basename — which is also why a symlink to a root-owned /Library aerial plays.
-- Codec note: WebKit decodes H.264/HEVC (Apple's SDR aerials are HEVC); ProRes/
-- Sorenson give error.code 4 — transcode with ffmpeg -c:v libx264 first.
-- ===========================================================================
local WP_EXTS     = { mp4 = true, mov = true, m4v = true }
-- playbackRate repeats source frames; it does not synthesize intermediate ones.
-- Preserve the deep-slow choices as intentional ambient textures while making
-- their cadence clear. Motion-interpolated/high-frame-rate sources smooth them.
local WP_SPEEDS   = {
  { rate = 1.0,  title = "Normal" },
  { rate = 0.75, title = "0.75× — Gentle" },
  { rate = 0.5,  title = "0.5× — Calm" },
  { rate = 0.25, title = "0.25× — Dreamy (best with 120 fps source)" },
  { rate = 0.1,  title = "0.1× — Deep drift (stepped)" },
  { rate = 0.05, title = "0.05× — Near-still (slideshow)" },
}
local WP_CHANGE_MINUTES = { 0, 20, 60, 120 }     -- 0 = keep looping the selected clip
local WP_FADE_SECONDS = 0.45                     -- fade old/new frames through black
-- Apple keeps aerials in TWO stores, and which one a clip lands in depends on how
-- you added it: the system SCREENSAVER store (idleassetsd, SDR subdirs) vs. the
-- per-user WALLPAPER store (populated only when you *Activate* an aerial in
-- System Settings ▸ Wallpaper — merely previewing it downloads nothing). Scan both.
local AERIAL_ROOT = "/Library/Application Support/com.apple.idleassetsd/Customer"
local AERIAL_WP   = os.getenv("HOME") .. "/Library/Application Support/com.apple.wallpaper/aerials/videos"

-- Quote a basename as a JS double-quoted string (hs.json.encode rejects bare
-- strings); assigning it to video.src lets the browser resolve spaces/Unicode.
local function jsString(s) return '"' .. s:gsub('[\\"]', '\\%0') .. '"' end

function obj:_wpDir() return expand(self.wallpaperDirs[1]) end

-- Sorted basenames of every video clip in the folder (own drops AND aerial
-- symlinks alike). Called lazily on menu open, so a new drop needs no reload.
function obj:_wallpapers()
  local names, dir = {}, self:_wpDir()
  if hs.fs.attributes(dir) then
    for f in hs.fs.dir(dir) do
      local ext = f:match("%.(%w+)$")
      if ext and WP_EXTS[ext:lower()] then names[#names + 1] = f end
    end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- Symlink whatever Apple Aerials are downloaded (any category — Landscape,
-- Cityscape, Underwater, Earth) into the folder; a symlink into the folder plays
-- even though the target is root-owned /Library. Scans BOTH stores (screensaver +
-- wallpaper). Friendly names come from entries.json (id → accessibilityLabel).
-- SDR only from idleassetsd (skip HDR washout); the wallpaper store is already
-- SDR. Dedups by name, prunes symlinks whose target has vanished. Returns count.
function obj:_syncAerials()
  local dir = self:_wpDir(); hs.fs.mkdir(dir)
  -- Merge id→name from BOTH catalogs: the idleassetsd one and the wallpaper
  -- store's own manifest (newer, names the recently-added aerials the old one
  -- lacks). Wallpaper manifest is read second so it wins on any conflict.
  local names = {}
  for _, ejson in ipairs({
    AERIAL_ROOT .. "/entries.json",
    (AERIAL_WP:gsub("/videos$", "")) .. "/manifest/entries.json",
  }) do
    local fh = io.open(ejson, "r")
    if fh then
      local ok, data = pcall(hs.json.decode, fh:read("a")); fh:close()
      if ok and type(data) == "table" and data.assets then
        for _, a in ipairs(data.assets) do
          if a.id then names[a.id:lower()] = a.accessibilityLabel or a.id end
        end
      end
    end
  end
  -- Collect source dirs: idleassetsd SDR subdirs + the flat wallpaper store.
  local sources = {}
  if hs.fs.attributes(AERIAL_ROOT) then
    for sub in hs.fs.dir(AERIAL_ROOT) do
      local subdir = AERIAL_ROOT .. "/" .. sub
      if sub:find("SDR") and hs.fs.attributes(subdir, "mode") == "directory" then
        sources[#sources + 1] = subdir
      end
    end
  end
  if hs.fs.attributes(AERIAL_WP) then sources[#sources + 1] = AERIAL_WP end

  local linked, seen = 0, {}
  for _, srcdir in ipairs(sources) do
    for f in hs.fs.dir(srcdir) do
      local uuid = f:match("^(.+)%.mov$")
      if uuid then
        local nm   = (names[uuid:lower()] or uuid):gsub("[/:]", "-")
        local base = "Aerial - " .. nm .. ".mov"
        if not seen[base] then                                 -- dedup: same aerial can be in both stores
          seen[base] = true
          local link = dir .. "/" .. base
          os.remove(link)
          if hs.fs.link(srcdir .. "/" .. f, link, true) then linked = linked + 1 end
        end
      end
    end
  end
  -- Prune symlinks that are dangling (target gone) OR stale "Aerial - …" links
  -- not (re)created this run — the latter clears duplicates left behind when an
  -- aerial gains a better name. Real user-dropped files (not symlinks) are kept.
  for f in hs.fs.dir(dir) do
    local p  = dir .. "/" .. f
    local la = hs.fs.symlinkAttributes(p)
    if la and la.mode == "link" then
      if not hs.fs.attributes(p) or (f:match("^Aerial %- ") and not seen[f]) then
        os.remove(p)
      end
    end
  end
  return linked
end

function obj:_writeWallpaperHTML(name)
  local html = table.concat({
    '<!doctype html><html><head><meta charset="utf-8"><style>',
    'html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}',
    'video{position:fixed;inset:0;width:100%;height:100%;object-fit:cover;',
    'opacity:0;transition:opacity ' .. string.format("%.2f", WP_FADE_SECONDS) .. 's ease}',
    'video.ready{opacity:1}',
    '</style></head><body><video autoplay loop muted playsinline></video><script>',
    'var v=document.querySelector("video"), R=' .. string.format("%.4f", self._wpSpeed) .. ';',
    'v.src=' .. jsString(name) .. '; v.muted=true; v.loop=true;',
    'function go(){v.playbackRate=R; var p=v.play();',
    'if(p&&p.then)p.then(function(){requestAnimationFrame(function(){v.classList.add("ready")})})',
    '.catch(function(){});else requestAnimationFrame(function(){v.classList.add("ready")});}',
    'v.addEventListener("canplay",go); go();',
    'v.addEventListener("ended",function(){v.currentTime=0;go();});',
    'document.addEventListener("visibilitychange",function(){if(!document.hidden)go();});',
    '</script></body></html>',
  }, "\n")
  local fh = io.open(self:_wpDir() .. "/.klonk-wallpaper.html", "w")
  if fh then fh:write(html); fh:close() end
end

function obj:_tearDownWallpaperViews()
  for _, w in ipairs(self._wpViews) do w:delete() end
  self._wpViews = {}
end

function obj:_tearDownWallpaper()
  self:_tearDownWallpaperViews()
  for _, c in ipairs(self._wpBackdrops) do c:delete() end
  self._wpBackdrops = {}
end

-- WKWebView's native surface is briefly white before its HTML paints. Keep an
-- ordinary black canvas underneath every view so an unloaded/transparent view,
-- or the gap while views are replaced, can reveal only black.
function obj:_rebuildWallpaperBackdrops()
  local old = self._wpBackdrops
  self._wpBackdrops = {}
  for _, scr in ipairs(hs.screen.allScreens()) do
    local frame = scr:fullFrame()
    local c = hs.canvas.new(frame)
    c[1] = {
      type = "rectangle", action = "fill",
      fillColor = { white = 0, alpha = 1 },
      frame = { x = 0, y = 0, w = frame.w, h = frame.h },
    }
    c:level(hs.canvas.windowLevels.desktopIcon - 2)
    c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    c:show()
    self._wpBackdrops[#self._wpBackdrops + 1] = c
  end
  for _, c in ipairs(old) do c:delete() end
end

function obj:_makeWallpaperView(screen)
  local w = hs.webview.new(screen:fullFrame(), { developerExtrasEnabled = false })
  w:windowStyle(hs.webview.windowMasks.borderless)
  w:transparent(true)                                      -- reveal black canvas until HTML paints
  w:level(hs.canvas.windowLevels.desktopIcon - 1)              -- behind icons, above wallpaper
  w:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  w:allowTextEntry(false)
  return w
end

function obj:_applyWallpaper()
  self._wpApplyGeneration = self._wpApplyGeneration + 1
  if self._wpFadeTimer then self._wpFadeTimer:stop(); self._wpFadeTimer = nil end
  local generation = self._wpApplyGeneration

  local function rebuild()
    if generation ~= self._wpApplyGeneration then return end
    self._wpFadeTimer = nil
    local name = self._wp
    if not name then self:_tearDownWallpaper(); return end
    local dir = self:_wpDir()
    if not hs.fs.attributes(dir .. "/" .. name) then          -- clip vanished
      self._wp = nil; hs.settings.clear("klonk.wallpaper")
      self:_tearDownWallpaper()
      return
    end
    if self._wpPauseBattery and hs.battery.powerSource() == "Battery Power" then
      self:_tearDownWallpaper()
      return
    end
    -- Show the replacement black layer before removing the faded-out views.
    self:_rebuildWallpaperBackdrops()
    self:_tearDownWallpaperViews()
    self:_writeWallpaperHTML(name)
    local htmlURL = "file://" .. dir .. "/.klonk-wallpaper.html"
    for _, scr in ipairs(hs.screen.allScreens()) do
      local w = self:_makeWallpaperView(scr)
      w:url(htmlURL); w:show()
      self._wpViews[#self._wpViews + 1] = w
    end
  end

  if #self._wpViews == 0 then
    rebuild()
  else
    -- The existing webviews stay in place while their videos fade away, so the
    -- page's black background covers the desktop instead of exposing a white
    -- WebKit/loading frame. The replacement fades in only after it can play.
    local js = "var v=document.querySelector('video');if(v){v.classList.remove('ready');}"
    for _, w in ipairs(self._wpViews) do w:evaluateJavaScript(js) end
    self._wpFadeTimer = hs.timer.doAfter(WP_FADE_SECONDS, rebuild)
  end
end

function obj:_setWallpaper(name, keepSchedule)
  self._wp = name
  self:_rememberRecent("_recentWallpapers", "klonk.recentwallpapers", name)
  if name then hs.settings.set("klonk.wallpaper", name) else hs.settings.clear("klonk.wallpaper") end
  self:_applyWallpaper()
  if not keepSchedule then self:_restartWallpaperTimer() end
end

-- Pick a different clip when possible. The selected clip still loops continuously;
-- shuffling only replaces that selection now or on the configured long cadence.
function obj:_shuffleWallpaper()
  local clips = self:_wallpapers()
  if #clips == 0 then return end
  local choices = {}
  for _, name in ipairs(clips) do
    if #clips == 1 or name ~= self._wp then choices[#choices + 1] = name end
  end
  self:_setWallpaper(choices[math.random(#choices)], true)
end

function obj:_restartWallpaperTimer()
  if self._wpChangeTimer then self._wpChangeTimer:stop(); self._wpChangeTimer = nil end
  if self._wp and self._wpChangeMinutes > 0 then
    self._wpChangeTimer = hs.timer.doEvery(self._wpChangeMinutes * 60, function()
      if not (self._wpPauseBattery and hs.battery.powerSource() == "Battery Power") then
        self:_shuffleWallpaper()
      end
    end)
  end
end

function obj:_setWallpaperChangeMinutes(minutes)
  self._wpChangeMinutes = minutes
  hs.settings.set("klonk.wpchangeminutes", minutes)
  if minutes > 0 and not self._wp then self:_shuffleWallpaper() end
  self:_restartWallpaperTimer()
end

-- Change playback rate live on every showing view (no reload/restart) and persist
-- it; _writeWallpaperHTML bakes the same rate in for the next fresh load.
function obj:_setWallpaperSpeed(r)
  self._wpSpeed = r
  hs.settings.set("klonk.wpspeed", r)
  local js = "var v=document.querySelector('video'); if(v){v.playbackRate=" .. string.format("%.4f", r) .. ";}"
  for _, w in ipairs(self._wpViews) do w:evaluateJavaScript(js) end
end

-- ===========================================================================
-- Presenter mode — make an otherwise invisible demonstration legible. It uses
-- the same observe-only event tap as Klonk's sounds, but its lifecycle is
-- independent: muting audio must not blind the visual listener. Presenter mode
-- is deliberately NOT persisted, so a Hammerspoon restart can never resume
-- broadcasting keystrokes unexpectedly.
-- ===========================================================================
local PRESENTER_KEY_NAMES = {
  [36] = "Return", [48] = "Tab", [49] = "Space", [51] = "Delete", [53] = "Esc",
  [71] = "Clear", [76] = "Enter", [115] = "Home", [116] = "Page Up",
  [117] = "Forward Delete", [119] = "End", [121] = "Page Down",
  [123] = "←", [124] = "→", [125] = "↓", [126] = "↑",
}
local PRESENTER_MODIFIERS = {
  { flag = "cmd", symbol = "⌘" },
  { flag = "alt", symbol = "⌥" },
  { flag = "ctrl", symbol = "⌃" },
  { flag = "shift", symbol = "⇧" },
  { flag = "fn", symbol = "fn" },
  { flag = "capslock", symbol = "⇪" },
}

local function presenterModifierPrefix(flags)
  local out = {}
  for _, modifier in ipairs(PRESENTER_MODIFIERS) do
    if flags[modifier.flag] then out[#out + 1] = modifier.symbol end
  end
  return table.concat(out, "+")
end

local function presenterKey(event)
  local keyCode = event:getKeyCode()
  local flags = event:getFlags()
  local named = PRESENTER_KEY_NAMES[keyCode]
  local characters = event:getCharacters(true)
  local name = named
  if not name and characters and characters ~= "" then name = characters end
  if not name then name = hs.keycodes.map[keyCode] end
  if not name or name == "" then
    name = "Key " .. tostring(keyCode)
  end
  local prefix = presenterModifierPrefix(flags)
  local label = prefix ~= "" and (prefix .. "+" .. name) or name
  local shortcut = flags.cmd or flags.ctrl or flags.alt or flags.fn
  local functionKey = type(name) == "string" and name:lower():match("^f%d+$") ~= nil
  local special = shortcut or functionKey or (named ~= nil and keyCode ~= 49)
  return label, special, name, prefix
end

function obj:_deletePresenterHUD()
  if self._presenterRenderTimer then self._presenterRenderTimer:stop(); self._presenterRenderTimer = nil end
  if self._presenterHUDTimer then self._presenterHUDTimer:stop(); self._presenterHUDTimer = nil end
  if self._presenterHUD then self._presenterHUD:delete(); self._presenterHUD = nil end
end

function obj:_showPresenterKey(label, replaceLast)
  local now = hs.timer.secondsSinceEpoch()
  if now - self._presenterLastKey > PRESENTER_KEY_GAP then self._presenterKeys = {} end
  self._presenterLastKey = now
  if replaceLast and #self._presenterKeys > 0 then
    table.remove(self._presenterKeys)
  end
  self._presenterKeys[#self._presenterKeys + 1] = label
  while #self._presenterKeys > PRESENTER_KEY_LIMIT do table.remove(self._presenterKeys, 1) end

  -- CGEventTap callbacks have a strict latency budget. Coalesce all text
  -- measurement and canvas work onto the next run-loop tick so a burst of
  -- physical keyDown events only mutates these small Lua tables synchronously.
  if not self._presenterRenderTimer then
    self._presenterRenderTimer = hs.timer.doAfter(0, function()
      self._presenterRenderTimer = nil
      self:_renderPresenterHUD()
    end)
  end
end

function obj:_renderPresenterHUD()
  if self._presenterHUDTimer then self._presenterHUDTimer:stop(); self._presenterHUDTimer = nil end
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  if not screen then return end
  local sf = screen:frame()
  local text = table.concat(self._presenterKeys, "   ")
  local measured = hs.drawing.getTextDrawingSize(text, {
    font = "SFMono-Semibold", size = 25,
  })
  local width = math.max(150, math.min((measured and measured.w or 420) + 48, 560, sf.w - 80))
  local frame = {
    x = sf.x + (sf.w - width) / 2,
    y = sf.y + (sf.h - 64) / 2,
    w = width, h = 64,
  }
  local canvas = self._presenterHUD
  if canvas then canvas:frame(frame) else canvas = hs.canvas.new(frame) end
  canvas[1] = {
    type = "rectangle", action = "fill",
    fillColor = { white = 0.05, alpha = 0.88 },
    roundedRectRadii = { xRadius = 15, yRadius = 15 },
    frame = { x = 0, y = 0, w = frame.w, h = frame.h },
  }
  canvas[2] = {
    type = "text", text = text,
    textAlignment = "center",
    textColor = { white = 1, alpha = 1 },
    textFont = "SFMono-Semibold", textSize = 25,
    frame = { x = 18, y = 15, w = frame.w - 36, h = 38 },
  }
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "transient" })
  canvas:show(0.08)
  self._presenterHUD = canvas
  self._presenterHUDTimer = hs.timer.doAfter(PRESENTER_KEY_GAP, function()
    self:_deletePresenterHUD()
    self._presenterKeys = {}
  end)
end

function obj:_presenterKeyDown(event, isRepeat)
  if isRepeat then return end
  local label, special = presenterKey(event)
  if self._presenterSpecialOnly and not special then return end
  local replaceModifier = self._presenterModifierChord ~= nil
    and self._presenterKeys[#self._presenterKeys] == self._presenterModifierChord
  self:_showPresenterKey(label, replaceModifier)
  if replaceModifier then self._presenterModifierChord = nil end
end

local function presenterModifierCount(flags)
  local count = 0
  for _, modifier in ipairs(PRESENTER_MODIFIERS) do
    if flags[modifier.flag] then count = count + 1 end
  end
  return count
end

function obj:_presenterFlagsChanged(event)
  local flags = event:getFlags()
  local oldCount = presenterModifierCount(self._presenterFlags)
  local newCount = presenterModifierCount(flags)
  if newCount > oldCount then
    local chord = presenterModifierPrefix(flags)
    local replace = self._presenterModifierChord ~= nil
      and self._presenterKeys[#self._presenterKeys] == self._presenterModifierChord
    self:_showPresenterKey(chord, replace)
    self._presenterModifierChord = chord
  elseif newCount < oldCount then
    -- A release closes this chord. A later modifier-down begins a new history
    -- element instead of rewriting the chord that was already demonstrated.
    self._presenterModifierChord = nil
  end
  self._presenterFlags = flags
end

function obj:_showPresenterClick(point, rightClick)
  local size = 96
  local canvas = hs.canvas.new({
    x = point.x - size / 2, y = point.y - size / 2, w = size, h = size,
  })
  canvas[1] = {
    type = "oval", action = "stroke",
    strokeColor = { white = 0.35, alpha = 0.82 },
    strokeWidth = 5,
    frame = { x = 12, y = 12, w = size - 24, h = size - 24 },
  }
  if rightClick then
    canvas[2] = {
      type = "oval", action = "fill",
      fillColor = { white = 0.35, alpha = 0.95 },
      frame = { x = 64, y = 6, w = 26, h = 26 },
    }
    canvas[3] = {
      type = "text", text = "R", textAlignment = "center",
      textColor = { white = 1, alpha = 1 },
      textFont = "Menlo-Bold", textSize = 14,
      frame = { x = 64, y = 9, w = 26, h = 20 },
    }
  end
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "transient" })
  canvas:show()
  canvas:hide(0.42)
  local timer = hs.timer.doAfter(0.45, function()
    if self._presenterRings[canvas] then
      self._presenterRings[canvas] = nil
      canvas:delete()
    end
  end)
  self._presenterRings[canvas] = timer
end

function obj:_queuePresenterClick(point, rightClick)
  local timer
  timer = hs.timer.doAfter(0, function()
    self._presenterClickQueue[timer] = nil
    if self._presenter then self:_showPresenterClick(point, rightClick) end
  end)
  self._presenterClickQueue[timer] = true
end

function obj:_updatePresenterTapWatch()
  if self._presenter and not self._presenterTapWatchTimer then
    self._presenterTapWatchTimer = hs.timer.doEvery(0.25, function()
      if self._presenter and self._tap and not self._tap:isEnabled() then
        self._presenterTapRecoveries = self._presenterTapRecoveries + 1
        hs.printf("klonk presenter: event tap disabled; recovery #%d",
          self._presenterTapRecoveries)
        self._tap:start()
      end
    end)
  elseif not self._presenter and self._presenterTapWatchTimer then
    self._presenterTapWatchTimer:stop()
    self._presenterTapWatchTimer = nil
  end
end

function obj:_tearDownPresenter()
  self:_deletePresenterHUD()
  self._presenterKeys = {}
  self._presenterFlags = {}
  self._presenterModifierChord = nil
  for canvas, timer in pairs(self._presenterRings) do
    timer:stop()
    canvas:delete()
  end
  self._presenterRings = {}
  for timer in pairs(self._presenterClickQueue) do timer:stop() end
  self._presenterClickQueue = {}
end

function obj:_refresh()
  if self._menu then self._menu:setIcon(icon(not self._audioMuted and self._on)) end
  if self._tap then
    local audioListening = self._on and not self._audioMuted
    if audioListening or self._presenter then self._tap:start() else self._tap:stop() end
  end
  self:_updatePresenterTapWatch()
  hs.settings.set("klonk.audiomuted", self._audioMuted)
  hs.settings.set("klonk.on", self._on)
  hs.settings.set("klonk.mouse", self._mouse)
  hs.settings.set("klonk.set", self._set)
  hs.settings.set("klonk.vol", self._vol)
  hs.settings.set("klonk.ambient", self._ambient)
  hs.settings.set("klonk.ambientvol", self._ambientVol)
end

local function pickerRows(names, current, titleFor, onPick)
  local rows = {}
  for _, name in ipairs(names) do
    local selected = name
    rows[#rows + 1] = {
      title = titleFor and titleFor(selected) or selected,
      checked = (selected == current),
      fn = function() onPick(selected) end,
    }
  end
  return rows
end

local function availableRecents(recent, available)
  local rows = {}
  for _, name in ipairs(recent or {}) do
    if listContains(available, name) then rows[#rows + 1] = name end
  end
  return rows
end

local function clipTitle(name)
  return name:gsub("^Aerial %- ", ""):gsub("%.%w+$", "")
end

function obj:_ambientSource(name)
  local path = self:_ambientFile(name)
  if not path then return "legacy" end
  for i, dir in ipairs(self.ambientDirs or {}) do
    local root = expand(dir) .. "/"
    if path:sub(1, #root) == root then
      if i == 1 then return "bundled" end
      if i == 2 then return "personal" end
      return "legacy"
    end
  end
  return "legacy"
end

function obj:_studioScriptPath()
  return hs.fs.pathToAbsolute(hs.spoons.resourcePath("../tools/studio.py"))
end

local function pythonPath()
  for _, path in ipairs({
    "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3",
  }) do
    if hs.fs.attributes(path) then return path end
  end
end

local function shellQuote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Studio is the deliberate browse/audition surface; the menu remains the fast
-- controller. Start its stdlib-only localhost server on demand and wait until it
-- answers before opening the browser.
function obj:_openStudio()
  local url, health = "http://127.0.0.1:8801", "http://127.0.0.1:8801/api/state"
  local function openWhenReady(attempt)
    hs.http.asyncGet(health, nil, function(status)
      if status == 200 then
        hs.urlevent.openURL(url)
      elseif attempt < 12 then
        hs.timer.doAfter(0.2, function() openWhenReady(attempt + 1) end)
      else
        hs.alert.show("Klonk Studio did not start — see the Hammerspoon Console")
      end
    end)
  end
  hs.http.asyncGet(health, nil, function(status)
    if status == 200 then hs.urlevent.openURL(url); return end
    local script = self:_studioScriptPath()
    if not script or not hs.fs.attributes(script) then
      hs.alert.show("Klonk Studio is unavailable — tools/studio.py was not found")
      return
    end
    local python = pythonPath()
    if not python then
      hs.alert.show("Klonk Studio needs Python 3")
      return
    end
    self._studioLastError = nil

    -- Clear a stale submitted job before creating the on-demand server. A
    -- launchd-hosted process belongs to the GUI bootstrap session, so Studio's
    -- hs CLI can call back into Hammerspoon; a direct hs.task child cannot.
    hs.execute("/bin/launchctl remove " .. shellQuote(STUDIO_LABEL) .. " >/dev/null 2>&1")
    local command = table.concat({
      "/bin/launchctl submit -l", shellQuote(STUDIO_LABEL),
      "-p", shellQuote(python),
      "-o /tmp/klonk-studio.out -e /tmp/klonk-studio.err --",
      shellQuote(python), shellQuote(script), "--port 8801",
    }, " ")
    local output, ok, reason, code = hs.execute(command)
    self._studioLaunchTelemetry = {
      ok = ok and true or false, reason = reason, code = code, output = output,
    }
    if not ok then
      self._studioLastError = ("launchctl %s %s: %s"):format(
        tostring(reason), tostring(code), output or "")
      hs.printf("klonk studio launch failed: %s", self._studioLastError)
      hs.alert.show("Klonk Studio could not be launched")
      return
    end
    openWhenReady(1)
  end)
end

function obj:_menuItems()
  -- ---- Shared volume controls ---------------------------------------------
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

  -- ---- Keyboard sounds ----------------------------------------------------
  local sets, groupedSets = self:_sets(), {}
  for _, s in ipairs(self:_sets()) do
    local category = self:_category(s)
    groupedSets[category] = groupedSets[category] or {}
    groupedSets[category][#groupedSets[category] + 1] = s
  end
  local browseSets = {}
  for _, category in ipairs(CATEGORIES) do
    local names = groupedSets[category.key]
    if names then
      browseSets[#browseSets + 1] = {
        title = category.label,
        checked = listContains(names, self._set),
        menu = pickerRows(names, self._set, nil, function(name)
          self:_load(name); self:_refresh()
        end),
      }
    end
  end
  local kbControls = {
    { title = self._mouse and "Turn mouse clicks off" or "Turn mouse clicks on",
      fn = function() self._mouse = not self._mouse; self:_refresh() end },
    { title = "Volume", menu = vol },
  }
  local kbLibrary = {
    { title = "Add sound sets…", fn = function()
      local d = expand("~/Music/Klonk/keyboard"); hs.fs.mkdir(d); hs.execute(("open '%s'"):format(d))
    end },
    { title = "Get recorded keyboard sounds…", fn = function()
      hs.urlevent.openURL("https://github.com/giantravens/klonk#real-recorded-keyboards")
    end },
    { title = "a set = folder of WAVs: down1..N, up1..N,", disabled = true, indent = 1 },
    { title = "space, enter, backspace; optional click, scroll", disabled = true, indent = 1 },
  }
  local kb = {
    { title = "Current — " .. tostring(self._set), disabled = true },
    { title = self._on and "Turn keyboard sounds off" or "Turn keyboard sounds on",
      fn = function() self._on = not self._on; self:_refresh() end },
  }
  local recentSets = availableRecents(self._recentSets, sets)
  if #recentSets > 0 then
    kb[#kb + 1] = { title = "Recent", menu = pickerRows(recentSets, self._set, nil, function(name)
      self:_load(name); self:_refresh()
    end) }
  end
  kb[#kb + 1] = { title = "Browse all", menu = browseSets }
  kb[#kb + 1] = { title = "Controls", menu = kbControls }
  kb[#kb + 1] = { title = "Library", menu = kbLibrary }

  -- ---- Ambient sounds -----------------------------------------------------
  local ambientVolumes = {}
  for _, v in ipairs(VOLUMES) do
    ambientVolumes[#ambientVolumes + 1] = { title = math.floor(v * 100 + 0.5) .. "%",
      checked = (math.abs(v - self._ambientVol) < 0.01),
      fn = function()
        self._ambientVol = v
        if self._ambientSound then self._ambientSound:volume(v) end
        self:_refresh()
      end }
  end
  local ambientNames = self:_ambientSounds()
  local ambientGroups = { bundled = {}, personal = {}, legacy = {} }
  for _, name in ipairs(ambientNames) do
    local source = self:_ambientSource(name)
    ambientGroups[source][#ambientGroups[source] + 1] = name
  end
  local browseAmbient = {}
  for _, source in ipairs({
    { key = "bundled", title = "Included with Klonk" },
    { key = "personal", title = "My Library" },
    { key = "legacy", title = "Legacy folders" },
  }) do
    local names = ambientGroups[source.key]
    if #names > 0 then
      browseAmbient[#browseAmbient + 1] = {
        title = source.title,
        checked = self._ambient and listContains(names, self._ambient) or false,
        menu = pickerRows(names, self._ambient, nil, function(name)
          self:_playAmbient(name); self:_refresh()
        end),
      }
    end
  end
  local amb = {
    { title = "Current — " .. (self._ambient or "Off"), disabled = true },
    { title = "Off", checked = (self._ambient == nil),
      fn = function() self:_playAmbient(nil); self:_refresh() end },
  }
  local recentAmbient = availableRecents(self._recentAmbient, ambientNames)
  if #recentAmbient > 0 then
    amb[#amb + 1] = { title = "Recent",
      menu = pickerRows(recentAmbient, self._ambient, nil, function(name)
        self:_playAmbient(name); self:_refresh()
      end) }
  end
  amb[#amb + 1] = { title = "Browse all", menu = browseAmbient }
  amb[#amb + 1] = { title = "Controls", menu = {
    { title = "Volume", menu = ambientVolumes },
  } }
  amb[#amb + 1] = { title = "Library", menu = {
    { title = "Add ambient sounds…", fn = function()
      local d = expand("~/Music/Klonk/ambient"); hs.fs.mkdir(d); hs.execute(("open '%s'"):format(d))
    end },
  } }

  -- ---- Video desktop ------------------------------------------------------
  local spd = {}
  for _, option in ipairs(WP_SPEEDS) do
    local rate = option.rate
    spd[#spd + 1] = { title = option.title,
      checked = (math.abs(rate - self._wpSpeed) < 0.001),
      fn = function() self:_setWallpaperSpeed(rate) end }
  end
  local cadence = {}
  for _, minutes in ipairs(WP_CHANGE_MINUTES) do
    cadence[#cadence + 1] = {
      title = minutes == 0 and "Never — loop selected" or ("Every " .. minutes .. " minutes"),
      checked = (minutes == self._wpChangeMinutes),
      fn = function() self:_setWallpaperChangeMinutes(minutes) end,
    }
  end
  local clips = self:_wallpapers()
  local videoGroups = { aerials = {}, personal = {} }
  for _, name in ipairs(clips) do
    local group = name:match("^Aerial %- ") and "aerials" or "personal"
    videoGroups[group][#videoGroups[group] + 1] = name
  end
  local browseVideo = {}
  for _, source in ipairs({
    { key = "aerials", title = "Apple Aerials" },
    { key = "personal", title = "My Clips" },
  }) do
    local names = videoGroups[source.key]
    if #names > 0 then
      browseVideo[#browseVideo + 1] = {
        title = source.title,
        checked = self._wp and listContains(names, self._wp) or false,
        menu = pickerRows(names, self._wp, clipTitle, function(name) self:_setWallpaper(name) end),
      }
    end
  end
  local vid = {
    { title = "Current — " .. (self._wp and clipTitle(self._wp) or "Off"), disabled = true },
    { title = "Off", checked = (self._wp == nil),
      fn = function() self:_setWallpaper(nil) end },
    { title = "Shuffle now", disabled = (#clips == 0), fn = function() self:_shuffleWallpaper() end },
  }
  local recentVideos = availableRecents(self._recentWallpapers, clips)
  if #recentVideos > 0 then
    vid[#vid + 1] = { title = "Recent",
      menu = pickerRows(recentVideos, self._wp, clipTitle, function(name) self:_setWallpaper(name) end) }
  end
  vid[#vid + 1] = { title = "Browse all", disabled = (#clips == 0), menu = browseVideo }
  vid[#vid + 1] = { title = "Playback", menu = {
    { title = "Speed", menu = spd, checked = (self._wpSpeed ~= 1.0) },
    { title = "Change desktop", menu = cadence, checked = (self._wpChangeMinutes > 0) },
    { title = "Pause on battery", checked = self._wpPauseBattery,
      fn = function()
        self._wpPauseBattery = not self._wpPauseBattery
        hs.settings.set("klonk.wppausebattery", self._wpPauseBattery)
        self:_applyWallpaper()
      end },
  } }
  local videoLibrary = {
    { title = "Sync Apple aerials now", fn = function()
      local n = self:_syncAerials()
      hs.alert.show(n > 0
        and ("Linked " .. n .. " Apple aerial" .. (n == 1 and "" or "s") .. " — reopen this menu")
        or  "No aerials downloaded — add them in System Settings ▸ Wallpaper, then sync")
    end },
    { title = "Add your own clips…", fn = function()
      local d = self:_wpDir(); hs.fs.mkdir(d); hs.execute(("open '%s'"):format(d))
    end },
  }
  if #clips == 0 then
    videoLibrary[#videoLibrary + 1] = {
      title = "No clips yet — add .mp4/.mov, or sync aerials above", disabled = true
    }
  end
  vid[#vid + 1] = { title = "Library", menu = videoLibrary }

  local presenter = {
    { title = self._presenter and "Stop" or "Start",
      fn = function() self:togglePresenter() end },
    { title = "Keys shown", menu = {
      { title = "All keys", checked = not self._presenterSpecialOnly,
        fn = function() self:_setPresenterSpecialOnly(false) end },
      { title = "Special keys only", checked = self._presenterSpecialOnly,
        fn = function() self:_setPresenterSpecialOnly(true) end },
    } },
  }

  -- ---- Top level: experience groups and session utilities ------------------
  return {
    { title = hs.styledtext.new("klonk", { font = { name = "Menlo-Bold", size = 11 },
        color = { white = 0.5 } }), disabled = true },
    { title = "-" },
    { title = self._audioMuted and "All sounds on" or "All sounds off",
      fn = function() self:_setAudioMuted(not self._audioMuted) end },
    { title = "-" },
    { title = "Keyboard sounds", menu = kb,  checked = self._on },
    { title = "Ambient sounds",  menu = amb, checked = (self._ambient ~= nil) },
    { title = "Video desktop",   menu = vid, checked = (self._wp ~= nil) },
    { title = "-" },
    { title = "Presenter mode", menu = presenter, checked = self._presenter },
    { title = "Open Klonk Studio…", fn = function() self:_openStudio() end },
  }
end

--- Klonk:toggle()
--- Method
--- Toggles all sounds on/off (the master switch).
function obj:toggle()
  self:_setAudioMuted(not self._audioMuted); return self
end

function obj:_setAudioMuted(muted)
  self._audioMuted = muted
  if muted then
    if self._ambientSound then self._ambientSound:stop(); self._ambientSound = nil end
  elseif self._ambient then
    self:_playAmbient(self._ambient)
  end
  self:_refresh()
end

--- Klonk:toggleMouse()
--- Method
--- Toggles mouse-click and scroll sounds on/off, independent of keystrokes.
function obj:toggleMouse()
  self._mouse = not self._mouse; self:_refresh(); return self
end

--- Klonk:togglePresenter()
--- Method
--- Toggles the session-only keystroke HUD and click highlights.
function obj:togglePresenter()
  self._presenter = not self._presenter
  if not self._presenter then self:_tearDownPresenter() end
  self:_refresh()
  if self._presenter and hs.eventtap.isSecureInputEnabled() then
    hs.alert.show("Presenter mode on — secure input is active, so keys may stay hidden")
  else
    hs.alert.show("Presenter mode " .. (self._presenter and "on" or "off"), 0.8)
  end
  return self
end

function obj:_setPresenterSpecialOnly(specialOnly)
  self._presenterSpecialOnly = specialOnly
  hs.settings.set("klonk.presenterspecialonly", specialOnly)
  self:_deletePresenterHUD()
  self._presenterKeys = {}
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
  self.soundDirs = self.soundDirs or {
    hs.spoons.resourcePath("sounds"), "~/Music/Klonk/keyboard",
    "~/Music/Klonk/Sounds", "~/.klonk/sounds"
  }
  self.ambientDirs = self.ambientDirs or {
    hs.spoons.resourcePath("ambient"), "~/Music/Klonk/ambient",
    "~/Music/Klonk/Ambience", "~/.klonk/ambient"
  }
  self.wallpaperDirs = self.wallpaperDirs or { "~/Music/Klonk/livedesktop" }
  return self
end

--- Klonk:start()
--- Method
--- Installs the menu-bar item and the keystroke listener. Restores your last
--- set / volume / on-state from `hs.settings`.
function obj:start()
  self._audioMuted = hs.settings.get("klonk.audiomuted") or false
  self._on = hs.settings.get("klonk.on"); if self._on == nil then self._on = true end
  self._mouse = hs.settings.get("klonk.mouse"); if self._mouse == nil then self._mouse = true end
  self._vol = hs.settings.get("klonk.vol") or 0.7
  self._recentSets = settingsList("klonk.recentsets")
  self._recentAmbient = settingsList("klonk.recentambient")
  self._recentWallpapers = settingsList("klonk.recentwallpapers")
  local savedSet = hs.settings.get("klonk.set")
  local selected = SET_ALIASES[savedSet] or savedSet
  self._set = selected and self:_setDir(selected) and selected or (self:_sets()[1] or "thock")
  -- Read the pre-2.2 keys once so existing selections survive the terminology
  -- migration; all subsequent writes use the new ambient keys above.
  self._ambientVol = hs.settings.get("klonk.ambientvol") or hs.settings.get("klonk.bedvol") or 0.5
  self._presenter = false
  self._presenterSpecialOnly = hs.settings.get("klonk.presenterspecialonly") or false

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

  -- Never perform NSSound stop/play inside the CGEventTap callback: that
  -- callback gates delivery to the foreground app. Queue compact pool chains
  -- and drain them on the next run-loop turn instead.
  local function queuePlay(...)
    if #self._audioQueue >= AUDIO_QUEUE_LIMIT then
      table.remove(self._audioQueue, 1)
      self._audioQueueDrops = self._audioQueueDrops + 1
    end
    self._audioQueue[#self._audioQueue + 1] = { ... }
    if not self._audioDrainTimer then
      self._audioDrainTimer = hs.timer.doAfter(0, function()
        self._audioDrainTimer = nil
        local pending = self._audioQueue
        self._audioQueue = {}
        for _, chain in ipairs(pending) do play(table.unpack(chain)) end
      end)
    end
  end

  self._tap = hs.eventtap.new({
    et.keyDown, et.keyUp, et.flagsChanged,
    et.leftMouseDown,  et.leftMouseUp,
    et.rightMouseDown, et.rightMouseUp,
    et.scrollWheel,
  }, function(e)
    local callbackStarted = hs.timer.secondsSinceEpoch()
    local p, t = self._pool, e:getType()
    local audioListening = self._on and not self._audioMuted

    if t == et.keyDown then
      local isRepeat = e:getProperty(props.keyboardEventAutorepeat) == 1
      if self._presenter then self:_presenterKeyDown(e, isRepeat) end
      if audioListening then queuePlay(p[e:getKeyCode()], p.down) end
    elseif t == et.keyUp then
      if audioListening then queuePlay(p.up) end
    elseif t == et.flagsChanged then
      if self._presenter then self:_presenterFlagsChanged(e) end
    elseif t == et.leftMouseDown then
      if self._presenter then self:_queuePresenterClick(e:location(), false) end
      if audioListening and self._mouse then queuePlay(p.click, p.down) end
    elseif t == et.rightMouseDown then
      if self._presenter then self:_queuePresenterClick(e:location(), true) end
      if audioListening and self._mouse then queuePlay(p.rightclick, p.click, p.down) end
    elseif t == et.leftMouseUp or t == et.rightMouseUp then
      if audioListening and self._mouse then queuePlay(p.clickup, p.up) end
    elseif t == et.scrollWheel and audioListening and self._mouse then
      -- Tick on wheel notches and active trackpad scroll, but stay SILENT during
      -- inertial "momentum" coasting (phase ~= 0). Throttle so a fast two-finger
      -- swipe is a gentle tick-tick, not a roar.
      if e:getProperty(props.scrollWheelEventMomentumPhase) == 0 then
        local now = hs.timer.secondsSinceEpoch()
        if now - self._lastScroll >= SCROLL_GAP then
          self._lastScroll = now
          queuePlay(p.scroll, p.up)
        end
      end
    end
    local elapsed = hs.timer.secondsSinceEpoch() - callbackStarted
    self._eventTapEvents = self._eventTapEvents + 1
    if elapsed > self._eventTapMaxSeconds then self._eventTapMaxSeconds = elapsed end
    return false        -- observe only; never swallow the event
  end)

  self._menu = hs.menubar.new()
  self._menu:setMenu(function() return self:_menuItems() end)
  self:_load(self._set)
  self:_playAmbient(hs.settings.get("klonk.ambient") or hs.settings.get("klonk.bed"))

  -- Video desktop: restore last pick, keep Apple aerials linked, and re-render
  -- on screen-layout / battery changes so the clip tracks the live geometry.
  self._wpPauseBattery = hs.settings.get("klonk.wppausebattery") or false
  self._wpSpeed = hs.settings.get("klonk.wpspeed") or 1.0
  self._wpChangeMinutes = hs.settings.get("klonk.wpchangeminutes") or 0
  self._wp = hs.settings.get("klonk.wallpaper")
  self:_rememberRecent("_recentWallpapers", "klonk.recentwallpapers", self._wp)
  self:_syncAerials()
  self._wpScreen = self._wpScreen or hs.screen.watcher.new(function() self:_applyWallpaper() end):start()
  self._wpBattery = self._wpBattery or hs.battery.watcher.new(function()
    if self._wpPauseBattery then self:_applyWallpaper() end
  end):start()
  self:_applyWallpaper()
  self:_restartWallpaperTimer()

  self:_refresh()
  return self
end

--- Klonk:stop()
--- Method
--- Removes the menu-bar item and stops listening.
function obj:stop()
  if self._tap then self._tap:stop(); self._tap = nil end
  if self._audioDrainTimer then self._audioDrainTimer:stop(); self._audioDrainTimer = nil end
  self._audioQueue = {}
  self._presenter = false
  self:_tearDownPresenter()
  if self._presenterTapWatchTimer then
    self._presenterTapWatchTimer:stop()
    self._presenterTapWatchTimer = nil
  end
  if self._ambientSound then self._ambientSound:stop(); self._ambientSound = nil end
  if self._wpChangeTimer then self._wpChangeTimer:stop(); self._wpChangeTimer = nil end
  self._wpApplyGeneration = self._wpApplyGeneration + 1
  if self._wpFadeTimer then self._wpFadeTimer:stop(); self._wpFadeTimer = nil end
  hs.execute("/bin/launchctl remove " .. STUDIO_LABEL)
  self:_tearDownWallpaper()
  if self._wpScreen then self._wpScreen:stop(); self._wpScreen = nil end
  if self._wpBattery then self._wpBattery:stop(); self._wpBattery = nil end
  if self._menu then self._menu:delete(); self._menu = nil end
  return self
end

--- Klonk:bindHotkeys(mapping)
--- Method
--- Binds hotkeys. Keys: `toggle`, `toggleMouse`, `togglePresenter`, `nextSet`,
--- `prevSet`. Example:
--- `spoon.Klonk:bindHotkeys({ toggle = {{"cmd","alt"}, "k"} })`
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({
    toggle      = function() self:toggle() end,
    toggleMouse = function() self:toggleMouse() end,
    togglePresenter = function() self:togglePresenter() end,
    nextSet     = function() self:cycleSet(1) end,
    prevSet     = function() self:cycleSet(-1) end,
  }, mapping)
  return self
end

return obj
