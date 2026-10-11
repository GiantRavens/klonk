// Run inside Klonk's WKWebView with evaluateJavaScript. Restores preferences.
// Deliberately silent: preview playback is exercised at zero volume.
(async()=>{
 const initial=JSON.parse(JSON.stringify(state));
 const results=[];
 const receivers=new Map();
 const receive=window.klonkReceive;
 window.klonkReceive=message=>{receive(message);if(receivers.has(message.id)){const done=receivers.get(message.id);receivers.delete(message.id);done(message)}};
 const action=(name,value)=>new Promise((resolve,reject)=>{
  const id=seq+1;
  const timer=setTimeout(()=>{receivers.delete(id);reject(Error('No acknowledgement: '+name))},6000);
  receivers.set(id,message=>{clearTimeout(timer);message.error?reject(Error(message.error)):resolve(message)});
  send(name,value);
 });
 const check=(condition,name)=>{results.push({name,ok:!!condition});if(!condition)throw Error(name)};
 const change=(id,value)=>{const el=$(id);if(el.classList.contains('chip')){if((el.getAttribute('aria-pressed')==='true')!==value)el.click();else send(id,value);return}if(el.type==='checkbox')el.checked=value;else el.value=value;el.dispatchEvent(new Event('change',{bubbles:true}))};
 const fromControl=(id,value)=>new Promise((resolve,reject)=>{
  const n=seq+1,timer=setTimeout(()=>reject(Error('Control timeout: '+id)),6000);
  receivers.set(n,message=>{clearTimeout(timer);message.error?reject(Error(message.error)):resolve(message)});
  change(id,value);
 });
 try{
  await action('mute',true);
  await fromControl('keyboardOn',false);check($('keyboard-body').hidden&&!state.keyboardOn,'Keyboard off collapses controls');
  await fromControl('keyboardOn',true);check(!$('keyboard-body').hidden&&state.keyboard===initial.keyboard,'Keyboard on preserves sound');
  await fromControl('volume',42);check(state.volume===.42,'Volume control reaches engine');
  await fromControl('mouse',!initial.mouse);check(state.mouse!==initial.mouse&&$('mouse').getAttribute('aria-pressed')===String(state.mouse),'Clicks chip reaches engine');
  await fromControl('scroll',!initial.scroll);check(state.scroll!==initial.scroll,'Scroll chip reaches engine');
  await fromControl('keys',!initial.keys);check(state.keys!==initial.keys,'Keys chip reaches engine');
  const other=catalog.sets.find(x=>x.clicks&&x.name!==state.keyboard);
  await fromControl('clickSet',other.name);check(state.clickSet===other.name&&state.clickSource===other.name,'Click set reaches engine');
  check(![...$('clickSet').options].some(o=>catalog.sets.find(x=>x.name===o.value)&&!catalog.sets.find(x=>x.name===o.value).clicks),'Performed sets are not offered for clicks');
  await fromControl('ambientOn',true);const ambient=state.ambient;check(!!ambient&&!$('ambient-body').hidden,'Ambient on restores a sound');
  await fromControl('ambientOn',false);check(state.ambient===ambient&&!state.ambientOn,'Ambient off remembers choice');
  await fromControl('ambientOn',true);check(state.ambient===ambient,'Ambient re-enable restores selection');
  await fromControl('ambientVolume',24);check(state.ambientVolume===.24,'Ambient volume reaches engine');
  const desktop=state.desktop;
  await fromControl('desktopOn',false);check(!state.desktopOn&&state.desktop===desktop,'Desktop off preserves clip');
  await fromControl('desktopOn',true);check(state.desktop===desktop&&state.desktopOn,'Desktop on restores clip');
  await fromControl('speed',.75);check(state.speed===.75,'Playback speed reaches engine');
  await fromControl('cadence',20);check(state.cadence===20,'Rotation reaches engine');
  await fromControl('battery',!initial.battery);check(state.battery!==initial.battery,'Battery preference reaches engine');
  $('tab-tools').click();check(!$('tools').hidden&&$('keyboard-panel').hidden,'Tools tab opens');$('tab-presenter').click();check(!$('presenter-panel').hidden&&$('tools').hidden,'Presenter tab opens');
  await fromControl('presenter',true);await fromControl('specialOnly',true);check(state.presenter&&state.specialOnly&&!$('presenter-options').hidden,'Presenter controls reach engine');
  await fromControl('presenter',false);
  await fromControl('ambientOn',false);await fromControl('volume',0);
  await fromControl('keyboardOn',false);await action('mute',true);
  check($('preview-keyboard').textContent==='Unmute and try'&&!$('preview-keyboard').disabled,'Muted preview offers an explicit usable action');
  await action('unmutePreviewKeyboard',state.keyboard);check(state.preview==='keyboard'&&!state.muted,'Unmute and try starts preview independently of keyboard switch');
  await action('mute',true);check(!state.preview&&state.muted,'Mute stops active preview');
  let rejected=false;try{await action('volume',2)}catch{rejected=true}check(rejected&&state.volume===0,'Invalid value rejected without mutation');
  $('tab-desktop').click();check(!$('desktop-panel').hidden,'Desktop tab opens');
  $('desktop-search').value='no such desktop';$('desktop-search').dispatchEvent(new Event('input'));check(!$('gallery').querySelector('.tile'),'Empty search handled');
  $('desktop-search').value='';$('desktop-search').dispatchEvent(new Event('input'));
  check(document.querySelectorAll('input:not([aria-label]):not([id])').length===0,'Form inputs have label targets');
 }catch(error){results.push({name:error.message,ok:false})}
 finally{
  for(const [name,value] of Object.entries({mute:true,volume:initial.volume,ambientVolume:initial.ambientVolume,keyboardOn:initial.keyboardOn,keys:initial.keys,mouse:initial.mouse,scroll:initial.scroll,clickSet:initial.clickSet,speed:initial.speed,cadence:initial.cadence,battery:initial.battery,presenter:initial.presenter,specialOnly:initial.specialOnly,ambientOn:initial.ambientOn,desktopOn:initial.desktopOn})){
   try{await action(name,value)}catch(error){results.push({name:'Restore '+name+': '+error.message,ok:false})}
  }
  try{await action('mute',initial.muted)}catch(error){results.push({name:'Restore mute',ok:false})}
  window.klonkReceive=receive;
  window.klonkTestResult={ok:results.every(r=>r.ok),results};
  section('keyboard');window.scrollTo(0,0);
 }
})();
'Live checks started';
