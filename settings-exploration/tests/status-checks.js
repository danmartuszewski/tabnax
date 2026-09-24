async page => {
  await page.reload();
  await page.locator('#hand').selectOption('left');
  if (await page.locator('#save-status').textContent() !== 'Label changes not applied') throw Error('draft status');
  await page.locator('button[data-pane=appearance]').click();
  if (await page.locator('#save-status').textContent() !== 'Label changes not applied') throw Error('draft status across panes');
  await page.locator('button[data-pane=selection]').click();
  await page.locator('#discard').click();
  if (await page.locator('#save-status').textContent() !== 'Saved on this device') throw Error('discard status');
  return {passed: 3};
}
