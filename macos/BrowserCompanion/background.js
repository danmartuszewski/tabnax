/* No content scripts or page access. Native host identifies the browser process. */
const api = globalThis.browser;
let port, connection = crypto.randomUUID(), pending = false, dirty = false;
let reconnectDelay = 1000, newestSelection = 0, enabled = false, snapshotDebounce;
// tabs.onUpdated fires repeatedly per page load (title/favicon/loading state), each of
// which would otherwise re-enumerate every window/tab. Coalesce bursts into one snapshot.
function scheduleSnapshot() { clearTimeout(snapshotDebounce); snapshotDebounce = setTimeout(snapshot,200); }
async function snapshot() {
  if (!port || !enabled) return;
  if (pending) { dirty = true; return; }
  pending = true;
  try {
    const windows = await api.windows.getAll({populate:true,windowTypes:['normal']});
    const tabs = windows.filter(w => w.incognito === false).flatMap(w => (w.tabs || [])
      .filter(t => t.incognito === false && Number.isInteger(t.id))
      .map(t => ({id:String(t.id),window:String(w.id),title:String(t.title || 'Untitled tab').slice(0,4096),
        active:!!t.active,focusedWindow:!!w.focused,incognito:false,pinned:!!t.pinned})));
    port.postMessage({version:1,kind:'snapshot',connection,tabs});
  } catch (_) { /* Connection loss is handled by onDisconnect. */ }
  finally { pending = false; if (dirty) { dirty = false; snapshot(); } }
}
async function select(message) {
  if (message.version !== 1 || message.connection !== connection) return;
  if (message.kind === 'cancel') { newestSelection++; return; }
  if (message.kind === 'configure') { const wasEnabled = enabled; enabled = message.enabled === true; if (!enabled) newestSelection++; else if (!wasEnabled) snapshot(); return; }
  if (message.kind !== 'select' || !enabled || typeof message.request !== 'string') return;
  const intent = ++newestSelection;
  try {
    const id = Number(message.tab);
    if (!Number.isSafeInteger(id)) throw Error('Invalid tab identity');
    const tab = await api.tabs.get(id);
    const window = await api.windows.get(tab.windowId);
    if (tab.incognito !== false || window.incognito !== false) throw Error('Private tabs are excluded');
    if (intent !== newestSelection) return;
    await api.tabs.update(id,{active:true});
    if (intent !== newestSelection) return;
    await api.windows.update(tab.windowId,{focused:true});
    const confirmed = await api.tabs.get(id), focused = await api.windows.get(confirmed.windowId);
    const selected = confirmed.active && focused.focused && !confirmed.incognito && !focused.incognito;
    if (intent === newestSelection) port?.postMessage({version:1,kind:'result',connection,request:message.request,selected});
    snapshot();
  } catch (error) {
    port?.postMessage({version:1,kind:'result',connection,request:message.request,selected:false,error:String(error.message).slice(0,300)});
  }
}
function connect() {
  try {
    port = api.runtime.connectNative('pl.tabnax.bridge');
    port.onMessage.addListener(select);
    port.onDisconnect.addListener(() => { port = null; newestSelection++; connection = crypto.randomUUID(); setTimeout(connect,reconnectDelay); reconnectDelay = Math.min(30000,reconnectDelay*2); });
    reconnectDelay = 1000; port.postMessage({version:1,kind:'hello',connection});
  } catch (_) { setTimeout(connect,3000); }
}
for (const event of [api.tabs.onCreated,api.tabs.onUpdated,api.tabs.onRemoved,api.tabs.onMoved,api.tabs.onAttached,api.tabs.onDetached,api.tabs.onActivated,api.windows.onFocusChanged,api.windows.onCreated,api.windows.onRemoved]) event.addListener(scheduleSnapshot);
connect();
