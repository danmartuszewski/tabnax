async (page)=>{
 let passed=0;const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const base='http://127.0.0.1:4174/settings-exploration/';
 const check=(value,name)=>{if(!value)throw new Error(name);passed++;};
 const inspect=()=>page.evaluate(()=>window.TabnaxStudy.inspect());
 const pane=name=>page.locator('button[data-pane="'+name+'"]').click();
 const detail=async selector=>{if(!await page.locator(selector).evaluate(e=>e.open))await page.locator(selector+'>summary').click();};
 const shot=name=>page.screenshot({path:'settings-exploration/output/playwright/'+name+'.png',fullPage:true});
 const color=async(id,value)=>{await page.locator(id).focus();await page.locator(id).fill(value);await page.locator(id).blur();};
 await page.setViewportSize({width:1280,height:1080});await page.goto(base+'tabnax-settings.html');
 await page.evaluate(()=>localStorage.removeItem('tabnax.settings-study.v1'));await page.reload();
 check(await page.locator('.toolbar button').count()===5,'five settings panes');
 const original=(await inspect()).engine.map;
 await pane('appearance');await page.locator('[name=appearance][value=light]').check();
 for(const mode of ['light','dark'])for(const theme of ['graphite','tabnax','sage','iris']){
  await page.locator('[name=appearance][value='+mode+']').check();await page.locator('button[data-theme='+theme+']').click();
  check((await inspect()).cfg.theme===theme&&await page.locator('button[data-theme='+theme+']').getAttribute('aria-pressed')==='true',theme+' '+mode+' selected');
 }
 check(JSON.stringify((await inspect()).engine.map)===JSON.stringify(original),'all themes preserve labels');
 await page.locator('button[data-theme=tabnax]').click();await detail('#customize-theme');
 check(await page.locator('#custom-key-color').inputValue()==='#d9f68c','original green in native picker');
 await color('#custom-key-color','#181818');await color('#custom-selection-color','#202720');
 check((await inspect()).cfg.themeOverrides.tabnax.dark.keyBg==='#181818','dark custom badge saved');
 check((await page.locator('#theme-contrast').textContent()).includes('adjusted'),'invisible selection shade explained');
 check(await page.locator('body').evaluate(e=>e.style.getPropertyValue('--keyFg'))==='#ffffff','dark badge gets readable white letters');
 await page.locator('[name=appearance][value=light]').check();
 check(await page.locator('#custom-key-color').inputValue()==='#d9f68c','dark customization does not alter light');
 await color('#custom-key-color','#fcad38');
 await page.locator('button[data-theme=graphite]').click();check(await page.locator('#custom-key-color').inputValue()==='#e5e7e9','other presets stay independent');
 await color('#custom-key-color','#123456');await page.locator('button[data-theme=tabnax]').click();
 check(await page.locator('#custom-key-color').inputValue()==='#fcad38','return to preset restores custom color');
 await page.reload();await detail('#customize-theme');
 check((await inspect()).cfg.themeOverrides.tabnax.dark.keyBg==='#181818'&&await page.locator('#custom-key-color').inputValue()==='#fcad38','both appearances survive reload');
 await page.locator('#reset-theme').click();check(!(await inspect()).cfg.themeOverrides.tabnax,'reset clears both appearances of selected preset');
 check((await inspect()).cfg.themeOverrides.graphite.light.keyBg==='#123456','reset preserves other presets');
 await page.locator('#undo').click();check((await inspect()).cfg.themeOverrides.tabnax.light.keyBg==='#fcad38','theme reset is undoable');
 await page.locator('#reset-theme').click();await page.locator('[name=appearance][value=dark]').check();await shot('themes-tabnax');
 await page.locator('button[data-theme=graphite]').click();await page.locator('#reset-theme').click();await page.locator('[name=appearance][value=light]').check();await shot('themes-macos');
 await pane('position');
 for(const anchor of ['top-left','top-center','top-right','middle-left','middle-center','middle-right','bottom-left','bottom-center','bottom-right']){
  await page.locator('[data-anchor='+anchor+']').click();
  check((await inspect()).cfg.position.anchor===anchor,'anchor saves '+anchor);
  check(await page.evaluate(()=>{const a=document.querySelector('#position-desktop').getBoundingClientRect(),b=document.querySelector('#position-mini-switcher').getBoundingClientRect();return b.left>=a.left&&b.right<=a.right&&b.top>=a.top+20&&b.bottom<=a.bottom-20;}),'anchor stays within usable sample '+anchor);
 }
 await page.locator('#position-display').selectOption('main');await page.locator('#position-inset').fill('64');
 check((await inspect()).cfg.position.inset===64,'edge spacing saved');
 await page.locator('#position-display').selectOption('pointer');check((await page.locator('#position-caption').textContent()).includes('Main'),'pointer display preview');
 await page.locator('#position-display').selectOption('focused');check((await page.locator('#position-caption').textContent()).includes('External'),'focused display preview');
 await page.reload();check((await inspect()).cfg.position.anchor==='bottom-right'&&(await inspect()).cfg.position.inset===64,'placement persisted');await shot('position');
 await page.locator('#position-reset').click();check((await inspect()).cfg.position.anchor==='middle-right'&&(await inspect()).cfg.position.inset===24,'position resets');
 await page.locator('#undo').click();check((await inspect()).cfg.position.anchor==='bottom-right','position reset undo');
 await pane('tabs');await page.locator('#preview-tabs').click();
 check((await inspect()).harness.dataset==='tabs'&&await page.locator('.target').count()===48,'product tabs control opens all samples');
 let tabs=(await inspect()).engine.map;
 await page.keyboard.press('k');check((await inspect()).prefix==='K','tab prefix captured');
 await page.keyboard.press('1');check((await inspect()).harness.dataset==='8'&&(await inspect()).prefix===''&&(await inspect()).active,'1 switches scope and clears prefix');
 check(JSON.stringify((await inspect()).engine.map)===JSON.stringify(original),'window labels preserved');
 await page.keyboard.press('2');check(JSON.stringify((await inspect()).engine.map)===JSON.stringify(tabs),'2 restores same tab labels');
 await page.keyboard.press('Escape');await page.locator('#tabs-range').selectOption('browser');check(await page.locator('.target').count()===4,'active browser range');
 await page.locator('#tabs-range').selectOption('window');check(await page.locator('.target').count()===2,'active browser window range');
 check(JSON.stringify((await inspect()).engine.map)===JSON.stringify(tabs),'range filtering reserves excluded labels');
 await page.locator('#tabs-range').selectOption('all');await detail('.inventory');
 await page.locator('[data-remove="tab-1"]').click();await page.locator('#add-window').click();
 check((await inspect()).engine.retired.includes('JK')&&(await inspect()).engine.map['new-1']!=='JK','tab closure retains retired label');
 tabs=(await inspect()).engine;
 await page.locator('#scope-windows').click();await pane('selection');await page.locator('#policy').selectOption('mnemonic');await page.locator('#apply').click();
 check(JSON.stringify((await inspect()).otherCatalogue.engine)===JSON.stringify(tabs),'window policy preserves entire tab session');
 await page.locator('#hand').selectOption('left');await pane('tabs');await page.locator('#scope-tabs').click();
 check((await inspect()).harness.dataset!=='tabs','pending label draft blocks scope switch');
 await page.locator('#default-scope').selectOption('tabs');check((await inspect()).cfg.browserTabs.defaultScope==='windows','pending draft blocks default scope change');
 await pane('selection');await page.locator('#apply').click();await pane('tabs');
 check((await inspect()).otherCatalogue.engine.selection.alphabet==='ASDFWERCGQ','alphabet applied to inactive tab namespace');
 await page.locator('#scope-tabs').click();check(Object.values((await inspect()).engine.map).every(x=>x.length===2&&/^[ASDFWERCGQ]+$/.test(x)),'tab labels use shared alphabet and pairs');
 await page.locator('#tabs-enabled').uncheck();check((await inspect()).harness.dataset!=='tabs'&&await page.locator('#scope-tabs').isDisabled(),'disabling tabs returns to windows');
 await page.locator('#undo').click();check((await inspect()).cfg.browserTabs.enabled&&(await inspect()).harness.dataset==='tabs','disabling tabs undo restores view');
 await page.locator('#default-scope').selectOption('tabs');await page.reload();
 check((await inspect()).cfg.browserTabs.defaultScope==='tabs'&&(await inspect()).harness.dataset==='tabs','default view opens after reload');
 check((await page.locator('.browser-connection').first().textContent()).includes('sample tabs only'),'connection state honest');
 await page.locator('[data-browser-info=Safari]').click();check((await page.locator('#dialog-copy').textContent()).includes('cannot inspect your browser'),'adapter limitation disclosed');await page.locator('#dialog-confirm').click();
 await pane('appearance');await page.locator('[name=appearance][value=dark]').check();await page.locator('button[data-theme=tabnax]').click();await pane('tabs');await shot('browser-tabs');
 for(const width of [1280,620,390,320]){
  await page.setViewportSize({width,height:1080});
  for(const name of ['general','selection','position','appearance','tabs']){await pane(name);if(name==='appearance')await detail('#customize-theme');check(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth),name+' reflows at '+width);}
 }
 await pane('appearance');await shot('themes-compact');
 await page.setViewportSize({width:860,height:720});await page.evaluate(()=>document.body.style.zoom='2');
 check(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth),'expanded appearance reflows at 200 percent');
 await page.evaluate(()=>document.body.style.zoom='1');await page.setViewportSize({width:1280,height:1080});
 // Existing v1 preferences predate these additions: preserve old choices and merge new defaults.
 await page.evaluate(()=>{const old=JSON.parse(localStorage.getItem('tabnax.settings-study.v1'));delete old.config.position;delete old.config.browserTabs;delete old.config.themeOverrides;old.config.theme='sage';localStorage.setItem('tabnax.settings-study.v1',JSON.stringify(old));});await page.reload();
 check((await inspect()).cfg.theme==='sage'&&(await inspect()).cfg.position.anchor==='middle-right'&&(await inspect()).cfg.browserTabs.enabled,'old preferences gain defaults without losing theme');
 check(errors.length===0,'no JavaScript errors: '+errors.join(';'));
 await page.locator('#restore').click();await page.locator('#dialog-confirm').click();await page.waitForFunction(()=>window.TabnaxStudy.inspect().cfg.theme==='graphite');await pane('appearance');
 return {passed,errors};
}
