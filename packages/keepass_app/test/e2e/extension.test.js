const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const EXT_PATH = path.resolve(__dirname, '../../build/extension');
const TEST_DB = path.resolve(__dirname, 'fixtures/test_with_entries.kdbx');
const TEST_PASSWORD = 'demopass';

// Flutter CanvasKit renders to <canvas>. We interact via:
//   - Coordinate-based clicks (layout is deterministic at 1280x1024)
//   - page.waitForFileChooser() to intercept Flutter's <input type="file">
//   - page.keyboard for text entry (Flutter creates hidden <input> on focus)
//   - Screenshot hash comparison to verify screen transitions

// Layout at 1280x1024:
// Unlock screen: centered 420px card.
const CENTER_X = 640;
const UNLOCK = {
  filePickerBtn: { x: CENTER_X, y: 450 },
  passwordField: { x: CENTER_X, y: 490 },
  unlockBtn: { x: CENTER_X, y: 640 },
};
// Vault screen: top bar 48px, group tree 280px, entry list flexible, detail flexible.
const VAULT = {
  lockBtn: { x: 1200, y: 24 },
  settingsBtn: { x: 1130, y: 24 },
  openFullPageBtn: { x: 1165, y: 24 },
  // Group tree (left panel, 0-280px).
  group: {
    general: { x: 90, y: 132 },
    internet: { x: 90, y: 203 },
    recycleBin: { x: 90, y: 238 },
  },
  // Entry list (center panel, 280-740px). Entries at ~55px vertical intervals.
  entry: {
    first: { x: 400, y: 115 },
    second: { x: 400, y: 170 },
  },
  // Detail panel (right panel, 740-1280px).
  detail: { x: 960, y: 400 },
  // Search box in group tree panel.
  searchBox: { x: 140, y: 80 },
};

function hash(buf) {
  return crypto.createHash('md5').update(buf).digest('hex');
}

async function shot(page, x, y, w, h) {
  return page.screenshot({ clip: { x, y, width: w, height: h }, encoding: 'binary' });
}

