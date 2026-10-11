-- Settings window adapter. The engine remains the only owner of persisted state.
return function(obj, resourceDir, options)
  local function contains(items, wanted)
    for _, item in ipairs(items or {}) do if item == wanted then return true end end
    return false
  end
  local function requireValue(ok, message) if not ok then error(message, 0) end end
  local function boolean(v) requireValue(type(v) == "boolean", "Expected an on/off value"); return v end
  local function volume(v)
    requireValue(type(v) == "number" and v == v and v >= 0 and v <= 1, "Volume must be between 0 and 100 percent")
    return v
  end
  local function firstAvailable(saved, recent, available)
    if contains(available, saved) then return saved end
    for _, name in ipairs(recent or {}) do if contains(available, name) then return name end end
    return available[1]
  end
  local function choice(value, available)
    requireValue(type(value) == "string" and contains(available, value), "This item is no longer available. Refresh the library.")
    return value
  end
  local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

  -- A keyboard preview is a short performance, not one sample: a typed phrase
  -- with a correction and Return, then clicks and scroll ticks for the channels
  -- that are on. Each step is { seconds after the previous step, pool keys }.
  local SPACE, ENTER, BACKSPACE = 49, 36, 51
  local function previewScript(keys, clicks, scroll, brief)
    local steps = {}
    local function hit(gap, ...) steps[#steps + 1] = { gap, { ... } } end
    local function key(gap, code)
      if code then hit(gap, code, "down") else hit(gap, "down") end
      hit(0.06 + math.random() * 0.03, "up")
    end
    if brief then
      -- A volume nudge only needs a few keystrokes to judge loudness.
      for _ = 1, 5 do key(0.08 + math.random() * 0.06) end
      key(0.10, SPACE)
      return steps
    end
    if keys then
      for word in ("klonk sets the mood"):gmatch("%S+") do
        for _ = 1, #word do key(0.07 + math.random() * 0.09) end
        key(0.10, SPACE)
      end
      key(0.25, BACKSPACE); key(0.18, BACKSPACE)
      for _ = 1, 3 do key(0.09 + math.random() * 0.05) end
      key(0.30, ENTER)
    end
    if clicks then
      for i = 1, 2 do hit(i == 1 and 0.45 or 0.35, "click", "down"); hit(0.09, "clickup", "up") end
      hit(0.40, "rightclick", "click", "down"); hit(0.10, "clickup", "up")
    end
    if scroll then
      for i = 1, 6 do hit(i == 1 and 0.45 or 0.07, "scroll", "up") end
    end
    return steps
  end

  function obj:_settingsCatalog()
    local catalog = { sets = {}, ambient = {}, wallpapers = {}, speeds = options.speeds,
      cadences = options.cadences, categories = options.categories }
    for _, name in ipairs(self:_sets()) do
      catalog.sets[#catalog.sets + 1] = { name = name, title = self:_setTitle(name), about = self:_setAbout(name),
        rank = self:_setRank(name) ~= math.huge and self:_setRank(name) or nil, category = self:_category(name),
        performed = self:_performerKind(self:_setDir(name)) ~= nil, clicks = self:_hasClicks(self:_setDir(name)) }
    end
    for _, name in ipairs(self:_ambientSounds()) do
      catalog.ambient[#catalog.ambient + 1] = { name = name, category = self:_ambientSource(name) }
    end
    for _, name in ipairs(self:_wallpapers()) do
      catalog.wallpapers[#catalog.wallpapers + 1] = { name = name,
        title = name:gsub("^Aerial %- ", ""):gsub("%.%w+$", ""),
        category = name:match("^Aerial %- ") and "aerials" or "personal" }
    end
    catalog.aerialCollections = self:_aerialCollections()
    return catalog
  end

  function obj:_settingsState(includeCatalog)
    local state = {
      muted = self._audioMuted, keyboardOn = self._on, keys = self._keys, mouse = self._mouse, scroll = self._scroll,
      clickSet = self._clickSet or "", clickSource = self._mouseSet or "",
      patternable = self._performer == "techno", patternText = "", patternCustom = false,
      keyboard = self._set or "", volume = self._vol,
      ambientOn = self._ambient ~= nil,
      ambient = self._ambient or hs.settings.get("klonk.lastambient") or self._recentAmbient[1] or "",
      ambientVolume = self._ambientVol, desktopOn = self._wp ~= nil,
      desktop = self._wp or hs.settings.get("klonk.lastwallpaper") or self._recentWallpapers[1] or "",
      speed = self._wpSpeed, cadence = self._wpChangeMinutes, battery = self._wpPauseBattery,
      reduceMotion = hs.screen and hs.screen.accessibilitySettings and hs.screen.accessibilitySettings().ReduceMotion or false,
      batteryPaused = self._wp ~= nil and self._wpPauseBattery and hs.battery.powerSource() == "Battery Power",
      presenter = self._presenter, specialOnly = self._presenterSpecialOnly,
      preview = self._settingsPreviewKind or "", previewName = self._settingsPreviewName or "",
      aerials = self:_aerialStatus(),
      recentSets = self._recentSets, recentAmbient = self._recentAmbient, recentWallpapers = self._recentWallpapers,
    }
    if state.patternable then state.patternText, state.patternCustom = self:_patternText(self._set) end
    state.patternText = state.patternText or ""
    if includeCatalog then state.catalog = self:_settingsCatalog() end
    return state
  end

  function obj:_sendSettings(payload)
    if not self._settingsView then return end
    self._settingsView:evaluateJavaScript("window.klonkReceive(" .. hs.json.encode(payload) .. ")", function(_, err)
      if err and err.code ~= 0 then hs.printf("klonk settings delivery=failed class=javascript code=%s", tostring(err.code)) end
    end)
  end

  function obj:_stopSettingsPreview()
    if self._settingsPreviewTimer then self._settingsPreviewTimer:stop(); self._settingsPreviewTimer = nil end
    if self._settingsPreviewSound then self._settingsPreviewSound:stop(); self._settingsPreviewSound = nil end
    local wasPlaying = self._settingsPreviewKind ~= nil
    if self._settingsPreviewKind == "keyboard" and self._sustainOff then self:_sustainOff(0) end
    self._settingsPreviewKind, self._settingsPreviewName = nil, nil
    if wasPlaying and self._ambient and not self._audioMuted then self:_playAmbient(self._ambient) end
  end

  function obj:_previewSettingsSound(kind, name, unmute)
    requireValue(unmute or not self._audioMuted, "All sounds are muted. Unmute to hear a preview.")
    if kind == "keyboard" then return self:_previewKeyboardStream(name, unmute) end
    choice(name, self:_ambientSounds())
    local path = self:_ambientFile(name)
    requireValue(path ~= nil, "No playable preview was found for this sound.")
    self:_stopSettingsPreview()
    local sound = hs.sound.getByFile(path)
    requireValue(sound ~= nil, "This sound could not be decoded.")
    if unmute then self:_setAudioMuted(false) end
    if self._ambientSound then self._ambientSound:stop() end
    self._settingsPreviewSound, self._settingsPreviewKind, self._settingsPreviewName = sound, kind, name
    sound:volume(kind == "keyboard" and self._vol or self._ambientVol)
    if not sound:play() then
      self:_stopSettingsPreview()
      error("The sound could not start playing. Check your audio output and try again.", 0)
    end
    self._settingsPreviewTimer = hs.timer.doAfter(6, function()
      self:_stopSettingsPreview()
      self:_sendSettings({ state = self:_settingsState() })
    end)
  end

  -- Choosing a click set plays a few clicks and scroll ticks from it.
  function obj:_auditionClicks()
    if self._audioMuted then return end
    local m = self._mousePool or self._pool
    local hits = { { 0, { "click", "down" } }, { 0.09, { "clickup", "up" } }, { 0.25, { "click", "down" } },
      { 0.09, { "clickup", "up" } }, { 0.3, { "rightclick", "click", "down" } }, { 0.35, { "scroll", "up" } },
      { 0.07, { "scroll", "up" } }, { 0.07, { "scroll", "up" } } }
    local i = 0
    local function step()
      i = i + 1
      local item = hits[i]
      if not item then return end
      self._clickAuditionTimer = hs.timer.doAfter(item[1], function()
        local chain = {}
        for _, k in ipairs(item[2]) do chain[#chain + 1] = m[k] or false end
        options.play(table.unpack(chain))
        step()
      end)
    end
    if self._clickAuditionTimer then self._clickAuditionTimer:stop() end
    step()
  end

  -- Changing the set or volume auditions it right away. Best-effort: a failed
  -- audition must never undo or report the change itself as failed.
  function obj:_auditionKeyboard(brief)
    if self._audioMuted or not self._set then return end
    local ok, err = pcall(self._previewKeyboardStream, self, self._set, false, brief)
    if not ok then hs.printf("klonk audition=failed reason=%s", tostring(err)) end
  end

  -- A performed set auditions by playing the same typing phrase into its live
  -- page: key-downs and key-ups with real timing, Return as the cadence.
  function obj:_previewPerformer(name, unmute, brief)
    local steps = previewScript(true, self._mouse, self._scroll, brief)
    local mouse = self._mousePool or {}
    self:_stopSettingsPreview()
    if unmute then self:_setAudioMuted(false) end
    if self._ambientSound then self._ambientSound:stop() end
    self._settingsPreviewKind, self._settingsPreviewName = "keyboard", name
    local warm = math.max(0, 2.0 - (hs.timer.secondsSinceEpoch() - (self._perfStartedAt or 0)))
    local i, lastDown = 0, 0
    local function step()
      i = i + 1
      local item = steps[i]
      if not item then
        self:_stopSettingsPreview()
        self:_sendSettings({ state = self:_settingsState() })
        return
      end
      self._settingsPreviewTimer = hs.timer.doAfter(item[1] + (i == 1 and warm or 0), function()
        local first, ms = item[2][1], hs.timer.absoluteTime() / 1e6
        if first == "click" or first == "clickup" or first == "rightclick" or first == "scroll" then
          local chain = {}
          for _, k in ipairs(item[2]) do chain[#chain + 1] = mouse[k] or false end
          options.play(table.unpack(chain))
        elseif first == "up" then
          self:_performerSend({ { "u", lastDown, ms } })
        else
          lastDown = type(first) == "number" and first or 0
          self:_performerSend({ { "d", lastDown, ms, false } })
        end
        step()
      end)
    end
    step()
  end

  function obj:_previewKeyboardStream(name, unmute, brief)
    choice(name, self:_sets())
    if name == self._set and self._performer then return self:_previewPerformer(name, unmute, brief) end
    local pool = self._pool
    if name ~= self._set or not next(pool) then
      local dir = self:_setDir(name)
      requireValue(dir ~= nil, "No playable preview was found for this sound.")
      pool = (self:_poolFor(dir))
    end
    requireValue(pool.down and #pool.down > 0, "No playable preview was found for this sound.")
    -- With every channel off the preview would be silent; play the full phrase.
    local any = self._keys or self._mouse or self._scroll
    local steps = previewScript(self._keys or not any, self._mouse or not any, self._scroll or not any, brief)
    self:_stopSettingsPreview()
    if unmute then self:_setAudioMuted(false) end
    if self._ambientSound then self._ambientSound:stop() end
    self._settingsPreviewKind, self._settingsPreviewName = "keyboard", name
    local holds = name == self._set and self._sustainPath ~= nil
    local i = 0
    local function step()
      i = i + 1
      local item = steps[i]
      if not item then
        self:_stopSettingsPreview()
        self:_sendSettings({ state = self:_settingsState() })
        return
      end
      self._settingsPreviewTimer = hs.timer.doAfter(item[1], function()
        local chain = {}
        local first = item[2][1]
        local src = (self._mousePool and name == self._set and (first == "click" or first == "clickup"
          or first == "rightclick" or first == "scroll")) and self._mousePool or pool
        for _, k in ipairs(item[2]) do chain[#chain + 1] = src[k] or false end
        if holds then   -- the previewed set holds a sustain: Return ends it, input keeps it
          if item[2][1] == ENTER then self:_sustainOff(0)
          elseif item[2][1] ~= "up" and item[2][1] ~= "clickup" then self:_sustainOn() end
        end
        options.play(table.unpack(chain))
        step()
      end)
    end
    step()
  end

  function obj:_setKeyboardVolume(value)
    self._vol = volume(value)
    for _, pool in pairs(self._mousePool or {}) do
      for _, bank in ipairs(pool) do
        for _, sound in ipairs(bank.copies) do sound:volume(self._vol) end
      end
    end
    if self._sustainSound then self._sustainSound:volume(self._vol) end
    if self._performerVolume then self:_performerVolume() end
    for _, pool in pairs(self._pool) do
      for _, bank in ipairs(pool) do
        for _, sound in ipairs(bank.copies) do sound:volume(self._vol) end
      end
    end
  end

  function obj:_setAmbientEnabled(enabled)
    boolean(enabled)
    if enabled then
      local name = firstAvailable(hs.settings.get("klonk.lastambient"), self._recentAmbient, self:_ambientSounds())
      requireValue(name ~= nil, "Add an ambient sound to your library first.")
      self:_playAmbient(name)
      requireValue(self._ambient == name and (self._audioMuted or self._ambientSound ~= nil), "This ambient sound could not be played.")
    else
      if self._ambient then hs.settings.set("klonk.lastambient", self._ambient) end
      self:_playAmbient(nil)
    end
  end

  function obj:_setDesktopEnabled(enabled)
    boolean(enabled)
    if enabled then
      local name = firstAvailable(hs.settings.get("klonk.lastwallpaper"), self._recentWallpapers, self:_wallpapers())
      requireValue(name ~= nil, "Add a clip or sync Apple Aerials first.")
      self:_setWallpaper(name)
    else
      if self._wp then hs.settings.set("klonk.lastwallpaper", self._wp) end
      self:_setWallpaper(nil)
    end
  end

  function obj:_settingsAction(action, value)
    if action == "ready" or action == "refresh" then return true end
    if action ~= "previewKeyboard" and action ~= "previewAmbient" then self:_stopSettingsPreview() end
    if action == "mute" then self:_setAudioMuted(boolean(value))
    elseif action == "keyboardOn" then
      self._on = boolean(value)
      if not self._on then self:_stopKeyboardAudio() end
    elseif action == "keyboard" then self:_load(choice(value, self:_sets())); self:_auditionKeyboard()
    elseif action == "volume" then self:_setKeyboardVolume(value); self:_auditionKeyboard(true)
    elseif action == "keys" then self._keys = boolean(value)
    elseif action == "mouse" then self._mouse = boolean(value)
    elseif action == "scroll" then self._scroll = boolean(value)
    elseif action == "pattern" then
      requireValue(type(value) == "string" and #value <= 8000, "A pattern must be text under 8000 characters.")
      requireValue(self._performer == "techno", "Patterns apply to the techno set.")
      local path = self:_patternPath(self._set)
      if value == "" then os.remove(path)
      else
        hs.fs.mkdir(os.getenv("HOME") .. "/Music/Klonk"); hs.fs.mkdir(os.getenv("HOME") .. "/Music/Klonk/patterns")
        local f = assert(io.open(path, "w")); f:write(value); f:close()
      end
      self:_performerPattern()
      self._settingsNotice = value == "" and "Pattern reset to the default." or "Pattern applied. It takes over at the next bar."
    elseif action == "clickSet" then
      requireValue(type(value) == "string", "Choose a sound set for clicks.")
      if value ~= "" then
        choice(value, self:_sets())
        requireValue(self:_hasClicks(self:_setDir(value)), "That set plays only from typing; choose a set with click sounds.")
      end
      self._clickSet = value ~= "" and value or nil
      self:_loadMouse()
      self:_auditionClicks()
    elseif action == "ambientOn" then self:_setAmbientEnabled(value)
    elseif action == "ambient" then
      choice(value, self:_ambientSounds())
      hs.settings.set("klonk.lastambient", value)
      if self._ambient then
        self:_playAmbient(value)
        requireValue(self._ambient == value and (self._audioMuted or self._ambientSound ~= nil), "This ambient sound could not be played.")
      end
    elseif action == "ambientVolume" then
      self._ambientVol = volume(value)
      if self._ambientSound then self._ambientSound:volume(self._ambientVol) end
    elseif action == "desktopOn" then self:_setDesktopEnabled(value)
    elseif action == "desktop" then
      choice(value, self:_wallpapers()); hs.settings.set("klonk.lastwallpaper", value)
      if self._wp then self:_setWallpaper(value) end
    elseif action == "speed" then
      local valid = false
      for _, item in ipairs(options.speeds) do if value == item.rate then valid = true end end
      requireValue(valid, "Choose one of the available playback speeds.")
      self:_setWallpaperSpeed(value)
    elseif action == "cadence" then
      requireValue(contains(options.cadences, value), "Choose one of the available rotation intervals.")
      self:_setWallpaperChangeMinutes(value)
    elseif action == "battery" then
      self._wpPauseBattery = boolean(value); hs.settings.set("klonk.wppausebattery", value); self:_applyWallpaper()
    elseif action == "shuffle" then
      requireValue(self._wp ~= nil, "Turn on the live desktop before shuffling."); self:_shuffleWallpaper()
    elseif action == "presenter" then
      if boolean(value) ~= self._presenter then self:togglePresenter() end
    elseif action == "specialOnly" then self:_setPresenterSpecialOnly(boolean(value))
    elseif action == "unmutePreviewKeyboard" then self:_previewSettingsSound("keyboard", value, true)
    elseif action == "unmutePreviewAmbient" then self:_previewSettingsSound("ambient", value, true)
    elseif action == "previewKeyboard" then self:_previewSettingsSound("keyboard", value)
    elseif action == "previewAmbient" then self:_previewSettingsSound("ambient", value)
    elseif action == "stopPreview" then -- cleanup above
    elseif action == "studio" then self:_openStudio()
    elseif action == "syncAerials" then
      local count = self:_syncAerials()
      self._settingsNotice = count > 0 and ("Linked " .. count .. " Apple Aerials.")
        or "No new Aerials found. Activate one in macOS Wallpaper settings, then sync again."
      return true
    elseif action == "aerialPlan" then
      local known = false
      for _, c in ipairs(self:_aerialCollections()) do if c.key == value then known = true end end
      requireValue(known, "This Aerial collection is not in Apple's catalog.")
      requireValue(not (self._aerialJob and self._aerialJob.active), "Wait for the current download to finish.")
      self:_aerialPlan(value)
    elseif action == "downloadAerials" then
      requireValue(type(value) == "string", "Choose an Aerial collection.")
      local ok, err = pcall(function() self:_downloadAerials(value) end)
      requireValue(ok, tostring(err))
      self._settingsNotice = "Downloading " .. value .. " Aerials. New desktops appear as each one finishes."
    elseif action == "cancelAerials" then
      self:_cancelAerials()
      self._settingsNotice = "Download stopped. Finished clips are kept; the next download resumes the rest."
        elseif action == "folder" then
      local folders = { keyboard = os.getenv("HOME") .. "/Music/Klonk/keyboard",
        ambient = os.getenv("HOME") .. "/Music/Klonk/ambient", desktop = self:_wpDir() }
      requireValue(folders[value] ~= nil, "Unknown library.")
      hs.fs.mkdir(folders[value])
      local _, ok = hs.execute("/usr/bin/open " .. quote(folders[value]))
      requireValue(ok, "The library folder could not be opened.")
    elseif action == "recordedSounds" then hs.urlevent.openURL("https://github.com/giantravens/klonk#real-recorded-keyboards")
    else error("Unknown settings action", 0) end
    self:_refresh()
    return false
  end

  -- Still frames only. Bounded to one asynchronous decoder and six requests;
  -- ffmpeg is optional, and no video bytes pass through the message bridge.
  function obj:_settingsThumbnail(name)
    choice(name, self:_wallpapers())
    self._settingsThumbCache = self._settingsThumbCache or {}
    local path = self:_wpDir() .. "/" .. name
    local stamp = tostring(hs.fs.attributes(path, "modification"))
    local key = name .. ":" .. stamp
    if self._settingsThumbCache[key] then
      self:_sendSettings({ thumbnail = name, image = self._settingsThumbCache[key] }); return
    end
    local executable
    for _, candidate in ipairs({ "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg" }) do
      if hs.fs.attributes(candidate) then executable = candidate; break end
    end
    if not executable then self:_sendSettings({ thumbnail = name, unavailable = true }); return end
    self._settingsThumbQueue = self._settingsThumbQueue or {}
    if self._settingsThumbName == name then return end
    for _, pending in ipairs(self._settingsThumbQueue) do if pending.name == name then return end end
    if #self._settingsThumbQueue >= 6 then self:_sendSettings({ thumbnail = name, unavailable = true }); return end
    self._settingsThumbQueue[#self._settingsThumbQueue + 1] = { name = name, key = key, path = path, executable = executable }
    self:_nextSettingsThumbnail()
  end

  function obj:_nextSettingsThumbnail()
    if self._settingsThumbTask or not self._settingsView then return end
    local item = table.remove(self._settingsThumbQueue, 1)
    if not item then return end
    self._settingsThumbName = item.name
    local generation = self._settingsGeneration
    -- hs.task decodes stdout as UTF-8; JPEG bytes must use a temporary file.
    local outputPath = os.tmpname()
    self._settingsThumbFile = outputPath
    self._settingsThumbTask = hs.task.new(item.executable, function(code)
      local file = io.open(outputPath, "rb")
      local bytes = file and file:read("*a") or ""
      if file then file:close() end
      os.remove(outputPath)
      if generation ~= self._settingsGeneration then return end
      self._settingsThumbFile = nil
      if self._settingsThumbTimer then self._settingsThumbTimer:stop(); self._settingsThumbTimer = nil end
      self._settingsThumbTask, self._settingsThumbName = nil, nil
      if code == 0 and #bytes > 0 then
        local data = "data:image/jpeg;base64," .. hs.base64.encode(bytes)
        self._settingsThumbCache[item.key] = data
        self:_sendSettings({ thumbnail = item.name, image = data })
      else
        hs.printf("klonk settings thumbnail=failed class=decode code=%s", tostring(code))
        self:_sendSettings({ thumbnail = item.name, unavailable = true })
      end
      self:_nextSettingsThumbnail()
    end, { "-nostdin", "-y", "-v", "error", "-threads", "1", "-ss", "1", "-i", item.path,
      "-frames:v", "1", "-vf", "scale=320:180:force_original_aspect_ratio=increase,crop=320:180",
      "-f", "image2", "-vcodec", "mjpeg", outputPath })
    if not self._settingsThumbTask or not self._settingsThumbTask:start() then
      os.remove(outputPath); self._settingsThumbFile = nil
      self._settingsThumbTask, self._settingsThumbName = nil, nil
      self:_sendSettings({ thumbnail = item.name, unavailable = true })
      self:_nextSettingsThumbnail(); return
    end
    self._settingsThumbTimer = hs.timer.doAfter(8, function()
      if self._settingsThumbTask then self._settingsThumbTask:terminate() end
    end)
  end

  function obj:_closeSettings()
    self._settingsGeneration = (self._settingsGeneration or 0) + 1
    self:_stopSettingsPreview()
    if self._settingsPoll then self._settingsPoll:stop(); self._settingsPoll = nil end
    if self._settingsThumbTimer then self._settingsThumbTimer:stop(); self._settingsThumbTimer = nil end
    if self._settingsThumbTask then self._settingsThumbTask:terminate(); self._settingsThumbTask = nil end
    if self._settingsThumbFile then os.remove(self._settingsThumbFile); self._settingsThumbFile = nil end
    self._settingsThumbName, self._settingsThumbQueue = nil, {}
    local view = self._settingsView
    self._settingsView, self._settingsController = nil, nil
    if view then view:windowCallback(nil); view:delete() end
  end

  function obj:showSettings(section)
    self._settingsSection = section == "tools" and "tools" or "experiences"
    if self._settingsView then
      self:_sendSettings({ state = self:_settingsState(true), section = self._settingsSection })
      self._settingsView:show():bringToFront(true); self._settingsView:hswindow():focus(); return self
    end
    local file = assert(io.open(resourceDir .. "settings.html", "r"))
    local html = file:read("*a"); file:close()
    -- The pattern editor checks syntax with the same parser the groovebox runs.
    local mf = io.open(resourceDir .. "performer/mini.js", "r")
    local mini = mf and mf:read("*a") or ""; if mf then mf:close() end
    html = html:gsub("<!%-%- MINI %-%->", function() return "<script>\n" .. mini .. "\n</script>" end)
    self._settingsGeneration = (self._settingsGeneration or 0) + 1
    local controller = hs.webview.usercontent.new("klonkSettings")
    self._settingsController = controller
    controller:setCallback(function(message)
      local body = message.body
      if type(body) ~= "table" or type(body.action) ~= "string" then return end
      if body.action == "thumbnail" then
        local ok = pcall(function() self:_settingsThumbnail(body.value) end)
        if not ok then self:_sendSettings({ thumbnail = body.value, unavailable = true }) end
        return
      end
      local started = hs.timer.secondsSinceEpoch()
      hs.printf("klonk settings action=start name=%s", body.action:gsub("[^%w]", ""))
      self._settingsNotice = nil
      local ok, result = pcall(function() return self:_settingsAction(body.action, body.value) end)
      if not ok then self:_refresh() end
      self._settingsLastAction = { action = body.action, ok = ok,
        elapsed = hs.timer.secondsSinceEpoch() - started, error = not ok and tostring(result) or nil }
      hs.printf("klonk settings action=finish name=%s ok=%s class=%s elapsed=%.3f",
        body.action:gsub("[^%w]", ""), tostring(ok), ok and "none" or "validation-or-operation", self._settingsLastAction.elapsed)
      self:_sendSettings({ id = body.id, notice = self._settingsNotice, state = self:_settingsState(ok and result == true),
        section = body.action == "ready" and self._settingsSection or nil,
        error = not ok and tostring(result) or nil })
    end)
    local screen = hs.screen.mainScreen():frame()
    local width, height = math.min(820, screen.w - 40), math.min(850, screen.h - 60)
    local view = hs.webview.new({ x = screen.x + (screen.w - width) / 2,
      y = screen.y + (screen.h - height) / 2, w = width, h = height },
      { developerExtrasEnabled = false, javaScriptCanOpenWindowsAutomatically = false }, controller)
    self._settingsView = view
    -- Hammerspoon initializes NSWindow with a clear background. Extend the
    -- opaque HTML header beneath the native title bar so it cannot show through.
    view:windowStyle({ "titled", "closable", "resizable", "miniaturizable", "fullSizeContentView" })
      :windowTitle("klonk settings"):titleVisibility("hidden"):shadow(true):transparent(false):allowTextEntry(true):allowNewWindows(false):closeOnEscape(true)
    view:windowCallback(function(event)
      if event == "closing" then
        -- Closing is already in progress; don't recursively delete the window.
        self._settingsView = nil; self:_closeSettings()
      end
    end)
    view:deleteOnClose(true)
    view:html(html):show():bringToFront(true)
    view:hswindow():focus()
    self._settingsPoll = hs.timer.doEvery(1, function()
      if self._settingsView and self._settingsView:isVisible() then
        self:_sendSettings({ state = self:_settingsState() })
      end
    end)
    return self
  end
end
