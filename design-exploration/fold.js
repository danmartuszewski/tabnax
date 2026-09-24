/* Fold is a simulated two-stage app → window interaction. */
(() => {
  'use strict';
  const extension = {
    name: 'Fold',
    kicker: '05 / FOLD',
    headline: 'One app at a time.<br>Room for the difference.',
    scan: 'Choose an app from a compact icon spine. Its window sheet unfolds beside it, giving similar titles room to separate. App address, then window address: even a single-window app takes both stages. You can type the full address without waiting for the sheet.',
    tradeoff: 'Usually two selection keys replace one; overflow adds letters. The extra step may pay off when a few apps contain many similar windows; it is a cost when most apps have only one. Fold has its own stable app + window addresses. Search crosses all families and shows complete addresses.',
    tabs: false,
    address(target, ctx) {
      if (ctx.state.scope !== 'windows') return ctx.baseAddress(target, ctx.state.scope);
      const family = ctx.windows.filter(window => window.app === target.app);
      const index = family.findIndex(window => window.id === target.id);
      if (index < 0) return ctx.baseAddress(target, 'windows');
      const alphabet = ctx.state.alphabet;
      const child = alphabet.at(-1).repeat(Math.floor(index / (alphabet.length - 1))) + alphabet[index % (alphabet.length - 1)];
      return ctx.appAddress(target.app) + child;
    },
    modeText(ctx) {
      if (ctx.state.scope === 'apps') return 'One letter to an app';
      const group = Object.keys(ctx.APPS).find(app => ctx.state.prefix.startsWith(ctx.appAddress(app)));
      return group ? 'Choose a window · full address stays visible' : 'App letter, then window letter';
    },
    render(ctx) {
      const {state, list, all, item, icon, escape, APPS} = ctx;
      if (state.mode === 'search') {
        return `<div class="fold-results"><div class="fold-section-label">ALL ${escape(state.scope.toUpperCase())} · SEARCH</div>${list.length ? list.map(item).join('') : '<div class="empty-results">No matching targets.<small>Change the search, or press Escape to return to app choices.</small></div>'}</div>`;
      }
      if (state.scope !== 'windows') {
        return `<div class="fold-results fold-app-scope"><div class="fold-section-label">DIRECT APP SELECTION</div>${list.map(item).join('')}</div>`;
      }
      const groups = Object.keys(APPS).map(app => ({app, key: ctx.appAddress(app), windows: all.filter(window => window.app === app)})).filter(group => group.windows.length);
      const selected = groups.find(group => state.prefix.startsWith(group.key));
      const familyButton = group => {
        const active = selected?.app === group.app;
        const muted = state.prefix && !selected && !group.key.startsWith(state.prefix);
        return `<button type="button" class="fold-family${active ? ' is-selected' : ''}${muted ? ' is-muted' : ''}" data-prefix="${escape(group.key)}" aria-pressed="${active}" aria-label="${escape(group.key.toUpperCase())}: choose ${escape(APPS[group.app].name)} windows">${icon(group.app)}<span class="fold-family-text"><strong>${escape(APPS[group.app].short)}</strong><small>${group.windows.length} ${group.windows.length === 1 ? 'window' : 'windows'}</small></span><kbd>${escape(group.key.toUpperCase())}</kbd><span class="fold-chevron" aria-hidden="true">›</span></button>`;
      };
      const detail = selected ? `<section class="fold-detail" aria-label="${escape(APPS[selected.app].name)} windows"><div class="fold-detail-heading"><div><span class="fold-section-label">02 / CHOOSE THE WINDOW</span><strong>${escape(APPS[selected.app].name)}</strong></div><button type="button" class="fold-back" data-clear-prefix aria-label="Back to all applications">← All apps</button></div><div class="fold-window-list">${selected.windows.map(item).join('')}</div><p class="fold-detail-note"><kbd>${escape(selected.key.toUpperCase())}</kbd> is already typed. Press the remaining letter.</p></section>` : '';
      return `<div class="fold-layout ${selected ? 'is-branch' : 'is-root'}"><section class="fold-spine" aria-label="Application families"><div class="fold-section-label">01 / CHOOSE THE APP</div>${groups.map(familyButton).join('')}<p class="fold-spine-note">${selected ? '⌫ back to apps' : 'Every window has a two-stage address.'}</p></section>${detail}</div>`;
    }
  };
  window.TabnaxExtensions = window.TabnaxExtensions || {};
  window.TabnaxExtensions.fold = extension;
})();
