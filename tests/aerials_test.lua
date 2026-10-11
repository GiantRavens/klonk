-- Aerial catalog / plan / sync / download contracts against a temp-dir fake of
-- hs.fs, with the network (HEAD, curl) stubbed. Run: lua tests/aerials_test.lua
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p '" .. tmp .. "'")
local function sh(cmd) return os.execute(cmd) end
local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end
local root, wpStore, lib = tmp .. "/idle", tmp .. "/wp/videos", tmp .. "/lib"
for _, d in ipairs({ root .. "/4KSDR240FPS", root .. "/4KHDR", wpStore, tmp .. "/wp/manifest", lib }) do sh("mkdir -p " .. q(d)) end

local function write(p, bytes) local f = assert(io.open(p, "wb")); f:write(string.rep("x", bytes or 1)); f:close() end
local fixtures = {}
local function catalog(path, tag, t) local f = io.open(path, "w"); f:write(tag); f:close(); fixtures[tag] = t end
local UW, SP = "cat-uw", "cat-sp"
local cats = { { id = UW, localizedNameKey = "AerialCategoryUnderwater" }, { id = SP, localizedNameKey = "AerialCategorySpace" } }
local function asset(id, label, cat) return { id = id, accessibilityLabel = label, categories = { cat }, ["url-4K-SDR-240FPS"] = "https://cdn/" .. id } end
catalog(root .. "/entries.json", "OLD", { categories = cats, assets = {
  asset("AAA1", "Palau Jellies", UW), asset("BBB2", "Old Name", UW), asset("EEE5", "Earth", SP) } })
catalog(tmp .. "/wp/manifest/entries.json", "NEW", { categories = cats, assets = {
  asset("CCC3", "Palau Jellies", UW), asset("DDD4", "Palau Jellies", UW), asset("BBB2", "Kelp", UW) } })

