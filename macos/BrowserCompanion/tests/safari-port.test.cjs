const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function run() {
  let elapsed = 0, nextID = 0, pendingCommand, reject = false;
  const timers = new Map(), messages = [], delivered = [];
  const context = vm.createContext({
    browser: {runtime: {sendNativeMessage: async (host, message) => {
      assert.equal(host, 'pl.tabnax.Tabnax');
      messages.push({...message, at:elapsed});
      if (reject) throw Error('Disconnected');
      const commands = pendingCommand ? [pendingCommand] : [];
      pendingCommand = undefined;
      return {commands};
    }}},
    setTimeout: (callback, delay) => { const id = ++nextID; timers.set(id, {callback, at:elapsed + delay}); return id; },
    clearTimeout: id => timers.delete(id)
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../../SafariCompanion/Resources/safari-port.js'), 'utf8'), context);
  const port = context.tabnaxSafariAPI.runtime.connectNative();
  port.onMessage.addListener(command => delivered.push(command));
  let disconnected = 0; port.onDisconnect.addListener(() => disconnected++);
  await port.postMessage({version:1, kind:'hello', connection:'test-connection'});
  async function tick() {
    const [id, timer] = [...timers].sort((a,b) => a[1].at - b[1].at)[0];
    timers.delete(id); elapsed = timer.at; timer.callback();
    await new Promise(resolve => setImmediate(resolve));
  }
  for (let i = 0; i < 15; i++) await tick();
  const requestedAt = elapsed;
  pendingCommand = {version:1, kind:'select', connection:'test-connection', request:'after-idle', tab:'7'};
  await tick();
  assert.equal(delivered.length, 1);
  assert.equal(delivered[0].request, 'after-idle');
  assert(elapsed - requestedAt <= 1000, 'Idle heartbeat must deliver selection before the native 3-second deadline');
  await port.postMessage({version:1, kind:'result', connection:'test-connection', request:'after-idle', selected:true});
  assert.equal(messages.at(-1).kind, 'result');
  assert(messages.filter(m => m.kind === 'hello').every(m => !('tabs' in m)), 'Heartbeats do not enumerate tabs');
  reject = true; await tick();
  assert.equal(disconnected, 1); assert.equal(timers.size, 0);
  console.log('Safari transport passed: idle selection delivery, immediate results, metadata-free heartbeats, disconnect cleanup.');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
