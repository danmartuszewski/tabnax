/* Lattice is a visual extension. All selection/focus remains in the shared simulator. */
(() => {
  'use strict';

  function inventoryTarget(t, ctx) {
    const key = ctx.address(t);
    return `<button type="button" class="lattice-inventory-target" data-target="${ctx.escape(t.id)}" data-address="${ctx.escape(key)}" title="${ctx.escape(t.full || t.title)}" aria-label="${key.toUpperCase()}: ${ctx.escape(t.full || t.title)}. ${ctx.escape(t.context)}"><kbd aria-hidden="true">${key.toUpperCase()}</kbd><span>${ctx.escape(t.title)}</span></button>`;
  }

  function emptyCell(key, known, ctx) {
    return `<div class="lattice-cell lattice-empty${known ? ' lattice-retired' : ''}" aria-label="${key.toUpperCase()}: ${known ? 'unavailable address' : 'unassigned address'}"><span class="lattice-empty-key">${ctx.escape(key.toUpperCase())}</span><span>${known ? 'Address held' : 'Unassigned'}<small>${known ? 'Other places stay put' : 'Ready for a new target'}</small></span></div>`;
  }

  function addressGrid(ctx) {
    const {state, all, escape} = ctx;
    const map = state.addresses[state.scope];
    const prefix = state.prefix;
    const allocated = [...map.values()];
    return `<div class="lattice-field" style="--lattice-columns:${state.alphabet.length <= 9 ? 3 : state.alphabet.length <= 10 ? 5 : 4}">${[...state.alphabet].map(letter => {
      const key = prefix + letter;
      const target = all.find(t => ctx.address(t) === key);
      if (target) {
        const windowRecord = state.scope === 'windows' ? target : ctx.windows.find(w => w.id === (target.parent || target.windowId));
        return `<div class="lattice-cell${windowRecord?.minimized ? ' lattice-minimized' : ''}">${ctx.item(target)}${windowRecord?.minimized ? '<span class="lattice-window-status">MINIMIZED · STILL HERE</span>' : ''}</div>`;
      }
      const descendants = all.filter(t => ctx.address(t).startsWith(key) && ctx.address(t).length > key.length);
      const isWindowBranch = state.scope !== 'tabs' && letter === state.alphabet.at(-1);
      if (descendants.length || isWindowBranch) {
        return `<button type="button" class="lattice-cell lattice-branch" data-prefix="${escape(key)}" ${descendants.length ? '' : 'disabled'} aria-label="${key.toUpperCase()}: ${descendants.length ? `show ${descendants.length} more ${state.scope}` : 'reserved overflow branch'}"><span class="lattice-branch-top"><kbd aria-hidden="true">${escape(key.toUpperCase())}</kbd><span aria-hidden="true">↗</span></span><strong>${descendants.length ? `${descendants.length} more ${state.scope}` : 'Room to grow'}</strong><span>${descendants.length ? descendants.slice(0, 2).map(t => escape(t.title)).join('<br>') : 'Reserved for overflow.<br>Your other addresses stay put.'}</span></button>`;
      }
      return emptyCell(key, allocated.includes(key), ctx);
    }).join('')}</div>`;
  }

  function tabOverview(ctx) {
    const {state, all, escape} = ctx;
    const allocated = [...state.addresses.tabs.values()];
    const prefixes = [...state.alphabet].filter(letter => allocated.some(key => key.startsWith(letter)));
    return `<div class="lattice-tab-overview" style="--lattice-tab-columns:${Math.min(prefixes.length, 5)}">${prefixes.map(prefix => {
      const targets = all.filter(t => ctx.address(t).startsWith(prefix));
      const parents = [...new Set(targets.map(t => t.parent))];
      const context = parents.map(id => ({lesson:'Lesson editor',preview:'Learner preview',personal:'Personal'})[id] || id).join(' / ');
      return `<section class="lattice-tab-group"><button type="button" class="lattice-tab-entry" data-prefix="${escape(prefix)}" ${targets.length ? '' : 'disabled'} aria-label="${prefix.toUpperCase()}: narrow to ${targets.length} tabs"><kbd aria-hidden="true">${escape(prefix.toUpperCase())}</kbd><span><strong>${targets.length} tabs</strong><small>${escape(context || 'Parent windows closed')}</small></span><span class="lattice-branch-arrow" aria-hidden="true">↗</span></button><div class="lattice-inventory">${targets.length ? targets.map(t => inventoryTarget(t, ctx)).join('') : '<p class="lattice-unavailable">This place is held.<br>Its windows are currently closed.</p>'}</div></section>`;
    }).join('')}</div>`;
  }

  function render(ctx) {
    const {state, list, escape} = ctx;
    if (state.mode === 'search') {
      return `<div class="lattice-search-results">${list.length ? list.map(ctx.item).join('') : '<div class="empty-results">No matching targets.<small>Change the search, or press Escape for the address grid.</small></div>'}</div>`;
    }
    const rootTabs = state.scope === 'tabs' && !state.prefix;
    return `<div class="lattice-guide"><span>${state.prefix ? `<button type="button" data-clear-prefix class="lattice-breadcrumb">All ${escape(state.scope)}</button><span class="lattice-guide-divider">/</span><strong>${escape(state.prefix.toUpperCase())}</strong><span class="lattice-guide-next">Choose the next letter</span>` : rootTabs ? '<strong>One letter narrows. The next lands.</strong>' : '<strong>Every window gets a place.</strong>'}</span><span>${rootTabs ? 'Full addresses stay visible' : state.prefix ? '⌫ back' : 'Positions follow addresses'}</span></div>${rootTabs ? tabOverview(ctx) : addressGrid(ctx)}`;
  }

  window.TabnaxExtensions = window.TabnaxExtensions || {};
  window.TabnaxExtensions.lattice = {
    name:'Lattice',
    kicker:'04 / LATTICE',
    headline:'A field of windows.<br>A place you can learn.',
    scan:'Every window occupies a fixed address cell, including covered and minimized windows. Press one letter to land; only overflow and optional tabs narrow into another grid. Closed windows leave holes, so the places you learn stay put.',
    tradeoff:'The screen-wide scan can be slower than a short list. Grid positions follow your alphabet order, not physical keyboard geometry. Tab prefixes are arbitrary address groups; search may be faster when you do not know a tab’s address.',
    tabs:true,
    modeText:ctx => ctx.state.scope === 'tabs' ? (ctx.state.prefix ? 'Next letter goes immediately' : 'Type two letters, or narrow with the first') : ctx.state.prefix ? 'Next letter goes immediately' : 'One letter per window · overflow opens a grid',
    render
  };
})();
