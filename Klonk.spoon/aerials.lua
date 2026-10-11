-- Apple Aerial collections: catalog, plan, download. Apple only fetches an aerial
-- when you activate it in System Settings, so a whole collection (Underwater,
-- Landscapes, …) normally means twenty clicks. Apple's own catalogs carry a
-- direct 4K SDR URL per clip; this module downloads a collection straight into
-- the live-desktop folder as real files named like the synced links, so the
-- picker files them under "Apple Aerials" either way.
--
-- Observe before act: _aerialPlan() classifies every clip (on this Mac / partly
-- downloaded / missing), HEADs the missing ones for exact sizes and checks free
-- disk. Only a ready plan can start _downloadAerials(). Each file is verified
-- against its Content-Length before it is renamed into place, and every step is
-- logged as `klonk aerials event=…` so failures carry a class, not just a count.
return function(obj, options)
  local ROOT, WP = options.root, options.wallpaperStore
  local CATALOGS = { ROOT .. "/entries.json", (WP:gsub("/videos$", "")) .. "/manifest/entries.json" }
  local FLOOR_BYTES = 5 * 1024 ^ 3          -- leave this much disk free after a collection
  local HEAD_TIMEOUT = 20                   -- seconds before a plan settles with unknown sizes
  -- curl aborts itself below 16 KB/s for 2 minutes: the stall detector lives in
  -- the tool, not in a Lua timer.
  local CURL_ARGS = { "-fsSL", "--retry", "3", "--retry-delay", "5", "--connect-timeout", "20",
    "--speed-limit", "16384", "--speed-time", "120", "-C", "-" }

  local function catKey(k) return (k or ""):gsub("^AerialCategory", "") end

  -- Merged id → { id, name, category, url, file } from BOTH Apple catalogs (the
  -- wallpaper manifest is newer and read second, so it wins). Cached on catalog
  -- mtimes because the settings poll asks every second.
  function obj:_aerialCatalog()
    local stamp = ""
    for _, p in ipairs(CATALOGS) do stamp = stamp .. tostring(hs.fs.attributes(p, "modification")) .. ";" end
    if self._aerialCache and self._aerialCache.stamp == stamp then
      return self._aerialCache.byId, self._aerialCache.order
    end
    local byId, order = {}, {}
    for _, path in ipairs(CATALOGS) do
      local fh = io.open(path, "r")
      if fh then
        local ok, data = pcall(hs.json.decode, fh:read("a")); fh:close()
        if ok and type(data) == "table" and data.assets then
          local cats = {}
          for _, c in ipairs(data.categories or {}) do cats[c.id] = catKey(c.localizedNameKey) end
          for _, a in ipairs(data.assets) do
            if a.id then
              local id = a.id:lower()
              if not byId[id] then order[#order + 1] = id end
              byId[id] = { id = id, name = (a.accessibilityLabel or a.id):gsub("[/:]", "-"),
                category = cats[(a.categories or {})[1]] or "Other", url = a["url-4K-SDR-240FPS"] }
            end
          end
        end
      end
    end
    -- Stable, unique file names: repeated labels (three "Palau Jellies" takes)
    -- become "… 2", "… 3" in id order, so every take is its own desktop.
    table.sort(order)
    local taken = {}
    for _, id in ipairs(order) do
      local a = byId[id]
      taken[a.name] = (taken[a.name] or 0) + 1
      a.file = "Aerial - " .. a.name .. (taken[a.name] > 1 and (" " .. taken[a.name]) or "") .. ".mov"
    end
    self._aerialCache = { stamp = stamp, byId = byId, order = order }
    return byId, order
  end

  -- Directories where Apple keeps downloaded aerials (SDR only; HDR washes out).
  function obj:_aerialSources()
    local sources = {}
    if hs.fs.attributes(ROOT) then
      for sub in hs.fs.dir(ROOT) do
        local subdir = ROOT .. "/" .. sub
        if sub:find("SDR") and hs.fs.attributes(subdir, "mode") == "directory" then sources[#sources + 1] = subdir end
      end
    end
    if hs.fs.attributes(WP) then sources[#sources + 1] = WP end
    return sources
  end

  local function appleIds(self)
    local ids = {}
    for _, dir in ipairs(self:_aerialSources()) do
      for f in hs.fs.dir(dir) do
        local id = f:match("^(.+)%.mov$")
        if id then ids[id:lower()] = true end
      end
    end
    return ids
  end

  local function partPath(dir, item) return dir .. "/." .. item.file .. ".part" end

  -- Collections with counts, for the category picker. Cheap: no network.
  function obj:_aerialCollections()
    local byId, order = self:_aerialCatalog()
    local apple, dir, out, index = appleIds(self), self:_wpDir(), {}, {}
    for _, id in ipairs(order) do
      local a = byId[id]
      if a.url then
        if not index[a.category] then
          index[a.category] = { key = a.category, total = 0, missing = 0 }; out[#out + 1] = index[a.category]
        end
        local c = index[a.category]; c.total = c.total + 1
        if not apple[id] and not hs.fs.attributes(dir .. "/" .. a.file) then c.missing = c.missing + 1 end
      end
    end
    table.sort(out, function(x, y) return x.key < y.key end)
    return out
  end

  local function freeBytes(dir)
    local out = hs.execute("/bin/df -k " .. "'" .. dir:gsub("'", "'\\''") .. "'")
    local avail = out and out:match("\n%S+%s+%d+%s+%d+%s+(%d+)")
    return avail and tonumber(avail) * 1024 or nil
  end

  local function publish(self)
    if self._settingsView then self:_sendSettings({ state = self:_settingsState(true) }) end
  end

  -- Manifest: classify each clip in a collection, then HEAD the missing ones.
  -- Settles when every HEAD answers or after HEAD_TIMEOUT, whichever is first.
  function obj:_aerialPlan(category)
    local byId, order = self:_aerialCatalog()
    local apple, dir = appleIds(self), self:_wpDir()
    hs.fs.mkdir(dir)
    local plan = { category = category, items = {}, onMac = 0, pending = 0, ready = false,
      started = hs.timer.secondsSinceEpoch() }
    for _, id in ipairs(order) do
      local a = byId[id]
      if a.category == category and a.url then
        if apple[id] or hs.fs.attributes(dir .. "/" .. a.file) then
          plan.onMac = plan.onMac + 1
        else
          plan.items[#plan.items + 1] = { id = id, name = a.name, file = a.file, url = a.url,
            partial = hs.fs.attributes(partPath(dir, a), "size") or 0 }
        end
      end
    end
    if self._aerialPlanTimer then self._aerialPlanTimer:stop() end
    self._aerialPlanState = plan
    local function settle()
      if plan.ready or self._aerialPlanState ~= plan then return end
      if self._aerialPlanTimer then self._aerialPlanTimer:stop(); self._aerialPlanTimer = nil end
      local bytes, remaining, unknown = 0, 0, 0
      for _, item in ipairs(plan.items) do
        if item.bytes then bytes = bytes + item.bytes; remaining = remaining + item.bytes - item.partial
        else unknown = unknown + 1 end
      end
      plan.bytes, plan.remaining, plan.unknown, plan.free = bytes, remaining, unknown, freeBytes(dir)
      plan.verdict = #plan.items == 0 and "complete"
        or (plan.free and plan.free - remaining < FLOOR_BYTES) and "no-space"
        or unknown == #plan.items and "unreachable" or "ready"
      plan.ready = true
      hs.printf("klonk aerials event=plan category=%s missing=%d on_mac=%d unknown=%d predicted_bytes=%d free_bytes=%s verdict=%s elapsed=%.2f",
        category, #plan.items, plan.onMac, unknown, remaining, tostring(plan.free), plan.verdict,
        hs.timer.secondsSinceEpoch() - plan.started)
      publish(self)
    end
    plan.pending = #plan.items
    if plan.pending == 0 then settle(); return plan end
    for _, item in ipairs(plan.items) do
      hs.http.doAsyncRequest(item.url, "HEAD", nil, nil, function(status, _, headers)
        local len = headers and (headers["Content-Length"] or headers["content-length"])
        if status == 200 and tonumber(len) then item.bytes = tonumber(len)
        else item.headStatus = status end
        plan.pending = plan.pending - 1
        if plan.pending == 0 then settle() end
      end)
    end
    self._aerialPlanTimer = hs.timer.doAfter(HEAD_TIMEOUT, settle)
    return plan
  end

  local function finishJob(self, job)
    job.active, job.current, self._aerialTask = false, nil, nil
    local elapsed = hs.timer.secondsSinceEpoch() - job.started
    hs.printf("klonk aerials event=finish category=%s ok=%d failed=%d cancelled=%s predicted_bytes=%d actual_bytes=%d elapsed=%.0f",
      job.category, job.ok, #job.failed, tostring(job.cancelled or false), job.predicted, job.actual, elapsed)
    self:_syncAerials()
    self._aerialPlanState = nil
    publish(self)
  end

  function obj:_aerialNext()
    local job = self._aerialJob
    if not job or not job.active then return end
    local item = not job.cancelled and table.remove(job.queue, 1)
    if not item then finishJob(self, job); return end
    local dir = self:_wpDir()
    local part, final = partPath(dir, item), dir .. "/" .. item.file
    job.current, item.started = item, hs.timer.secondsSinceEpoch()
    local startSize = hs.fs.attributes(part, "size") or 0
    hs.printf("klonk aerials event=file-start id=%s name=%q expected_bytes=%s resume_from=%d",
      item.id, item.file, tostring(item.bytes), startSize)
    local args = { table.unpack(CURL_ARGS) }
    args[#args + 1] = "-o"; args[#args + 1] = part; args[#args + 1] = item.url
    self._aerialTask = hs.task.new("/usr/bin/curl", function(code, _, stderr)
      if self._aerialJob ~= job then return end
      local size = hs.fs.attributes(part, "size") or 0
      local class
      if job.cancelled then class = "cancelled"                      -- .part kept; next run resumes
      elseif code ~= 0 then class = "curl-" .. code                  -- 22 http, 28 stall, 23 disk, 6 dns
      elseif item.bytes and size ~= item.bytes then class = "size-mismatch"
      elseif not os.rename(part, final) then class = "rename"
      else class = "ok" end
      if class == "size-mismatch" and size > item.bytes then os.remove(part) end   -- corrupt: restart next time
      job.actual = job.actual + math.max(0, size - startSize)
      if class == "ok" then job.ok = job.ok + 1
      elseif class ~= "cancelled" then job.failed[#job.failed + 1] = { name = item.file, class = class } end
      local secs = hs.timer.secondsSinceEpoch() - item.started
      hs.printf("klonk aerials event=file-finish id=%s class=%s bytes=%d expected_bytes=%s elapsed=%.0f mbps=%.1f stderr=%q",
        item.id, class, size, tostring(item.bytes), secs, (size - startSize) * 8 / 1e6 / math.max(secs, 0.001),
        (stderr or ""):sub(1, 160))
      job.done = job.done + 1
      if class == "ok" then publish(self) end                        -- new desktop appears as it lands
      self:_aerialNext()
    end, args)
    if not self._aerialTask or not self._aerialTask:start() then
      job.failed[#job.failed + 1] = { name = item.file, class = "spawn" }
      job.done = job.done + 1
      hs.timer.doAfter(0, function() self:_aerialNext() end)
    end
  end

  -- Start a verified plan. One file at a time: Apple's CDN is fast enough that
  -- parallelism buys little and would multiply partial files on cancel.
  function obj:_downloadAerials(category)
    local plan = self._aerialPlanState
    assert(not (self._aerialJob and self._aerialJob.active), "A download is already running.")
    assert(plan and plan.category == category and plan.ready, "Check the collection first.")
    assert(plan.verdict ~= "no-space", "Not enough free disk space for this collection.")
    assert(plan.verdict ~= "unreachable", "Apple's aerial server did not answer. Try again later.")
    assert(#plan.items > 0, "Every clip in this collection is already on your Mac.")
    local queue = {}
    for _, item in ipairs(plan.items) do queue[#queue + 1] = item end
    self._aerialJob = { category = category, queue = queue, total = #queue, done = 0, ok = 0,
      failed = {}, predicted = plan.remaining or 0, actual = 0, active = true,
      started = hs.timer.secondsSinceEpoch() }
    hs.printf("klonk aerials event=start category=%s files=%d predicted_bytes=%d",
      category, #queue, self._aerialJob.predicted)
    self:_aerialNext()
    return self._aerialJob
  end

  function obj:_cancelAerials()
    local job = self._aerialJob
    if not (job and job.active) then return end
    job.cancelled = true
    if self._aerialTask then self._aerialTask:terminate() else finishJob(self, job) end
  end

  -- Small, JSON-safe snapshot for the settings poll.
  function obj:_aerialStatus()
    local out = {}
    local plan = self._aerialPlanState
    if plan then
      out.plan = { category = plan.category, ready = plan.ready, verdict = plan.verdict,
        missing = #plan.items, onMac = plan.onMac, bytes = plan.remaining, free = plan.free,
        unknown = plan.unknown }
    end
    local job = self._aerialJob
    if job then
      local current = 0
      if job.active and job.current then
        current = hs.fs.attributes(partPath(self:_wpDir(), job.current), "size") or 0
      end
      local failed = {}
      for _, f in ipairs(job.failed) do failed[#failed + 1] = f.name:gsub("^Aerial %- ", ""):gsub("%.mov$", "") .. " (" .. f.class .. ")" end
      out.job = { category = job.category, active = job.active, cancelled = job.cancelled or false,
        done = job.done, total = job.total, ok = job.ok, failed = failed,
        current = job.current and job.current.name or "", currentBytes = current,
        currentTotal = job.current and job.current.bytes or 0 }
    end
    return out
  end
end
