/*
 * Tabnax homepage playground. This is a deliberately bounded browser simulation:
 * no system APIs, permission prompts, analytics, network calls, or native preferences.
 * Update MODE_INFO, TARGETS and PANE_INFO to keep the site in sync with the app.
 */
(() => {
  "use strict";

  const $ = (selector, parent = document) => parent.querySelector(selector);
  const $$ = (selector, parent = document) => [
    ...parent.querySelectorAll(selector),
  ];
  const escapeHTML = (value) =>
    String(value).replace(
      /[&<>"']/g,
      (character) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[character],
    );

  const MODE_INFO = {
    shore: [
      "01",
      "A quiet edge. One clear scan.",
      "All your destinations in a compact list. A familiar letter for every window, tab and app.",
    ],
    beacons: [
      "02",
      "Your desktop becomes the map.",
      "Letters sit beside visible windows. Minimized windows, tabs and apps wait in a compact bank. On small screens, plaques stack.",
    ],
    canopy: [
      "03",
      "Think app. Find your window.",
      "A column for each app, with its windows and tabs underneath. Type the full address; single-destination apps need just one letter.",
    ],
    lattice: [
      "04",
      "A place your fingers remember.",
      "Stable addresses in a spatial grid. Your destinations keep their places while you move between them.",
    ],
    fold: [
      "05",
      "One app. A little unfolding.",
      "Choose an app to unfold its windows and tabs, then type a child letter. Single-destination apps open directly.",
    ],
    relay: [
      "06",
      "Back and forth. Without the friction.",
      "Your current and previous windows, side by side. Enter takes you back; a direct-address shelf keeps everything else close.",
    ],
  };
  const APPS = {
    xcode: { name: "Xcode", key: "X" },
    safari: { name: "Safari", key: "S" },
    finder: { name: "Finder", key: "D" },
    notes: { name: "Notes", key: "N" },
    arc: { name: "Arc", key: "A" },
    figma: { name: "Figma", key: "F" },
  };
  const TARGETS = [
    {
      id: "code",
      app: "xcode",
      title: "Tabnax · InputRouter.swift",
      type: "window",
      key: "J",
      groupKey: "X",
    },
    {
      id: "lesson",
      app: "safari",
      title: "Tabnax · Keyboard guide",
      type: "window",
      key: "K",
      groupKey: "SJ",
    },
    {
      id: "assets",
      app: "finder",
      title: "Brand assets",
      type: "window",
      key: "L",
      groupKey: "D",
    },
    {
      id: "ideas",
      app: "notes",
      title: "A few good ideas",
      type: "window",
      key: "U",
      groupKey: "N",
      minimized: true,
    },
    {
      id: "docs",
      app: "safari",
      title: "Designing for macOS",
      type: "tab",
      key: "I",
      groupKey: "SK",
      context: "developer.apple.com",
    },
    {
      id: "research",
      app: "arc",
      title: "A calmer workspace",
      type: "tab",
      key: "O",
      groupKey: "A",
      context: "Design references",
    },
    {
      id: "safari-app",
      app: "safari",
      title: "Safari",
      type: "app",
      key: "S",
      groupKey: "S",
    },
    {
      id: "figma-app",
      app: "figma",
      title: "Figma",
      type: "launch",
      key: "F",
      groupKey: "F",
    },
  ];
  const PANE_INFO = {
    general: [
      "The right shortcut is yours.",
      "Record your shortcut, choose press or hold, set mouse behavior, and manage Accessibility and launch at login.",
    ],
    letters: [
      "Make a little muscle memory.",
      "Choose a hand preset, reorder your alphabet, and preview stable letters, initials or pairs. Apply or discard letter changes together.",
    ],
    apps: [
      "Your favorites, a letter away.",
      "Reserve persistent app letters and optionally launch assigned apps when they are closed. Saved assignments follow the app across relaunches.",
    ],
    position: [
      "Right where you want it.",
      "Choose a display and remember a different anchor and inset for each layout. The placement illustration updates as you adjust.",
    ],
    appearance: [
      "Make it feel like you.",
      "Six themes, light and dark appearances, readable labels, and per-theme colors. Native glass where your macOS version supports it.",
    ],
    browsers: [
      "Bring your tabs along.",
      "Choose your browsers and tab range. Connection setup explains each browser’s Automation or extension approval. Private tabs stay excluded.",
    ],
  };
  const ICONS = {
    xcode:
      '<rect width="32" height="32" rx="7" fill="#39a8f0"/><path d="m9 23 12-15 3 2-12 15z" fill="#cbddec"/><path d="m16 6 3-2 9 7-3 4-3-3-4 1-4-4z" fill="#e8f6fe"/><path d="m9 23 2-3 3 3-2 3z" fill="#436a97"/>',
    safari:
      '<rect width="32" height="32" rx="7" fill="#eaf4f7"/><circle cx="16" cy="16" r="13" fill="#42a7ee"/><circle cx="16" cy="16" r="10" fill="none" stroke="#b2ecff" stroke-width="1" stroke-dasharray="1 3"/><path d="m22 8-3 11-6-6z" fill="#f78b80"/><path d="m10 24 3-11 6 6z" fill="#fff"/>',
    finder:
      '<rect width="32" height="32" rx="7" fill="#72d4fa"/><path d="M16 1h9a7 7 0 0 1 7 7v17a7 7 0 0 1-7 7H17l-2-10h-4z" fill="#d6f3fc"/><path d="M10 10v3m13-3v3M7 20q9 7 18-1M17 3l-5 14h6l1 14" fill="none" stroke="#356b8b" stroke-width="1.1" stroke-linecap="round"/>',
    notes:
      '<rect width="32" height="32" rx="7" fill="#f7f5e9"/><path d="M0 9V7a7 7 0 0 1 7-7h18a7 7 0 0 1 7 7v2z" fill="#f5d465"/><path d="M5 15h22M5 20h22M5 25h16" stroke="#d5d8cf" stroke-width="1"/>',
    arc: '<rect width="32" height="32" rx="7" fill="#edb7b0"/><path d="m7 24 8-17h3l8 17M11 18q8-3 13 2" stroke="#fbf1d9" stroke-width="3.4" stroke-linejoin="round" fill="none"/><path d="m7 24 8-17h3l8 17M11 18q8-3 13 2" stroke="#6373b6" stroke-width="1.7" stroke-linejoin="round" fill="none"/>',
    figma:
      '<rect width="32" height="32" rx="7" fill="#f4f3ee"/><path d="M16 5h-5a4 4 0 0 0 0 8h5z" fill="#e86d52"/><path d="M16 5h5a4 4 0 0 1 0 8h-5z" fill="#ed9c8f"/><path d="M16 13h-5a4 4 0 0 0 0 8h5z" fill="#a48adc"/><circle cx="20" cy="17" r="4" fill="#68bceb"/><path d="M16 21h-5a4 4 0 1 0 5 4z" fill="#70be9b"/>',
  };

  const desktop = $("#desktop");
  const switcher = $("#switcher");
  const state = {
    mode: "shore",
    theme: "tabnax",
    tone: "dark",
    open: true,
    tabs: true,
    apps: true,
    search: false,
    query: "",
    prefix: "",
    family: null,
    highlight: "lesson",
    current: "code",
    previous: "lesson",
    restorePrompt: false,
    restored: new Set(),
    launched: new Set(),
  };
  let nativePane = "appearance";
  let nativeTone = "light";
  let navigables = [];

  function icon(app, minimized = false) {
    return `<span class="app-icon" aria-hidden="true"><svg viewBox="0 0 32 32" focusable="false">${ICONS[app]}</svg>${minimized ? '<span class="minimized-badge">−</span>' : ""}</span>`;
  }
  function isGrouped() {
    return state.mode === "canopy" || state.mode === "fold";
  }
  function isMinimized(target) {
    return target.minimized && !state.restored.has(target.id);
  }
  function address(target) {
    return isGrouped() ? target.groupKey : target.key;
  }
  function allTargets() {
    return TARGETS.filter(
      (target) =>
        (state.tabs || target.type !== "tab") &&
        (state.apps || !["app", "launch"].includes(target.type)) &&
        (!isGrouped() || target.type !== "app"),
    );
  }
  function filteredTargets() {
    const words = state.query
      .toLocaleLowerCase()
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    return allTargets().filter((target) =>
      state.search
        ? words.every((word) =>
            `${target.title} ${APPS[target.app].name} ${target.context || ""}`
              .toLocaleLowerCase()
              .includes(word),
          )
        : address(target).startsWith(state.prefix),
    );
  }
  function metadata(target) {
    if (isMinimized(target)) return `${APPS[target.app].name} · Minimized`;
    if (target.type === "launch")
      return state.launched.has(target.id)
        ? "Running · fixed app letter"
        : "Launch · fixed app letter";
    if (target.type === "app") return "Running app · fixed letter";
    if (target.type === "tab")
      return `${APPS[target.app].name} · ${target.context}`;
    return APPS[target.app].name;
  }
  function row(target, options = {}) {
    const key = options.localKey ? target.groupKey.slice(1) : address(target);
    const label = `${key}: ${target.title}, ${metadata(target)}`;
    return `<button type="button" class="destination${state.highlight === target.id ? " highlight" : ""}${state.current === target.id ? " is-current" : ""}" data-target="${target.id}" title="${escapeHTML(label)}" aria-label="${escapeHTML(label)}">${icon(target.app, isMinimized(target))}<span class="destination-text"><span class="destination-title">${escapeHTML(target.title)}</span><span class="destination-meta">${escapeHTML(metadata(target))}</span></span><kbd aria-hidden="true">${key}</kbd></button>`;
  }
  function groups(targets = allTargets()) {
    return Object.entries(APPS)
      .map(([id, app]) => ({
        id,
        ...app,
        children: targets.filter((target) => target.app === id),
      }))
      .filter((app) => app.children.length);
  }
  function renderCanopy(targets) {
    return `<div class="canopy-columns">${groups(targets)
      .map(
        (app) =>
          `<div class="app-family"><div class="family-heading">${icon(app.id)}<span>${app.name}</span><small>${app.children.length}</small></div>${app.children.map((target) => row(target)).join("")}</div>`,
      )
      .join("")}</div>`;
  }
  function renderFold() {
    const families = groups();
    const family = families.find((app) => app.id === state.family);
    const spine = families
      .map((app) => {
        const minimized = app.children.some(isMinimized);
        const direct =
          app.children.length === 1 && app.children[0].groupKey.length === 1;
        const highlight =
          state.highlight === `group:${app.id}` || state.family === app.id;
        return `<button type="button" class="family-button${highlight ? " selected" : ""}" data-family="${app.id}" aria-label="${app.key}: ${app.name}${minimized ? ", contains a minimized window" : ""}${direct ? ", select" : ", expand destinations"}"${!direct ? ` aria-expanded="${state.family === app.id}"` : ""}>${icon(app.id, minimized)}<span>${app.name}</span><kbd aria-hidden="true">${app.key}</kbd></button>`;
      })
      .join("");
    return `<div class="fold-layout"><div class="fold-spine"><div class="fold-heading">APPS</div>${spine}</div><div class="fold-sheet"><div class="fold-heading">${family ? family.name.toUpperCase() : "YOUR NEXT DESTINATION"}</div>${family ? family.children.map((target) => row(target, { localKey: true })).join("") : '<p class="fold-intro">Choose an app.<br>Let the rest unfold.</p>'}</div></div>`;
  }
  function renderBeacons(targets) {
    // Only the two drawn desktop windows have known visible geometry.
    // Other windows use the bank, just as uncertain native geometry does.
    const plaques = targets.filter(
      (target) => ["code", "lesson"].includes(target.id) && !isMinimized(target),
    );
    const bank = targets.filter((target) => !plaques.includes(target));
    return `<div class="beacons-layout">${plaques.map((target) => `<div class="beacon-plaque" data-window="${target.id}">${row(target)}</div>`).join("")}<div class="beacons-bank"><div class="bank-label">MORE DESTINATIONS</div>${bank.map((target) => row(target)).join("")}</div></div>`;
  }
  function renderRelay(targets) {
    const current = TARGETS.find((target) => target.id === state.current);
    const previous = TARGETS.find((target) => target.id === state.previous);
    return `<div class="relay-pair"><div class="relay-current"><p class="relay-label">YOU ARE HERE</p>${row(current)}</div><span aria-hidden="true">⇄</span><div class="relay-previous"><p class="relay-label">RIGHT BACK TO IT</p>${row(previous)}<button type="button" class="return-button" data-return>Return to previous <kbd>Enter ↵</kbd></button></div></div><div class="relay-shelf">${targets
      .filter((target) => ![current.id, previous.id].includes(target.id))
      .map((target) => row(target))
      .join("")}</div>`;
  }
  function announce(message) {
    $("#demo-status").textContent = message;
  }

  function render({ focusSearch = false } = {}) {
    desktop.dataset.mode = state.mode;
    desktop.dataset.theme = state.theme;
    desktop.dataset.tone = state.tone;
    desktop.dataset.state = state.open ? "open" : "closed";
    desktop.dataset.restore = state.restorePrompt;
    switcher.hidden = !state.open;
    $("#selection-card").hidden = state.open;
    const info = MODE_INFO[state.mode];
    $("#mode-index").textContent = `${info[0]} / ${state.mode.toUpperCase()}`;
    $("#mode-headline").textContent = info[1];
    $("#mode-description").textContent = info[2];
    $("#native-capture").textContent =
      `See the native ${capitalize(state.mode)} view ↗`;
    $$("[data-mode]", $(".mode-tabs")).forEach((button) =>
      button.setAttribute("aria-pressed", button.dataset.mode === state.mode),
    );
    if (!state.open) return;

    const targets = filteredTargets();
    let content;
    if (state.search)
      content = `<div class="search-results">${targets.length ? targets.map((target) => row(target)).join("") : '<p class="empty-results">No destinations found.<br>Try an app name, like Safari.</p>'}</div>`;
    else if (state.mode === "fold") content = renderFold();
    else if (state.mode === "canopy") content = renderCanopy(targets);
    else if (state.mode === "lattice")
      content = `<div class="lattice-grid">${targets.map((target) => row(target)).join("")}</div>`;
    else if (state.mode === "beacons") content = renderBeacons(targets);
    else if (state.mode === "relay") content = renderRelay(targets);
    else content = targets.map((target) => row(target)).join("");

    const searchHeader = state.search
      ? `<div class="switcher-search"><span aria-hidden="true">⌕</span><input id="destination-search" type="search" placeholder="Find a window, tab or app…" aria-label="Search sample destinations" value="${escapeHTML(state.query)}" autocomplete="off" spellcheck="false"></div>`
      : "";
    const prefixHeader =
      !state.search && state.prefix
        ? `<div class="prefix-bar"><kbd>${state.prefix}</kbd><span>Next letter</span><button type="button" data-back>← Back</button></div>`
        : "";
    const footer = `<div class="switcher-footer"><button type="button" data-search>${state.search ? "Done" : "Search /"}</button><span>↑ ↓ Choose · ↵ Select</span>${state.restorePrompt ? '<button type="button" class="restore-action" data-restore>Restore ⌥</button>' : ""}<button type="button" class="switcher-close" data-close aria-label="Close switcher">×</button></div>`;
    const searchInput = $("#destination-search");
    const hadSearchFocus = searchInput === document.activeElement;
    const selectionStart = searchInput?.selectionStart;
    switcher.innerHTML = `${searchHeader}${prefixHeader}<div class="switcher-content">${content}</div>${footer}`;
    navigables = $$("[data-target], [data-family]", switcher);
    if (!navigables.some((element) => itemId(element) === state.highlight)) {
      state.highlight = navigables.length ? itemId(navigables[0]) : null;
      updateHighlight();
    }
    if (state.search && (focusSearch || hadSearchFocus)) {
      const input = $("#destination-search");
      input.focus({ preventScroll: true });
      if (selectionStart !== null && selectionStart !== undefined)
        input.setSelectionRange(selectionStart, selectionStart);
    }
  }
  function itemId(element) {
    return element.dataset.target || `group:${element.dataset.family}`;
  }
  function updateHighlight() {
    navigables.forEach((element) => {
      const highlighted = itemId(element) === state.highlight;
      element.classList.toggle(
        element.dataset.family ? "selected" : "highlight",
        highlighted,
      );
    });
  }
  function scrollHighlight() {
    const selected = navigables.find(
      (element) => itemId(element) === state.highlight,
    );
    // Only scroll the panel. scrollIntoView can unexpectedly move the entire landing page.
    const container = $(".switcher-content", switcher);
    if (!selected || !container) return;
    const itemRect = selected.getBoundingClientRect();
    const containerRect = container.getBoundingClientRect();
    if (itemRect.bottom > containerRect.bottom)
      container.scrollTop += itemRect.bottom - containerRect.bottom + 8;
    else if (itemRect.top < containerRect.top)
      container.scrollTop -= containerRect.top - itemRect.top + 8;
  }
  function capitalize(value) {
    return value[0].toUpperCase() + value.slice(1);
  }
  function focusDesktop() {
    desktop.focus({ preventScroll: true });
  }
  function openSwitcher() {
    Object.assign(state, {
      open: true,
      search: false,
      query: "",
      prefix: "",
      family: null,
      restorePrompt: false,
      highlight: state.previous,
    });
    render();
    focusDesktop();
  }
  function closeSwitcher() {
    state.open = false;
    $("#selection-title").textContent = "A little room to think.";
    $("#selection-detail").textContent =
      "Switcher closed. Your sample workspace is right here.";
    announce("Switcher closed. Space opens it again.");
    render();
    focusDesktop();
  }
  function selectTarget(id) {
    const target = allTargets().find((item) => item.id === id);
    if (!target) return;
    const restored = isMinimized(target);
    const launching = target.type === "launch" && !state.launched.has(id);
    if (restored) state.restored.add(id);
    if (target.type === "launch") state.launched.add(id);
    if (target.type === "window" && target.id !== state.current) {
      state.previous = state.current;
      state.current = target.id;
    }
    state.open = false;
    state.restorePrompt = false;
    $("#menu-app").textContent = APPS[target.app].name;
    $("#selection-title").textContent = launching
      ? "Hello, Figma."
      : restored
        ? "Right where you left it."
        : "Back in your flow.";
    $("#selection-detail").textContent =
      `${target.title} · ${launching ? "launched in the demo" : restored ? "restored in the demo" : "selected in the demo"}`;
    announce(
      `${address(target)} → ${target.title}. ${launching ? "Sample app launched." : restored ? "Sample window restored and selected." : "Selected."} Space to switch again.`,
    );
    render();
    focusDesktop();
  }
  function chooseFamily(appId) {
    const family = groups().find((app) => app.id === appId);
    if (!family) return;
    if (
      family.children.length === 1 &&
      family.children[0].groupKey.length === 1
    ) {
      selectTarget(family.children[0].id);
      return;
    }
    state.family = appId;
    state.prefix = family.key;
    state.highlight = family.children[0].id;
    render();
    focusDesktop();
    announce(
      `${family.name} unfolded. Type the child letter to select, or Escape to go back.`,
    );
  }
  function startSearch() {
    Object.assign(state, {
      open: true,
      search: true,
      query: "",
      prefix: "",
      family: null,
      restorePrompt: false,
    });
    render({ focusSearch: true });
    announce(
      "Search by app, title or browser context. Enter selects a result.",
    );
  }
  function back() {
    if (state.search) {
      Object.assign(state, {
        search: false,
        query: "",
        prefix: "",
        family: null,
      });
      render();
      focusDesktop();
      announce("Back to letter selection.");
    } else if (state.prefix || state.family) {
      Object.assign(state, { prefix: "", family: null });
      render();
      focusDesktop();
      announce("Back to all destinations.");
    } else closeSwitcher();
  }
  function typeAddress(letter) {
    const candidate = state.prefix + letter;
    const matches = allTargets().filter((target) =>
      address(target).startsWith(candidate),
    );
    if (!matches.length) {
      announce(
        `No destination at ${candidate}. ${state.prefix ? "Use Backspace to go back." : "Try one of the displayed letters."}`,
      );
      return;
    }
    const exact = matches.find((target) => address(target) === candidate);
    if (exact) {
      selectTarget(exact.id);
      return;
    }
    state.prefix = candidate;
    state.highlight = matches[0].id;
    if (state.mode === "fold") state.family = matches[0].app;
    render();
    focusDesktop();
    announce(`${candidate} → next letter. ${matches.length} destinations.`);
  }
  function moveHighlight(delta) {
    if (!navigables.length) return;
    const index = navigables.findIndex(
      (element) => itemId(element) === state.highlight,
    );
    state.highlight = itemId(
      navigables[(index + delta + navigables.length) % navigables.length],
    );
    updateHighlight();
    scrollHighlight();
  }
  function chooseHighlight() {
    if (state.highlight?.startsWith("group:"))
      chooseFamily(state.highlight.slice(6));
    else if (state.highlight) selectTarget(state.highlight);
  }
  function restoreHighlighted() {
    let target = TARGETS.find((item) => item.id === state.highlight);
    if (state.highlight?.startsWith("group:"))
      target = allTargets().find(
        (item) => item.app === state.highlight.slice(6) && isMinimized(item),
      );
    if (!target || !isMinimized(target) || target.type !== "window") {
      announce(
        "The highlighted destination is not a minimized window. Nothing to restore.",
      );
      return;
    }
    state.restored.add(target.id);
    state.restorePrompt = false;
    render();
    focusDesktop();
    announce(
      `Restored “${target.title}” in the demo. Its address is still ${address(target)}. Enter or its letter selects it.`,
    );
  }
  function prepareRestore(scroll = false) {
    state.restored.delete("ideas");
    Object.assign(state, {
      open: true,
      search: false,
      query: "",
      prefix: "",
      family: null,
      highlight: state.mode === "fold" ? "group:notes" : "ideas",
      restorePrompt: true,
    });
    render();
    if (scroll)
      $("#playground").scrollIntoView({
        behavior: motionBehavior(),
        block: "start",
      });
    focusDesktop();
    scrollHighlight();
    announce(
      "“A few good ideas” is minimized. Press Option (Alt), or click Restore ⌥.",
    );
  }
  function motionBehavior() {
    return matchMedia("(prefers-reduced-motion: reduce)").matches
      ? "instant"
      : "smooth";
  }

  desktop.addEventListener("keydown", (event) => {
    // Native navigation/OS shortcuts keep their normal ownership outside the demo.
    if (event.metaKey || event.ctrlKey || event.isComposing) return;
    const input = event.target instanceof HTMLInputElement;
    if (
      input &&
      !["Escape", "ArrowDown", "ArrowUp", "Enter"].includes(event.key)
    )
      return;
    // Let focused buttons keep their ordinary Enter/Space activation and Tab order.
    if (event.target.closest("button") && ["Enter", " "].includes(event.key))
      return;
    if (event.key === "Alt" && !event.repeat && state.open && !state.search) {
      event.preventDefault();
      restoreHighlighted();
      return;
    }
    if (event.altKey) return;
    if (event.key === " " && !input) {
      event.preventDefault();
      state.open ? closeSwitcher() : openSwitcher();
      return;
    }
    if (!state.open) return;
    if (event.key === "Escape") {
      event.preventDefault();
      back();
    } else if (event.key === "Backspace" && !input) {
      event.preventDefault();
      if (state.prefix) back();
    } else if (event.key === "/" && !input) {
      event.preventDefault();
      startSearch();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      moveHighlight(event.key === "ArrowDown" ? 1 : -1);
    } else if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      if (state.search || state.mode === "shore") return;
      event.preventDefault();
      if (state.mode === "fold") {
        if (event.key === "ArrowLeft" && state.family) back();
        else if (
          event.key === "ArrowRight" &&
          state.highlight?.startsWith("group:")
        )
          chooseFamily(state.highlight.slice(6));
      } else if (state.mode === "canopy") {
        const families = groups();
        const currentTarget = allTargets().find(
          (target) => target.id === state.highlight,
        );
        const index = families.findIndex(
          (app) => app.id === currentTarget?.app,
        );
        const next =
          families[
            (index + (event.key === "ArrowRight" ? 1 : -1) + families.length) %
              families.length
          ];
        state.highlight = next.children[0].id;
        updateHighlight();
        scrollHighlight();
      } else moveHighlight(event.key === "ArrowRight" ? 1 : -1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (state.mode === "relay" && !state.search) selectTarget(state.previous);
      else chooseHighlight();
    } else if (/^[a-z]$/i.test(event.key) && !input) {
      event.preventDefault();
      typeAddress(event.key.toUpperCase());
    }
  });
  switcher.addEventListener("click", (event) => {
    const button = event.target.closest("button");
    if (!button) return;
    if (button.dataset.target) selectTarget(button.dataset.target);
    else if (button.dataset.family) chooseFamily(button.dataset.family);
    else if (button.hasAttribute("data-return")) selectTarget(state.previous);
    else if (button.hasAttribute("data-search"))
      state.search ? back() : startSearch();
    else if (button.hasAttribute("data-back")) back();
    else if (button.hasAttribute("data-close")) closeSwitcher();
    else if (button.hasAttribute("data-restore")) restoreHighlighted();
  });
  switcher.addEventListener("input", (event) => {
    if (event.target.id !== "destination-search") return;
    state.query = event.target.value;
    state.highlight = filteredTargets()[0]?.id || null;
    render();
  });
  switcher.addEventListener("focusin", (event) => {
    const item = event.target.closest("[data-target], [data-family]");
    if (item) {
      state.highlight = itemId(item);
      updateHighlight();
    }
  });
  desktop.addEventListener("click", (event) => {
    if (!event.target.closest("button, input, a")) focusDesktop();
  });
  $$(".mode-tabs button").forEach((button) =>
    button.addEventListener("click", () => {
      state.mode = button.dataset.mode;
      openSwitcher();
      announce(
        `${capitalize(state.mode)}. ${MODE_INFO[state.mode][1]} Try a displayed letter.`,
      );
    }),
  );
  $("#reopen").addEventListener("click", openSwitcher);
  $("#search-demo").addEventListener("click", startSearch);
  $("#restore-demo").addEventListener("click", () => prepareRestore());
  $("#hero-try").addEventListener("click", () => {
    openSwitcher();
  });
  $("#reset-demo").addEventListener("click", () => {
    Object.assign(state, {
      mode: "shore",
      theme: "tabnax",
      tone: "dark",
      tabs: true,
      apps: true,
      current: "code",
      previous: "lesson",
    });
    state.restored.clear();
    state.launched.clear();
    $("#include-tabs").checked = true;
    $("#include-apps").checked = true;
    $("#demo-theme").value = "tabnax";
    updateToneButton();
    $("#menu-app").textContent = "Xcode";
    openSwitcher();
    announce("Demo reset. Try K to open the keyboard guide.");
  });
  $("#demo-theme").addEventListener("change", (event) => {
    state.theme = event.target.value;
    render();
    announce(
      `${event.target.selectedOptions[0].text} theme. ${["macos", "frosted"].includes(state.theme) ? "Glass here is a browser approximation." : "Try the same letters in a new look."}`,
    );
  });
  function updateToneButton() {
    const button = $("#demo-tone");
    const label = `Use ${state.tone === "dark" ? "light" : "dark"} appearance`;
    button.setAttribute("aria-label", label);
    button.title = label;
    button.textContent = state.tone === "dark" ? "☼" : "☾";
  }
  $("#demo-tone").addEventListener("click", () => {
    state.tone = state.tone === "dark" ? "light" : "dark";
    updateToneButton();
    render();
    announce(
      `${capitalize(state.tone)} appearance. Your addresses are unchanged.`,
    );
  });
  [
    ["#include-tabs", "tabs"],
    ["#include-apps", "apps"],
  ].forEach(([selector, property]) => {
    $(selector).addEventListener("change", (event) => {
      state[property] = event.target.checked;
      openSwitcher();
      announce(
        `${property === "tabs" ? "Browser tabs" : "Fixed app targets"} ${state[property] ? "included" : "hidden"}. Existing addresses stay the same.`,
      );
    });
  });
  $$("[data-demo-action]").forEach((button) =>
    button.addEventListener("click", () => {
      if (button.dataset.demoAction === "restore") {
        prepareRestore(true);
        return;
      }
      if (button.dataset.demoAction === "search") startSearch();
      else {
        state.apps = true;
        $("#include-apps").checked = true;
        state.launched.delete("figma-app");
        openSwitcher();
        state.highlight = state.mode === "fold" ? "group:figma" : "figma-app";
        updateHighlight();
        scrollHighlight();
        announce(
          "F is reserved for Figma. Press F to launch it in this sample workspace.",
        );
      }
      $("#playground").scrollIntoView({
        behavior: motionBehavior(),
        block: "start",
      });
    }),
  );

  function showImage(source, title, alt) {
    $("#dialog-image").src = source;
    $("#dialog-image").alt = alt;
    $("#image-dialog-title").textContent = title;
    $("#image-dialog").showModal();
  }
  $("#native-capture").addEventListener("click", () => {
    showImage(
      `assets/native/mode-${state.mode}.png?v=tabnax-samples`,
      `${capitalize(state.mode)} · native switcher`,
      `Actual Tabnax ${capitalize(state.mode)} renderer showing sample windows and keyboard addresses`,
    );
  });
  function updateSettings() {
    const label =
      nativePane === "browsers" ? "Browser tabs" : capitalize(nativePane);
    const image = $("#settings-image");
    image.src = `assets/native/${nativePane}-${nativeTone}.png?v=tabnax-samples`;
    image.alt = `Native Tabnax ${label} settings in ${nativeTone} mode with sample data and the live switcher preview`;
    $("#expand-settings").setAttribute(
      "aria-label",
      `Enlarge native ${label} screenshot`,
    );
    $("#pane-title").textContent = PANE_INFO[nativePane][0];
    $("#pane-description").textContent = PANE_INFO[nativePane][1];
    $$("[data-pane]").forEach((button) =>
      button.setAttribute("aria-pressed", button.dataset.pane === nativePane),
    );
    const toneLabel = `Show ${nativeTone === "light" ? "dark" : "light"} settings screenshot`;
    $("#capture-tone").setAttribute("aria-label", toneLabel);
    $("#capture-tone").title = toneLabel;
  }
  $$("[data-pane]").forEach((button) =>
    button.addEventListener("click", () => {
      nativePane = button.dataset.pane;
      updateSettings();
    }),
  );
  $("#capture-tone").addEventListener("click", () => {
    nativeTone = nativeTone === "light" ? "dark" : "light";
    updateSettings();
  });
  $("#expand-settings").addEventListener("click", () => {
    const label =
      nativePane === "browsers" ? "Browser tabs" : capitalize(nativePane);
    showImage(
      $("#settings-image").getAttribute("src"),
      `${label} · native settings`,
      $("#settings-image").alt,
    );
  });
  $("#open-build").addEventListener("click", () =>
    $("#build-dialog").showModal(),
  );
  $$("[data-close-dialog]").forEach((button) =>
    button.addEventListener("click", () => button.closest("dialog").close()),
  );
  $$("dialog").forEach((dialog) =>
    dialog.addEventListener("click", (event) => {
      const rect = dialog.getBoundingClientRect();
      if (
        event.target === dialog &&
        (event.clientX < rect.left ||
          event.clientX > rect.right ||
          event.clientY < rect.top ||
          event.clientY > rect.bottom)
      )
        dialog.close();
    }),
  );
  $("#copy-command").addEventListener("click", async () => {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard unavailable");
      await navigator.clipboard.writeText("./macos/scripts/dev.sh");
      $("#copy-status").textContent =
        "Copied. Run it from the Tabnax project directory.";
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents($(".copy-command code"));
      selection.removeAllRanges();
      selection.addRange(range);
      $("#copy-status").textContent =
        "Command selected. Press Command–C (or Control–C) to copy.";
    }
  });

  $("#demo-dock").innerHTML = [
    "finder",
    "safari",
    "xcode",
    "notes",
    "arc",
    "figma",
  ]
    .map((app) => icon(app))
    .join("");
  render();
})();
