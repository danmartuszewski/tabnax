/* Relay is a simulated return-to-previous-window study, not native integration. */
(() => {
  'use strict';
  const registry = window.TabnaxExtensions = window.TabnaxExtensions || {};

  registry.relay = {
    name: 'Relay',
    kicker: '06 / RELAY',
    headline: 'Keep the conversation<br>between two windows.',
    scan: 'Your current window and the window you just left form a visible pair near the current work. Enter returns to the previous window; its normal letter still works. Every other window stays available below with the same stable address.',
    tradeoff: 'Useful for editor–preview or terminal–editor alternation. The large return target spends attention on one prediction, so a less recent window can take longer to find. Enter means “previous window”; it is a changing command, never a stable target address.',
    tabs: false,
    modeText(ctx) {
      if (ctx.state.scope !== 'windows') return 'Type a letter to go';
      return ctx.recentWindow ? 'Enter returns · letters go anywhere' : 'Choose a window to start a return pair';
    },
    render(ctx) {
      const { state, list, all, item, icon, escape, APPS, address, windows } = ctx;
      if (state.mode === 'search' || state.scope !== 'windows') {
        return `<div class="relay-index"><div class="relay-index-label">${state.mode === 'search' ? 'MATCHING TARGETS · ENTER SELECTS THE HIGHLIGHTED RESULT' : 'OPEN APPS · DIRECT ADDRESSES'}</div><div class="relay-index-targets">${list.length ? list.map(item).join('') : '<div class="empty-results">No matching targets.<small>Change the search, or press Escape to return to letters.</small></div>'}</div></div>`;
      }

      const current = all.find(target => target.id === state.focused);
      const previous = ctx.recentWindow && all.find(target => target.id === ctx.recentWindow.id && target.id !== state.focused);
      const rest = list.filter(target => target.id !== current?.id && target.id !== previous?.id);
      const focusedWindow = windows.find(target => target.id === state.focused);
      const anchorX = Number.isFinite(focusedWindow?.x) ? focusedWindow.x : 29;
      const anchorY = Number.isFinite(focusedWindow?.y) ? focusedWindow.y : 37;
      const currentMarkup = current ? `${icon(current.app)}<span class="relay-current-text"><small>YOU ARE HERE</small><strong>${escape(current.title)}</strong><span>${escape(APPS[current.app].short)} <span class="relay-current-address">${escape(address(current).toUpperCase())}</span></span></span>` : '<span class="relay-current-text"><small>YOUR CURRENT WORK</small></span>';
      const returnMarkup = previous
        ? `<div class="relay-return-label"><span>BACK TO</span><span>PREVIOUS WINDOW</span></div><div class="relay-return-target">${item(previous)}</div><button type="button" class="relay-return-action" data-return-window="true" aria-label="Return to ${escape(previous.title)}"><span>Return here</span><kbd>Enter ↵</kbd></button>`
        : '<div class="relay-return-label"><span>YOUR NEXT RETURN</span></div><div class="relay-empty-pair"><strong>Start with any letter below.</strong><p>The window you leave will appear here. Enter brings it back.</p></div>';

      return `<div class="relay-content"><div class="relay-pair" style="--relay-x:${anchorX}%;--relay-y:${anchorY}%"><div class="relay-current">${currentMarkup}</div><span class="relay-thread" aria-hidden="true"><i></i>↗</span><section class="relay-return${previous ? '' : ' relay-return-empty'}" aria-label="Previous window">${returnMarkup}</section></div><section class="relay-shelf" aria-label="All other open windows"><div class="relay-shelf-label"><span>ANYWHERE ELSE</span><span>${rest.length} WINDOWS · SAME LETTERS</span></div><div class="relay-shelf-targets">${rest.length ? rest.map(item).join('') : '<p class="relay-shelf-empty">These are your only open windows.</p>'}</div></section></div>`;
    }
  };
})();
