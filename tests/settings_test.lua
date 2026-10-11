-- State-contract regressions, independent of macOS. Run: lua tests/settings_test.lua
local saved, stopped, resumed = {}, 0, 0
hs = { settings = { get = function(k) return saved[k] end, set = function(k,v) saved[k]=v end },
  battery = { powerSource = function() return "AC Power" end }, timer = {}, printf = function() end }
local k = dofile('Klonk.spoon/init.lua')
local checks=0
local function same(a,b,label) checks=checks+1;assert(a==b,label..': expected '..tostring(b)..', got '..tostring(a)) end
local function rejects(action,value)
  local ok=pcall(function() k:_settingsAction(action,value) end)
  same(ok,false,'reject '..action)
end
function k:_refresh() end
function k:_sets() return {'quiet','loud'} end
function k:_ambientSounds() return {'rain','wind'} end
function k:_wallpapers() return {'forest.mov','sea.mp4'} end
function k:_playAmbient(name) self._ambient=name;self._ambientSound=name and {stop=function() stopped=stopped+1 end} or nil;resumed=resumed+1 end
function k:_setWallpaper(name) self._wp=name end
function k:_load(name) self._set=name end
k._set='quiet'; k._recentAmbient={'rain'};k._recentWallpapers={'forest.mov'}
k:_settingsAction('ambientOn',true);same(k._ambient,'rain','ambient restores recent')
k:_settingsAction('ambientOn',false);same(k._ambient,nil,'ambient off');same(saved['klonk.lastambient'],'rain','remembers ambient')
k:_settingsAction('ambient','wind');same(k._ambient,nil,'selection while off stays off')
k:_settingsAction('ambientOn',true);same(k._ambient,'wind','ambient restores saved choice')
k:_settingsAction('desktopOn',true);same(k._wp,'forest.mov','desktop restores recent')
k:_settingsAction('desktopOn',false);same(k._wp,nil,'desktop off');same(saved['klonk.lastwallpaper'],'forest.mov','remembers desktop')
k:_settingsAction('desktop','sea.mp4');same(k._wp,nil,'desktop choice stays off')
k:_settingsAction('desktopOn',true);same(k._wp,'sea.mp4','desktop restores saved')
k._pool={down={{copies={{stop=function() stopped=stopped+1 end,volume=function() end}}}}}
k._audioQueue={{'queued'}};k._settingsPreviewSound={stop=function() stopped=stopped+1 end};k._settingsPreviewKind='keyboard'
k:_setAudioMuted(true)
same(k._audioMuted,true,'master mute');same(#k._audioQueue,0,'mute clears queued voices')
same(k._settingsPreviewSound,nil,'mute stops preview');same(k._ambient,'wind','mute keeps ambient selection');same(k._set,'quiet','mute keeps keyboard selection');same(k._wp,'sea.mp4','mute keeps desktop')
same(stopped>=3,true,'mute stops active voices, preview and ambient')
k:_setAudioMuted(false);same(k._ambient,'wind','unmute restores ambient');same(k._ambientSound~=nil,true,'unmute starts ambient')
k:_settingsAction('volume',.42);same(k._vol,.42,'continuous volume')
rejects('volume',-1);rejects('volume',2);rejects('volume','0.5');rejects('volume',0/0)
rejects('keyboard','../outside');rejects('keyboardOn','false');rejects('speed',99);rejects('cadence',7);rejects('folder','arbitrary');rejects('unknown',true)
same(k._set,'quiet','invalid set preserved');same(k._vol,.42,'invalid volume preserved')
function k:_ambientSounds() return {} end
function k:_wallpapers() return {} end
k._ambient=nil;k._wp=nil
rejects('ambientOn',true);rejects('desktopOn',true)
same(k._ambient,nil,'empty ambient stays off');same(k._wp,nil,'empty desktop stays off')
local menu=k:_menuItems()
for _,item in ipairs(menu) do same(item.menu,nil,'menu is flat') end
same(menu[1].title,'Settings…','settings first')
-- Closing previews resumes ambience without changing saved settings.
k._ambient='wind';k._settingsPreviewKind='ambient';k._settingsPreviewSound={stop=function() end}
local before=resumed;k:_stopSettingsPreview();same(resumed,before+1,'preview cleanup resumes ambient')
-- Keys, clicks, and scroll are independent channels under the card switch.
for _,id in ipairs({'keys','mouse','scroll'}) do
  k:_settingsAction(id,false);same(k['_'..id],false,id..' off');k:_settingsAction(id,true);same(k['_'..id],true,id..' on');rejects(id,'off')
end
same(k:_settingsState().scroll,true,'state reports scroll')
-- Keyboard preview performs a stream of inputs through the real voice pools.
local timers,hits={},{}
hs.timer.doAfter=function(_,fn) local t={stop=function(self) self.dead=true end,fn=fn};timers[#timers+1]=t;return t end
local function bank(stem) return {copies={{volume=function() end,stop=function() end,play=function() hits[stem]=(hits[stem] or 0)+1 end}},i=0} end
k._pool={down={bank('down')},up={bank('up')},click={bank('click')},scroll={bank('scroll')},[49]={bank('space')},[36]={bank('enter')}}
function k:_sets() return {'quiet','loud'} end
k._set='quiet';k._audioMuted=false;k._ambientSound=nil;k._keys,k._mouse,k._scroll=true,true,true
local function drain() local n=0;while #timers>0 do local t=table.remove(timers,1);if not t.dead then t.fn() end;n=n+1;assert(n<500,'preview never ends') end end
k:_settingsAction('previewKeyboard','quiet');same(k._settingsPreviewKind,'keyboard','preview starts');drain()
same((hits.down or 0)>10,true,'preview types a phrase');same(hits.space~=nil and hits.enter~=nil,true,'preview uses dedicated keys')
same(hits.click~=nil,true,'preview clicks');same(hits.scroll~=nil,true,'preview scrolls');same(k._settingsPreviewKind,nil,'preview ends itself')
hits={};k._mouse,k._scroll=false,false;k:_settingsAction('previewKeyboard','quiet');drain()
same(hits.click,nil,'preview skips muted clicks');same(hits.scroll,nil,'preview skips muted scroll');same((hits.down or 0)>10,true,'preview still types')
hits={};k:_settingsAction('previewKeyboard','quiet');k:_settingsAction('stopPreview');drain()
same(hits.down,nil,'stop cancels pending preview hits')
-- Choosing a set or volume auditions it; muted, it stays silent.
k._keys,k._mouse,k._scroll=true,true,true
function k:_load(name) self._set=name end
hits={};k:_settingsAction('keyboard','loud');same(k._settingsPreviewKind,'keyboard','set change auditions');drain()
same((hits.down or 0)>10,true,'set change plays the full phrase')
hits={};k:_settingsAction('volume',.5);drain();same(hits.down~=nil and (hits.down or 0)<10,true,'volume plays a short burst');same(hits.click,nil,'volume burst is keys only')
k:_setAudioMuted(true);hits={};k:_settingsAction('volume',.6);drain();same(next(hits),nil,'muted volume change stays silent');same(k._vol,.6,'muted volume still applies')
-- A set's sustain.wav is held across input until Return or an idle fade.
k._audioMuted=false;k._vol=.5
local held={playing=false,starts=0,vol=nil}
function held:play() self.playing=true;self.starts=self.starts+1 end
function held:stop() self.playing=false end
function held:isPlaying() return self.playing end
function held:loopSound() end
function held:volume(v) self.vol=v end
hs.sound={getByFile=function() return held end}
hs.timer.doEvery=function(_,fn) local t={stop=function(self) self.dead=true end};t.fn=fn;timers[#timers+1]={stop=function() end,fn=function() for _=1,20 do if t.dead then break end fn() end end};return t end
k._sustainPath='drone.wav';k._sustainSound=nil
k:_sustainOn();k:_sustainOn();same(held.playing and held.starts==1,true,'sustain starts once and stays')
k:_sustainOff(0);same(held.playing,false,'return ends sustain');same(k._sustainSound,nil,'sustain released')
timers={};k:_sustainOn();drain();same(held.playing,false,'idle sustain fades out')
k:_sustainOn();k:_setAudioMuted(true);same(held.playing,false,'mute ends sustain');k:_setAudioMuted(false)
-- Preview of a sustain set holds the drone through the phrase and drops it on Return.
timers={};held.starts=0
local sawDuring=false
local realOff=k._sustainOff
k._sustainOff=function(self,f) if held.playing then sawDuring=true end return realOff(self,f) end
k._set='quiet';k:_settingsAction('previewKeyboard','quiet')
for _=1,30 do local t=table.remove(timers,1);if t and not t.dead then t.fn() end end
same(held.starts>=1,true,'preview starts the sustain');k._sustainOff=realOff
drain();same(sawDuring,true,'preview Return or end releases the sustain');same(held.playing,false,'preview leaves no drone behind')
k._sustainPath=nil
-- Performed sets: a `performer` file routes typing to a live page.
local js={}
local view={evaluateJavaScript=function(_,code) js[#js+1]=code end,delete=function() end}
hs.webview={new=function() return {url=function() return view end} end}
hs.json=hs.json or {encode=function(t) return '[...]' end}
hs.timer.absoluteTime=function() return 1e9 end
hs.timer.secondsSinceEpoch=hs.timer.secondsSinceEpoch or os.time
local tmp=os.tmpname();os.remove(tmp);os.execute('mkdir -p '..tmp);local f=io.open(tmp..'/performer','w');f:write('gregorian\n');f:close()
same(k:_performerKind(tmp),'gregorian','performer file names the engine');same(k:_performerKind(nil),nil,'no dir, no performer')
k:_performerStart('gregorian');same(k._perfView,view,'performer page created');same(k._performer,'gregorian','performer active')
k:_performerSend({{'d',0,1,false}});same(js[#js]:match('K.events')~=nil,true,'events batched to the page')
k._audioMuted=true;k:_performerVolume();same(js[#js]:match('K.volume%(0.000%)')~=nil,true,'muted performer is silent')
k._audioMuted=false
timers={};k._set='quiet';k._performer='gregorian';k._perfStartedAt=0
local before=#js;k:_settingsAction('previewKeyboard','quiet');drain()
same(#js-before>10,true,'preview performs the phrase into the page')
k:_performerStop();same(k._perfView,nil,'performer page released');same(k._performer,nil,'performer inactive')
os.execute('rm -rf '..tmp)
-- Clicks and scroll can come from another set; performed key sets borrow one.
local dirs={quiet='/q',loud='/l',chant='/c'}
function k:_sets() return {'chant','loud','quiet'} end
function k:_setDir(n) return dirs[n] end
function k:_performerKind(d) return d=='/c' and 'gregorian' or nil end
function k:_hasClicks(d) return d=='/q' or d=='/l' end
local built={}
function k:_poolFor(d) built[#built+1]=d;return {click={{copies={{stop=function() end,volume=function() end,play=function() end}},i=0}}} end
k._recentSets={'loud','quiet'};k._clickSet=nil;k._audioMuted=true
k._set='quiet';k:_loadMouse();same(k._mouseSet,'quiet','clicks follow the key set');same(k._mousePool,nil,'no second pool when sets match')
k._set='chant';k:_loadMouse();same(k._mouseSet,'loud','performed key set borrows the most recent regular set');same(built[#built],'/l','borrowed set pools loaded')
k:_settingsAction('clickSet','quiet');same(k._clickSet,'quiet','click set chosen');same(k._mouseSet,'quiet','chosen click set wins')
rejects('clickSet','chant');same(k._clickSet,'quiet','performed sets cannot voice clicks')
rejects('clickSet','../elsewhere');rejects('clickSet',3)
k:_settingsAction('clickSet','');same(k._clickSet,nil,'same as keys');same(k._mouseSet,'loud','back to the borrowed default')
same(k:_settingsState().clickSource,'loud','state reports the click source')
-- A musical set with clicks is not borrowed while a keyboard set is available.
dirs.pipes='/p'; function k:_sets() return {'chant','loud','pipes','quiet'} end
function k:_hasClicks(d) return d=='/q' or d=='/l' or d=='/p' end
local realCategory=k._category; function k:_category(n) return n=='pipes' and 'interactive' or 'keyboard' end
k._recentSets={'pipes','quiet','loud'};k._set='chant';k:_loadMouse()
same(k._mouseSet,'quiet','a performed set borrows the recent keyboard set, not the recent musical one')
function k:_hasClicks(d) return d=='/p' end;k:_loadMouse()
same(k._mouseSet,'pipes','a musical set is borrowed when nothing else has clicks')
k:_settingsAction('clickSet','pipes');same(k._mouseSet,'pipes','a musical click set can still be chosen')
k:_settingsAction('clickSet','');k._category=realCategory
function k:_hasClicks(d) return d=='/q' or d=='/l' end;function k:_sets() return {'chant','loud','quiet'} end
k._set='quiet';k._audioMuted=false
print('settings tests: '..checks..' passed')
