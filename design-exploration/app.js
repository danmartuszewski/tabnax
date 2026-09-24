/* Local interaction study. All windows, focus and tabs below are simulated. */
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const escape = (value) => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const APPS = {
    code: {name:'Visual Studio Code', short:'VS Code'}, safari:{name:'Safari',short:'Safari'}, finder:{name:'Finder',short:'Finder'},
    figma:{name:'Figma',short:'Figma'}, terminal:{name:'Terminal',short:'Terminal'}, notes:{name:'Notes',short:'Notes'}
  };
  const initialWindows = [
    {id:'code',app:'code',title:'Tabnax · switcher.ts',context:'tabnax / src',full:'switcher.ts — tabnax — Visual Studio Code',x:29,y:37,w:49,h:51,z:8},
    {id:'lesson',app:'safari',title:'Tabnax · Keyboard guide',context:'Workspace guide · Work',full:'Tabnax — Workspace guide — Keyboard guide — Window shortcuts, draft 04',x:3,y:23,w:51,h:57,z:4},
    {id:'preview',app:'safari',title:'Tabnax · Layout preview',context:'Workspace guide · Work',full:'Tabnax — Workspace guide — Layout preview — Window shortcuts, draft 04',x:12,y:29,w:55,h:61,z:1},
    {id:'assets',app:'finder',title:'Tabnax · Assets',context:'Projects / tabnax',full:'Assets — /Example/Tabnax/design/assets',x:69,y:20,w:28,h:50,z:5},
    {id:'design',app:'figma',title:'Tabnax · Interaction studies',context:'Exploration / 03',full:'Tabnax — Interaction studies — Comparison, revision 03',x:70,y:62,w:27,h:32,z:7},
    {id:'dev',app:'terminal',title:'tabnax · pnpm dev',context:'Local development',full:'tabnax — pnpm dev — zsh',x:4,y:61,w:44,h:33,z:6},
    {id:'ideas',app:'notes',title:'Switching · Interview notes',context:'Design research',full:'Switching ideas — Interview notes — Keyboard habits',x:24,y:35,w:39,h:53,z:2},
    {id:'personal',app:'safari',title:'Weekend walks · Saved routes',context:'Personal · minimized',full:'Weekend walks — Saved routes near Warsaw — Personal',x:14,y:19,w:48,h:57,z:3,minimized:true},
    {id:'review',app:'code',title:'Tabnax · Review diff',context:'tabnax-web / pull request',full:'Tabnax — Window shortcuts — Review diff — tabnax-web',x:20,y:25,w:62,h:64,z:1},
    {id:'export',app:'finder',title:'Tabnax · Exports',context:'Projects / tabnax / exports',full:'Exports — /Example/Tabnax/design/exports',x:50,y:34,w:42,h:52,z:1}
  ];
  const tabSpecs = [
    ['lesson','Tabnax · Window shortcuts — guide editor','tabnax.example'],['lesson','Tabnax · Window shortcuts — shortcut editor','tabnax.example'],
    ['lesson','Tabnax · Browser tabs — guide editor','tabnax.example'],['lesson','Tabnax · Browser tabs — shortcut editor','tabnax.example'],
    ['lesson','Keyboard guide · Stable letter addresses','tabnax.example'],['lesson','Keyboard guide · Windows and browser tabs','tabnax.example'],
    ['lesson','Tabnax · Design brief','github.com'],['lesson','Tabnax · Keyboard interaction notes','github.com'],
    ['lesson','AppKit · Window management','developer.apple.com'],['lesson','Human Interface Guidelines · Keyboards','developer.apple.com'],
    ['lesson','Accessibility · Focus and navigation','developer.apple.com'],['lesson','Pull request · Preserve selection addresses','github.com'],
    ['preview','Tabnax · Window shortcuts — layout preview','tabnax.example'],['preview','Tabnax · Window shortcuts — interaction preview','tabnax.example'],
    ['preview','Tabnax · Browser tabs — layout preview','tabnax.example'],['preview','Tabnax · Browser tabs — interaction preview','tabnax.example'],
    ['preview','Tabnax · Workspace overview','tabnax.example'],['preview','Tabnax · My shortcuts','tabnax.example'],
    ['preview','Tabnax · Guide preview — desktop, signed out','tabnax.example'],['preview','Tabnax · Guide preview — mobile, signed in','tabnax.example'],
    ['preview','Release notes · Shortcut library','tabnax.example'],['preview','Design review · Guide typography','figma.com'],
    ['personal','Weekend walks · Kampinos forest','saved routes'],['personal','Weekend walks · Vistula river trail','saved routes'],
    ['personal','A field guide to Warsaw architecture','reading list'],['personal','Coffee spots · Praga district','saved places'],
    ['personal','Books to read · Autumn','reading list'],['personal','Rail connections · Weekend ideas','travel notes']
  ];
  const concepts = {
    shore:{name:'Shore',kicker:'01 / SHORE',headline:'A place for every window.<br>A letter that stays put.',scan:'One vertical pass at the right edge. App icons identify the family; short, distinguishing titles identify the window. Letters sit in one predictable column. Familiar addresses bypass scanning entirely.',tradeoff:'The eye travels to the edge, and every window repeats an icon. Long titles have less room. It wins only if that compact scan is faster than recognizing a window in place.'},
    beacons:{name:'Beacons',kicker:'02 / BEACONS',headline:'Don’t leave the desktop.<br>Give it an alphabet.',scan:'Read the label near a visible window’s title bar. Your existing memory of where a window lives becomes useful. Occluded and minimized windows collect in a bottom strip so nothing disappears.',tradeoff:'Overlapping windows force a second scan in the hidden-window strip. New positions break spatial memory. The most expressive concept is also the most fragile when the desktop is crowded.'},
    canopy:{name:'Canopy',kicker:'03 / CANOPY',headline:'Find the app above.<br>Land on the exact window.',scan:'Scan the large app icons across the top, then read down within one family. Every window still has a direct address: there is no app-then-window key sequence. Optional tabs extend this surface into three browser-window columns.',tradeoff:'Two visual decisions: app, then window. A wide sweep replaces a short list, and large tab collections need search or scrolling. Better grouping may help duplicate windows, but it adds surface area.'}
  };
  const extensions=window.TabnaxExtensions||{};
  Object.assign(concepts,extensions);
  const state = {concept:'shore',scope:'windows',active:true,mode:'select',prefix:'',query:'',cursor:0,focused:'code',previousFocused:'lesson',alphabet:'jkluionmhp',hand:'right',hold:false,windows:[],tabs:[],addresses:{windows:new Map(),apps:new Map(),tabs:new Map()},retired:new Set(),nextWindow:0,z:10,notification:'',lastFocus:null};
  const stage = $('desktop');
  function icon(app) {
    const shapes = {
      code:'<svg viewBox="0 0 32 32" aria-hidden="true"><path fill="#188acf" d="M22 2 8 14 3 10 0 13 7 19 0 25 3 28 9 23 22 32 31 28V6Zm0 8v14l-9-6Z"/></svg>',
      safari:'<svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="14" fill="#299be5" stroke="#fff" stroke-width="1.5"/><circle cx="16" cy="16" r="11.5" fill="none" stroke="#d0f4ff" stroke-dasharray="1 2"/><path d="m11 21 3-8 7-2-3 8Z" fill="#fff"/><path d="m14 13 7-2-3 8Z" fill="#f35158"/></svg>',
      finder:'<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M17 0 13 19h7v13M4 23q11 7 23-1" stroke="#255983" stroke-width="1.2" fill="none"/><path d="M8 9v4m16-4v4" stroke="#183751" stroke-width="2"/></svg>',
      figma:'<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M12 1h5v10h-5a5 5 0 0 1 0-10" fill="#f24e1e"/><path d="M17 1h5a5 5 0 0 1 0 10h-5" fill="#ff7262"/><path d="M12 11h5v10h-5a5 5 0 0 1 0-10" fill="#a259ff"/><circle cx="22" cy="16" r="5" fill="#1abcfe"/><path d="M12 21h5v5a5 5 0 1 1-5-5" fill="#0acf83"/></svg>',
      terminal:'&gt;_',notes:'☰'
    };
    return `<span class="app-icon ${app}" aria-hidden="true">${shapes[app]}</span>`;
  }
  function allocate(id,scope) {
    const map = state.addresses[scope];
    if(map.has(id)) return map.get(id);
    const a=state.alphabet, n=map.size;
    let key;
    if(scope==='tabs') key=a[Math.floor(n/a.length)]+a[n%a.length];
    else key=a.at(-1).repeat(Math.floor(n/(a.length-1)))+a[n%(a.length-1)];
    // The final letter is always a branch, never a target. No silent remapping.
    if(!key || key.includes('undefined')) throw new Error('Address capacity exceeded');
    map.set(id,key);return key;
  }
  function extensionContext(list){return {state,list:list||filtered(),all:targets(),item,icon,escape,APPS,address,baseAddress:(t,scope=state.scope)=>allocate(t.id,scope),appAddress:app=>allocate('app-'+app,'apps'),windows:state.windows,recentWindow:alive().find(w=>w.id===state.previousFocused&&w.id!==state.focused)||null};}
  function address(target){return extensions[state.concept]?.address?.(target,extensionContext())||allocate(target.id,state.scope);}
  function hasTabs(){return state.concept==='canopy'||Boolean(extensions[state.concept]?.tabs);}
  function alive(){return state.windows.filter(w=>w.alive);}
  function targets(){
    if(state.scope==='windows') return alive();
    if(state.scope==='tabs') return state.tabs.filter(t=>state.windows.some(w=>w.id===t.parent&&w.alive));
    return Object.keys(APPS).map(app=>{
      const wins=alive().filter(w=>w.app===app);if(!wins.length)return null;
      const recent=[...wins].sort((a,b)=>b.z-a.z)[0];
      return {...recent,id:'app-'+app,title:APPS[app].name,full:APPS[app].name,context:`${wins.length} open window${wins.length===1?'':'s'} · most recent`,windowId:recent.id};
    }).filter(Boolean);
  }
  function filtered(){const q=state.query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);return targets().filter(t=>q.every(part=>`${t.title} ${t.full} ${t.context} ${APPS[t.app].name}`.toLocaleLowerCase().includes(part)));}
  function targetKeyLabel(t){const key=address(t);return [...key].map((c,i)=>`<span${state.prefix&&i<state.prefix.length?' class="typed"':''}>${escape(c.toUpperCase())}</span>`).join('');}
  function item(t){
    const key=address(t),matched=key.startsWith(state.prefix),list=filtered(),selected=state.mode==='search'&&list[state.cursor]?.id===t.id;
    const current=state.scope==='apps'?t.windowId===state.focused:state.scope==='tabs'?state.lastFocus===t.id:t.id===state.focused;
    return `<button type="button" class="target${!matched?' unmatched':''}${selected?' arrow-selected':''}" data-target="${escape(t.id)}" data-address="${key}" aria-label="${key.toUpperCase()}: ${escape(t.full||t.title)}. ${escape(t.context)}" title="${escape(t.full||t.title)}">${current?'<span class="focused-dot" aria-hidden="true"></span>':''}${icon(t.app)}<span class="target-text"><span class="target-title">${escape(t.title)}</span><span class="target-meta">${escape(t.context)}</span></span><kbd aria-hidden="true">${targetKeyLabel(t)}</kbd></button>`;
  }
  function head(){return `<div class="surface-head"><div class="scope-buttons">${['windows','apps',...(hasTabs()?['tabs']:[])].map((s,i)=>`<button type="button" data-scope="${s}" class="${state.scope===s?'selected':''}" aria-pressed="${state.scope===s}"><span>${i+1}</span>${s[0].toUpperCase()+s.slice(1)}</button>`).join('')}</div><span class="surface-count">${state.mode==='search'?filtered().length+'/':''}${targets().length}</span></div>`;}
  function modeStrip(){
    if(state.mode==='search')return `<div class="product-search"><span>/</span><input id="product-query" type="text" aria-label="Find ${state.scope}" placeholder="Find ${state.scope}…" value="${escape(state.query)}" autocomplete="off" spellcheck="false"></div>`;
    return `<div class="mode-strip"><span class="mode-light"></span><span>${escape(extensions[state.concept]?.modeText?.(extensionContext())||(state.scope==='tabs'?'Two letters to a tab':'Type a letter to go'))}</span><span class="prefix">${state.prefix?escape(state.prefix.toUpperCase())+' _':''}</span></div>`;
  }
  function foot(){return `<div class="surface-foot"><span>${state.mode==='search'?'↑ ↓ choose · Enter go':'/ Find'}</span><span>${state.scope==='tabs'?'Safari · simulated tabs':state.prefix?'⌫ Undo prefix':state.concept==='relay'&&state.scope==='windows'?'Enter · Previous window':state.concept==='fold'&&state.scope==='windows'?'App → window':'Direct selection'}</span><button type="button" class="cancel-button" id="product-cancel">Esc ${state.mode==='search'||state.prefix?'Back':'Close'}</button></div>`;}
  function noResults(){return '<div class="empty-results">No matching targets.<small>Change the search, or press Escape to return to letters.</small></div>';}
  function isExposed(t){
    const win=state.windows.find(w=>w.id===(t.windowId||t.id));if(!win||win.minimized)return false;
    const anchor={x:win.x+3,y:win.y+2};
    return !alive().some(w=>w.id!==win.id&&!w.minimized&&w.z>win.z&&anchor.x>=w.x&&anchor.x<=w.x+w.w&&anchor.y>=w.y&&anchor.y<=w.y+w.h);
  }
  function layout(list){
    if(extensions[state.concept]?.render)return extensions[state.concept].render(extensionContext(list));
    if(state.concept==='shore')return `<div class="target-list">${list.length?list.map(item).join(''):noResults()}</div>`;
    if(state.concept==='beacons'){
      const visible=list.filter(isExposed),hidden=list.filter(t=>!isExposed(t));
      return `<div class="target-list">${list.length?'':noResults()}${visible.map(t=>`<div class="beacon-position" style="left:clamp(14px,${t.x}%,calc(100% - 258px));top:calc(${t.y}% - 70px)">${item(t)}</div>`).join('')}${hidden.length?`<div class="hidden-bank"><div class="bank-caption"><span>OUT OF SIGHT · ${hidden.length}</span><span>OCCLUDED / MINIMIZED</span></div><div class="bank-targets">${hidden.map(item).join('')}</div></div>`:''}</div>`;
    }
    if(state.scope==='apps')return `<div class="canopy-groups app-scope">${list.length?list.map(item).join(''):noResults()}</div>`;
    const groups=state.scope==='tabs'?['lesson','preview','personal']:Object.keys(APPS);
    const headings={lesson:'Work · Keyboard guide',preview:'Work · Layout preview',personal:'Personal · Saved routes'};
    return `<div class="canopy-groups ${state.scope==='tabs'?'tab-groups':''}">${list.length?'':noResults()}${groups.map(group=>{
      const groupList=list.filter(t=>state.scope==='tabs'?t.parent===group:t.app===group);if(!groupList.length)return '';
      const app=state.scope==='tabs'?'safari':group;
      return `<section class="canopy-group"><div class="group-heading">${icon(app)}<div><strong>${escape(state.scope==='tabs'?headings[group]:APPS[group].short)}</strong><small>${groupList.length} ${state.scope==='tabs'?'tabs':groupList.length===1?'window':'windows'}</small></div></div><div>${groupList.map(item).join('')}</div></section>`;
    }).join('')}</div>`;
  }
  function renderSwitcher({focusSearch=false}={}){
    stage.className=`desktop ${state.concept}${state.active?' is-open':''}`;
    $('switcher').inert=!state.active;
    $('switcher').setAttribute('aria-hidden',String(!state.active));
    if(!state.active){$('switcher').innerHTML='';return;}
    state.cursor=Math.max(0,Math.min(state.cursor,filtered().length-1));
    const searchFocused=document.activeElement?.id==='product-query';
    const selection=searchFocused?document.activeElement.selectionStart:null;
    $('switcher').innerHTML=`<div class="surface">${head()}${modeStrip()}${layout(filtered())}${foot()}</div>`;
    if(focusSearch||searchFocused){$('product-query')?.focus({preventScroll:true});if(selection!==null)$('product-query')?.setSelectionRange(selection,selection);}
    if(state.prefix){const match=$('switcher').querySelector('.target:not(.unmatched)');match?.scrollIntoView({block:'nearest',inline:'nearest'});}
  }
  function windowContents(w){
    if(w.app==='code')return '<div class="code-layout"><div class="code-sidebar"><strong>EXPLORER</strong>⌄ TABNAX<br> &nbsp;⌄ src<br> &nbsp; &nbsp; switcher.ts<br> &nbsp; &nbsp; addresses.ts<br> &nbsp; &nbsp; keyboard.ts<br> &nbsp; package.json</div><div class="code-body"><div class="code-tab">◇ &nbsp; switcher.ts</div><pre><span class="comment">// A smaller distance.</span>\n\n<b>type</b> Target = {\n  id: <em>WindowID</em>;\n  address: <em>string</em>;\n};\n\n<b>function</b> <em>select</em>(key: string) {\n  <b>const</b> target = addresses.get(key);\n  <b>if</b> (target) focus(target);\n}\n\n<span class="comment">// Keep the letter. Change the window.</span></pre></div></div>';
    if(w.app==='safari')return `<div class="safari-url">◉ &nbsp; ${w.id==='personal'?'Saved places · Personal':'tabnax.example / guide / window-shortcuts'}</div><div class="website-body"><span class="sample-brand">${w.id==='personal'?'The weekend journal':'Tabnax'}</span><span class="site-nav">Explore &nbsp; Customize &nbsp; My shortcuts</span><p class="site-eyebrow">${w.id==='preview'?'Layout preview':w.id==='personal'?'OUTSIDE THE EVERYDAY':'TABNAX · KEYBOARD GUIDE'}</p><h4>${w.id==='personal'?'A little further<br>from the city.':'Familiar keys.<br>A calmer workspace.'}</h4><p>${w.id==='personal'?'Quiet trails, good coffee, and a route home.':'Find windows and tabs with a few familiar keys.'}</p><div class="lesson-line"></div><div class="lesson-line short"></div><span class="lesson-button">${w.id==='lesson'?'Explore shortcuts':'Continue exploring'} &nbsp; →</span></div>`;
    if(w.app==='finder')return '<div class="finder-body"><div class="finder-side">Favourites<br>⌂ Home<br>▣ Projects<br>↓ Downloads<br>☁ iCloud</div><div class="finder-files"><span>📁 &nbsp; app-icons</span><span>📁 &nbsp; exploration</span><span>📁 &nbsp; references</span><span>▧ &nbsp; concept-shore.png</span><span>▧ &nbsp; concept-beacons.png</span><span>▧ &nbsp; concept-canopy.png</span></div></div>';
    if(w.app==='terminal')return '<div class="terminal-body"><span class="terminal-green">➜ &nbsp; tabnax</span> git:(design) pnpm dev<br><br>Ready on localhost<br><span class="terminal-green">✓</span> Input handler ready<br><span class="terminal-green">✓</span> Window addresses retained<br><br>▊</div>';
    if(w.app==='figma')return '<div class="figma-body"><div class="figma-artboard"><i></i><i></i><i></i><i></i></div><div class="figma-artboard"><i></i><i></i><i></i></div></div>';
    return '<div class="note-body">17 SEPTEMBER<h4>What makes switching<br>feel effortless?</h4>01 &nbsp; Recognize before reading<br>02 &nbsp; Don’t make me cycle<br>03 &nbsp; Keep the letters where I left them<br><br>What if the edge of the desktop<br>could become an index?</div>';
  }
  function renderDesktop(){
    $('windows').innerHTML=alive().filter(w=>!w.minimized).map(w=>`<div class="mac-window${w.id===state.focused?' focused':''}" data-window="${w.id}" style="left:${w.x}%;top:${w.y}%;width:${w.w}%;height:${w.h}%;z-index:${w.z}"><div class="window-bar"><div class="traffic"><i></i><i></i><i></i></div><span>${escape(w.full)}</span></div><div class="window-content">${windowContents(w)}</div></div>`).join('');
    $('dock').innerHTML=Object.keys(APPS).filter(a=>alive().some(w=>w.app===a)).map(icon).join('');
    $('menu-app').textContent=APPS[alive().find(w=>w.id===state.focused)?.app||'code'].name;
    $('scene-label').textContent=`${alive().length} windows · ${new Set(alive().map(w=>w.app)).size} apps`;
    $('close-window').disabled=alive().length<=1;
    $('add-window').disabled=state.addresses.windows.size>=Math.min(16,state.alphabet.length*2-1);
    $('address-readout').textContent=alive().map(w=>`${(extensions[state.concept]?.address?.(w,{...extensionContext(),state:{...state,scope:'windows'}})||allocate(w.id,'windows')).toUpperCase()} ${APPS[w.app].short}`).join(' · ');
  }
  function say(message){state.notification=message;$('feedback').textContent=message;}
  function focusStage(){stage.focus({preventScroll:true});}
  function focusInteraction(){if(state.active&&state.mode==='search')$('product-query')?.focus({preventScroll:true});else focusStage();}
  function activate(hold=false){
    state.active=true;state.mode='select';state.prefix='';state.query='';state.cursor=0;state.hold=hold;
    focusStage();renderSwitcher();say(`Select ${state.scope} with ${state.scope==='tabs'?'two letters':'the displayed letters'}. / enters search; Escape cancels.`);
  }
  function cancel(){
    if(state.mode==='search'){state.mode='select';state.query='';state.cursor=0;state.prefix='';renderSwitcher();focusStage();say('Direct selection. Letters select targets again.');return;}
    if(state.prefix){state.prefix='';renderSwitcher();say('Prefix cleared. Choose any address.');return;}
    state.active=false;renderSwitcher();focusStage();say('Cancelled. Focus did not change. Space opens again.');
  }
  function selectTarget(id){
    const target=targets().find(t=>t.id===id);if(!target)return;
    const winId=state.scope==='apps'?target.windowId:state.scope==='tabs'?target.parent:target.id;
    const win=alive().find(w=>w.id===winId);if(!win)return;
    const key=address(target).toUpperCase();
    if(state.focused!==winId)state.previousFocused=state.focused;
    state.focused=winId;state.lastFocus=target.id;win.minimized=false;win.context=win.context.replace(' · minimized','');win.z=++state.z;
    if(state.scope==='tabs'){win.title=target.title;win.full=target.title+' — '+target.context;win.context=target.context+' · Safari';}
    state.active=false;state.prefix='';state.query='';state.mode='select';
    renderDesktop();renderSwitcher();focusStage();say(`Focused ${target.title} · ${key}. Space to switch again.`);
  }
  function setScope(scope){
    if(scope==='tabs'&&!hasTabs()){say('Tabs are optional experiments in Canopy and Lattice. Choose either to explore them.');return;}
    state.scope=scope;state.prefix='';state.query='';state.mode='select';state.cursor=0;state.active=true;
    targets().forEach(address);renderSwitcher();focusStage();say(scope==='tabs'?'28 simulated Safari tabs. Type two letters, or / to search.':'Scope: '+scope+'. Displayed letters select directly.');
  }
  function setConcept(concept){
    if(!concepts[concept])return;
    state.concept=concept;if(state.scope==='tabs'&&!hasTabs())state.scope='windows';
    const info=concepts[concept];$('concept-kicker').textContent=info.kicker;$('concept-headline').innerHTML=info.headline;$('concept-scan').textContent=info.scan;$('concept-tradeoff').textContent=info.tradeoff;
    document.querySelectorAll('[data-concept]').forEach(b=>{const on=b.dataset.concept===concept;b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));});
    $('tabs-key-label').textContent=hasTabs()?' tabs':' tabs in Canopy / Lattice';
    $('concept-extra-key').hidden=concept!=='relay';
    renderDesktop();
    activate();say(`${info.name}. ${concept==='fold'&&state.scope==='windows'?'Choose an app letter, then a window letter.':concept==='relay'&&state.scope==='windows'?'Enter returns to the previous window; letters go directly to any window.':state.scope==='tabs'?'Two letters select a tab.':'Type a letter to focus a window.'}`);
  }
  function seed(count=8){
    state.addresses={windows:new Map(),apps:new Map(),tabs:new Map()};state.retired.clear();state.focused='code';state.previousFocused='lesson';state.lastFocus=null;state.z=10;state.nextWindow=0;
    state.windows=initialWindows.slice(0,count).map(w=>({...w,alive:true}));
    state.tabs=tabSpecs.map(([parent,title,domain],i)=>({id:'tab-'+i,parent,title,full:title,context:domain,app:'safari'}));
    state.windows.forEach(w=>allocate(w.id,'windows'));
    Object.keys(APPS).forEach(app=>allocate('app-'+app,'apps'));
    state.tabs.forEach(t=>allocate(t.id,'tabs'));
    state.scope='windows';renderDesktop();activate();
  }
  function changeCount(count){
    // Scenario presets preserve identity and addresses; only Reset starts a new session.
    initialWindows.slice(0,count).forEach(spec=>{let w=state.windows.find(x=>x.id===spec.id);if(!w){w={...spec,alive:true};state.windows.push(w);}else w.alive=true;allocate(w.id,'windows');});
    state.windows.forEach(w=>{if(!initialWindows.slice(0,count).some(x=>x.id===w.id))w.alive=false;});
    if(!alive().some(w=>w.id===state.focused))state.focused=alive()[0].id;
    state.prefix='';renderDesktop();renderSwitcher();focusInteraction();say(`${count} windows. Existing letters retained; scenario restoration keeps the same simulated identities.`);
  }
  function addWindow(){
    if($('add-window').disabled)return;
    const n=++state.nextWindow,id='new-'+n;
    const win={id,app:n%2?'safari':'code',title:n%2?`Tabnax · Reference ${n}`:`Tabnax · Scratch ${n}`,context:n%2?'Research · New window':'tabnax / scratch',full:n%2?`Tabnax — Workspace guide — Additional reference window ${n}`:`Tabnax — Scratch window ${n}`,x:18+(n%3)*8,y:24+(n%3)*7,w:49,h:59,z:1,alive:true};
    state.windows.push(win);allocate(id,'windows');state.prefix='';renderDesktop();renderSwitcher();focusInteraction();say(`Opened ${win.title} at ${allocate(id,'windows').toUpperCase()}. Every existing address stayed unchanged.`);
  }
  function closeWindow(){
    if(alive().length<=1)return;
    const win=alive().find(w=>w.id===state.focused),key=allocate(win.id,'windows').toUpperCase();win.alive=false;state.retired.add(key);
    state.focused=[...alive()].sort((a,b)=>b.z-a.z)[0].id;state.prefix='';state.cursor=0;renderDesktop();renderSwitcher();focusInteraction();say(`Closed ${win.title}. ${key} is retired until Reset; other addresses stayed unchanged.`);
  }
  function applyAlphabet(a){
    if(!/^[a-z]{6,12}$/.test(a)||new Set(a).size!==a.length){$('alphabet-error').textContent='Use 6–12 unique letters A–Z. Six keys allow all 28 tabs to keep two-letter addresses.';return false;}
    $('alphabet-error').textContent='';state.alphabet=a;state.hand=$('hand').value;
    $('hold-key').textContent=state.hand==='left'?'Right Shift':'Left Shift';
    $('alphabet-note').textContent=`${state.hand==='left'?'Right thumb opens; left hand selects.':state.hand==='right'?'Left thumb opens; right hand selects.':'Keys follow your chosen order.'} ${a.at(-1).toUpperCase()} is reserved for overflow: ${(a.at(-1)+a[0]).toUpperCase()}, ${(a.at(-1)+a[1]).toUpperCase()}… Applying an alphabet starts a new address session.`;
    seed(Number($('scenario').value));say('Alphabet applied. A new address session started.');return true;
  }
  function directKey(key){
    const next=state.prefix+key,matches=targets().filter(t=>address(t).startsWith(next));
    if(!matches.length){say(`No target at ${next.toUpperCase()}. ${state.prefix?'Backspace clears the prefix.':'Use a displayed address, or / to search.'}`);return;}
    const exact=matches.find(t=>address(t)===next);
    if(exact){selectTarget(exact.id);return;}
    state.prefix=next;renderSwitcher();say(`${next.toUpperCase()} prefix. Type the next letter; Backspace undoes.`);
  }
  function keydown(event){
    if(event.isComposing||event.metaKey||event.ctrlKey||event.altKey)return;
    let key=event.key;const queryField=event.target.id==='product-query';
    const inStage=stage.contains(event.target)||event.target===stage;
    if(!inStage)return;
    if(event.repeat&&key!=='Backspace'&&key!=='ArrowDown'&&key!=='ArrowUp')return;
    if(key==='Shift'&&event.code===(state.hand==='left'?'ShiftRight':'ShiftLeft')){if(!state.active){event.preventDefault();activate(true);}return;}
    if(queryField){
      if(key==='Escape'){event.preventDefault();cancel();}
      else if(key==='Enter'){event.preventDefault();const t=filtered()[state.cursor];if(t)selectTarget(t.id);}
      else if(key==='ArrowDown'||key==='ArrowUp'){event.preventDefault();const list=filtered();state.cursor=list.length?(state.cursor+(key==='ArrowDown'?1:-1)+list.length)%list.length:0;renderSwitcher({focusSearch:true});$('switcher').querySelector('.arrow-selected')?.scrollIntoView({block:'nearest'});}
      return;
    }
    // Held Shift is a demo trigger; recognize command positions despite shifted glyphs.
    if(state.hold){if(event.code==='Slash')key='/';else if(/^Digit[123]$/.test(event.code))key=event.code.slice(-1);}
    // Native button activation remains usable after navigating with Tab.
    if((key==='Enter'||key===' ')&&event.target.closest('button'))return;
    // Tab retains normal browser focus navigation. Scope keys never form target addresses.
    if(key===' '){event.preventDefault();state.active?cancel():activate();return;}
    if(!state.active)return;
    if(key==='Escape'){event.preventDefault();cancel();return;}
    if(key==='/'){event.preventDefault();state.mode='search';state.query='';state.prefix='';state.cursor=0;renderSwitcher({focusSearch:true});say('Search mode. Letters now type text. Enter selects; Escape returns to direct letters.');return;}
    if(['1','2','3'].includes(key)){event.preventDefault();setScope({1:'windows',2:'apps',3:'tabs'}[key]);return;}
    if(key==='Backspace'){event.preventDefault();state.prefix=state.prefix.slice(0,-1);renderSwitcher();return;}
    if(key==='Enter'&&state.mode==='select'&&state.concept==='relay'&&state.scope==='windows'){event.preventDefault();const previous=extensionContext().recentWindow;if(previous)selectTarget(previous.id);else say('No previous window is available. Choose a displayed address.');return;}
    if(state.mode==='select'&&/^[a-z]$/i.test(key)){event.preventDefault();directKey(key.toLowerCase());}
  }
  document.addEventListener('keydown',keydown);
  document.addEventListener('keyup',event=>{
    if(event.code===(state.hand==='left'?'ShiftRight':'ShiftLeft')&&state.hold){state.hold=false;if(state.active){state.active=false;renderSwitcher();say('Peek released. Focus did not change.');}}
  });
  window.addEventListener('blur',()=>{if(state.active){state.active=false;state.hold=false;renderSwitcher();say('Demo lost focus. Space opens the switcher again.');}});
  document.addEventListener('click',event=>{
    const concept=event.target.closest('[data-concept]');if(concept){setConcept(concept.dataset.concept);return;}
    const scope=event.target.closest('[data-scope]');if(scope){setScope(scope.dataset.scope);return;}
    const target=event.target.closest('[data-target]');if(target){selectTarget(target.dataset.target);return;}
    const branch=event.target.closest('[data-prefix]');if(branch){state.prefix=branch.dataset.prefix;renderSwitcher();focusStage();say(`Prefix ${state.prefix.toUpperCase()}. Choose the next letter.`);return;}
    if(event.target.closest('[data-clear-prefix]')){state.prefix='';renderSwitcher();focusStage();return;}
    if(event.target.closest('[data-return-window]')){const previous=extensionContext().recentWindow;if(previous)selectTarget(previous.id);return;}
    if(event.target.id==='product-cancel'){cancel();return;}
    if(event.target===stage||event.target.closest('.wallpaper,.windows,.dock,.menubar,.desktop-dim,.idle-hint'))focusStage();
  });
  document.addEventListener('input',event=>{if(event.target.id==='product-query'){state.query=event.target.value;state.cursor=0;renderSwitcher({focusSearch:true});}});
  $('activate').addEventListener('click',()=>activate());
  $('reset').addEventListener('click',()=>{seed(Number($('scenario').value));say('Reset to a fresh address session. Type a displayed letter.');});
  $('scenario').addEventListener('change',event=>changeCount(Number(event.target.value)));
  $('add-window').addEventListener('click',addWindow);$('close-window').addEventListener('click',closeWindow);
  $('hand').addEventListener('change',event=>{const custom=event.target.value==='custom';$('custom-controls').hidden=!custom;if(!custom)applyAlphabet(event.target.value==='right'?'jkluionmhp':'asdfwercvq');});
  $('apply-alphabet').addEventListener('click',()=>applyAlphabet($('custom-alphabet').value.toLowerCase()));
  $('custom-alphabet').addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();applyAlphabet(event.target.value.toLowerCase());}});
  $('reduce-motion').addEventListener('change',event=>document.body.classList.toggle('reduce-motion',event.target.checked));
  $('tab-experiment').addEventListener('click',()=>{setConcept('canopy');setScope('tabs');stage.scrollIntoView({block:'center',behavior:'instant'});});
  // Read-only snapshot for browser verification; it never changes the simulation.
  window.tabnaxSnapshot=()=>({concept:state.concept,scope:state.scope,active:state.active,mode:state.mode,prefix:state.prefix,query:state.query,focused:state.focused,previousFocused:state.previousFocused,lastFocus:state.lastFocus,alphabet:state.alphabet,targets:targets().map(t=>({id:t.id,address:address(t),title:t.title})),windows:alive().map(w=>({id:w.id,address:allocate(w.id,'windows'),title:w.title})),retired:[...state.retired],message:state.notification});
  const info=concepts.shore;$('concept-scan').textContent=info.scan;$('concept-tradeoff').textContent=info.tradeoff;
  seed(8);
  say('Ready. Type a displayed letter to focus its window.');
  const requested=new URLSearchParams(location.search).get('concept');if(requested&&concepts[requested])setConcept(requested);
})();
