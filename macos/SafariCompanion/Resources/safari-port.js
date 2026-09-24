/* Safari uses request/reply native messaging; bridge it to the shared companion
 * port contract. Metadata is sent on browser events, heartbeats carry no tabs. */
globalThis.tabnaxSafariAPI = Object.create(browser);
globalThis.tabnaxSafariAPI.runtime = {
  connectNative() {
    const listeners = [], disconnected = [];
    // Native selection expires after 3 seconds. Leave room for command delivery,
    // browser activation and its result even after the extension has been idle.
    const minDelay = 750, maxDelay = 1000;
    let connection, closed = false, timer, delay = minDelay;
    async function exchange(message) {
      if (closed) return;
      connection = message.connection;
      if (message.kind !== 'hello') delay = minDelay; // real traffic resets the idle heartbeat cadence
      try {
        const response = await browser.runtime.sendNativeMessage('pl.tabnax.Tabnax',message);
        if (response?.error) throw Error(response.error);
        for (const command of response?.commands || []) for (const callback of listeners) callback(command);
      } catch (_) {
        closed = true; clearTimeout(timer); for (const callback of disconnected) callback();
      }
    }
    // Native messaging is request/reply, so this heartbeat is what keeps the
    // native host aware the extension is alive. Idle sessions back off toward
    // maxDelay without outlasting the native selection deadline; any real message (snapshot,
    // select, result) snaps the cadence back to minDelay via exchange() above.
    function heartbeat() {
      if (closed) return;
      if (connection) { exchange({version:1,kind:'hello',connection}); delay = Math.min(maxDelay, delay + minDelay); }
      timer = setTimeout(heartbeat, delay);
    }
    timer = setTimeout(heartbeat, delay);
    return {postMessage:exchange,onMessage:{addListener:f=>listeners.push(f)},onDisconnect:{addListener:f=>disconnected.push(f)}};
  }
};