local executed, heads, tasks = {}, {}, {}
local freeKB = 100 * 1024 * 1024
hs = {
  settings = { get = function() end, set = function() end }, timer = {
    secondsSinceEpoch = os.time, doAfter = function(_, fn) return { stop = function() end, fire = fn } end },
  battery = { powerSource = function() return "AC Power" end },
  printf = function(fmt, ...) executed[#executed + 1] = string.format(fmt, ...) end,
  json = { decode = function(s) return fixtures[s] end },
  execute = function() return "Filesystem 1024-blocks Used Available\n/dev/x 1 1 " .. freeKB .. " 1% /\n", true end,
  http = { doAsyncRequest = function(url, method, _, _, cb) heads[#heads + 1] = { url = url, cb = cb } end },
  task = { new = function(exe, cb, args)
    local t = { exe = exe, cb = cb, args = args }
    function t:start() tasks[#tasks + 1] = self; return true end
    function t:terminate() self.killed = true end
    return t end },
  fs = {
    mkdir = function(p) sh("mkdir -p " .. q(p)) end,
    dir = function(p)
      local h = io.popen("ls -A " .. q(p)); local out = {}
      for l in h:lines() do out[#out + 1] = l end; h:close()
      local i = 0; return function() i = i + 1; return out[i] end
    end,
    attributes = function(p, key)
      if not sh("test -e " .. q(p)) then return nil end
      local a = { mode = sh("test -d " .. q(p)) and "directory" or "file", modification = 1 }
      if a.mode == "file" then local f = io.open(p, "rb"); a.size = f:seek("end"); f:close() end
      if key then return a[key] end; return a
    end,
    symlinkAttributes = function(p)
      if sh("test -L " .. q(p)) then return { mode = "link" } end
      if sh("test -e " .. q(p)) then return { mode = "file" } end
    end,
    link = function(src, dst) return sh("ln -s " .. q(src) .. " " .. q(dst)) end,
  },
}
local k = dofile("Klonk.spoon/init.lua")
k.wallpaperDirs = { lib }
dofile("Klonk.spoon/aerials.lua")(k, { root = root, wallpaperStore = wpStore })   -- rebind to fixtures
local checks = 0
local function same(a, b, label) checks = checks + 1; assert(a == b, label .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function exists(p) return sh("test -e " .. q(p)) and true or false end
local function isLink(p) return sh("test -L " .. q(p)) and true or false end

-- Catalog: newer manifest wins the name; repeated labels get take numbers.
local byId = k:_aerialCatalog()
same(byId.bbb2.name, "Kelp", "wallpaper manifest wins")
same(byId.bbb2.category, "Underwater", "category key stripped")
same(byId.aaa1.file, "Aerial - Palau Jellies.mov", "first take unsuffixed")
same(byId.ccc3.file, "Aerial - Palau Jellies 2.mov", "second take numbered")
same(byId.ddd4.file, "Aerial - Palau Jellies 3.mov", "third take numbered")

-- On disk: AAA1 in Apple's SDR store (HDR ignored), CCC3 in the wallpaper
-- store, and a real downloaded file already holds DDD4's name.
write(root .. "/4KSDR240FPS/AAA1.mov"); write(root .. "/4KHDR/EEE5.mov"); write(wpStore .. "/CCC3.mov")
write(lib .. "/Aerial - Palau Jellies 3.mov", 7)
local cols = k:_aerialCollections()
same(#cols, 2, "two collections"); same(cols[2].key, "Underwater", "sorted")
same(cols[2].total, 4, "underwater total"); same(cols[2].missing, 1, "only Kelp missing")

-- Sync links every take and never replaces a real file.
same(k:_syncAerials(), 2, "two links")
same(isLink(lib .. "/Aerial - Palau Jellies.mov"), true, "take 1 linked")
same(isLink(lib .. "/Aerial - Palau Jellies 2.mov"), true, "take 2 linked")
same(isLink(lib .. "/Aerial - Palau Jellies 3.mov"), false, "real download kept")
same(exists(lib .. "/Aerial - Earth.mov"), false, "HDR store skipped")

-- Plan: observe first. Only Kelp is missing; HEAD settles the size.
write(lib .. "/.Aerial - Kelp.mov.part", 4)
local plan = k:_aerialPlan("Underwater")
same(plan.ready, false, "plan waits for HEAD"); same(#heads, 1, "one HEAD for one missing clip")
same(plan.items[1].partial, 4, "partial bytes observed")
heads[1].cb(200, "", { ["Content-Length"] = "10" })
same(plan.ready, true, "plan settles"); same(plan.verdict, "ready", "verdict ready")
same(plan.remaining, 6, "predicted remaining bytes excludes partial")
same(k:_aerialStatus().plan.missing, 1, "status exposes plan")

-- A download that is too big for the disk floor is refused before any byte moves.
freeKB = 1; heads = {}
local tight = k:_aerialPlan("Underwater"); heads[1].cb(200, "", { ["Content-Length"] = "10" })
same(tight.verdict, "no-space", "disk floor enforced")
same(pcall(function() k:_downloadAerials("Underwater") end), false, "no-space plan refused")
freeKB = 100 * 1024 * 1024; heads = {}
k:_aerialPlan("Underwater"); heads[1].cb(200, "", { ["Content-Length"] = "10" })
same(pcall(function() k:_downloadAerials("Space") end), false, "plan must match collection")

-- Download: curl resumes into the hidden .part and renames only when verified.
k:_downloadAerials("Underwater")
same(#tasks, 1, "one curl"); same(tasks[1].exe, "/usr/bin/curl", "curl binary")
local args = table.concat(tasks[1].args, " ")
same(args:find("-C -", 1, true) ~= nil, true, "resumes"); same(args:find("--speed-time", 1, true) ~= nil, true, "stall detector")
write(lib .. "/.Aerial - Kelp.mov.part", 10); tasks[1].cb(0, "", "")
same(exists(lib .. "/Aerial - Kelp.mov"), true, "verified file renamed into place")
same(exists(lib .. "/.Aerial - Kelp.mov.part"), false, "part consumed")
local st = k:_aerialStatus().job
same(st.active, false, "job finished"); same(st.ok, 1, "one ok"); same(#st.failed, 0, "no failures")
same(k:_aerialCollections()[2].missing, 0, "collection complete")

-- Size mismatch is a classified failure; the file never lands.
sh("rm " .. q(lib .. "/Aerial - Kelp.mov")); tasks, heads = {}, {}
k:_aerialPlan("Underwater"); heads[1].cb(200, "", { ["Content-Length"] = "10" })
k:_downloadAerials("Underwater"); write(lib .. "/.Aerial - Kelp.mov.part", 12); tasks[1].cb(0, "", "")
same(exists(lib .. "/Aerial - Kelp.mov"), false, "mismatch not renamed")
same(exists(lib .. "/.Aerial - Kelp.mov.part"), false, "oversize part discarded")
same(k:_aerialStatus().job.failed[1], "Kelp (size-mismatch)", "failure class reported")

-- Cancel keeps the partial for the next run.
tasks, heads = {}, {}
k:_aerialPlan("Underwater"); heads[1].cb(200, "", { ["Content-Length"] = "10" })
k:_downloadAerials("Underwater"); write(lib .. "/.Aerial - Kelp.mov.part", 3)
k:_cancelAerials(); same(tasks[1].killed, true, "curl terminated"); tasks[1].cb(15, "", "")
same(exists(lib .. "/.Aerial - Kelp.mov.part"), true, "partial kept for resume")
same(k:_aerialStatus().job.cancelled, true, "cancel reported"); same(#k:_aerialStatus().job.failed, 0, "cancel is not a failure")

-- Telemetry: plan, start, file-finish and finish events all carry a class.
local log = table.concat(executed, "\n")
for _, ev in ipairs({ "event=plan", "verdict=no%-space", "event=start", "class=ok", "class=size%-mismatch", "class=cancelled", "event=finish" }) do
  same(log:find(ev) ~= nil, true, "telemetry " .. ev)
end
sh("rm -rf " .. q(tmp))
print("aerials tests: " .. checks .. " passed")
