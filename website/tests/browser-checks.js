async (page) => {
  let passed = 0;
  const errors = [];
  const check = (value, label) => {
    if (!value) throw new Error(label);
    passed++;
  };
  page.on("pageerror", (error) => errors.push(error.message));
  const desktop = page.locator("#desktop");
  const mode = async (name) =>
    page.locator('.mode-tabs button[data-mode="' + name + '"]').click();
  const status = () => page.locator("#demo-status").textContent();
  const open = async () => {
    await desktop.focus();
    if (!(await page.locator("#switcher").isVisible()))
      await page.keyboard.press("Space");
  };
  await page.setViewportSize({ width: 1440, height: 1080 });
  // Open the homepage in this session first; keep the chosen server/root portable.
  await page.reload();
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const name of [
    "shore",
    "beacons",
    "canopy",
    "lattice",
    "fold",
    "relay",
  ]) {
    await mode(name);
    check(await page.locator("#switcher").isVisible(), name + " opens");
    await page.keyboard.type(["canopy", "fold"].includes(name) ? "sj" : "k");
    check(
      (await status()).includes("Tabnax · Keyboard guide"),
      name + " keyboard selects",
    );
    check(
      !(await page.locator("#switcher").isVisible()),
      name + " closes after selection",
    );
    await open();
    await page.keyboard.press("/");
    await page.locator("#destination-search").fill("safari macos");
    check(
      (await page.locator(".search-results .destination").count()) === 1,
      name + " multi-term search",
    );
    await page.keyboard.press("Enter");
    check(
      (await status()).includes("Designing for macOS"),
      name + " search Enter selects normally",
    );
    await open();
    await page.keyboard.press("/");
    await page.locator("#destination-search").fill("no-such-window");
    check(
      await page.locator(".empty-results").isVisible(),
      name + " empty state",
    );
    await page.keyboard.press("Enter");
    check(
      await page.locator("#switcher").isVisible(),
      name + " empty Enter safe",
    );
    await page.keyboard.press("Escape");
    check(
      (await page.locator("#switcher").isVisible()) &&
        (await page.locator("#destination-search").count()) === 0,
      name + " Escape exits search",
    );
    await page.keyboard.press("Escape");
    check(
      !(await page.locator("#switcher").isVisible()),
      name + " Escape closes",
    );
    await page.locator("#restore-demo").click();
    await page.keyboard.press("Alt");
    check(
      (await status()).includes("Restored “A few good ideas”"),
      name + " Option restores",
    );
    check(
      (await page.locator(".minimized-badge").count()) === 0,
      name + " minimized badge removed",
    );
    await page.keyboard.press("Alt");
    check(
      (await status()).includes("Nothing to restore"),
      name + " restore never minimizes",
    );
    await page.keyboard.press("f");
    check(
      (await status()).includes("Figma"),
      name + " fixed app letter selects",
    );
    await open();
  }
  await mode("fold");
  await page.keyboard.press("s");
  check(
    (await page.locator(".fold-sheet [data-target]").count()) === 2,
    "Fold app prefix expands",
  );
  await page.keyboard.press("Backspace");
  check(
    await page.locator(".fold-intro").isVisible(),
    "Backspace returns to app spine",
  );
  await page.locator('[data-family="safari"]').click();
  await page.locator('.fold-sheet [data-target="docs"]').click();
  check(
    (await status()).includes("Designing for macOS"),
    "Fold mouse branch and tab",
  );
  await mode("relay");
  await page.keyboard.press("j");
  await open();
  await page.keyboard.press("Enter");
  check(
    (await status()).includes("Tabnax · Keyboard guide"),
    "Relay returns to previous window",
  );
  await open();
  await page.keyboard.press("Enter");
  check(
    (await status()).includes("InputRouter.swift"),
    "Relay back and forth updates history",
  );
  await mode("shore");
  const keyBefore = await page
    .locator('[data-target="lesson"] kbd')
    .textContent();
  await page.locator("#include-tabs").uncheck();
  check(
    (await page.locator('[data-target="docs"]').count()) === 0,
    "Tabs hide",
  );
  check(
    (await page.locator('[data-target="lesson"] kbd').textContent()) ===
      keyBefore,
    "Filter preserves letters",
  );
  await page.locator("#include-tabs").check();
  check(
    (await page.locator('[data-target="docs"]').count()) === 1,
    "Tabs return",
  );
  await page.locator("#include-apps").uncheck();
  check(
    (await page.locator('[data-target="figma-app"]').count()) === 0,
    "App targets hide",
  );
  await page.locator("#include-apps").check();
  await page.keyboard.press("z");
  check(
    (await status()).includes("No destination at Z") &&
      (await page.locator("#switcher").isVisible()),
    "Unknown key keeps demo open",
  );
  for (const theme of [
    "tabnax",
    "graphite",
    "sage",
    "iris",
    "frosted",
    "macos",
  ]) {
    await page.locator("#demo-theme").selectOption(theme);
    check(
      (await desktop.getAttribute("data-theme")) === theme,
      theme + " applies",
    );
    await page.locator("#demo-tone").click();
    check(
      (await desktop.getAttribute("data-tone")) === "light",
      theme + " light",
    );
    await page.locator("#demo-tone").click();
    check(
      (await desktop.getAttribute("data-tone")) === "dark",
      theme + " dark",
    );
  }
  for (const pane of [
    "general",
    "letters",
    "apps",
    "position",
    "appearance",
    "browsers",
  ]) {
    await page.locator('[data-pane="' + pane + '"]').click();
    for (const tone of ["light", "dark"]) {
      await page.waitForFunction(() => {
        const image = document.querySelector("#settings-image");
        return image.complete && image.naturalWidth > 0;
      });
      check(
        (await page.locator("#settings-image").getAttribute("src")).includes(
          pane + "-" + tone,
        ),
        pane + " " + tone + " screenshot",
      );
      await page.locator("#capture-tone").click();
    }
  }
  await page.locator("#expand-settings").click();
  check(
    await page.locator("#image-dialog").isVisible(),
    "Native image enlarges",
  );
  await page.keyboard.press("Escape");
  check(
    !(await page.locator("#image-dialog").isVisible()),
    "Image Escape closes",
  );
  check(
    await page
      .locator("#expand-settings")
      .evaluate((el) => el === document.activeElement),
    "Dialog focus restored",
  );
  await page.locator("#native-capture").click();
  check(
    (await page.locator("#dialog-image").getAttribute("src")).includes(
      "mode-shore",
    ),
    "Native mode screenshot correct",
  );
  await page.keyboard.press("Escape");
  await page.locator("#open-build").click();
  check(await page.locator("#build-dialog").isVisible(), "Build guide opens");
  await page.keyboard.press("Escape");
  await page.locator("summary").first().click();
  check(
    await page
      .locator("details")
      .first()
      .evaluate((el) => el.open),
    "FAQ opens",
  );
  await page.locator("summary").first().click();
  for (const width of [1440, 1024, 768, 390, 320]) {
    await page.setViewportSize({ width, height: 900 });
    for (const name of [
      "shore",
      "beacons",
      "canopy",
      "lattice",
      "fold",
      "relay",
    ]) {
      await mode(name);
      const bounds = await page.evaluate(() => {
        const d = document.querySelector("#desktop").getBoundingClientRect();
        const s = document.querySelector("#switcher").getBoundingClientRect();
        const c = document.querySelector(".switcher-content");
        return {
          bodyWidth: document.documentElement.scrollWidth,
          viewport: innerWidth,
          inside:
            s.left >= d.left - 1 &&
            s.right <= d.right + 1 &&
            s.top >= d.top &&
            s.bottom <= d.bottom + 1,
          scrollX: c.scrollWidth - c.clientWidth,
        };
      });
      check(
        bounds.bodyWidth <= bounds.viewport,
        width + " " + name + " no page overflow: " + JSON.stringify(bounds),
      );
      check(
        bounds.inside,
        width + " " + name + " panel bounded: " + JSON.stringify(bounds),
      );
      check(
        bounds.scrollX <= 1,
        width +
          " " +
          name +
          " no horizontal panel clipping: " +
          JSON.stringify(bounds),
      );
      if (width === 390)
        await page
          .locator(".demo-shell")
          .screenshot({ path: "output/playwright/mobile-" + name + ".png" });
    }
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.locator("#reset-demo").click();
  await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
  await page.screenshot({
    path: "output/playwright/home-mobile.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 1440, height: 1080 });
  await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
  await page.screenshot({ path: "output/playwright/home-desktop.png" });
  check(errors.length === 0, "No browser errors: " + errors.join("; "));
  return { passed, errors };
}