describe('ManyKee Chrome Extension', () => {
  let browser;
  let page;
  let extId;
  const consoleErrors = [];

  let unlockScreenHash;

  beforeAll(async () => {
    if (!fs.existsSync(EXT_PATH)) {
      throw new Error(
        `Extension not built at: ${EXT_PATH}\nRun: bash scripts/build_extension.sh`
      );
    }

    browser = await puppeteer.launch({
      headless: false,
      args: [
        `--disable-extensions-except=${EXT_PATH}`,
        `--load-extension=${EXT_PATH}`,
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--window-size=1280,1024',
      ],
      executablePath: process.env.CHROME_PATH || undefined,
      defaultViewport: { width: 1280, height: 1024 },
    });

    await sleep(3000);

    const targets = await browser.targets();
    for (const target of targets) {
      const match = target.url().match(/^chrome-extension:\/\/([a-z]{32})/);
      if (match) {
        extId = match[1];
        break;
      }
    }
    if (!extId) throw new Error('Could not determine extension ID');

    page = await browser.newPage();
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
  }, 120000);

  afterAll(async () => {
    if (browser) await browser.close();
  });

  // -------------------------------------------------------------------------
  // 1. Extension loads
  // -------------------------------------------------------------------------

  it('loads extension and renders Flutter app', async () => {
    await page.goto(`chrome-extension://${extId}/index.html`);
    await page.waitForSelector('flt-glass-pane', { timeout: 15000 });
    await sleep(5000);

    const hasGlassPane = await page.evaluate(
      () => !!document.querySelector('flt-glass-pane')
    );
    expect(hasGlassPane).toBe(true);

    unlockScreenHash = hash(await page.screenshot({ encoding: 'binary' }));
  });

  it('has no CSP violations', () => {
    const cspErrors = consoleErrors.filter(
      (e) =>
        e.includes('Content-Security-Policy') ||
        e.includes('content security policy') ||
        e.includes('Refused to execute')
    );
    expect(cspErrors).toEqual([]);
  });

  // -------------------------------------------------------------------------
  // 2. Unlock flow
  // -------------------------------------------------------------------------

  it('uploads a KDBX file via file picker', async () => {
    const before = hash(await page.screenshot({ encoding: 'binary' }));

    const fcPromise = page.waitForFileChooser({ timeout: 10000 });
    await page.mouse.click(UNLOCK.filePickerBtn.x, UNLOCK.filePickerBtn.y);
    const fileChooser = await fcPromise;
    await fileChooser.accept([TEST_DB]);
    await sleep(1500);

    // Button text changes from "Choose KDBX File" to filename.
    const after = hash(await page.screenshot({ encoding: 'binary' }));
    expect(after).not.toBe(before);
  });

  it('enters password and unlocks vault', async () => {
    await page.mouse.click(UNLOCK.passwordField.x, UNLOCK.passwordField.y);
    await sleep(500);
    await page.keyboard.type(TEST_PASSWORD, { delay: 30 });
    await sleep(300);

    await page.mouse.click(UNLOCK.unlockBtn.x, UNLOCK.unlockBtn.y);
    await sleep(12000);

    // Must have transitioned away from unlock screen.
    const after = hash(await page.screenshot({ encoding: 'binary' }));
    expect(after).not.toBe(unlockScreenHash);
  }, 30000);

  // -------------------------------------------------------------------------
  // 3. Vault layout
  // -------------------------------------------------------------------------

  it('shows 3-panel vault layout with dividers', async () => {
    const leftOfDiv = await shot(page, 270, 60, 4, 80);
    const divider = await shot(page, 279, 60, 2, 80);
    const rightOfDiv = await shot(page, 284, 60, 4, 80);

    const dividerIsVisible =
      hash(divider) !== hash(leftOfDiv) || hash(divider) !== hash(rightOfDiv);
    expect(dividerIsVisible).toBe(true);
  });

  it('top bar shows filename and icons', async () => {
    const topBarLeft = await shot(page, 10, 5, 150, 38);
    const topBarRight = await shot(page, 1080, 5, 150, 38);
    const blank = await shot(page, 300, 800, 150, 38);

    expect(hash(topBarLeft)).not.toBe(hash(blank));
    expect(hash(topBarRight)).not.toBe(hash(blank));
  });

  it('shows "Open in full tab" button in extension context', async () => {
    // Area between settings and lock icons has the open_in_new icon.
    const iconArea = await shot(page, 1145, 5, 40, 38);
    const emptyArea = await shot(page, 1050, 5, 40, 38);

    expect(hash(iconArea)).not.toBe(hash(emptyArea));
  });

  // -------------------------------------------------------------------------
  // 4. Group navigation
  // -------------------------------------------------------------------------

  it('shows groups in left panel with entries in center', async () => {
    // General group is selected by default — center panel shows entries.
    // The center panel header area (above entries) should differ from empty.
    const centerHeader = await shot(page, 285, 55, 440, 30);
    const emptyCenter = await shot(page, 285, 600, 440, 30);

    expect(hash(centerHeader)).not.toBe(hash(emptyCenter));
  });

  it('can switch groups and entry list updates', async () => {
    // Capture center panel with General selected.
    const generalEntries = hash(await shot(page, 285, 85, 440, 120));

    // Click Internet group.
    await page.mouse.click(VAULT.group.internet.x, VAULT.group.internet.y);
    await sleep(500);

    // Center panel should change (different entries).
    const internetEntries = hash(await shot(page, 285, 85, 440, 120));
    expect(internetEntries).not.toBe(generalEntries);

    // Click Recycle Bin (empty group).
    await page.mouse.click(VAULT.group.recycleBin.x, VAULT.group.recycleBin.y);
    await sleep(500);

    const recycleBinEntries = hash(await shot(page, 285, 85, 440, 120));
    expect(recycleBinEntries).not.toBe(internetEntries);

    // Go back to General for next tests.
    await page.mouse.click(VAULT.group.general.x, VAULT.group.general.y);
    await sleep(500);
  });

  // -------------------------------------------------------------------------
  // 5. Entry selection and detail view
  // -------------------------------------------------------------------------

  it('clicking an entry shows detail panel', async () => {
    // Detail panel should show "Select an entry..." placeholder initially.
    const detailBefore = hash(await shot(page, 750, 300, 450, 300));

    // Click first entry (Sample Entry #2).
    await page.mouse.click(VAULT.entry.first.x, VAULT.entry.first.y);
    await sleep(1000);

    // Detail panel must change — now shows entry fields.
    const detailAfter = hash(await shot(page, 750, 300, 450, 300));
    expect(detailAfter).not.toBe(detailBefore);
  });

  it('selecting a different entry updates detail panel', async () => {
    // Capture detail with first entry selected.
    const firstDetail = hash(await shot(page, 750, 300, 450, 300));

    // Click second entry (Sample Entry #3).
    await page.mouse.click(VAULT.entry.second.x, VAULT.entry.second.y);
    await sleep(1000);

    // Detail panel must change — different entry data.
    const secondDetail = hash(await shot(page, 750, 300, 450, 300));
    expect(secondDetail).not.toBe(firstDetail);
  });

  it('entry detail shows fields (username, password, url)', async () => {
    // With an entry selected, the detail panel (right third of screen)
    // should have content in multiple vertical sections: title area,
    // username field, password field, URL field.
    // Sample strips at different vertical positions in the detail panel.
    const titleArea = await shot(page, 770, 340, 380, 30);
    const usernameArea = await shot(page, 770, 440, 380, 50);
    const passwordArea = await shot(page, 770, 520, 380, 50);
    const urlArea = await shot(page, 770, 600, 380, 50);

    // All four areas should have content (not blank).
    const blank = await shot(page, 770, 800, 380, 50);
    const blankHash = hash(blank);

    expect(hash(titleArea)).not.toBe(blankHash);
    expect(hash(usernameArea)).not.toBe(blankHash);
    expect(hash(passwordArea)).not.toBe(blankHash);
    expect(hash(urlArea)).not.toBe(blankHash);
  });

  // -------------------------------------------------------------------------
  // 6. Search
  // -------------------------------------------------------------------------

  it('can search entries across groups', async () => {
    // Capture entry list before search.
    const beforeSearch = hash(await shot(page, 285, 85, 440, 200));

    // Click search box and type a query.
    await page.mouse.click(VAULT.searchBox.x, VAULT.searchBox.y);
    await sleep(500);
    await page.keyboard.type('asdf', { delay: 50 });
    await sleep(1000);

    // Entry list should change to show search results.
    const afterSearch = hash(await shot(page, 285, 85, 440, 200));
    expect(afterSearch).not.toBe(beforeSearch);

    // Clear search — select all and delete.
    await page.keyboard.down('Control');
    await page.keyboard.press('a');
    await page.keyboard.up('Control');
    await page.keyboard.press('Backspace');
    await sleep(500);

    // Click General to reset view.
    await page.mouse.click(VAULT.group.general.x, VAULT.group.general.y);
    await sleep(500);
  });

  // -------------------------------------------------------------------------
  // 7. Lock and re-unlock
  // -------------------------------------------------------------------------

  it('locks vault and returns to lock screen', async () => {
    const beforeLock = hash(await page.screenshot({ encoding: 'binary' }));

    await page.mouse.click(VAULT.lockBtn.x, VAULT.lockBtn.y);
    await sleep(2000);

    const afterLock = hash(await page.screenshot({ encoding: 'binary' }));
    expect(afterLock).not.toBe(beforeLock);
  });

  it('re-unlocks from lock screen with pre-filled filename', async () => {
    // Lock screen pre-fills the filename — just need password.
    await page.mouse.click(UNLOCK.passwordField.x, UNLOCK.passwordField.y);
    await sleep(500);
    await page.keyboard.type(TEST_PASSWORD, { delay: 30 });
    await page.keyboard.press('Enter');
    await sleep(12000);

    // Should be back on vault screen with entries.
    const after = hash(await page.screenshot({ encoding: 'binary' }));
    expect(after).not.toBe(unlockScreenHash);
  }, 30000);

  // -------------------------------------------------------------------------
  // 8. Error check
  // -------------------------------------------------------------------------

  it('had no critical console errors during the flow', () => {
    const critical = consoleErrors.filter(
      (e) =>
        !e.includes('DevTools') &&
        !e.includes('favicon') &&
        !e.includes('Manifest') &&
        !e.includes('service worker') &&
        !e.includes('Service Worker')
    );
    if (critical.length > 0) {
      console.log('Console errors:', critical);
    }
    expect(critical).toEqual([]);
  });
});

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
