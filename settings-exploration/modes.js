/* Mode behavior for the settings simulation. No native window geometry or focus APIs. */
(function(root){
'use strict';
const M=root.TabnaxModel||(typeof require==='function'?require('./model.js'):null);
const definitions={
 shore:{name:'Shore',anchor:'middle-right',description:'A compact index with direct window labels. Overflow adds a prefix; the other letters stay put.',position:'Places the window index and the browser-tab list.'},
 beacons:{name:'Beacons',anchor:'bottom-center',description:'Labels beside visible windows, with an out-of-sight bank for covered, hidden and minimized windows. Tabs use a compact list.',position:'Places the out-of-sight bank and tab list. Window plaques follow their windows; they do not move to this anchor.'},
 canopy:{name:'Canopy',anchor:'top-center',description:'Windows grouped by app. Every window still has a direct label. Tabs group by browser and browser window.',position:'Places the grouped panel. Grouping changes the scan, never the address.'},
 lattice:{name:'Lattice',anchor:'middle-center',description:'Fixed address cells, with held places after closing. A prefix opens its next grid; full tab addresses remain visible.',position:'Places the grid. Cells follow alphabet order and reflow to fit; labels never change on resize.'},
 fold:{name:'Fold',anchor:'middle-center',description:'App first, window second—even for an app with one window. Fold keeps its own stable addresses. Tabs use their existing two-letter list.',position:'Places the app spine and window sheet together. The sheet stays inside the usable screen.'},
 relay:{name:'Relay',anchor:'middle-right',description:'Enter returns to the previous distinct live window. Other windows keep their direct labels. Tab selection does not enter window history.',position:'Places the current/previous window pair and the remaining window index.'}
};
function createFold(selection,targets){
 const s={selection:{...M.clone(selection),policy:'stable'},apps:M.create({...selection,policy:'stable'},[]),children:{},map:{},pins:{},retired:[]};
 for(const t of targets)allocateFold(s,t);
 return s;
}
function refresh(s){
 s.map={};s.pins={};s.retired=[];
 for(const [app,children] of Object.entries(s.children)){
  const head=s.apps.map[app];if(!head)continue;
  for(const [id,label] of Object.entries(children.map))s.map[id]=label?head+label:null;
  for(const [id,label] of Object.entries(children.pins))s.pins[id]=head+label;
  s.retired.push(...children.retired.map(label=>head+label));
 }
}
function allocateFold(s,t){
 if(!s.children[t.app]){M.allocate(s.apps,{id:t.app,name:t.name,title:t.name});s.children[t.app]=M.create(s.selection,[]);}
 M.allocate(s.children[t.app],t);refresh(s);
}
function retireFold(s,t){if(s.children[t.app])M.retire(s.children[t.app],t.id);refresh(s);}
function pinFold(s,t,raw){
 const label=M.normalize(raw),head=s.apps.map[t.app];
 if(!head||!label.startsWith(head))return 'Keep this app’s prefix: '+(head||'unavailable')+'. Pin a free complete app + window address.';
 const error=M.pin(s.children[t.app],t.id,label.slice(head.length));if(error)return error;
 refresh(s);return '';
}
function reassignFold(s,selection,targets){
 const candidate=createFold(selection,targets);
 for(const t of targets){
  const old=s.children[t.app]?.pins[t.id];if(!old)continue;
  if(!M.codes(selection.alphabet,'stable').includes(old))return {error:'The new alphabet cannot keep a pinned Fold label. Reset Fold labels first.'};
 }
 // Seed all child reservations together so a pin can never collide with a newly allocated sibling.
 for(const app of Object.keys(candidate.children)){
  const family=targets.filter(t=>t.app===app),pins={};
  for(const t of family)if(s.children[app]?.pins[t.id])pins[t.id]=s.children[app].pins[t.id];
  candidate.children[app]=M.create(candidate.selection,family,pins);
 }
 refresh(candidate);return {state:candidate,error:''};
}
function render(ctx){
 const {mode,tabs,list,state,prefix,query,markup,esc,focus}=ctx;
 if(query!==null)return null; // Shared global search never gains another hierarchy.
 const heading=text=>`<div class="mode-section-title">${esc(text)}</div>`;
 const group=(title,rows)=>`<section class="mode-group">${heading(title)}${rows.map(markup).join('')}</section>`;
 if(mode==='canopy'){
  const keys=[...new Set(list.map(t=>tabs?t.browserId+':'+t.windowId:t.app))];
  return '<div class="canopy-preview">'+keys.map(key=>{const rows=list.filter(t=>(tabs?t.browserId+':'+t.windowId:t.app)===key),first=rows[0];return group(first.name+(tabs?' · '+(first.context||'Window').split(' / ')[0]:''),rows);}).join('')+'</div>';
 }
 if(mode==='fold'&&!tabs){
  const apps=state.apps.order.filter(app=>list.some(t=>t.app===app)),selected=apps.find(app=>state.apps.map[app]&&prefix.startsWith(state.apps.map[app]));
  const spine=apps.map(app=>{const rows=list.filter(t=>t.app===app),key=state.apps.map[app],selectedApp=app===selected;return `<button class="fold-app ${selectedApp?'selected':''}" data-mode-prefix="${esc(key||'')}" ${key?'':'disabled'} aria-pressed="${selectedApp}" aria-label="${esc(rows[0].name)} windows. App prefix ${esc(key||'unavailable')}"><span>${esc(rows[0].name)}<small>${rows.length} window${rows.length===1?'':'s'}</small></span><kbd class="key-label">${esc(key||'—')}</kbd></button>`;}).join('');
  return `<div class="fold-preview"><div class="fold-spine">${heading('Choose app')}${spine}</div><section class="fold-sheet">${selected?heading('Choose window')+'<button class="mode-back" data-mode-back>← All apps</button>'+list.filter(t=>t.app===selected).map(markup).join(''):'<p class="mode-empty">Choose an app, then a window.<br>Both parts of the full label are required.</p>'}</section></div>`;
 }
 if(mode==='lattice'){
  const allCodes=Object.values(state.map).filter(Boolean),held=state.retired||[];
  const cells=[...state.selection.alphabet].map(letter=>{
   const code=prefix+letter,target=list.find(t=>state.map[t.id]===code),descendants=list.filter(t=>state.map[t.id]?.startsWith(code)&&state.map[t.id].length>code.length);
   if(target)return `<div class="address-cell" data-cell="${esc(code)}">${markup(target)}</div>`;
   const branch=descendants.length||(state.selection.policy!=='pairs'&&letter===state.selection.alphabet.at(-1)&&code.length<4);
   if(branch)return `<section class="address-cell branch-cell" data-cell="${esc(code)}"><button data-mode-prefix="${esc(code)}" ${descendants.length?'':'disabled'} aria-label="${esc(code)}: ${descendants.length?'show '+descendants.length+' targets':'reserved overflow'}"><kbd class="key-label">${esc(code)}</kbd><span>${descendants.length?descendants.length+' '+(tabs?'tabs':'windows'):'More windows'}</span></button>${tabs&&!prefix?'<div class="address-inventory">'+descendants.map(markup).join('')+'</div>':descendants.slice(0,2).map(t=>`<p class="branch-title">${esc(t.title)}</p>`).join('')}</section>`;
   return `<div class="address-cell empty-cell" data-cell="${esc(code)}"><kbd class="key-label">${esc(code)}</kbd><span>${held.some(x=>x.startsWith(code))?'Address held':allCodes.some(x=>x.startsWith(code))?'Not included':'Available'}</span></div>`;
  }).join('');
  const unaddressed=list.filter(t=>!state.map[t.id]);
  return `${prefix?'<button class="mode-back" data-mode-back>← All addresses</button>':''}<div class="address-grid">${cells}</div>${unaddressed.length?group('Without a short label · search or click',unaddressed):''}`;
 }
 if(mode==='beacons'&&!tabs){
  // Deliberately synthetic visibility: show three unobstructed title bars, bank every other target.
  const exposed=list.filter(t=>!t.minimized&&!t.hidden).sort((a,b)=>(b.id===focus.current)-(a.id===focus.current)).slice(0,3),bank=list.filter(t=>!exposed.includes(t));
  return `<div class="beacon-preview" aria-label="Simulated desktop geometry">${heading('Visible windows · sample geometry')}<div class="beacon-field">${exposed.map((t,i)=>`<div class="beacon-window beacon-${i}">${markup(t)}</div>`).join('')}</div>${bank.length?group('Out of sight · '+bank.length,bank):''}</div>`;
 }
 if(mode==='relay'&&!tabs){
  const current=list.find(t=>t.id===focus.current),previous=list.find(t=>t.id===focus.previous&&t.id!==focus.current),rest=list.filter(t=>t!==current&&t!==previous);
  return `<div class="relay-preview">${group('Current window',current?[current]:[])}<section class="relay-previous">${heading('Previous window')}${previous?markup(previous)+'<button class="return-action" data-return-window>Return here <kbd>Enter ↵</kbd></button>':'<p class="mode-empty">No previous available window. Select a different window to start a return pair.</p>'}</section>${group('Other windows · same letters',rest)}</div>`;
 }
 return null;
}
const api={definitions,createFold,allocateFold,retireFold,pinFold,reassignFold,render};
if(typeof module!=='undefined')module.exports=api;root.TabnaxModes=api;
})(typeof globalThis!=='undefined'?globalThis:this);
