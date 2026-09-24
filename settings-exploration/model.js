/* Pure simulation model. No native APIs, title-derived identity, or system access. */
(function (root) {
  'use strict';
  const presets = {right:'JKLUIONMHP',left:'ASDFWERCGQ',both:'ASDFJKLWERUIOP'};
  const browsers=[
    {id:'arc',name:'Arc',icon:'A',setup:'builtin',note:'Permission may be needed'},
    {id:'zen',name:'Zen',icon:'◌',setup:'addon',note:'Add-on likely needed'},
    {id:'safari',name:'Safari',icon:'◈',setup:'verify',note:'Connection being evaluated'},
    {id:'chrome',name:'Chrome',icon:'◉',setup:'builtin',note:'Permission may be needed'},
    {id:'firefox',name:'Firefox',icon:'◉',setup:'addon',note:'Add-on likely needed'},
    {id:'edge',name:'Edge',icon:'e',setup:'builtin',note:'Permission may be needed'},
    {id:'brave',name:'Brave',icon:'♜',setup:'builtin',note:'Permission may be needed'}
  ];
  const defaults = {version:1,displayMode:'shore',modePositions:{},themeOverrides:{},position:{display:'focused',anchor:'middle-right',inset:24},browserTabs:{enabled:true,range:'all',defaultScope:'windows',selection:'automatic',selectedBrowsers:browsers.map(b=>b.id)},appearance:'system',theme:'graphite',labelSize:'standard',strongLabels:false,login:false,minimized:true,hidden:true,shortcut:'⌃ ⌥ Space',activation:'latch',modifierSide:'either',keyMode:'physical',selection:{hand:'right',baseHand:'right',alphabet:presets.right,policy:'stable'}};
  const themes={
    graphite:{light:{surface:'#fafafa',text:'#22272c',muted:'#62666c',keyBg:'#e5e7e9',keyFg:'#292d33',keyBorder:'#adb2b8',selection:'#006bd6'},dark:{surface:'#24282e',text:'#f1f3f5',muted:'#b7bec8',keyBg:'#424a54',keyFg:'#fafbfc',keyBorder:'#87919e',selection:'#77baff'}},
    tabnax:{light:{surface:'#f5f7ef',text:'#293323',muted:'#59634f',keyBg:'#d9f68c',keyFg:'#28361b',keyBorder:'#91aa5f',selection:'#557719'},dark:{surface:'#202720',text:'#f6f8ee',muted:'#bac3b3',keyBg:'#d9f68c',keyFg:'#28361b',keyBorder:'#b0cb7a',selection:'#d9f68c'}},
    sage:{light:{surface:'#fafafa',text:'#22272c',muted:'#62666c',keyBg:'#dcebdd',keyFg:'#254a36',keyBorder:'#8aab95',selection:'#3a7753'},dark:{surface:'#24282e',text:'#f1f3f5',muted:'#b7bec8',keyBg:'#c0d9ba',keyFg:'#1d3b28',keyBorder:'#8faa89',selection:'#c0d9ba'}},
    iris:{light:{surface:'#fafafa',text:'#22272c',muted:'#62666c',keyBg:'#e7e1fa',keyFg:'#4d367d',keyBorder:'#b0a0cd',selection:'#7755b6'},dark:{surface:'#24282e',text:'#f1f3f5',muted:'#b7bec8',keyBg:'#d0c2ee',keyFg:'#362258',keyBorder:'#ad96d5',selection:'#c3a8f7'}}
  };
  function luminance(hex){return hex.slice(1).match(/../g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4).reduce((n,x,i)=>n+x*[.2126,.7152,.0722][i],0);}
  function contrast(a,b){const hi=Math.max(luminance(a),luminance(b)),lo=Math.min(luminance(a),luminance(b));return (hi+.05)/(lo+.05);}
  function readableText(bg){return contrast('#000000',bg)>=contrast('#ffffff',bg)?'#000000':'#ffffff';}
  function safeAccent(color,surface){
    if(contrast(color,surface)>=3)return color;
    const toward=readableText(surface),a=color.slice(1).match(/../g).map(x=>parseInt(x,16)),b=toward.slice(1).match(/../g).map(x=>parseInt(x,16));
    for(let i=1;i<=20;i++){const c='#'+a.map((v,j)=>Math.round(v+(b[j]-v)*i/20).toString(16).padStart(2,'0')).join('');if(contrast(c,surface)>=3)return c;}
    return toward;
  }
  function resolveTheme(theme,appearance,overrides={}){
    const base={...(themes[theme]||themes.graphite)[appearance]},custom=overrides[theme]?.[appearance]||{};
    if(/^#[0-9a-f]{6}$/i.test(custom.keyBg||'')){base.keyBg=custom.keyBg;base.keyFg=readableText(custom.keyBg);base.keyBorder=safeAccent(custom.keyBg,base.surface);}
    if(/^#[0-9a-f]{6}$/i.test(custom.selection||''))base.selection=safeAccent(custom.selection,base.surface);
    return base;
  }
  const windows = [
    {id:'code',app:'code',name:'VS Code',title:'Tabnax · switcher.swift'},
    {id:'lesson',app:'safari',name:'Safari',title:'Tabnax · Keyboard guide',context:'Work'},
    {id:'preview',app:'safari',name:'Safari',title:'Tabnax · Layout preview',context:'Work'},
    {id:'assets',app:'finder',name:'Finder',title:'Tabnax · Assets'},
    {id:'design',app:'figma',name:'Figma',title:'Interaction studies'},
    {id:'terminal',app:'terminal',name:'Terminal',title:'tabnax · zsh'},
    {id:'notes',app:'notes',name:'Notes',title:'Switching · Interview notes'},
    {id:'personal',app:'safari',name:'Safari',title:'Weekend walks',context:'Personal',minimized:true},
    {id:'review',app:'code',name:'VS Code',title:'Tabnax · Review diff'},
    {id:'exports',app:'finder',name:'Finder',title:'Tabnax · Exports',hidden:true}
  ];
  const tabs = Array.from({length:28},(_,i)=>({
    id:'tab-'+i,app:i<14?'safari':'chrome',name:i<14?'Safari':'Chrome',
    browserId:i<14?'safari':'chrome',windowId:i<8?'safari-work':i<14?'safari-personal':i<23?'chrome-work':'chrome-reference',
    title:['Tabnax · Window shortcuts','Workspace guide · Lesson '+(i+1),'Apple · Accessibility','Tabnax · Notes','Saved walks · Route '+(i+1),'Reference · Keyboard layouts'][i%6],
    context:(i<8||i>=14&&i<23?'Work':'Personal')+' / tab '+(i+1),private:false
  }));
  for(const browser of browsers.filter(b=>!['safari','chrome'].includes(b.id))){
    for(let i=0;i<4;i++)tabs.push({id:browser.id+'-tab-'+i,app:browser.id,name:browser.name,browserId:browser.id,windowId:browser.id+(i<2?'-work':'-personal'),title:['Tabnax · Research','Tabnax · Shortcut planning','Saved walks · Route notes','Reference · Keyboard layouts'][i],context:(i<2?'Work':'Personal')+(browser.id==='arc'?' Space':browser.id==='zen'?' workspace':' window')+(i===0&&browser.id==='arc'?' · pinned':''),private:false});
  }
  function includedBrowsers(preference){return preference.selection==='selected'?browsers.filter(b=>preference.selectedBrowsers.includes(b.id)).map(b=>b.id):browsers.map(b=>b.id);}
  const clone = x => JSON.parse(JSON.stringify(x));
  const normalize = s => s.toUpperCase().replace(/\s/g,'');
  function baseHand(selection) {
    if(Object.hasOwn(presets,selection.hand))return selection.hand;
    if(Object.hasOwn(presets,selection.baseHand))return selection.baseHand;
    return Object.keys(presets).find(hand=>presets[hand]===normalize(selection.alphabet||''))||'right';
  }
  function validateAlphabet(raw) {
    const a=normalize(raw);
    if (!/^[A-Z]*$/.test(a)) return {error:'Use letters A–Z only. Slash, digits and punctuation are reserved for commands.'};
    if (a.length<6 || a.length>20) return {error:'Use 6–20 letters so there is room for comfortable short sequences.'};
    const duplicates=[...new Set([...a].filter((c,i)=>a.indexOf(c)!==i))];
    if (duplicates.length) return {error:`Remove repeated letters: ${duplicates.join(', ')}.`};
    return {alphabet:a,error:''};
  }
  function codes(alphabet, policy) {
    const a=[...alphabet], out=[];
    if(policy==='pairs') {for(const x of a) for(const y of a) out.push(x+y);}
    else {const branch=a.pop(); for(let depth=0;depth<4;depth++) for(const c of a) out.push(branch.repeat(depth)+c);}
    return out;
  }
  function create(selection, targets, pins={}) {
    const state={selection:clone(selection),map:{},retired:[],pins:clone(pins),order:[],nextSlot:0,slots:{}};
    const pool=codes(selection.alphabet,selection.policy);
    for(const t of targets) if(pins[t.id] && pool.includes(pins[t.id])) state.map[t.id]=pins[t.id];
    for(const t of targets) allocate(state,t);
    return state;
  }
  function allocate(state,target) {
    if(state.order.includes(target.id)) return;
    const used=new Set([...Object.values(state.map),...state.retired]);
    const pool=codes(state.selection.alphabet,state.selection.policy);
    let code=state.map[target.id];
    if(!code && state.selection.policy==='mnemonic') {
      // First available name initial, then distinguishing title initials; never move existing labels.
      const words=(target.name+' '+target.title).toUpperCase().match(/[A-Z]+/g)||[];
      code=words.map(w=>w[0]).find(c=>pool.includes(c)&&!used.has(c));
    }
    if(!code) code=pool.find(c=>!used.has(c))||null;
    state.map[target.id]=code;
    state.slots[target.id]=state.nextSlot++;
    state.order.push(target.id);
  }
  function retire(state,id) {
    if(state.map[id]) state.retired.push(state.map[id]);
    delete state.map[id];delete state.pins[id];
    state.order=state.order.filter(x=>x!==id);
    // Keep old slot occupied by a hole until deliberate reset.
  }
  function pin(state,id,raw) {
    const label=normalize(raw), pool=codes(state.selection.alphabet,state.selection.policy);
    if(!label) return 'Enter a label.';
    if(Object.entries(state.map).some(([key,c])=>key!==id&&c===label)) return `${label} already belongs to another window. Choose a free label.`;
    if(state.retired.includes(label)&&state.map[id]!==label) return `${label} is held for a closed or reassigned window. Reset labels to reuse it.`;
    if(!pool.includes(label)) return `That label is a reserved prefix or is outside this alphabet. Try a free complete label, such as ${pool.find(c=>!Object.values(state.map).includes(c)&&!state.retired.includes(c))||'a label after resetting'}.`;
    const old=state.map[id];if(old&&old!==label) state.retired.push(old);
    state.map[id]=label;state.pins[id]=label;return '';
  }
  const api={browsers,includedBrowsers,presets,baseHand,defaults,themes,contrast,readableText,safeAccent,resolveTheme,windows,tabs,clone,normalize,validateAlphabet,codes,create,allocate,retire,pin};
  if(typeof module!=='undefined') module.exports=api;
  root.TabnaxModel=api;
})(typeof globalThis!=='undefined'?globalThis:this);
