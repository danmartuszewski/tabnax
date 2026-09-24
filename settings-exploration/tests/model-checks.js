const assert = require('node:assert/strict');
const M = require('../model.js');
let checks=0;
function check(value, message) {assert.ok(value,message);checks++;}
const sel=M.defaults.selection;
for(const p of ['stable','mnemonic','pairs'])for(const a of Object.values(M.presets)){
 const pool=M.codes(a,p);
 check(new Set(pool).size===pool.length,`${p} labels unique`);
 check(pool.every(x=>pool.every(y=>x===y||!y.startsWith(x))),`${p} prefix-free`);
}
check(!!M.validateAlphabet('JJKKLL').error,'duplicates rejected');
check(!!M.validateAlphabet('ABC').error,'short alphabet rejected');
check(!!M.validateAlphabet('JKLU/IONMHP').error,'command rejected');
check(M.validateAlphabet('j k l u i o n m h p').alphabet==='JKLUIONMHP','normalization');
const s=M.create(sel,M.windows.slice(0,8));
check(JSON.stringify(Object.values(s.map))===JSON.stringify(['J','K','L','U','I','O','N','M']),'eight default addresses');
M.allocate(s,M.windows[8]);M.allocate(s,M.windows[9]);
check(s.map.review==='H'&&s.map.exports==='PJ','tenth overflows without relabel');
M.retire(s,'lesson');M.allocate(s,{id:'new',name:'Safari',title:'Lesson'});
check(s.map.new==='PK'&&s.retired.includes('K'),'closed label held');
check(s.map.preview==='L','survivor label unchanged');
check(!!M.pin(s,'code','L'),'collision rejected');
check(!!M.pin(s,'code','P'),'branch rejected');
check(!!M.pin(s,'code','K'),'retired rejected');
check(M.pin(s,'code','PL')==='','free pin accepted');
check(s.map.code==='PL'&&s.retired.includes('J'),'pin retires old code');
const small={...sel,alphabet:'ASDFGQ'};
const exhaust=M.create(small,Array.from({length:21},(_,i)=>({id:String(i),name:'Test',title:'Test'})));
check(Object.values(exhaust.map).filter(Boolean).length===20,'bounded depth');
check(exhaust.map['20']===null,'overflow fallback, no reshuffle');
const pair=M.create({...sel,policy:'pairs'},Array.from({length:28},(_,i)=>({id:String(i),name:'Safari',title:'Tab'})));
check(Object.values(pair.map).every(x=>x.length===2),'28 tabs two keys');
const mnemonic=M.create({...sel,policy:'mnemonic'},M.windows.slice(0,8));
check(mnemonic.map.lesson==='K'&&mnemonic.map.preview==='L'&&mnemonic.map.notes==='N','constrained mnemonic examples');
check(M.create(sel,M.windows.slice(0,8)).retired.length===0,'reset clears retirement');
function lum(hex){return hex.match(/\w\w/g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4).reduce((sum,x,i)=>sum+x*[.2126,.7152,.0722][i],0);}
const pairs=[['22272c','fafafa'],['f1f3f5','24282e'],['62666c','fafafa'],['b7bec8','24282e'],['292d33','e5e7e9'],['fafbfc','424a54'],['254a36','dcebdd'],['1d3b28','c0d9ba'],['4d367d','e7e1fa'],['362258','d0c2ee']];
const contrast=pairs.map(([fg,bg])=>{const [a,b]=[lum(fg),lum(bg)].sort((a,b)=>b-a);return {fg,bg,ratio:(a+.05)/(b+.05)};});
for(const x of contrast)check(x.ratio>=4.5,'contrast '+x.fg+'/'+x.bg);
console.log(JSON.stringify({passed:checks,contrast:contrast.map(x=>({...x,ratio:x.ratio.toFixed(2)}))},null,2));
