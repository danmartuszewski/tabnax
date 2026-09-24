const assert=require('node:assert/strict');
const M=require('../model.js');let passed=0;
const check=(value,name)=>{assert.ok(value,name);passed++;};
// Independent luminance calculation validates rendered tokens, including arbitrary user colors.
const lum=color=>{const rgb=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16)/255).map(x=>x>.04045?Math.pow((x+.055)/1.055,2.4):x/12.92);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;};
const ratio=(a,b)=>(Math.max(lum(a),lum(b))+.05)/(Math.min(lum(a),lum(b))+.05);
const original=JSON.stringify(M.themes);let minimumText=Infinity,minimumAccent=Infinity;
for(const preset of Object.keys(M.themes))for(const mode of ['light','dark']){
 const base=M.resolveTheme(preset,mode);
 check(ratio(base.text,base.surface)>=4.5&&ratio(base.muted,base.surface)>=4.5&&ratio(base.keyFg,base.keyBg)>=4.5,preset+' '+mode+' preset text');
 check(ratio(base.selection,base.surface)>=3,preset+' '+mode+' selection boundary');
 const colors=['#000000','#ffffff','#777777',base.surface,...Array.from({length:128},(_,i)=>'#'+((i*131071+69711)%16777216).toString(16).padStart(6,'0'))];
 const palettes=colors.map(color=>M.resolveTheme(preset,mode,{[preset]:{[mode]:{keyBg:color,selection:color}}}));
 const text=palettes.map(p=>ratio(p.keyFg,p.keyBg)),accent=palettes.map(p=>ratio(p.selection,p.surface));
 minimumText=Math.min(minimumText,...text);minimumAccent=Math.min(minimumAccent,...accent);
 check(text.every(x=>x>=4.5),preset+' '+mode+' custom text remains readable');
 check(accent.every(x=>x>=3),preset+' '+mode+' custom selection remains visible');
 check(JSON.stringify(M.resolveTheme(preset,mode,{[preset]:{[mode]:{keyBg:'invalid',selection:'#xyz'}}}))===JSON.stringify(base),'malformed overrides ignored');
}
check(JSON.stringify(M.themes)===original,'customization never mutates presets');
check(M.themes.tabnax.dark.keyBg==='#d9f68c'&&M.themes.tabnax.dark.surface==='#202720','original design colors retained');
check(JSON.stringify(M.resolveTheme('unknown','light'))===JSON.stringify(M.themes.graphite.light),'unknown preset falls back to macOS');
console.log(JSON.stringify({passed,customPalettesChecked:1056,minimumText,minimumAccent},null,2));
