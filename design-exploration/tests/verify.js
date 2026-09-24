async (page) => {
  const passed=[];
  const check=(ok,label)=>{if(!ok)throw new Error(label);passed.push(label);};
  const snap=()=>page.evaluate(()=>window.tabnaxSnapshot());
  const press=key=>page.keyboard.press(key);
  const reset=()=>page.locator('#reset').click();
  const choose=name=>page.locator(`[data-concept="${name}"]`).click();
  const stable=(before,after)=>before.every(t=>!after.find(x=>x.id===t.id)||after.find(x=>x.id===t.id).address===t.address);
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:4173/design-exploration/index.html');
  await page.setViewportSize({width:1440,height:1100});
  for(const concept of ['shore','beacons','canopy']){
    await choose(concept);await reset();
    const initial=await snap();
    check(initial.targets.length===8,concept+': eight initial windows');
    await press('l');let s=await snap();
    check(s.focused==='preview'&&!s.active,concept+': direct same-app window selected');
    check(stable(initial.windows,s.windows),concept+': focus preserves addresses');
    await press('Space');await press('/');await page.locator('#product-query').fill('keyboard guide');s=await snap();
    check(s.active&&s.mode==='search'&&s.focused==='preview'&&s.query==='keyboard guide',concept+': search letters do not select');
    await press('Enter');s=await snap();
    check(!s.active&&s.focused==='lesson',concept+': search Enter selects exact result');
    await press('Space');await press('/');await page.locator('#product-query').fill('no-such-window-xyz');await press('Enter');s=await snap();
    check(s.active&&s.focused==='lesson',concept+': empty search cannot change focus');
    await press('Escape');s=await snap();check(s.mode==='select'&&s.active,concept+': Escape leaves text mode');
    await press('Escape');s=await snap();check(!s.active&&s.focused==='lesson',concept+': cancellation preserves focus');
    await press('Space');await press('2');s=await snap();check(s.scope==='apps'&&s.targets.length===6,concept+': apps scope');
    await press('k');s=await snap();check(s.focused==='lesson'&&!s.active,concept+': app selects most recent window');
    await press('Space');await press('1');await press('m');s=await snap();check(s.focused==='personal'&&!s.active,concept+': minimized target restored');
    await page.keyboard.down('Shift');s=await snap();check(s.active,concept+': held activation opens');
    await page.keyboard.up('Shift');s=await snap();check(!s.active&&s.focused==='personal',concept+': release without address cancels');
    await page.keyboard.down('Shift');await press('o');await page.keyboard.up('Shift');s=await snap();check(!s.active&&s.focused==='dev',concept+': held selection commits on letter');
    const immediate=await page.evaluate(()=>{
      const d=document.getElementById('desktop');d.focus();
      d.dispatchEvent(new KeyboardEvent('keydown',{key:' ',code:'Space',bubbles:true}));
      d.dispatchEvent(new KeyboardEvent('keydown',{key:'k',code:'KeyK',bubbles:true}));
      return tabnaxSnapshot();
    });
    check(!immediate.active&&immediate.focused==='lesson',concept+': synchronous input during opening transition');
    await reset();await page.locator('#desktop').screenshot({path:`design-exploration/verification/screenshots/${concept}.png`});
  }
  await choose('shore');await reset();await page.locator('summary').click();
  const original=(await snap()).windows;
  await page.locator('#scenario').selectOption('10');let s=await snap();
  check(s.targets.length===10&&stable(original,s.windows),'ten-window scenario preserves original addresses');
  check(s.targets.find(t=>t.id==='export').address==='pj','tenth window uses reserved prefix PJ');
  await press('p');s=await snap();check(s.active&&s.prefix==='p','overflow prefix waits for second letter');
  await press('Backspace');s=await snap();check(s.prefix===''&&s.active,'Backspace undoes overflow prefix');
  await press('p');await press('j');s=await snap();check(s.focused==='export'&&!s.active,'two-letter window selection');
  await press('Space');const beforeClose=s.windows;
  await page.locator('#close-window').click();s=await snap();
  check(!s.windows.some(t=>t.id==='export')&&s.retired.includes('PJ')&&stable(beforeClose,s.windows),'closing retires address and preserves survivors');
  await page.locator('#add-window').click();s=await snap();
  check(s.windows.at(-1).address==='pk'&&stable(original,s.windows),'opening never recycles a retired address');
  await press('p');await page.locator('#add-window').click();s=await snap();check(s.prefix==='','churn clears an incomplete sequence');
  await press('3');s=await snap();check(s.scope==='windows','tabs remain isolated to Canopy');
  await page.locator('#scenario').selectOption('6');s=await snap();check(s.windows.length===6&&stable(original,s.windows),'six-window set keeps addresses');
  await page.locator('#scenario').selectOption('8');await reset();await choose('canopy');await press('3');s=await snap();
  check(s.scope==='tabs'&&s.targets.length===28&&s.targets.every(t=>t.address.length===2),'28 tabs all have two-letter addresses');
  const tabs=s.targets;
  await page.locator('#desktop').screenshot({path:'design-exploration/verification/screenshots/canopy-tabs.png'});
  await press('j');s=await snap();check(s.prefix==='j'&&s.active,'tab first letter narrows without selecting');
  await press('Escape');s=await snap();check(s.active&&s.prefix==='','Escape clears tab prefix');
  await press('j');await press('k');s=await snap();check(!s.active&&s.lastFocus==='tab-1'&&s.focused==='lesson','second tab letter focuses its parent window');
  await press('Space');await press('/');await page.locator('#product-query').fill('window shortcuts');s=await snap();
  check(s.active&&s.query==='window shortcuts'&&s.lastFocus==='tab-1','typing a tab query cannot select');
  check(stable(tabs,s.targets),'tab filtering preserves addresses');
  const firstResult=await page.locator('.target.arrow-selected').getAttribute('data-target');
  await press('ArrowDown');const nextResult=await page.locator('.target.arrow-selected').getAttribute('data-target');
  check(firstResult!==nextResult,'search arrow navigation changes selected result');
  await press('Enter');s=await snap();check(!s.active&&s.lastFocus===nextResult,'search Enter follows highlighted result');
  await page.locator('#hand').selectOption('left');s=await snap();check(s.alphabet==='asdfwercvq'&&s.targets[0].address==='a','left-hand alphabet is applied');
  await press('s');s=await snap();check(s.focused==='lesson'&&!s.active,'left-hand direct selection works');
  await page.keyboard.down('ShiftRight');s=await snap();check(s.active,'opposite-hand hold trigger for left selection');await page.keyboard.up('ShiftRight');
  await page.locator('#hand').selectOption('custom');await page.locator('#custom-alphabet').fill('aabcde');await page.locator('#apply-alphabet').click();
  check((await page.locator('#alphabet-error').textContent()).length>0&&(await snap()).alphabet==='asdfwercvq','duplicate custom letters rejected without reset');
  await page.locator('#custom-alphabet').fill('asdfjk');await page.locator('#apply-alphabet').click();s=await snap();
  check(s.alphabet==='asdfjk'&&s.targets.every((a,i,all)=>all.every((b,j)=>i===j||!b.address.startsWith(a.address))),'six-letter custom alphabet is prefix-free');
  await press('3');s=await snap();check(s.targets.length===28&&new Set(s.targets.map(t=>t.address)).size===28,'minimum alphabet handles all 28 unique tabs');
  await page.locator('#hand').selectOption('right');await choose('shore');
  await page.emulateMedia({reducedMotion:'reduce'});
  check(await page.locator('.surface').evaluate(el=>getComputedStyle(el).transitionDuration)==='0s','system reduced motion removes transitions');
  await page.emulateMedia({reducedMotion:'no-preference'});await page.locator('#reduce-motion').check();
  check(await page.locator('.surface').evaluate(el=>getComputedStyle(el).transitionDuration)==='0s','lab reduced motion removes transitions');
  await page.locator('#reduce-motion').uncheck();await page.locator('summary').click();
  for(const width of [1440,1024,768,390,320]){
    await page.setViewportSize({width,height:1000});
    for(const concept of ['shore','beacons','canopy']){
      await choose(concept);
      const bounds=await page.evaluate(()=>{
        const s=document.getElementById('desktop').getBoundingClientRect(),p=document.querySelector('.surface').getBoundingClientRect();
        return {overflow:document.documentElement.scrollWidth>innerWidth,sx:s.x,sy:s.y,sr:s.right,sb:s.bottom,px:p.x,py:p.y,pr:p.right,pb:p.bottom};
      });
      check(!bounds.overflow&&bounds.px>=bounds.sx-1&&bounds.pr<=bounds.sr+1&&bounds.py>=bounds.sy-1&&bounds.pb<=bounds.sb+1,`${concept}: surface fits at ${width}px`);
      if(width===390)await page.locator('#desktop').screenshot({path:`design-exploration/verification/screenshots/${concept}-compact.png`});
    }
    await press('3');check((await snap()).targets.length===28,`tabs remain selectable at ${width}px`);
    if(width===390)await page.locator('#desktop').screenshot({path:'design-exploration/verification/screenshots/tabs-compact.png'});
  }
  check(errors.length===0,'no JavaScript page errors during interaction suite');
  await page.setViewportSize({width:1440,height:1100});await choose('shore');await reset();await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({path:'design-exploration/verification/screenshots/gallery-final.png',fullPage:true});
  return {passed:passed.length,checks:passed,errors};
}
