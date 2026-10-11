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
--- The menu bar shows a keyboard icon (dims when muted). Open Settings for
--- sound choices, volumes, and desktop controls. Sets are
--- scanned from the bundled `sounds/` folder plus `~/Music/Klonk/keyboard`.
---
--- Download: https://github.com/giantravens/klonk

local obj = {}
obj.__index = obj

obj.name = "Klonk"
obj.version = "2.5"
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
--- `_syncAerials()` symlink Apple's downloaded Aerials in for free, or download a
--- whole Aerial collection (Settings ▸ Tools). Defaults to
--- `~/Music/Klonk/livedesktop`. Each file's basename (minus extension) is a
--- pick's menu name. Set before `:start()`.
obj.wallpaperDirs = nil

-- runtime state (underscore-prefixed → not part of the public API)
obj._menu  = nil
obj._tap   = nil
obj._pool  = {}
obj._set   = nil
obj._on    = true
obj._keys  = true -- keystroke sounds (the card switch gates keys, clicks, and scroll)
obj._mouse = true -- click sounds
obj._clickSet = nil -- set that voices clicks and scroll; nil = same as keys
obj._mousePool = nil -- that set's pools when it differs from the key set
obj._scroll = true
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
obj._tapWatchTimer = nil
obj._tapRecoveries = 0 -- times the watchdog re-enabled a tap macOS had disabled
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
-- Renamed sets keep saved selections and recents. Retired sets (console,
-- crystal) have no successor and fall back to the first available set.
local SET_ALIASES = { paper = "scratchy-quill", calligraph = "scratchy-quill",
                      water = "splash", pingpong = "ping-pong", jazzy = "jazz-piano",
                      ["war-chant"] = "the-quest", lcars = "star-voyage" }
-- Sound sets as Settings, the menu and alerts show them: { folder, name, a few words }.
-- Edit names and descriptions freely, and reorder lines: within each category (see
-- CATEGORIES below for their order) the list follows this order; sets not listed here
-- come after, alphabetically, under their folder name. The folder name is the set's
-- identity, so renaming here never breaks saved choices, recents, or performer pages.
local SET_LIST = {
  -- Recorded keyboards (press and release recordings)
  { "cherrymx-black-abs",      "Cherry MX Black, ABS",     "heavy linear, deep and smooth" },
  { "cherrymx-black-pbt",      "Cherry MX Black, PBT",     "heavy linear, drier PBT caps" },
  { "cherrymx-red-abs",        "Cherry MX Red, ABS",       "light linear, quick and soft" },
  { "cherrymx-brown-abs",      "Cherry MX Brown, ABS",     "tactile bump, no click" },
  { "cherrymx-brown-pbt",      "Cherry MX Brown, PBT",     "tactile bump, PBT caps" },
  { "browns",                  "Browns",                   "Cherry MX Brown, older single-sample pack" },
  { "cherrymx-blue-abs",       "Cherry MX Blue, ABS",      "crisp clicky switches" },
  { "cherrymx-blue-pbt",       "Cherry MX Blue, PBT",      "clicky, deeper PBT caps" },
  { "blues",                   "Blues",                    "Cherry MX Blue, older single-sample pack" },
  { "pandas",                  "Holy Pandas",              "strongly tactile, rounded" },
  { "eg-crystal-purple",       "Everglide Crystal Purple", "tactile, bright housing" },
  { "eg-oreo",                 "Everglide Oreo",           "tactile, muted" },
  { "topre-purple-hybrid-pbt", "Topre Purple Hybrid",      "electro-capacitive thock" },
  -- Interactive moods (music that follows your typing)
  { "film-score",              "Film score",               "an action theme that builds to the hit" },
  { "orchestra-build",         "Orchestra build",          "strings and brass swell to a cadence" },
  { "techno-build",            "Techno build",             "a dance groove that builds as you type" },
  { "the-quest",               "The Quest",                "a video-game quest choir and drums" },
  { "khoomei",                 "Khoomei",                  "Tuvan throat singing on the steppe" },
  { "live-chant",              "Live chant",               "Gregorian chant, a syllable per key" },
  { "salon",                   "Salon",                    "a string quartet plays Mozart" },
  { "harpsichord",             "Harpsichord",              "Bach's Prelude in C, bar by bar" },
  { "jazz-piano",              "Jazz piano",               "bebop on a dusty upright" },
  { "wurlitzer",               "Wurlitzer",                "soul electric piano" },
  { "vibraphone",              "Vibraphone",               "a late-night lounge" },
  { "schmoove-guitar",         "Schmoove guitar",          "bossa nova comping" },
  { "slap-bass",               "Slap bass",                "a funk groove with drums" },
  { "kalimba",                 "Kalimba",                  "interlocking mbira figures" },
  { "hard-drive-music-box",    "Hard-drive music box",     "Brahms' lullaby, wound by hand" },
  { "bagpipe",                 "Bagpipe",                  "Scotland the Brave over the drones" },
  { "gregorian",               "Gregorian",                "choir notes over an organum drone" },
  -- Fun sounds
  { "thock",                   "Thock",                    "creamy synthesized keyboard" },
  { "telegraph",               "Telegraph",                "a recorded telegraph sounder" },
  { "ping-pong",               "Ping-pong",                "a table-tennis rally" },
  { "tennis",                  "Tennis",                   "racket and ball" },
  { "star-voyage",             "Star voyage",              "a starship console you can play" },
  { "scratchy-quill",          "Scratchy quill",           "a quill scratching on paper" },
  { "spark",                   "Spark",                    "electric sparks" },
  { "splash",                  "Splash",                   "water splashes" },
}
local SET_INFO = {}
for rank, entry in ipairs(SET_LIST) do SET_INFO[entry[1]] = { title = entry[2], about = entry[3], rank = rank } end

