async (page) => {
  const checks=[];
  const check=(ok,label)=>{if(!ok)throw new Error(label);checks.push(label);};
  await page.goto('http://127.0.0.1:4173/design-exploration/index.html');
  await page.setViewportSize({width:1440,height:1200});
  await page.locator('summary').click();
  for(const name of ['shore','beacons','canopy','lattice','fold','relay']){
    await page.locator(`[data-concept="${name}"]`).click();
    await page.locator('#scenario').selectOption('8');await page.locator('#reset').click();
    await page.keyboard.press('/');await page.keyboard.press('ArrowUp');
    await page.locator('#scenario').selectOption('6');
    check(await page.locator('#product-query').evaluate(el=>el===document.activeElement),name+': search focus survives target churn');
    check(await page.locator('.arrow-selected').getAttribute('data-target')==='dev',name+': result cursor clamps after shrinking');
    await page.keyboard.press('Enter');
    check(await page.evaluate(()=>tabnaxSnapshot().focused==='dev'&&!tabnaxSnapshot().active),name+': Enter works after search churn');
  }
  await page.goto(new URL('tabnax-gallery.html?concept=lattice', page.url()).href);
  check(await page.evaluate(()=>tabnaxSnapshot().concept==='lattice'&&tabnaxSnapshot().active),'standalone bundle opens with chosen concept');
  check(await page.locator('script[src],link[rel="stylesheet"]').count()===0,'standalone interaction has no external scripts or styles');
  await page.keyboard.press('l');
  check(await page.evaluate(()=>tabnaxSnapshot().focused==='preview'),'standalone keyboard selection works');
  await page.keyboard.press('Space');await page.keyboard.press('3');await page.keyboard.press('k');await page.keyboard.press('l');
  check(await page.evaluate(()=>tabnaxSnapshot().lastFocus==='tab-12'),'standalone progressive tab selection works');
  await page.locator('#reset').click();
  await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({path:'design-exploration/verification/screenshots/gallery-six-final.png',fullPage:true});
  await page.locator('#desktop').screenshot({path:'design-exploration/verification/screenshots/lattice-final.png'});
  return {passed:checks.length,checks};
}
