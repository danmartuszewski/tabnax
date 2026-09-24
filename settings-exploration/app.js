/* Browser-only settings study. Preferences persist locally; windows, permissions and focus are synthetic. */
(() => {
'use strict';
const M=TabnaxModel,V=TabnaxModes, $=id=>document.getElementById(id), clone=M.clone;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const STORE='tabnax.settings-study.v1';
let cfg=clone(M.defaults), storageOK=true, pane='selection';
try { const old=JSON.parse(localStorage.getItem(STORE)); if(old?.config?.version===1) {
  const c=old.config, valid=M.validateAlphabet(c.selection?.alphabet||'');
  if(!valid.error&&['stable','mnemonic','pairs'].includes(c.selection?.policy)) cfg={...cfg,...c,selection:{...cfg.selection,...c.selection,baseHand:M.baseHand(c.selection)},position:{...cfg.position,...c.position},browserTabs:{...cfg.browserTabs,...c.browserTabs},themeOverrides:c.themeOverrides||{}};
  if(['general','selection','position','appearance','tabs'].includes(old.pane))pane=old.pane;
}}catch{storageOK=false;}
if(!V.definitions[cfg.displayMode])cfg.displayMode='shore';
cfg.modePositions=cfg.modePositions||{};
cfg.selection.baseHand=M.baseHand(cfg.selection);
let targets=clone(M.windows.slice(0,8)),engine=M.create(cfg.selection,targets),draft=null,draftSelection=null,draftInvalid=false;
let foldEngine=V.createFold(cfg.selection,targets),foldDraft=null,focus={current:'code',previous:null};
let history=[],picked=0,active=false,prefix='',query=null,searchIndex=0,held=false,nextID=1,recording=false,dialogAction=null;
let harness={dataset:'8',layout:'list',system:'auto',activeBrowser:'arc',contrast:false,motion:false,focusFailure:false,permission:'unknown'};
let otherCatalogue={targets:clone(M.tabs),engine:M.create({...cfg.selection,policy:'pairs'},M.tabs),dataset:'tabs'};
const icons={arc:'A',zen:'◌',firefox:'◉',edge:'e',brave:'♜',chrome:'◉',code:'‹›',safari:'◈',finder:'⌣',figma:'●',terminal:'›_',notes:'≡'};
const foldActive=()=>cfg.displayMode==='fold'&&!isTabs();
const effective=()=>foldActive()?(foldDraft||foldEngine):(draft||engine);
const hasDraft=()=>!!(draft||foldDraft||draftInvalid);
const windowTargets=()=>isTabs()?otherCatalogue.targets:targets;
const currentPosition=()=>cfg.displayMode==='shore'?cfg.position:(cfg.modePositions[cfg.displayMode]||{...M.defaults.position,anchor:V.definitions[cfg.displayMode].anchor});
const isTabs=()=>harness.dataset==='tabs';
const visible=()=>{
 const included=M.includedBrowsers(cfg.browserTabs),list=targets.filter(t=>isTabs()?cfg.browserTabs.enabled&&included.includes(t.browserId)&&!t.private&&(cfg.browserTabs.range==='all'||(cfg.browserTabs.range==='browser'?t.browserId===harness.activeBrowser:t.windowId===harness.activeBrowser+'-work')):(cfg.minimized||!t.minimized)&&(cfg.hidden||!t.hidden));
 return isTabs()?list.sort((a,b)=>M.browsers.findIndex(x=>x.id===a.browserId)-M.browsers.findIndex(x=>x.id===b.browserId)):list;
};
function snapshot(){return clone({cfg,engine,foldEngine,targets,otherCatalogue,dataset:harness.dataset});}
function checkpoint(){history.push(snapshot());if(history.length>20)history.shift();$('undo').disabled=false;}
function save(message='Saved on this device') {
 try{localStorage.setItem(STORE,JSON.stringify({config:cfg,pane}));}catch{storageOK=false;}
 $('save-status').textContent=storageOK?message:'Storage unavailable · changes last for this page';
}
function announce(text){$('selection-result').textContent=text;}
function cancel(message){active=false;held=false;prefix='';query=null;$('search-box').hidden=true;if(message)announce(message);renderPreview();}
function mutate(key,value){checkpoint();cfg[key]=value;save();renderControls();renderPreview();}
function currentSelection(){return draftSelection||cfg.selection;}
function otherSelectionChanges(selection){return selection.alphabet!==cfg.selection.alphabet||(otherCatalogue.dataset!=='tabs'&&selection.policy!==cfg.selection.policy);}
function setPane(name){pane=name;document.querySelectorAll('button[data-pane]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.pane===pane)));document.querySelectorAll('.pane').forEach(p=>p.hidden=p.id!=='pane-'+name);$('window-title').textContent=name==='tabs'?'Browser Tabs':name[0].toUpperCase()+name.slice(1);document.body.dataset.pane=name;save();renderDraft();renderPosition();}
function isDark(){return cfg.appearance==='dark'||(cfg.appearance==='system'&&(harness.system==='dark'||(harness.system==='auto'&&matchMedia('(prefers-color-scheme: dark)').matches)));}
function style(){
 const dark=isDark();
 document.body.classList.toggle('dark',dark);document.body.dataset.theme=cfg.theme;
 document.body.classList.toggle('strong',cfg.strongLabels);document.body.classList.toggle('contrast',harness.contrast||matchMedia('(prefers-contrast: more)').matches);document.body.classList.toggle('no-motion',harness.motion||matchMedia('(prefers-reduced-motion: reduce)').matches);
 const palette=M.resolveTheme(cfg.theme,dark?'dark':'light',cfg.themeOverrides);
 for(const [token,value] of Object.entries({preview:palette.surface,previewText:palette.text,previewMuted:palette.muted,keyBg:palette.keyBg,keyFg:palette.keyFg,keyBorder:palette.keyBorder,selectionAccent:palette.selection}))document.body.style.setProperty('--'+token,value);
 renderThemeControls(palette,dark);
 document.body.style.setProperty('--labelFont',({standard:12,large:17,extra:24}[cfg.labelSize]||12)+'px');
}
function renderControls(){
 const s=currentSelection();$('hand').value=s.hand;$('alphabet').value=s.alphabet;$('policy').value=isTabs()?'pairs':foldActive()?'stable':s.policy;$('policy').disabled=isTabs()||foldActive();
 $('display-mode').value=cfg.displayMode;$('mode-description').textContent=V.definitions[cfg.displayMode].description;
 $('pin-code').maxLength=foldActive()?8:4;$('pin-code').placeholder=foldActive()?'Full label, e.g. JH':'Free label, e.g. H';
 $('key-mode').value=cfg.keyMode;$('record').textContent=recording?'Press shortcut…':cfg.shortcut;$('activation').value=cfg.activation;$('modifier-side').value=cfg.modifierSide;
 $('reset-shortcut').disabled=cfg.shortcut===M.defaults.shortcut&&!recording;
 $('activation-help').textContent=cfg.activation==='latch'?'Release the shortcut, then type. Escape cancels.':'Select while holding the shortcut. Releasing without selection cancels.';
 for(const id of ['login','minimized','hidden'])$(id).checked=cfg[id];
 document.querySelectorAll('[name=appearance]').forEach(r=>r.checked=r.value===cfg.appearance);
 document.querySelectorAll('button[data-theme]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.theme===cfg.theme)));
 $('label-size').value=cfg.labelSize;$('strong-labels').checked=cfg.strongLabels;
 const position=currentPosition();$('position-display').value=position.display;$('position-inset').value=position.inset;$('inset-value').textContent=position.inset+' pt';
 $('position-mode').textContent='Position for '+V.definitions[cfg.displayMode].name+' · other modes keep their own placement';$('mode-position-note').textContent=V.definitions[cfg.displayMode].position;
 document.querySelectorAll('[data-anchor]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.anchor===position.anchor)));
 $('tabs-enabled').checked=cfg.browserTabs.enabled;$('tabs-range').value=cfg.browserTabs.range;$('default-scope').value=cfg.browserTabs.defaultScope;
 $('tabs-range').disabled=!cfg.browserTabs.enabled;$('default-scope').disabled=!cfg.browserTabs.enabled;$('preview-tabs').disabled=!cfg.browserTabs.enabled;
 const activeBrowser=M.browsers.find(b=>b.id===harness.activeBrowser).name;
 $('tabs-range-help').textContent=cfg.browserTabs.range==='all'?'The preview includes Arc, Zen, Safari, Chrome, Firefox, Edge and Brave.':cfg.browserTabs.range==='browser'?`Sample active browser: ${activeBrowser}. Only included browsers appear.`:`Sample active browser window: ${activeBrowser} · Work. No matching window means an empty tab view.`;
 renderBrowserControls();
 renderLetters(s.alphabet);policyHelp();renderDraft();style();renderPosition();
}
function renderLetters(raw){
 const a=M.normalize(raw);picked=Math.min(picked,Math.max(0,a.length-1));
 $('letter-order').innerHTML=[...a].map((c,i)=>`<button type="button" data-letter="${i}" aria-label="${esc(c)}, position ${i+1}${i===a.length-1?', overflow prefix':''}" aria-pressed="${i===picked}" class="${i===a.length-1?'branch':''}">${esc(c)}</button>`).join('');
 $('selected-letter').textContent=a[picked]?`${a[picked]} selected`:'Select a letter';$('move-left').disabled=picked===0;$('move-right').disabled=picked===a.length-1;$('remove-ambiguous').disabled=!/[IO]/.test(a);
 const hand=M.baseHand(currentSelection()),name={right:'Right hand',left:'Left hand',both:'Both hands'}[hand];
 $('reset-alphabet').disabled=a===M.presets[hand];
 $('alphabet-reset-help').textContent=`Restores the ${name} preset. Preview first, then Apply labels.`;
 $('reset-alphabet').title=`Restore ${name.toLowerCase()} order: ${[...M.presets[hand]].join(' ')}`;
}
function policyHelp(){
 const s=currentSelection(),policy=isTabs()?'pairs':foldActive()?'stable':s.policy,a=s.alphabet,last=a.at(-1);
 $('policy-help').textContent=({stable:'Windows keep their letters as you switch, rename or open other windows.',mnemonic:'Try an available app or title initial, then use your comfort order. Existing labels stay put.',pairs:'Every window starts with two letters. More room, with an extra key for every selection.'})[policy];
 $('overflow-note').innerHTML=policy==='pairs'?`Type both letters, with no pause or Enter. ${a.length*a.length} complete labels are available.`:`<kbd>${esc(last)}</kbd> is kept for more windows. The first ${a.length-1} use one letter; the next uses <kbd>${esc(last+a[0])}</kbd>. Learned labels never shift.`;
 if(foldActive()){$('policy-help').textContent='Fold uses a stable app prefix and stable child label. Your flat-window policy is kept for the other modes.';$('overflow-note').textContent='Type app then window, including singleton apps. The full label stays visible. Both stages can overflow; / searches all apps.';}
}
function renderDraft(){
 let changed=draft?targets.filter(t=>draft.map[t.id]!==engine.map[t.id]).length:0;
 if(draft&&draftSelection&&otherSelectionChanges(draftSelection)){
  const proposal=M.create({...draftSelection,policy:otherCatalogue.dataset==='tabs'?'pairs':draftSelection.policy},otherCatalogue.targets,otherCatalogue.engine.pins);
  changed+=otherCatalogue.targets.filter(t=>proposal.map[t.id]!==otherCatalogue.engine.map[t.id]).length;
 }
 if(foldDraft)changed+=windowTargets().filter(t=>foldDraft.map[t.id]!==foldEngine.map[t.id]).length;
 $('draft-bar').hidden=!hasDraft();$('apply').disabled=draftInvalid||(!draft&&!foldDraft);
 if(hasDraft())$('save-status').textContent='Label changes not applied';
 else if($('save-status').textContent==='Label changes not applied')$('save-status').textContent=storageOK?'Saved on this device':'Storage unavailable · changes last for this page';
 $('draft-summary').textContent=draftInvalid?'Fix the alphabet to continue':`${changed} label assignment${changed===1?'':'s'} will change`;
 $('draft-help').textContent='Preview only. Applying replaces the address session. You can undo it.';
 $('preview-state').textContent=draftInvalid?'Last valid labels':(draft||foldDraft)?'Unsaved labels':'Saved settings';
}
function stageSelection(selection){
 selection={...selection,baseHand:M.baseHand(selection)};
 cancel();draftInvalid=false;
 const result=M.validateAlphabet(selection.alphabet);
 $('alphabet-error').textContent=result.error;$('alphabet').setAttribute('aria-invalid',String(!!result.error));
 if(result.error){draftInvalid=true;renderDraft();return;}
 selection.alphabet=result.alphabet;draftSelection=selection;
 const allocSelection={...selection,policy:harness.dataset==='tabs'?'pairs':selection.policy};
 const otherSelection={...selection,policy:otherCatalogue.dataset==='tabs'?'pairs':selection.policy};
 const incompatible=Object.values((draft||engine).pins).some(p=>!M.codes(allocSelection.alphabet,allocSelection.policy).includes(p))||Object.values(otherCatalogue.engine.pins).some(p=>!M.codes(otherSelection.alphabet,otherSelection.policy).includes(p));
 if(incompatible){$('alphabet-error').textContent='This alphabet cannot keep a pinned label. Discard, then reset label assignments to clear pins first.';draftInvalid=true;renderDraft();return;}
 if(selection.alphabet!==(foldDraft||foldEngine).selection.alphabet){const nextFold=V.reassignFold(foldDraft||foldEngine,selection,windowTargets());if(nextFold.error){$('alphabet-error').textContent=nextFold.error;draftInvalid=true;renderDraft();return;}foldDraft=nextFold.state;}
 draft=M.create(allocSelection,targets,(draft||engine).pins);prefix='';renderControls();renderPreview();
}
function discard(){foldDraft=null;draft=null;draftSelection=null;draftInvalid=false;$('mode-error').textContent='';$('alphabet-error').textContent='';$('alphabet').setAttribute('aria-invalid','false');$('pin-error').textContent='';cancel();renderControls();renderPreview();}
function apply(){
 if((!draft&&!foldDraft)||draftInvalid)return;checkpoint();
 if(draftSelection&&otherSelectionChanges(draftSelection))otherCatalogue.engine=M.create({...draftSelection,policy:otherCatalogue.dataset==='tabs'?'pairs':draftSelection.policy},otherCatalogue.targets,otherCatalogue.engine.pins);
 cfg.selection=clone(draftSelection||cfg.selection);if(draft)engine=draft;if(foldDraft)foldEngine=foldDraft;
 draft=null;foldDraft=null;draftSelection=null;draftInvalid=false;$('mode-error').textContent='';cancel();save('Labels applied · Undo available');renderControls();renderPreview();announce('New labels applied. Undo restores the previous labels.');
}
function renderPreview(){
 style();const state=effective(),list=visible();
 $('preview-surface').dataset.mode=cfg.displayMode;
 $('mode-preview-note').textContent=V.definitions[cfg.displayMode].name+' · '+(isTabs()?({canopy:'tabs grouped by browser window',lattice:'two-letter tab grid'}[cfg.displayMode]||'two-letter tab list'):({fold:'app → window · separate addresses',relay:'Enter returns · letters select',beacons:'plaques + out-of-sight bank',canopy:'grouped apps · direct window labels',lattice:'address cells · prefixes open another grid',shore:'compact index · direct window labels'}[cfg.displayMode]));
 const matches=query===null?(prefix&&harness.dataset==='tabs'&&harness.layout==='list'?list.filter(t=>state.map[t.id]?.startsWith(prefix)):list):list.filter(t=>(query.toLowerCase().trim().split(/\s+/)).every(q=>(t.name+' '+t.title+' '+(t.context||'')).toLowerCase().includes(q)));
 searchIndex=Math.max(0,Math.min(searchIndex,matches.length-1));
 $('scope-name').textContent=isTabs()?'Browser tabs':'Windows';$('window-count').textContent=String(matches.length);
 $('scope-windows').setAttribute('aria-pressed',String(!isTabs()));$('scope-tabs').setAttribute('aria-pressed',String(isTabs()));$('scope-tabs').disabled=!cfg.browserTabs.enabled;
 $('search').placeholder=isTabs()?'Find a browser tab…':'Find a window…';
 document.querySelector('.inventory>summary').textContent=isTabs()?'Inspect labels & tabs':'Inspect labels & windows';
 $('add-window').textContent=isTabs()?'＋ Add a tab':'＋ Add a window';
 $('preview-surface').classList.toggle('armed',active);$('targets').classList.toggle('grid',harness.layout==='grid'&&query===null&&cfg.displayMode==='shore');
 const markup=t=>{
   const label=state.map[t.id]||'—',idx=matches.indexOf(t),isMatch=!prefix||label.startsWith(prefix);
   const labelHTML=prefix&&isMatch?`<span class="entered">${esc(prefix)}</span>${esc(label.slice(prefix.length))}`:esc(label);
   return `<button type="button" class="target ${!isMatch?'dim':''} ${query!==null&&idx===searchIndex?'highlight':''}" data-target="${esc(t.id)}" aria-label="${esc(t.name+': '+t.title+'. Label '+label+(t.minimized?'. Minimized':''))}" title="${esc(t.title)}"><span class="app-icon ${esc(t.app)}" aria-hidden="true">${icons[t.app]||'▧'}</span><span class="target-text"><span class="target-title">${esc(t.title)}</span><span class="target-meta">${esc(t.name+(t.context?' · '+t.context:'')+(t.minimized?' · minimized':'')+(t.hidden?' · hidden':''))}</span></span><span class="key-label" aria-hidden="true">${labelHTML}</span></button>`;
 };
 const modeMarkup=V.render({mode:cfg.displayMode,tabs:isTabs(),list:cfg.displayMode==='lattice'?list:matches,state,prefix,query,markup,esc,focus});
 if(modeMarkup!==null&&list.length)$('targets').innerHTML=modeMarkup;
 else if(harness.layout==='grid'&&query===null&&cfg.displayMode==='shore'){let cells=[];for(let i=0;i<state.nextSlot;i++){const t=list.find(t=>state.slots[t.id]===i);cells.push(t?markup(t):'<div class="empty-cell">Held position</div>');}$('targets').innerHTML=cells.join('');}
 else $('targets').innerHTML=matches.map(markup).join('')||(query!==null?`<p class="help">No matching ${isTabs()?'tabs':'windows'}. Edit your search or press Escape.</p>`:(isTabs()?'<p class="help">No included tabs. Choose a browser or a wider scope in Browser Tabs settings.</p>':'<p class="help">No included windows. Add a sample window below.</p>'));
 $('sequence-hint').textContent=query!==null?'↑ ↓ choose · Enter selects':prefix?`${prefix} … next letter`:(active?'Listening for a label':'Type a label to switch');
 $('try').textContent=active?'Restart preview':'Try these keys';$('cancel-try').hidden=!active;
 $('try-instruction').textContent=active?'Letters select · Esc cancels':'No real windows will move.';
 const oldPin=$('pin-target').value;$('pin-target').innerHTML=targets.map(t=>`<option value="${esc(t.id)}">${esc(t.name+' · '+t.title)}</option>`).join('');if(targets.some(t=>t.id===oldPin))$('pin-target').value=oldPin;
 $('inventory').innerHTML=targets.map(t=>`<div class="inventory-row"><code>${esc(state.map[t.id]||'—')}${state.pins[t.id]?' ⌖':''}</code><span class="inv-title" title="${esc(t.title)}">${esc(t.title)}${!list.includes(t)?' (excluded)':''}</span><button data-rename="${esc(t.id)}" aria-label="Rename ${esc(t.title)}" title="Rename">✎</button><button data-remove="${esc(t.id)}" aria-label="Close ${esc(t.title)}" title="Close simulated window">−</button></div>`).join('');
 $('held-labels').textContent=targets.some(t=>!state.map[t.id])?'All short labels are in use. Reset labels to reuse closed-window labels. Unlabelled windows can still be clicked or found with /.':state.retired.length?`Held labels: ${state.retired.join(', ')}. They are not reused until you reset.`:'Closing a window holds its label for this session.';
 $('add-window').disabled=targets.length>=(isTabs()?80:40);renderDraft();renderPosition();
}
function arm(){active=true;prefix='';query=null;searchIndex=0;$('search-box').hidden=true;renderPreview();$('preview-surface').focus();announce('Preview ready. Type the visible letter or sequence.');}
function selectTarget(id){const t=visible().find(t=>t.id===id);if(!t)return;
 if(harness.focusFailure){cancel();announce('Could not select '+t.name+' · '+t.title+'. Simulated failure; return history unchanged.');return;}
 if(!isTabs()&&focus.current!==id){focus.previous=windowTargets().some(w=>w.id===focus.current)?focus.current:null;focus.current=id;}
 cancel();announce(`Selected ${t.name} · ${t.title}. Simulated only.`);$('try').focus();}
function returnPrevious(){const t=visible().find(t=>t.id===focus.previous&&t.id!==focus.current);if(t&&!isTabs())selectTarget(t.id);else announce('No previous available window. Choose a window first.');}

function keyDown(e){
 if(e.isComposing||e.repeat)return;
 if(active&&!e.metaKey&&!e.ctrlKey&&!e.altKey&&(e.code==='Digit1'||e.code==='Digit2')&&query===null){e.preventDefault();switchScope(e.code==='Digit2'?'tabs':'windows',true);return;}
 if(e.key==='Tab'){cancel('Preview stopped. Tab continues through the settings.');return;}
 if(e.key==='Shift'&&e.code===(currentSelection().hand==='left'?'ShiftRight':'ShiftLeft')&&e.target===$('preview-surface')){if(!active)arm();held=true;return;}
 if(e.metaKey||e.ctrlKey||e.altKey)return;
 if(query!==null){
  if(e.key==='Escape'){e.preventDefault();query=null;prefix='';$('search-box').hidden=true;renderPreview();$('preview-surface').focus();}
  else if(['ArrowDown','ArrowUp','Enter'].includes(e.key)){
   e.preventDefault();const matches=visible().filter(t=>query.toLowerCase().trim().split(/\s+/).every(q=>(t.name+' '+t.title+' '+(t.context||'')).toLowerCase().includes(q)));
   if(e.key==='Enter'){if(matches[searchIndex])selectTarget(matches[searchIndex].id);}else{searchIndex=Math.max(0,Math.min(matches.length-1,searchIndex+(e.key==='ArrowDown'?1:-1)));renderPreview();}
  }return;
 }
 if(e.target.closest('button')&&['Enter',' '].includes(e.key))return;
 if(e.key===' '){e.preventDefault();if(active)cancel('Cancelled. No window selected.');else arm();return;}
 if(!active)return;
 if(e.key==='Enter'&&cfg.displayMode==='relay'&&!isTabs()&&!prefix){e.preventDefault();returnPrevious();return;}
 if(e.key==='Escape'){e.preventDefault();if(prefix){prefix='';renderPreview();announce('Sequence cleared.');}else cancel('Cancelled. No window selected.');return;}
 if(e.key==='Backspace'){e.preventDefault();prefix=prefix.slice(0,-1);renderPreview();return;}
 if(e.code==='Slash'||e.key==='/'){e.preventDefault();prefix='';query='';searchIndex=0;$('search-box').hidden=false;$('search').value='';renderPreview();$('search').focus();return;}
 const key=cfg.keyMode==='physical'?(e.code.startsWith('Key')?e.code.slice(3):''):e.key.toUpperCase();
 if(!/^[A-Z]$/.test(key))return;
 e.preventDefault();const next=prefix+key,state=effective(),list=visible();
 const exact=list.find(t=>state.map[t.id]===next);if(exact){selectTarget(exact.id);return;}
 if(list.some(t=>state.map[t.id]?.startsWith(next))){prefix=next;renderPreview();announce(`${prefix}. Type the next letter.`);}
 else{announce(`No ${isTabs()?'tab':'window'} has ${next}. ${prefix?'Your prefix '+prefix+' is kept. Backspace goes back.':'Try a visible label.'}`);}
}
function showDialog(title,copy,action,confirm='Continue'){$('dialog-title').textContent=title;$('dialog-copy').textContent=copy;$('dialog-confirm').textContent=confirm;dialogAction=action;$('dialog').showModal();}
$('dialog').addEventListener('close',()=>{if($('dialog').returnValue==='confirm')dialogAction?.();dialogAction=null;});
document.querySelectorAll('button[data-pane]').forEach(b=>b.onclick=()=>setPane(b.dataset.pane));
$('hand').onchange=e=>stageSelection({...currentSelection(),hand:e.target.value,alphabet:M.presets[e.target.value]||$('alphabet').value});
$('alphabet').oninput=e=>{const raw=e.target.value;renderLetters(raw);stageSelection({...currentSelection(),hand:'custom',alphabet:raw});if(!draftInvalid){$('alphabet').focus();$('alphabet').setSelectionRange(raw.length,raw.length);}};
$('letter-order').onclick=e=>{const b=e.target.closest('[data-letter]');if(b){picked=Number(b.dataset.letter);renderLetters($('alphabet').value);document.querySelector(`[data-letter="${picked}"]`)?.focus();}};
function move(delta){let a=[...M.normalize($('alphabet').value)],j=picked+delta;if(j<0||j>=a.length)return;[a[picked],a[j]]=[a[j],a[picked]];picked=j;stageSelection({...currentSelection(),hand:'custom',alphabet:a.join('')});}
$('move-left').onclick=()=>move(-1);$('move-right').onclick=()=>move(1);
$('remove-ambiguous').onclick=()=>stageSelection({...currentSelection(),hand:'custom',alphabet:$('alphabet').value.replace(/[IOio]/g,'')});
$('reset-alphabet').onclick=()=>{
 const hand=M.baseHand(currentSelection());
 stageSelection({...currentSelection(),hand,baseHand:hand,alphabet:M.presets[hand]});
 renderControls();renderPreview();
 if(!draftInvalid)announce('Default letter order previewed. Apply labels to save, or Discard to keep your saved order.');
};
$('policy').onchange=e=>stageSelection({...currentSelection(),policy:e.target.value});
$('discard').onclick=discard;$('apply').onclick=apply;
$('pin').onclick=()=>{
 if(draftInvalid){$('pin-error').textContent='Fix the alphabet first.';return;}
 const candidate=clone(effective()),target=targets.find(t=>t.id===$('pin-target').value);if(!target)return;
 const error=foldActive()?V.pinFold(candidate,target,$('pin-code').value):M.pin(candidate,target.id,$('pin-code').value);$('pin-error').textContent=error;if(error)return;
 if(foldActive())foldDraft=candidate;else draft=candidate;draftSelection=clone(currentSelection());cancel();renderDraft();renderPreview();
};
$('reset-labels').onclick=()=>showDialog('Reset label assignments?','Preview fresh labels for the current view and mode. Held labels become available and its session pins are removed. Other namespaces stay unchanged. Nothing changes until you apply.',()=>{
 if(foldActive())foldDraft=V.createFold(currentSelection(),targets);else draft=M.create({...currentSelection(),policy:isTabs()?'pairs':currentSelection().policy},targets);
 draftSelection=clone(currentSelection());draftInvalid=false;$('alphabet-error').textContent='';cancel();renderControls();renderPreview();
},'Preview reset');
for(const id of ['login','minimized','hidden'])$(id).onchange=e=>{cancel();mutate(id,e.target.checked);if(id==='login')save('Login preference saved · OS unchanged');};
for(const [id,key] of [['activation','activation'],['modifier-side','modifierSide'],['key-mode','keyMode'],['label-size','labelSize']])$(id).onchange=e=>{if(id!=='label-size')cancel();mutate(key,e.target.value);};
$('strong-labels').onchange=e=>mutate('strongLabels',e.target.checked);
document.querySelectorAll('[name=appearance]').forEach(r=>r.onchange=()=>mutate('appearance',r.value));
document.querySelectorAll('button[data-theme]').forEach(b=>b.onclick=()=>mutate('theme',b.dataset.theme));
$('undo').onclick=()=>{const old=history.pop();if(!old)return;cfg=old.cfg;engine=old.engine;foldEngine=old.foldEngine;foldDraft=null;targets=old.targets;otherCatalogue=old.otherCatalogue;harness.dataset=old.dataset;$('dataset').value=harness.dataset;draft=null;draftSelection=null;draftInvalid=false;$('alphabet-error').textContent='';cancel();$('undo').disabled=!history.length;save('Previous settings restored');renderControls();renderPreview();};
$('restore').onclick=()=>showDialog('Restore Tabnax defaults?','Restore display mode, themes, all mode positions, browser tabs, activation preferences and selection keys. Window, tab and Fold addresses receive fresh labels and pins are removed. System permissions stay unchanged. Undo restores this session’s previous settings.',()=>{checkpoint();cfg=clone(M.defaults);foldDraft=null;draft=null;draftSelection=null;draftInvalid=false;$('alphabet-error').textContent='';engine=M.create({...cfg.selection,policy:harness.dataset==='tabs'?'pairs':cfg.selection.policy},targets);otherCatalogue.engine=M.create({...cfg.selection,policy:otherCatalogue.dataset==='tabs'?'pairs':cfg.selection.policy},otherCatalogue.targets);foldEngine=V.createFold(cfg.selection,windowTargets());cancel();save('Defaults restored · Undo available');renderControls();renderPreview();},'Restore defaults');
$('permission-info').onclick=()=>showDialog('Accessibility access','In the native app, this explains why access is needed and opens the relevant System Settings page. This prototype cannot inspect, request or grant permissions. The selected scenario is only an illustration.',null,'Done');
$('record').onclick=()=>{recording=!recording;$('shortcut-error').textContent='';$('record').textContent=recording?'Press shortcut…':cfg.shortcut;$('reset-shortcut').disabled=cfg.shortcut===M.defaults.shortcut&&!recording;};
$('reset-shortcut').onclick=()=>{
 recording=false;$('shortcut-error').textContent='';cancel();
 if(cfg.shortcut!==M.defaults.shortcut)mutate('shortcut',M.defaults.shortcut);else renderControls();
 announce('Suggested shortcut restored. Activation behavior and modifier side are kept.');
};
$('record').addEventListener('keydown',e=>{
 if(!recording)return;
 if(e.key==='Tab'){recording=false;renderControls();return;}
 e.preventDefault();if(e.key==='Escape'){recording=false;renderControls();return;}
 if(['Meta','Control','Alt','Shift'].includes(e.key))return;
 if(!(e.ctrlKey||e.metaKey||e.altKey)){$('shortcut-error').textContent='Use Control, Option or Command with a key. Plain typing keys stay available.';return;}
 if((e.metaKey&&['tab',' ','q','w',','].includes(e.key.toLowerCase()))||(e.ctrlKey&&e.key===' ')){$('shortcut-error').textContent='This combination commonly belongs to macOS. Record another shortcut.';return;}
 const parts=[e.ctrlKey?'⌃':'',e.altKey?'⌥':'',e.shiftKey?'⇧':'',e.metaKey?'⌘':'',e.code==='Space'?'Space':e.key.toUpperCase()].filter(Boolean);
 recording=false;$('shortcut-error').textContent='';mutate('shortcut',parts.join(' '));$('shortcut-help').textContent='Sample recorded. Global conflicts cannot be checked in this browser.';
});
$('record').addEventListener('blur',()=>{if(recording){recording=false;renderControls();}});
$('try').onclick=arm;$('cancel-try').onclick=()=>cancel('Cancelled. No window selected.');
$('preview-surface').addEventListener('keydown',keyDown);
$('preview-surface').addEventListener('keyup',e=>{if(held&&e.code===(currentSelection().hand==='left'?'ShiftRight':'ShiftLeft'))cancel('Hold released. No window selected.');});
$('targets').onclick=e=>{
 const target=e.target.closest('[data-target]'),branch=e.target.closest('[data-mode-prefix]');
 if(target){selectTarget(target.dataset.target);return;}
 if(branch){if(!active)arm();prefix=branch.dataset.modePrefix;renderPreview();$('preview-surface').focus();return;}
 if(e.target.closest('[data-mode-back]')){prefix='';renderPreview();$('preview-surface').focus();return;}
 if(e.target.closest('[data-return-window]'))returnPrevious();
};
$('search').oninput=e=>{query=e.target.value;searchIndex=0;renderPreview();};
$('inventory').onclick=e=>{
 const close=e.target.closest('[data-remove]'),rename=e.target.closest('[data-rename]');
 if(close){const id=close.dataset.remove,closed=targets.find(t=>t.id===id);checkpoint();if(!isTabs()&&closed){V.retireFold(foldEngine,closed);if(foldDraft)V.retireFold(foldDraft,closed);if(focus.current===id)focus.current=null;if(focus.previous===id)focus.previous=null;}targets=targets.filter(t=>t.id!==id);M.retire(engine,id);if(draft)M.retire(draft,id);prefix='';renderPreview();announce((isTabs()?'Tab':'Window')+' closed. Its label is held until reset.');}
 if(rename){const t=targets.find(t=>t.id===rename.dataset.rename);if(t){checkpoint();t.title=t.title.endsWith(' · renamed')?t.title.replace(' · renamed',''):t.title+' · renamed';renderPreview();announce('Title changed. Its label stayed the same.');}}
};
$('add-window').onclick=()=>{checkpoint();const browser=M.browsers.find(b=>b.id===harness.activeBrowser),t={id:'new-'+nextID++,app:isTabs()?browser.id:'safari',name:isTabs()?browser.name:'Safari',title:'Reference · New '+(isTabs()?'tab ':'window ')+(nextID-1),...(isTabs()?{browserId:browser.id,windowId:browser.id+'-work',context:'Work',private:false}:{})};targets.push(t);if(!isTabs()){V.allocateFold(foldEngine,t);if(foldDraft)V.allocateFold(foldDraft,t);}M.allocate(engine,t);if(draft)M.allocate(draft,t);prefix='';renderPreview();announce((isTabs()?'Tab':'Window')+' added. Existing labels stayed the same.');};
$('dataset').onchange=e=>{
 if((e.target.value==='tabs')!==isTabs())otherCatalogue={targets,engine,dataset:harness.dataset};
 harness.dataset=e.target.value;foldDraft=null;draft=null;draftSelection=null;draftInvalid=false;history=[];$('undo').disabled=true;$('alphabet-error').textContent='';
 targets=isTabs()?clone(M.tabs):clone(M.windows.slice(0,Number(harness.dataset)));
 engine=M.create({...cfg.selection,policy:harness.dataset==='tabs'?'pairs':cfg.selection.policy},targets);if(!isTabs()){foldEngine=V.createFold(cfg.selection,targets);focus={current:targets[0]?.id||null,previous:null};}cancel();renderControls();renderPreview();announce('New simulated dataset. A fresh address session has started.');
};
$('layout').onchange=e=>{harness.layout=e.target.value;renderPreview();};$('system-appearance').onchange=e=>{harness.system=e.target.value;style();};
$('simulate-focus-failure').onchange=e=>{harness.focusFailure=e.target.checked;cancel();};
$('simulate-contrast').onchange=e=>{harness.contrast=e.target.checked;style();};$('simulate-motion').onchange=e=>{harness.motion=e.target.checked;style();};
$('permission-scenario').onchange=e=>{harness.permission=e.target.value;$('permission-status').textContent=({unknown:'Not checked in this prototype',denied:'Access denied · simulated',revoked:'Access revoked · simulated',granted:'Access granted · simulated only'})[e.target.value];cancel();announce('Permission scenario changed. The sample preview remains available; macOS is unchanged.');};
window.addEventListener('blur',()=>{if(active)cancel('Preview cancelled when browser focus changed.');});
document.addEventListener('pointerdown',e=>{if(active&&!e.target.closest('.preview-column'))cancel();});
for(const media of ['(prefers-color-scheme: dark)','(prefers-contrast: more)','(prefers-reduced-motion: reduce)'])matchMedia(media).addEventListener('change',style);
// Read-only inspection hook for repeatable prototype verification.
window.TabnaxStudy={inspect:()=>clone({cfg,engine,draft,foldEngine,foldDraft,focus,targets,active,prefix,query,harness,storageOK,otherCatalogue})};

function switchScope(next,keepOpen=false){
 if((next==='tabs')===isTabs()){if(keepOpen){prefix='';query=null;renderPreview();}return;}
 if(next==='tabs'&&!cfg.browserTabs.enabled){announce('Enable browser tabs in Browser Tabs settings first.');return;}
 if(hasDraft()){announce('Apply or discard label changes before switching between windows and tabs.');return;}
 const wasHeld=held,old={targets,engine,dataset:harness.dataset};
 targets=otherCatalogue.targets;engine=otherCatalogue.engine;harness.dataset=otherCatalogue.dataset;otherCatalogue=old;$('dataset').value=harness.dataset;
 cancel();renderControls();renderPreview();if(keepOpen){arm();held=wasHeld;}
 announce(next==='tabs'?'Sample browser tabs. Type both letters, or / to find a title.':'Windows. Your window labels are unchanged.');
}
function mutateGroup(group,key,value){checkpoint();cfg[group]={...cfg[group],[key]:value};cancel();save();renderControls();renderPreview();}
function renderPosition(previewInset){
 const {anchor,display}=currentPosition(),inset=previewInset??currentPosition().inset,parts=anchor.split('-'),vertical=parts[0],horizontal=parts[1];
 const text=anchor==='middle-center'?'Center':anchor.replace('middle-','Middle ').replace('top-','Top ').replace('bottom-','Bottom ');
 $('position-summary').textContent=text;
 $('position-preview').hidden=pane!=='position';
 const mini=$('position-mini-switcher'),gap=8+inset*.16;
 mini.style.left=horizontal==='left'?gap+'px':horizontal==='right'?`calc(100% - ${gap}px)`:'50%';
 mini.style.top=vertical==='top'?(22+inset*.16)+'px':vertical==='bottom'?`calc(100% - ${22+inset*.16}px)`:'50%';
 mini.style.transform=`translate(${horizontal==='right'?'-100%':horizontal==='center'?'-50%':'0'},${vertical==='bottom'?'-100%':vertical==='middle'?'-50%':'0'})`;
 const external=display==='focused';$('display-main').classList.toggle('selected',!external);$('display-external').classList.toggle('selected',external);
 $('position-caption').textContent=`${text} · ${external?'External':'Main'} display · ${inset} pt edge spacing. Sample active window: External; pointer: Main.`;
 $('position-desktop').setAttribute('aria-label',`Simulated ${text.toLowerCase()} switcher on ${external?'External':'Main'} display with ${inset} point edge spacing.`);
 const rows=visible().slice(0,4);$('position-mini-switcher').innerHTML='<b>'+ (isTabs()?'Tabs':'Windows')+'</b>'+rows.map(t=>`<span>▧ &nbsp; ${esc(t.name)} <kbd>${esc(effective().map[t.id]||'—')}</kbd></span>`).join('');
}
$('scope-windows').onclick=()=>switchScope('windows');$('scope-tabs').onclick=()=>switchScope('tabs');
$('preview-tabs').onclick=()=>{switchScope('tabs');if(isTabs())arm();};
$('position-display').onchange=e=>updatePosition('display',e.target.value);
$('position-inset').oninput=e=>{$('inset-value').textContent=e.target.value+' pt';renderPosition(Number(e.target.value));};
$('position-inset').onchange=e=>updatePosition('inset',Number(e.target.value));
document.querySelectorAll('[data-anchor]').forEach(b=>b.onclick=()=>updatePosition('anchor',b.dataset.anchor));
function updatePosition(key,value){
 if(cfg.displayMode==='shore')mutateGroup('position',key,value);
 else mutate('modePositions',{...cfg.modePositions,[cfg.displayMode]:{...currentPosition(),[key]:value}});
}
$('position-reset').onclick=()=>{
 if(cfg.displayMode==='shore')mutate('position',clone(M.defaults.position));
 else{const positions=clone(cfg.modePositions);delete positions[cfg.displayMode];mutate('modePositions',positions);}
};
$('display-mode').onchange=e=>{
 if(hasDraft()){$('mode-error').textContent='Apply or discard label changes in Selection before changing modes.';e.target.value=cfg.displayMode;return;}
 $('mode-error').textContent='';cancel();mutate('displayMode',e.target.value);announce(V.definitions[cfg.displayMode].name+' preview. '+V.definitions[cfg.displayMode].description);
};
$('tabs-enabled').onchange=e=>{
 if(hasDraft()){e.target.checked=cfg.browserTabs.enabled;announce('Apply or discard label changes before changing browser tab availability.');return;}
 checkpoint();cfg.browserTabs.enabled=e.target.checked;if(!e.target.checked){cfg.browserTabs.defaultScope='windows';switchScope('windows');}cancel();save();renderControls();renderPreview();
};
$('tabs-range').onchange=e=>mutateGroup('browserTabs','range',e.target.value);
$('default-scope').onchange=e=>{
 if(hasDraft()){e.target.value=cfg.browserTabs.defaultScope;announce('Apply or discard label changes before changing the opening view.');return;}
 const next=e.target.value;mutateGroup('browserTabs','defaultScope',next);switchScope(next);
};
function renderBrowserControls(){
 const automatic=cfg.browserTabs.selection==='automatic',included=M.includedBrowsers(cfg.browserTabs);
 $('browser-selection').value=cfg.browserTabs.selection;$('browser-selection').disabled=!cfg.browserTabs.enabled;
 $('browser-selection-status').textContent=!cfg.browserTabs.enabled?'Browser tabs are off. Your browser choices are kept.':automatic?'All 7 sample browsers included. Choose browsers to limit this list.':included.length?`${included.length} browser${included.length===1?'':'s'} included. Changes keep existing tab labels.`:'No browsers selected. Choose one below to show its tabs.';
 for(const b of M.browsers){$('browser-'+b.id).checked=included.includes(b.id);$('browser-'+b.id).disabled=automatic||!cfg.browserTabs.enabled;}
}
for(const container of ['primary-browsers','additional-browsers']){
 const list=container==='primary-browsers'?M.browsers.slice(0,4):M.browsers.slice(4);
 $(container).innerHTML=list.map(b=>`<div class="browser-connection"><input id="browser-${b.id}" data-browser="${b.id}" type="checkbox"><span class="app-icon ${b.id}" aria-hidden="true">${b.icon}</span><label for="browser-${b.id}"><strong>${b.name}</strong><span>${b.note} · sample tabs only</span></label><button data-browser-info="${b.name}" aria-label="${b.name} connection details">Setup…</button></div>`).join('');
 $(container).onchange=e=>{const id=e.target.dataset.browser;if(!id)return;const selected=new Set(cfg.browserTabs.selectedBrowsers);if(e.target.checked)selected.add(id);else selected.delete(id);mutateGroup('browserTabs','selectedBrowsers',[...selected]);};
}
$('browser-selection').onchange=e=>mutateGroup('browserTabs','selection',e.target.value);
$('active-browser').onchange=e=>{harness.activeBrowser=e.target.value;cancel();renderControls();renderPreview();};
for(const button of document.querySelectorAll('[data-browser-info]'))button.onclick=()=>{
 const b=M.browsers.find(b=>b.name===button.dataset.browserInfo);
 const copy=b.setup==='builtin'?`The planned ${b.name} connection is built in. Choose ${b.name}, then approve macOS access if asked. No extension or manual configuration is planned. Compatibility still needs a live connection test.`:b.setup==='addon'?`Choose ${b.name}. If a companion add-on is needed, Tabnax will guide you through installing and approving it in your browser. Tabnax will handle its app-side setup automatically. This connection still needs verification.`:`Choose ${b.name}. Tabnax will try the simplest supported connection and guide you through any required approval or add-on. The connection method is still being verified.`;
 showDialog(b.name+' setup',copy+' This prototype cannot inspect your browser, connect to it or install anything.',null,'Done');
};

function renderThemeControls(palette,dark){
 const mode=dark?'dark':'light',raw=cfg.themeOverrides[cfg.theme]?.[mode]||{};
 $('custom-mode').textContent='Editing '+(dark?'Dark':'Light')+' appearance · saved with this preset';
 $('custom-key-color').value=raw.keyBg||palette.keyBg;$('key-color-value').textContent=(raw.keyBg||palette.keyBg).toUpperCase();
 $('custom-selection-color').value=raw.selection||palette.selection;$('selection-color-value').textContent=(raw.selection||palette.selection).toUpperCase();
 $('theme-contrast').textContent='Letter contrast '+M.contrast(palette.keyFg,palette.keyBg).toFixed(1)+':1.'+(raw.selection&&raw.selection.toLowerCase()!==palette.selection.toLowerCase()?' Selection shade adjusted for visibility.':'');
 $('reset-theme').disabled=!Object.keys(cfg.themeOverrides[cfg.theme]||{}).length;
 for(const [id,key,label] of [['reset-key-color','keyBg','key'],['reset-selection-color','selection','selection']]){
  $(id).disabled=!Object.hasOwn(raw,key);
  $(id).setAttribute('aria-label',`Restore default ${label} color for ${mode} appearance`);
 }
 $('theme-description').textContent=({graphite:'Native neutral surfaces, with familiar Mac blue selection.',tabnax:'The original green: luminous keys on a quiet, green-tinted surface.',sage:'A softer green, paired with the native neutral surface.',iris:'A restrained violet accent, paired with the native neutral surface.'})[cfg.theme]||'';
}
let colorEdit=null;
function customizeTheme(key,color){
 const mode=isDark()?'dark':'light',overrides=clone(cfg.themeOverrides);
 overrides[cfg.theme]={...overrides[cfg.theme],[mode]:{...overrides[cfg.theme]?.[mode],[key]:color}};
 if(colorEdit!==key){checkpoint();colorEdit=key;}cfg.themeOverrides=overrides;save();renderControls();renderPreview();
}
for(const id of ['custom-key-color','custom-selection-color'])$(id).onblur=()=>{colorEdit=null;};
$('custom-key-color').oninput=e=>customizeTheme('keyBg',e.target.value);
$('custom-selection-color').oninput=e=>customizeTheme('selection',e.target.value);
$('reset-theme').onclick=()=>{const overrides=clone(cfg.themeOverrides);delete overrides[cfg.theme];mutate('themeOverrides',overrides);};
function resetThemeColor(key){
 const mode=isDark()?'dark':'light',overrides=clone(cfg.themeOverrides);
 if(!Object.hasOwn(overrides[cfg.theme]?.[mode]||{},key))return;
 delete overrides[cfg.theme][mode][key];
 if(!Object.keys(overrides[cfg.theme][mode]).length)delete overrides[cfg.theme][mode];
 if(!Object.keys(overrides[cfg.theme]).length)delete overrides[cfg.theme];
 colorEdit=null;mutate('themeOverrides',overrides);
 announce(`Default ${key==='keyBg'?'key':'selection'} color restored for ${mode} appearance. Undo is available.`);
}
$('reset-key-color').onclick=()=>resetThemeColor('keyBg');
$('reset-selection-color').onclick=()=>resetThemeColor('selection');

if(cfg.browserTabs.enabled&&cfg.browserTabs.defaultScope==='tabs')switchScope('tabs');

setPane(pane);renderControls();renderPreview();
})();
