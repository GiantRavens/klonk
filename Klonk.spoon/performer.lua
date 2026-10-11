-- Performed sets: a set folder holding a one-word `performer` file is played by
-- a live Web Audio page (performer/<kind>.html, e.g. gregorian, techno) instead
-- of WAV pools. Klonk
-- forwards key-down/key-up events with their timestamps; the page turns the
-- typing into a phrase (tempo from keystroke spacing, sustain from held keys,
-- a cadence on period or Return). The page lives only while such a set is loaded.
return function(obj, resourceDir)
  local function page(kind)
    return "file://" .. (resourceDir .. "performer/" .. kind .. ".html"):gsub(" ", "%%20")
  end

  -- Does a set folder carry its own key or click sounds? Scenes do (for mouse clicks);
  -- purely performed sets like techno-build do not.
  function obj:_hasClicks(dir)
    if not dir or not hs.fs.attributes(dir) then return false end
    for f in hs.fs.dir(dir) do
      if f:match("^down%d*%.") or f:match("^click%d*%.") then return true end
    end
    return false
  end

  function obj:_performerKind(dir)
    local f = dir and io.open(dir .. "/performer", "r")
    if not f then return nil end
    local kind = ((f:read("*a") or ""):match("%a+") or ""):lower()
    f:close()
    return kind ~= "" and kind or nil
  end

  -- Instrument scenes share one engine page, told which scene by its #fragment.
  -- The page a performed set plays in. A scene page needs the set's name after "#"
  -- (scene.html#bagpipe); without it the page has no scene and stays silent.
  function obj:_performerURL(kind, set)
    if kind == "scene" then return page("scene") .. "#" .. (set:gsub("[^%w%-]", "")) end
    return page(kind)
  end

  function obj:_performerStart(kind)
    local key = kind == "scene" and ("scene#" .. self._set) or kind
    if self._perfView and self._perfKind ~= key then self:_performerStop() end
    self._performer, self._perfKind = kind, key
    if self._perfView then return end
    self._perfView = hs.webview.new({ x = 0, y = 0, w = 10, h = 10 }):url(self:_performerURL(kind, self._set))
    self._perfStartedAt = hs.timer.secondsSinceEpoch()
    hs.timer.doAfter(1.5, function() self:_performerVolume(); self:_performerPattern() end)
  end

  function obj:_performerStop()
    self._performer, self._perfKind = nil, nil
    local view = self._perfView
    if not view then return end
    self._perfView = nil
    view:evaluateJavaScript("window.K && K.stop()")
    hs.timer.doAfter(3, function() view:delete() end)   -- let the abbey tail ring out
  end

  function obj:_performerSend(events)
    if not self._perfView or #events == 0 then return end
    self._perfView:evaluateJavaScript("window.K && K.events(" .. hs.json.encode(events) .. ")")
  end

  function obj:_performerSilence()
    if self._perfView then self._perfView:evaluateJavaScript("window.K && K.stop()") end
  end

  -- Pattern-driven performers (techno) read a mini-notation program: your edited
  -- copy in ~/Music/Klonk/patterns/<set>.txt, else the set's bundled pattern.txt,
  -- else the page's built-in default.
  function obj:_patternPath(set) return os.getenv("HOME") .. "/Music/Klonk/patterns/" .. set .. ".txt" end

  function obj:_patternText(set)
    for _, path in ipairs({ self:_patternPath(set), (self:_setDir(set) or "") .. "/pattern.txt" }) do
      local f = io.open(path, "r")
      if f then local text = f:read("*a"); f:close(); return text, path == self:_patternPath(set) end
    end
    return nil, false
  end

  function obj:_performerPattern()
    if not self._perfView or self._performer ~= "techno" then return end
    local text = self:_patternText(self._set)
    if text then self._perfView:evaluateJavaScript("window.K && K.pattern(" .. hs.json.encode({ text }):sub(2, -2) .. ")") end
  end

  function obj:_performerVolume()
    if self._perfView then
      self._perfView:evaluateJavaScript(string.format("window.K && K.volume(%.3f)", self._audioMuted and 0 or self._vol))
    end
  end
end
