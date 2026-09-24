async page => {
let passed=0;const errors=[];page.on('pageerror',e=>errors.push(e.message));const check=(v,n)=>{if(!v)throw Error(n);passed++;};
const url='http://127.0.0.1:4174/settings-exploration/tabnax-settings.html';
const state=()=>page.evaluate(()=>TabnaxStudy.inspect());
await page.goto(url);await page.evaluate(()=>localStorage.removeItem('tabnax.settings-study.v1'));await page.reload();await page.setViewportSize({width:1280,height:1000});
await page.locator('#hand').selectOption('left');await page.locator('#alphabet').fill('AAFFFF');
check(await page.locator('#preview-state').textContent()==='Last valid labels','invalid-after-valid draft status');await page.locator('#discard').click();
await page.locator('#try').click();await page.locator('#preview-surface').dispatchEvent('keydown',{key:'l',code:'KeyL',repeat:true});check((await state()).active,'autorepeat ignored');
await page.locator('#preview-surface').dispatchEvent('keydown',{key:'l',code:'KeyL',isComposing:true});check((await state()).active,'composition ignored');
await page.locator('#preview-surface').dispatchEvent('keydown',{key:'x',code:'KeyL'});check((await page.locator('#selection-result').textContent()).includes('Layout preview'),'physical key identity');
await page.locator('#advanced>summary').click();await page.locator('#key-mode').selectOption('characters');await page.locator('#try').click();await page.locator('#preview-surface').dispatchEvent('keydown',{key:'l',code:'KeyX'});check((await page.locator('#selection-result').textContent()).includes('Layout preview'),'character interpretation');
await page.locator('#key-mode').selectOption('physical');await page.locator('#preview-surface').focus();await page.keyboard.down('ShiftLeft');await page.keyboard.down('ShiftRight');await page.keyboard.up('ShiftRight');check((await state()).active,'opposite Shift release does not cancel hold');await page.keyboard.up('ShiftLeft');check(!(await state()).active,'correct side release cancels');
await page.locator('.test-controls>summary').click();await page.locator('#dataset').selectOption('tabs');await page.locator('#try').click();await page.keyboard.press('k');
check(await page.locator('.target').count()===10,'tabs narrow to ten K-prefixed targets');check((await state()).prefix==='K','narrowing preserves prefix');
check(await page.locator('.target').first().getAttribute('aria-label').then(s=>s.includes('KJ')),'matching branch begins in view');
await page.keyboard.press('x');check((await state()).prefix==='K','invalid second key preserves prefix');await page.keyboard.press('l');check((await page.locator('#selection-result').textContent()).includes('Selected Safari'),'narrowed leaf immediately selects');
await page.locator('#try').click();await page.keyboard.press('k');await page.screenshot({path:'settings-exploration/output/playwright/tabs-prefix.png',fullPage:true});await page.keyboard.press('Escape');await page.keyboard.press('Escape');
await page.locator('#dataset').selectOption('10');check(await page.locator('#targets').evaluate(e=>e.scrollHeight<=e.clientHeight),'ten normal-sized targets fully visible');
await page.locator('button[data-pane=general]').click();await page.locator('#hidden').uncheck();check(await page.locator('.target').count()===9,'hidden-app filter');await page.locator('#hidden').check();
await page.locator('#login').check();check((await state()).cfg.login,'login preference saved');check((await page.locator('#save-status').textContent()).includes('OS unchanged'),'login simulation clear');
for(const scenario of ['denied','revoked']){await page.locator('#permission-scenario').selectOption(scenario);check((await page.locator('#permission-status').textContent()).includes('simulated'),'permission '+scenario+' explicit');}
await page.locator('button[data-pane=selection]').click();await page.locator('#alphabet').fill('ASDFGQ');await page.locator('#apply').click();await page.locator('.inventory>summary').click();
for(let i=0;i<11;i++)await page.locator('#add-window').click();
check(Object.values((await state()).engine.map).filter(Boolean).length===20,'maximum depth capacity');check((await page.locator('#held-labels').textContent()).includes('All short labels'),'capacity exhaustion explained');
await page.locator('#try').click();await page.keyboard.press('/');await page.locator('#search').fill('Reference New window 11');await page.keyboard.press('Enter');check((await page.locator('#selection-result').textContent()).includes('New window 11'),'unlabelled target searchable');
await page.setViewportSize({width:320,height:1000});check(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth),'expanded advanced at 320 fits');
await page.goto(url);await page.evaluate(()=>localStorage.removeItem('tabnax.settings-study.v1'));await page.reload();await page.setViewportSize({width:1280,height:1000});
await page.screenshot({path:'settings-exploration/output/playwright/selection-final.png',fullPage:true});
await page.locator('button[data-pane=general]').click();await page.screenshot({path:'settings-exploration/output/playwright/general-final.png',fullPage:true});
await page.locator('button[data-pane=appearance]').click();await page.locator('[name=appearance][value=dark]').check();await page.locator('button[data-theme=sage]').click();await page.screenshot({path:'settings-exploration/output/playwright/appearance-final.png',fullPage:true});
await page.locator('[name=appearance][value=system]').check();await page.locator('button[data-theme=graphite]').click();await page.locator('button[data-pane=selection]').click();
check(errors.length===0,'no runtime errors');return {passed,errors};
}
