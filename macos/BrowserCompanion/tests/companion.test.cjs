const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {randomUUID} = require('node:crypto');
const event = () => ({addListener(){}});
async function run(source) {
  let reads = 0, selected = [], focus = [], posted = [], callbacks = [];
  const tabs = new Map([[1,{id:1,windowId:10,title:'Duplicate',active:true,incognito:false}], [2,{id:2,windowId:10,title:'Duplicate',active:false,incognito:false}], [3,{id:3,windowId:11,title:'Private secret',active:true,incognito:true}]]);
  const windows = new Map([[10,{id:10,focused:true,incognito:false}], [11,{id:11,focused:false,incognito:true}]]);
  const port = {postMessage:m=>posted.push(structuredClone(m)),onMessage:{addListener:f=>callbacks.push(f)},onDisconnect:event()};
  const browser = {runtime:{connectNative:()=>port},tabs:{get:async id=>({...tabs.get(id)}),update:async(id,opts)=>{ selected.push(id); for(const t of tabs.values()) if(t.windowId===tabs.get(id).windowId)t.active=t.id===id; return tabs.get(id); }},windows:{getAll:async()=>{reads++;return [...windows.values()].map(w=>({...w,tabs:[...tabs.values()].filter(t=>t.windowId===w.id)}));},get:async id=>({...windows.get(id)}),update:async(id,opts)=>{focus.push(id);for(const w of windows.values())w.focused=w.id===id;return windows.get(id);}}};
  for(const name of ['onCreated','onUpdated','onRemoved','onMoved','onAttached','onDetached','onActivated'])browser.tabs[name]=event();
  for(const name of ['onFocusChanged','onCreated','onRemoved'])browser.windows[name]=event();
  const context = vm.createContext({browser,tabnaxSafariAPI:browser,crypto:{randomUUID},setTimeout(){},structuredClone});
  vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,source),'utf8'),context);
  assert.equal(reads,0,'No tab read before native app configuration');
  const connection=posted[0].connection; assert.equal(posted[0].kind,'hello');
  await callbacks[0]({version:1,kind:'configure',connection,enabled:true}); await new Promise(resolve=>setImmediate(resolve));
  const snapshot=posted.find(m=>m.kind==='snapshot'); assert.deepEqual(snapshot.tabs.map(t=>t.id),['1','2']); assert(!JSON.stringify(snapshot).includes('secret'));
  await callbacks[0]({version:1,kind:'select',connection,request:'first',tab:'2',window:'10'});
  assert.deepEqual(selected,[2]);assert.deepEqual(focus,[10]);assert.equal(posted.find(m=>m.request==='first').selected,true);
  await callbacks[0]({version:1,kind:'select',connection,request:'private',tab:'3',window:'11'});
  assert.equal(posted.find(m=>m.request==='private').selected,false);assert.deepEqual(selected,[2]);
  await callbacks[0]({version:1,kind:'select',connection:randomUUID(),request:'stale',tab:'1'});assert.deepEqual(selected,[2]);
  await callbacks[0]({version:1,kind:'configure',connection,enabled:false});const before=reads;await context.snapshot();assert.equal(reads,before);
  await callbacks[0]({version:1,kind:'select',connection,request:'disabled',tab:'1'});assert.deepEqual(selected,[2]);
  await callbacks[0]({version:1,kind:'configure',connection,enabled:true});await new Promise(resolve=>setImmediate(resolve));
  // Cancel an in-flight tab lookup before either mutation is dispatched.
  let unblock; browser.tabs.get = id=>new Promise(resolve=>{unblock=()=>resolve({...tabs.get(id)})});
  const selecting=callbacks[0]({version:1,kind:'select',connection,request:'cancelled',tab:'1'});
  await callbacks[0]({version:1,kind:'cancel',connection});unblock();await selecting;assert.deepEqual(selected,[2]);
  // Selection follows the same exact tab after it moves to another window.
  browser.tabs.get = async id => ({...tabs.get(id)});
  windows.set(12,{id:12,focused:false,incognito:false}); tabs.get(2).windowId = 12;
  await callbacks[0]({version:1,kind:'select',connection,request:'moved',tab:'2',window:'10'});
  assert.deepEqual(selected,[2,2]); assert.deepEqual(focus,[10,12]);
  assert.equal(posted.find(m=>m.request==='moved').selected,true);
  console.log(source + ' companion checks passed: handshake, privacy, duplicate titles, exact selection, focus, stale generation, disable/re-enable, cancellation and tab movement.');
}
run('../background.js').then(()=>run('../../SafariCompanion/Resources/background.js')).catch(e=>{console.error(e);process.exitCode=1});
