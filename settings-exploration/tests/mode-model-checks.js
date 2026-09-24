const assert=require('node:assert/strict'),M=require('../model.js'),V=require('../modes.js');let passed=0;
const check=(v,n)=>{assert.ok(v,n);passed++;};
for(const alphabet of Object.values(M.presets)){
 const targets=Array.from({length:32},(_,i)=>({id:'w'+i,app:'app'+(i%4),name:'App '+(i%4),title:'Window '+i}));
 const s=V.createFold({...M.defaults.selection,alphabet},targets),codes=Object.values(s.map);
 check(new Set(codes).size===codes.length,'Fold composite labels unique');
 check(codes.every(a=>codes.every(b=>a===b||!b.startsWith(a))),'Fold composites prefix-free');
 const before={...s.map};V.retireFold(s,targets[0]);
 const added={id:'new',app:targets[0].app,name:'App',title:'New'};V.allocateFold(s,added);
 check(s.map.new!==before.w0&&Object.keys(s.map).filter(id=>id!=='new').every(id=>s.map[id]===before[id]),'Fold closure never relabels or reuses retired child');
}
const s=V.createFold(M.defaults.selection,M.windows.slice(0,8));
check(s.map.code==='JJ'&&s.map.lesson==='KJ'&&s.map.preview==='KK','Fold singleton and sibling addresses');
check(!Object.values(s.map).includes('J'),'singleton app key is never a complete window address');
check(!!V.pinFold(s,M.windows[1],'KK'),'Fold sibling pin collision rejected');
check(!!V.pinFold(s,M.windows[0],'KH'),'pin cannot change application prefix');
check(V.pinFold(s,M.windows[0],'JH')==='','free Fold child pin accepted');
check(s.map.code==='JH'&&s.retired.includes('JJ'),'Fold pin retires old composite');
check(!!V.reassignFold(s,{...M.defaults.selection,alphabet:M.presets.left},M.windows.slice(0,8)).error,'incompatible Fold pin blocks alphabet transaction');
const reassigned=V.reassignFold(s,{...M.defaults.selection,alphabet:'KJLUIONMHP'},M.windows.slice(0,8));
check(!reassigned.error&&reassigned.state.map.code==='KH','compatible child pin survives app-prefix reassignment');
const wholeApp=V.createFold(M.defaults.selection,[M.windows[0]]);V.retireFold(wholeApp,M.windows[0]);V.allocateFold(wholeApp,{...M.windows[0],id:'code-new'});
check(wholeApp.map['code-new']==='JK','empty family keeps app prefix and retired child');
const overflow=V.createFold(M.defaults.selection,Array.from({length:12},(_,i)=>({id:'w'+i,app:'a'+i,name:'App',title:'Window'})));
check(overflow.map.w9==='PJJ'&&overflow.map.w10==='PKJ','app overflow keeps two-stage parse');
const before=JSON.stringify(s);V.reassignFold(s,{...M.defaults.selection,alphabet:'KJLUIONMHP'},M.windows.slice(0,8));check(JSON.stringify(s)===before,'Fold preview does not mutate saved session');
console.log(JSON.stringify({passed}));
