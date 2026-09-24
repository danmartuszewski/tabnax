async page=>{
 let passed=0;const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const check=(value,name)=>{if(!value)throw Error(name);passed++;};
 const state=()=>page.evaluate(()=>TabnaxStudy.inspect());
 await page.goto('http://127.0.0.1:4174/settings-exploration/tabnax-settings.html');await page.evaluate(()=>localStorage.removeItem('tabnax.settings-study.v1'));await page.reload();await page.setViewportSize({width:1280,height:1200});
 await page.locator('button[data-pane=tabs]').click();await page.locator('#preview-tabs').click();
 check(await page.locator('.target').count()===48,'all seven browsers supply sample tabs');
 check((await page.locator('.target').first().getAttribute('aria-label')).startsWith('Arc:'),'Arc appears first');
 check(await page.locator('.browser-connection').count()===7,'seven browser choices');
 check(await page.locator('#browser-arc').isChecked()&&await page.locator('#browser-arc').isDisabled(),'automatic mode includes Arc without configuring list');
 const labels=(await state()).engine.map,windowLabels=(await state()).otherCatalogue.engine.map;
 await page.locator('#browser-selection').selectOption('selected');await page.locator('#more-browsers>summary').click();
 for(const browser of ['safari','chrome','firefox','edge','brave'])await page.locator('#browser-'+browser).uncheck();
 check(await page.locator('.target').count()===8,'Arc and Zen only');
 check(JSON.stringify((await state()).cfg.browserTabs.selectedBrowsers)===JSON.stringify(['arc','zen']),'selection stores browser IDs');
 check((await page.locator('#browser-selection-status').textContent()).includes('2 browsers'),'selected count visible');
 check(JSON.stringify((await state()).engine.map)===JSON.stringify(labels),'excluding browsers retains all labels');
 await page.locator('#try').click();await page.keyboard.press('/');await page.locator('#search').fill('zen planning');
 check(await page.locator('.target').count()===1,'Zen titles searchable');await page.keyboard.press('Enter');
 check((await page.locator('#selection-result').textContent()).includes('Selected Zen'),'Zen sample selects exact tab');
 await page.locator('#try').click();const arcLabel=(await state()).engine.map['arc-tab-0'];await page.keyboard.type(arcLabel.toLowerCase());
 check((await page.locator('#selection-result').textContent()).includes('Selected Arc'),'Arc pair label selects exact tab');
 await page.locator('#tabs-range').selectOption('browser');check(await page.locator('.target').count()===4,'active browser defaults to Arc');
 await page.locator('#tabs-range').selectOption('window');check(await page.locator('.target').count()===2,'Arc work window filter');
 await page.locator('.test-controls>summary').click();await page.locator('#active-browser').selectOption('zen');
 check(await page.locator('.target').count()===2&&(await page.locator('.target').first().getAttribute('aria-label')).startsWith('Zen:'),'Zen active window filter');
 await page.locator('#active-browser').selectOption('safari');check(await page.locator('.target').count()===0,'excluded active browser never falls back to another browser');
 check((await page.locator('#targets').textContent()).includes('No included tabs'),'empty filter is explained');
 await page.locator('#tabs-range').selectOption('all');await page.locator('#browser-selection').selectOption('automatic');check(await page.locator('.target').count()===48,'automatic includes every sample again');
 await page.locator('#browser-selection').selectOption('selected');check(await page.locator('.target').count()===8,'manual subset survives automatic mode');
 await page.reload();await page.locator('#scope-tabs').click();
 check(await page.locator('.target').count()===8&&(await state()).cfg.browserTabs.selection==='selected','browser subset persists');
 check((await state()).harness.activeBrowser==='arc','sample active browser is not a preference');
 await page.locator('#browser-arc').uncheck();await page.locator('#browser-zen').uncheck();check(await page.locator('.target').count()===0&&(await page.locator('#browser-selection-status').textContent()).includes('No browsers'),'zero selection shows empty state');
 await page.locator('#undo').click();check(await page.locator('.target').count()===4&&await page.locator('#browser-zen').isChecked(),'Undo restores browser eligibility');
 await page.locator('#browser-arc').check();await page.locator('#tabs-enabled').uncheck();
 check(await page.locator('#browser-selection').isDisabled()&&await page.locator('#browser-arc').isDisabled(),'global off disables browser selection controls');
 await page.locator('#tabs-enabled').check();await page.locator('#scope-tabs').click();check(await page.locator('.target').count()===8,'re-enabling keeps chosen browsers');
 for(const [browser,copy] of [['Arc','built in'],['Zen','companion add-on'],['Safari','simplest supported connection']]){
  await page.locator('[data-browser-info='+browser+']').click();check((await page.locator('#dialog-copy').textContent()).includes(copy),browser+' setup guidance');check((await page.locator('#dialog-copy').textContent()).includes('cannot inspect your browser'),browser+' simulation explicit');await page.locator('#dialog-confirm').click();
 }
 check(JSON.stringify((await state()).engine.map)===JSON.stringify(labels)&&JSON.stringify((await state()).otherCatalogue.engine.map)===JSON.stringify(windowLabels),'scope choices preserve both maps');
 await page.locator('button[data-pane=appearance]').click();await page.locator('[name=appearance][value=dark]').check();await page.locator('button[data-theme=tabnax]').click();await page.locator('button[data-pane=tabs]').click();
 await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));await page.screenshot({path:'settings-exploration/output/playwright/browser-arc-zen.png',fullPage:true});
 for(const width of [620,390,320]){await page.setViewportSize({width,height:1100});if(!await page.locator('#more-browsers').evaluate(e=>e.open))await page.locator('#more-browsers>summary').click();check(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth),'expanded browsers fit '+width);}
 await page.screenshot({path:'settings-exploration/output/playwright/browser-choices-compact.png',fullPage:true});
 await page.setViewportSize({width:1280,height:1200});
 await page.evaluate(()=>{const old=JSON.parse(localStorage.getItem('tabnax.settings-study.v1'));delete old.config.browserTabs.selection;delete old.config.browserTabs.selectedBrowsers;localStorage.setItem('tabnax.settings-study.v1',JSON.stringify(old));});await page.reload();
 check((await state()).cfg.browserTabs.selection==='automatic'&&(await state()).cfg.browserTabs.selectedBrowsers.length===7,'old browser preferences gain discovery defaults');
 check(errors.length===0,'no page errors: '+errors.join(';'));
 return {passed,errors};
}