local SCROLL_GAP = 0.05   -- min seconds between scroll ticks (trackpad throttle)
local RECENT_LIMIT = 5
local STUDIO_LABEL = "com.giantravens.klonk-studio"
local PRESENTER_KEY_GAP = 1.4
local PRESENTER_KEY_LIMIT = 6
local AUDIO_QUEUE_LIMIT = 32
local SUSTAIN_IDLE = 6     -- seconds of no input before a held sound fades out
local SUSTAIN_FADE = 1.5   -- fade length when it does

-- Play a random variant from the FIRST non-empty pool in a fallback chain,
-- so click → down and scroll → up when a set ships no dedicated mouse WAVs.
-- Rotate through the chosen variant's voice bank so repeats overlap + decay.
local function play(...)
  for _, pool in ipairs({ ... }) do
    if pool and #pool > 0 then
      local bank = pool[math.random(#pool)]
      if #bank.copies > 0 then
        bank.i = bank.i % #bank.copies + 1        -- next voice (round-robin)
        local s = bank.copies[bank.i]
        s:stop(); s:play()                        -- stop() only resets THIS copy
      end
      return
    end
  end
end

local function expand(p) return (p:gsub("^~", os.getenv("HOME"))) end

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
  table.sort(out, function(a, b)                 -- SET_LIST order, then the rest by name
    local ra, rb = SET_INFO[a] and SET_INFO[a].rank or math.huge, SET_INFO[b] and SET_INFO[b].rank or math.huge
    if ra ~= rb then return ra < rb end
    return a < b
  end)
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
local CATEGORIES = {   -- menu and settings order
  { key = "keyboard",    label = "Recorded keyboards"     },
  { key = "interactive", label = "Interactive moods"      },   -- music that morphs with your typing
  { key = "themed",      label = "Fun sounds"             },
  { key = "environment", label = "Environments"           },
  { key = "percussive",  label = "Percussive objects"     },
  { key = "mechanical",  label = "Machines and mechanisms" },
  { key = "other",       label = "More sets"              },
}

function obj:_category(name)
  local dir = self:_setDir(name)
  local f = dir and io.open(dir .. "/category", "r")
  if not f then return "other" end
  local c = ((f:read("*a") or ""):match("%a+") or ""):lower()
  f:close()
  if c == "samples" then c = "keyboard" end -- pre-2.3 compatibility
  if c == "musical" or c == "performed" then c = "interactive" end -- merged October 2026
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
  self:_stopKeyboardAudio()
  self._set = name
  self:_rememberRecent("_recentSets", "klonk.recentsets", name)
  self._pool, self._sustainPath = {}, nil
  local dir = self:_setDir(name)
  if dir then self._pool, self._sustainPath = self:_poolFor(dir) end
  local kind = self:_performerKind(dir)
  if kind then
    self._sustainPath = nil              -- a performed set carries its own drones
    self:_performerStart(kind)
  else self:_performerStop() end
  self:_loadMouse()
end

-- Which set voices clicks and scroll: the chosen click set, else the key set,
-- else (a performed key set has no click sounds) the most recent keyboard or fun
-- set. Another musical set is borrowed only when nothing else has clicks: going
-- from bagpipe to film-score should not leave bagpipe clicks behind.
function obj:_clickSource()
  local function playable(name)
    return name and self:_hasClicks(self:_setDir(name))
  end
  if playable(self._clickSet) then return self._clickSet end
  if playable(self._set) then return self._set end
  local function plain(name) return playable(name) and self:_category(name) ~= "interactive" end
  for _, ok in ipairs({ plain, playable }) do
    for _, name in ipairs(self._recentSets or {}) do if ok(name) then return name end end
    for _, name in ipairs(self:_sets()) do if ok(name) then return name end end
  end
end

local function stopPools(pool)
  for _, banks in pairs(pool or {}) do
    for _, bank in ipairs(banks) do
      for _, sound in ipairs(bank.copies) do sound:stop() end
    end
  end
end

function obj:_loadMouse()
  stopPools(self._mousePool)
  local source = self:_clickSource()
  if not source or source == self._set then
    self._mousePool = nil
  else
    self._mousePool = (self:_poolFor(self:_setDir(source)))
  end
  self._mouseSet = source
end

-- Build voice pools for a set folder: generic stems (down, up, click, scroll…)
-- plus the dedicated keycode files. Shared by _load and the settings preview.
-- Also returns the path of an optional `sustain` file (see _sustainOn).
function obj:_poolFor(dir)
  local pool, sustain = {}, nil
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
      if stem == "sustain" then
        sustain = dir .. "/" .. f
      elseif GENERIC[stem] then
        pool[stem] = pool[stem] or {}
        table.insert(pool[stem], self:_bank(dir .. "/" .. f))
      else
        for kc, want in pairs(KEYFILE) do
          if stem == want then pool[kc] = { self:_bank(dir .. "/" .. f) } end
        end
      end
    end
  end
  return pool, sustain
end

-- A set may ship `sustain.wav`: a loop held under the playing, like bagpipe
-- drones. The first key or click starts it, further input keeps it alive, Return
-- ends it (the set's enter.wav carries the final flourish), and SUSTAIN_IDLE
-- seconds of quiet fade it out so a stray click never drones forever.
function obj:_sustainOn()
  if not self._sustainPath then return end
  if self._sustainFadeTimer then self._sustainFadeTimer:stop(); self._sustainFadeTimer = nil end
  if not self._sustainSound then
    self._sustainSound = hs.sound.getByFile(self._sustainPath)
    if not self._sustainSound then self._sustainPath = nil; return end
    self._sustainSound:loopSound(true)
  end
  self._sustainSound:volume(self._vol)
  if not self._sustainSound:isPlaying() then self._sustainSound:play() end
  if self._sustainIdleTimer then self._sustainIdleTimer:stop() end
  self._sustainIdleTimer = hs.timer.doAfter(SUSTAIN_IDLE, function()
    self._sustainIdleTimer = nil
    self:_sustainOff(SUSTAIN_FADE)
  end)
end

function obj:_sustainOff(fade)
  if self._sustainIdleTimer then self._sustainIdleTimer:stop(); self._sustainIdleTimer = nil end
  if self._sustainFadeTimer then self._sustainFadeTimer:stop(); self._sustainFadeTimer = nil end
  local sound = self._sustainSound
  if not sound then return end
  if not fade or fade <= 0 then
    sound:stop(); self._sustainSound = nil; return
  end
  local steps, step = 15, 0
  self._sustainFadeTimer = hs.timer.doEvery(fade / steps, function()
    step = step + 1
    if step >= steps then
      self._sustainFadeTimer:stop(); self._sustainFadeTimer = nil
      sound:stop()
      if self._sustainSound == sound then self._sustainSound = nil end
    else
      sound:volume(self._vol * (1 - step / steps))
    end
  end)
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
  if name then hs.settings.set("klonk.lastambient", name) end
  self:_rememberRecent("_recentAmbient", "klonk.recentambient", name)
  if not name or self._audioMuted then return end
  local path = self:_ambientFile(name)
  if not path then self._ambient = nil; return end
  local s = hs.sound.getByFile(path)
  if s then
    s:loopSound(true); s:volume(self._ambientVol); s:play()
    self._ambientSound = s
  else
    self._ambient = nil
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
-- wallpaper). Names come from the merged catalog in aerials.lua, which gives
-- repeated labels a take number so every take is its own desktop. A real file
-- already holding the name (a download from _downloadAerials) is never replaced.
-- Prunes symlinks whose target has vanished. Returns count.
function obj:_syncAerials()
  local dir = self:_wpDir(); hs.fs.mkdir(dir)
  local catalog = self:_aerialCatalog()
  local linked, seen = 0, {}
  for _, srcdir in ipairs(self:_aerialSources()) do
    for f in hs.fs.dir(srcdir) do
      local uuid = f:match("^(.+)%.mov$")
      if uuid then
        local entry = catalog[uuid:lower()]
        local base = entry and entry.file or ("Aerial - " .. uuid .. ".mov")
        if not seen[base] then                                 -- dedup: same aerial can be in both stores
          seen[base] = true
          local link = dir .. "/" .. base
          local la = hs.fs.symlinkAttributes(link)
          if not la or la.mode == "link" then
            os.remove(link)
            if hs.fs.link(srcdir .. "/" .. f, link, true) then linked = linked + 1 end
          end
        end
      end
    end
  end
  -- Prune symlinks that are dangling (target gone) OR stale "Aerial - …" links
  -- not (re)created this run — the latter clears duplicates left behind when an
  -- aerial gains a better name. Real files (drops and downloads) are kept.
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
    '@media(prefers-reduced-motion:reduce){video{transition:none}}',
    '</style></head><body><video autoplay loop muted playsinline></video><script>',
    'var v=document.querySelector("video"), R=' .. string.format("%.4f", self._wpSpeed) .. ';',
    'v.src=' .. jsString(name) .. '; v.muted=true; v.loop=true;',
    'var motion=matchMedia("(prefers-reduced-motion: reduce)");',
    'function go(){if(motion.matches){v.pause();v.classList.add("ready");return;}v.playbackRate=R; var p=v.play();',
    'if(p&&p.then)p.then(function(){requestAnimationFrame(function(){v.classList.add("ready")})})',
    '.catch(function(){});else requestAnimationFrame(function(){v.classList.add("ready")});}',
    'motion.addEventListener("change",go);v.autoplay=!motion.matches;',
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
  if name then hs.settings.set("klonk.lastwallpaper", name) end
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
      if not (self._wpPauseBattery and hs.battery.powerSource() == "Battery Power")
         and not hs.screen.accessibilitySettings().ReduceMotion then
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

-- macOS disables an event tap it judges slow and never re-enables it, so keys go
-- silent until something restarts the tap (any settings toggle does, via _refresh).
-- Watch whenever the tap should be running: for sounds as well as for presenter mode.
function obj:_tapWanted() return (self._on and not self._audioMuted) or self._presenter end

function obj:_updateTapWatch()
  if self:_tapWanted() and not self._tapWatchTimer then
    self._tapWatchTimer = hs.timer.doEvery(0.25, function()
      if self:_tapWanted() and self._tap and not self._tap:isEnabled() then
        self._tapRecoveries = self._tapRecoveries + 1
        hs.printf("klonk event tap disabled by macOS; recovery #%d (slowest callback %.1f ms)",
          self._tapRecoveries, self._eventTapMaxSeconds * 1000)
        self._tap:start()
      end
    end)
  elseif not self:_tapWanted() and self._tapWatchTimer then
    self._tapWatchTimer:stop()
    self._tapWatchTimer = nil
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
    if self:_tapWanted() then self._tap:start() else self._tap:stop() end
  end
  self:_updateTapWatch()
  hs.settings.set("klonk.audiomuted", self._audioMuted)
  hs.settings.set("klonk.on", self._on)
  hs.settings.set("klonk.keys", self._keys)
  hs.settings.set("klonk.mouse", self._mouse)
  hs.settings.set("klonk.scroll", self._scroll)
  hs.settings.set("klonk.clickset", self._clickSet)
  hs.settings.set("klonk.set", self._set)
  hs.settings.set("klonk.vol", self._vol)
  hs.settings.set("klonk.ambient", self._ambient)
  hs.settings.set("klonk.ambientvol", self._ambientVol)
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
  return {
    { title = "Settings…", fn = function() self:showSettings() end },
    { title = "-" },
    { title = self._audioMuted and "Unmute all sounds" or "Mute all sounds",
      fn = function() self:_setAudioMuted(not self._audioMuted) end },
    { title = self._wp and "Pause live desktop" or "Resume live desktop",
      disabled = not self._wp and #self:_wallpapers() == 0,
      fn = function() self:_setDesktopEnabled(self._wp == nil) end },
    { title = self._presenter and "Stop Presenter mode" or "Start Presenter mode",
      fn = function() self:togglePresenter() end },
    { title = "-" },
    { title = "Open Klonk Tools…", fn = function() self:showSettings("tools") end },
    { title = "Open Klonk Studio…", fn = function() self:_openStudio() end },
  }
end

-- Silence the already-playing tails as well as future input. Clearing queued
-- voices prevents a next-run-loop sound from escaping a just-issued mute.
function obj:_stopKeyboardAudio()
  self:_sustainOff(0)
  if self._performerSilence then self:_performerSilence() end
  if self._audioDrainTimer then self._audioDrainTimer:stop(); self._audioDrainTimer = nil end
  self._audioQueue = {}
  stopPools(self._mousePool)
  for _, pool in pairs(self._pool) do
    for _, bank in ipairs(pool) do
      for _, sound in ipairs(bank.copies) do sound:stop() end
    end
  end
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
    self:_stopKeyboardAudio()
    self:_stopSettingsPreview()
    if self._ambientSound then self._ambientSound:stop(); self._ambientSound = nil end
  elseif self._ambient then
    self:_playAmbient(self._ambient)
  end
  if self._performerVolume then self:_performerVolume() end
  self:_refresh()
end

--- Klonk:toggleMouse()
--- Method
--- Toggles mouse-click and scroll sounds on/off together, independent of keystrokes.
function obj:toggleMouse()
  local on = not (self._mouse or self._scroll)
  self._mouse, self._scroll = on, on; self:_refresh(); return self
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

-- A set's name, description and place in the list, from SET_LIST.
function obj:_setTitle(name)
  local info = SET_INFO[name]
  return info and info.title or (tostring(name or ""):gsub("[-_]", " "))
end
function obj:_setAbout(name) return SET_INFO[name] and SET_INFO[name].about or "" end
function obj:_setRank(name) return SET_INFO[name] and SET_INFO[name].rank or math.huge end

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
  hs.alert.show("klonk: " .. self:_setTitle(sets[i]), 0.7)
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
  self._keys = hs.settings.get("klonk.keys"); if self._keys == nil then self._keys = true end
  self._mouse = hs.settings.get("klonk.mouse"); if self._mouse == nil then self._mouse = true end
  -- Scroll used to share the mouse flag; inherit it once so upgrades keep their choice.
  self._scroll = hs.settings.get("klonk.scroll"); if self._scroll == nil then self._scroll = self._mouse end
  self._clickSet = hs.settings.get("klonk.clickset")
  self._clickSet = SET_ALIASES[self._clickSet] or self._clickSet
  self._vol = hs.settings.get("klonk.vol") or 0.7
  self._recentSets = {}
  for _, name in ipairs(settingsList("klonk.recentsets")) do
    local current = SET_ALIASES[name] or name
    local seen = false
    for _, kept in ipairs(self._recentSets) do seen = seen or kept == current end
    if not seen then self._recentSets[#self._recentSets + 1] = current end
  end
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

  -- Never perform NSSound stop/play inside the CGEventTap callback: that
  -- callback gates delivery to the foreground app. Queue compact pool chains
  -- and drain them on the next run-loop turn instead.
  local function scheduleDrain()
    if not self._audioDrainTimer then
      self._audioDrainTimer = hs.timer.doAfter(0, function()
        self._audioDrainTimer = nil
        local pending = self._audioQueue
        self._audioQueue = {}
        local performed = {}
        for _, chain in ipairs(pending) do
          if chain.perform then performed[#performed + 1] = chain.perform
          elseif chain.sustain == "on" then self:_sustainOn()
          elseif chain.sustain == "off" then self:_sustainOff(0)
          else play(table.unpack(chain)) end
        end
        self:_performerSend(performed)
      end)
    end
  end

  local function queuePlay(...)
    if #self._audioQueue >= AUDIO_QUEUE_LIMIT then
      table.remove(self._audioQueue, 1)
      self._audioQueueDrops = self._audioQueueDrops + 1
    end
    self._audioQueue[#self._audioQueue + 1] = { ... }
    scheduleDrain()
  end

  -- Performed sets take raw key events (with timing) instead of pool chains.
  local function queuePerform(event)
    self._audioQueue[#self._audioQueue + 1] = { perform = event }
    scheduleDrain()
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
      if audioListening and self._keys and self._performer then
        queuePerform({ "d", e:getKeyCode(), hs.timer.absoluteTime() / 1e6, isRepeat })
      elseif audioListening and self._keys then
        local code = e:getKeyCode()
        if self._sustainPath and not isRepeat then
          self._audioQueue[#self._audioQueue + 1] = { sustain = code == 36 and "off" or "on" }
        end
        queuePlay(p[code], p.down)
      end
    elseif t == et.keyUp then
      if audioListening and self._keys and self._performer then
        queuePerform({ "u", e:getKeyCode(), hs.timer.absoluteTime() / 1e6 })
      elseif audioListening and self._keys then queuePlay(p.up) end
    elseif t == et.flagsChanged then
      if self._presenter then self:_presenterFlagsChanged(e) end
    elseif t == et.leftMouseDown then
      if self._presenter then self:_queuePresenterClick(e:location(), false) end
      if audioListening and self._mouse then
        local m = self._mousePool or p
        if self._sustainPath and not self._mousePool then self._audioQueue[#self._audioQueue + 1] = { sustain = "on" } end
        queuePlay(m.click, m.down)
      end
    elseif t == et.rightMouseDown then
      if self._presenter then self:_queuePresenterClick(e:location(), true) end
      if audioListening and self._mouse then
        local m = self._mousePool or p
        if self._sustainPath and not self._mousePool then self._audioQueue[#self._audioQueue + 1] = { sustain = "on" } end
        queuePlay(m.rightclick, m.click, m.down)
      end
    elseif t == et.leftMouseUp or t == et.rightMouseUp then
      if audioListening and self._mouse then local m = self._mousePool or p; queuePlay(m.clickup, m.up) end
    elseif t == et.scrollWheel and audioListening and self._scroll then
      -- Tick on wheel notches and active trackpad scroll, but stay SILENT during
      -- inertial "momentum" coasting (phase ~= 0). Throttle so a fast two-finger
      -- swipe is a gentle tick-tick, not a roar.
      if e:getProperty(props.scrollWheelEventMomentumPhase) == 0 then
        local now = hs.timer.secondsSinceEpoch()
        if now - self._lastScroll >= SCROLL_GAP then
          self._lastScroll = now
          local m = self._mousePool or p
          queuePlay(m.scroll, m.up)
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
  self:_closeSettings()
  self:_cancelAerials()
  self:_stopKeyboardAudio()
  self:_performerStop()
  if self._tap then self._tap:stop(); self._tap = nil end
  if self._audioDrainTimer then self._audioDrainTimer:stop(); self._audioDrainTimer = nil end
  self._audioQueue = {}
  self._presenter = false
  self:_tearDownPresenter()
  if self._tapWatchTimer then
    self._tapWatchTimer:stop()
    self._tapWatchTimer = nil
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
--- `prevSet`, `settings`. Example:
--- `spoon.Klonk:bindHotkeys({ toggle = {{"cmd","alt"}, "k"} })`
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({
    toggle      = function() self:toggle() end,
    toggleMouse = function() self:toggleMouse() end,
    togglePresenter = function() self:togglePresenter() end,
    settings = function() self:showSettings() end,
    nextSet     = function() self:cycleSet(1) end,
    prevSet     = function() self:cycleSet(-1) end,
  }, mapping)
  return self
end

-- Load bundled UI beside this file, including when the Spoon is symlinked.
local resourceDir = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
dofile(resourceDir .. "aerials.lua")(obj, { root = AERIAL_ROOT, wallpaperStore = AERIAL_WP })
obj._loadedAt = os.time()                 -- tests compare this with file times to catch stale code
dofile(resourceDir .. "performer.lua")(obj, resourceDir)
dofile(resourceDir .. "settings.lua")(obj, resourceDir, {
  speeds = WP_SPEEDS, cadences = WP_CHANGE_MINUTES, categories = CATEGORIES,
  play = play, keyfile = KEYFILE,
})

return obj
