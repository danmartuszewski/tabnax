async page=>{
 let passed=0;const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const check=(v,n)=>{if(!v)throw Error(n);passed++;};
 const state=()=>page.evaluate(()=>TabnaxStudy.inspect()),pane=n=>page.locator('button[data-pane='+n+']').click();
 const detail=async s=>{if(!await page.locator(s).evaluate(e=>e.open))await page.locator(s+'>summary').click();};
 const reset=async()=>{await page.goto('http://127.0.0.1:4174/settings-exploration/tabnax-settings.html');await page.evaluate(()=>localStorage.removeItem('tabnax.settings-study.v1'));await page.reload();};
 const rotate=a=>a.slice(1)+a[0];
 await reset();await page.setViewportSize({width:1280,height:1150});
 check(await page.locator('#reset-alphabet').isDisabled(),'order restore disabled when already default');
 await pane('appearance');await page.locator('[data-theme=iris]').click();await pane('position');await page.locator('[data-anchor=top-left]').click();await pane('selection');await page.locator('#policy').selectOption('pairs');await page.locator('#apply').click();
 for(const [hand,alphabet] of Object.entries({right:'JKLUIONMHP',left:'ASDFWERCGQ',both:'ASDFJKLWERUIOP'})){
  await page.locator('#hand').selectOption(hand);await page.locator('#apply').click();
  await page.locator('#alphabet').fill(rotate(alphabet));await page.locator('#apply').click();
  check((await state()).cfg.selection.baseHand===hand,'custom order keeps '+hand+' base');
  const saved=await state();await page.locator('#reset-alphabet').click();
  check(await page.locator('#alphabet').inputValue()===alphabet&&(await state()).draft.selection.hand===hand,'restore previews '+hand+' order');
  check(JSON.stringify((await state()).engine)===JSON.stringify(saved.engine)&&(await state()).cfg.selection.alphabet===rotate(alphabet),'restore does not apply silently');
  check((await state()).cfg.theme==='iris'&&(await state()).cfg.position.anchor==='top-left'&&(await state()).draft.selection.policy==='pairs','reset preserves unrelated preferences and policy');
  await page.locator('#discard').click();check(await page.locator('#alphabet').inputValue()===rotate(alphabet),'discard keeps custom order');
  await page.locator('#reset-alphabet').click();await page.locator('#apply').click();
  const applied=await state();check(applied.cfg.selection.alphabet===alphabet&&[applied.engine,applied.foldEngine,applied.otherCatalogue.engine].every(x=>x.selection.alphabet===alphabet),'restore updates all maps transactionally');
  await page.locator('#undo').click();check(JSON.stringify((await state()).engine.map)===JSON.stringify(saved.engine.map),'undo restores learned custom labels');
  await page.reload();check((await state()).cfg.selection.baseHand===hand&&(await page.locator('#alphabet-reset-help').textContent()).includes(hand==='both'?'Both hands':hand==='left'?'Left hand':'Right hand'),'custom base survives reload');
  await page.locator('#alphabet').fill('JJJJJJ');await page.locator('#reset-alphabet').click();check(await page.locator('#alphabet').inputValue()===alphabet&&await page.locator('#alphabet').getAttribute('aria-invalid')==='false'&&await page.locator('#apply').isEnabled(),'restore recovers invalid alphabet');await page.locator('#discard').click();
 }
 await reset();await page.locator('#remove-ambiguous').click();await page.locator('#reset-alphabet').click();check(await page.locator('#alphabet').inputValue()==='JKLUIONMHP','restore includes removed I/O');await page.locator('#discard').click();
 for(const mode of ['shore','beacons','canopy','lattice','fold','relay']){
  await pane('appearance');await page.locator('#display-mode').selectOption(mode);await pane('selection');await page.locator('#alphabet').fill('KJLUIONMHP');await page.locator('#apply').click();
  await page.locator('#reset-alphabet').click();check((await state()).cfg.selection.alphabet==='KJLUIONMHP'&&await page.locator('#apply').isEnabled(),mode+' reset is a draft');await page.locator('#apply').click();
  const s=await state();check([s.engine,s.foldEngine,s.otherCatalogue.engine].every(x=>x.selection.alphabet==='JKLUIONMHP'),mode+' reset keeps all alphabets consistent');
 }
 await reset();await page.locator('#alphabet').fill('KJLUIONMHP');await page.locator('#apply').click();await detail('#advanced');await page.locator('#pin-target').selectOption('code');await page.locator('#pin-code').fill('H');await page.locator('#pin').click();await page.locator('#apply').click();await page.locator('#reset-alphabet').click();await page.locator('#apply').click();check((await state()).engine.map.code==='H'&&(await state()).engine.pins.code==='H','compatible pin survives order restore');
 await reset();await page.locator('#alphabet').fill('ASDFGH');await page.locator('#apply').click();await detail('#advanced');await page.locator('#pin-target').selectOption('code');await page.locator('#pin-code').fill('HHG');await page.locator('#pin').click();await page.locator('#apply').click();const pinned=await state();await page.locator('#reset-alphabet').click();
 check(await page.locator('#apply').isDisabled()&&(await page.locator('#alphabet-error').textContent()).includes('pinned'),'incompatible pin blocks restore Apply');check(JSON.stringify((await state()).engine)===JSON.stringify(pinned.engine),'blocked restore never drops pin or changes labels');await page.locator('#discard').click();
 // Migration: old named presets and exact custom matches retain their hand; ambiguous custom orders use the documented default.
 for(const [hand,alphabet,expected] of [['left','ASDFWERCGQ','left'],['custom','ASDFJKLWERUIOP','both'],['custom','ZXCVBN','right']]){
  await page.evaluate(({hand,alphabet})=>{const old=JSON.parse(localStorage.getItem('tabnax.settings-study.v1'));old.config.selection={hand,alphabet,policy:'stable'};localStorage.setItem('tabnax.settings-study.v1',JSON.stringify(old));},{hand,alphabet});await page.reload();check((await state()).cfg.selection.baseHand===expected,'legacy base migration '+hand+' '+expected);
 }
 await reset();await pane('general');check(await page.locator('#reset-shortcut').isDisabled(),'suggested shortcut reset starts disabled');await page.locator('#activation').selectOption('hold');await page.locator('summary').filter({hasText:'Shortcut details'}).click();await page.locator('#modifier-side').selectOption('right');await page.locator('#record').click();await page.keyboard.press('Control+Shift+P');const shortcuts=await state();await page.locator('#reset-shortcut').click();
 check((await state()).cfg.shortcut==='⌃ ⌥ Space'&&(await state()).cfg.activation==='hold'&&(await state()).cfg.modifierSide==='right','shortcut restore only changes shortcut');check(JSON.stringify((await state()).engine)===JSON.stringify(shortcuts.engine),'shortcut restore preserves labels');await page.locator('#undo').click();check((await state()).cfg.shortcut===shortcuts.cfg.shortcut,'shortcut restore undo');
 await page.locator('#record').click();await page.keyboard.press('k');await page.locator('#reset-shortcut').click();check(await page.locator('#shortcut-error').textContent()===''&&await page.locator('#record').textContent()==='⌃ ⌥ Space','restore cancels recorder and clears error');
 await reset();await pane('appearance');await page.locator('[name=appearance][value=light]').check();await detail('#customize-theme');
 const color=async(s,v)=>{await page.locator(s).fill(v);await page.locator(s).blur();};
 check(await page.locator('#reset-key-color').isDisabled()&&await page.locator('#reset-selection-color').isDisabled(),'individual color resets disabled without overrides');
 await color('#custom-key-color','#123456');await color('#custom-selection-color','#654321');await page.locator('[name=appearance][value=dark]').check();await color('#custom-key-color','#111111');await page.locator('[data-theme=sage]').click();await color('#custom-key-color','#222222');await page.locator('[data-theme=graphite]').click();await page.locator('[name=appearance][value=light]').check();const colors=await state();
 await page.locator('#reset-key-color').click();let s=await state();check(!s.cfg.themeOverrides.graphite.light.keyBg&&s.cfg.themeOverrides.graphite.light.selection==='#654321','key reset preserves selection override');check(s.cfg.themeOverrides.graphite.dark.keyBg==='#111111'&&s.cfg.themeOverrides.sage.dark.keyBg==='#222222','key reset preserves other appearance and preset');check(await page.locator('#custom-key-color').inputValue()==='#e5e7e9','key picker returns to curated default');
 await page.locator('#undo').click();check(JSON.stringify((await state()).cfg.themeOverrides)===JSON.stringify(colors.cfg.themeOverrides),'single color reset Undo restores exact overrides');
 await page.locator('#reset-selection-color').click();s=await state();check(!s.cfg.themeOverrides.graphite.light.selection&&s.cfg.themeOverrides.graphite.light.keyBg==='#123456','selection reset preserves custom key color');await page.locator('#reset-key-color').click();check(!(await state()).cfg.themeOverrides.graphite.light&&await page.locator('#reset-theme').isEnabled(),'empty appearance overrides pruned while other appearance remains');await page.reload();await detail('#customize-theme');check(await page.locator('#reset-key-color').isDisabled()&&await page.locator('#custom-key-color').inputValue()==='#e5e7e9','color reset persists');check(JSON.stringify((await state()).engine.map)===JSON.stringify(colors.engine.map),'colors never reassign labels');
 for(const width of [1280,390,320]){await page.setViewportSize({width,height:1150});for(const name of ['selection','general','appearance']){await pane(name);check(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth),name+' scoped actions fit '+width);}}
 await page.screenshot({path:'settings-exploration/output/playwright/resets-colors-compact.png',fullPage:true});await page.setViewportSize({width:1280,height:1150});
 await reset();await page.locator('#alphabet').fill('KJLUIONMHP');await page.screenshot({path:'settings-exploration/output/playwright/resets-selection.png',fullPage:true});await page.locator('#discard').click();
 check(errors.length===0,'no runtime errors: '+errors.join(';'));return {passed,errors};
}
