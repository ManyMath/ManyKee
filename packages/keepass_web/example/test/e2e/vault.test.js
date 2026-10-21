const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');

const BUILD_PATH = path.resolve(__dirname, '../../build/web');
const TEST_DB = path.resolve(__dirname, 'fixtures/test_with_entries.kdbx');
const TEST_PASSWORD = 'demopass';
const RICH_TEST_DB = path.resolve(
  __dirname,
  '../../../../../apps/native/integration_test/fixtures/test_db_kdbx4_richcontent.kdbx',
);
const RICH_TEST_PASSWORD = 'testpass123';
const DOWNLOAD_DIR = path.resolve(__dirname, '.downloads');
const HEADLESS_MODE = process.env.HEADFUL === '1' ? false : 'new';
const SEMANTICS_QUERY = '?e2e_semantics=1';

function hash(buf) {
  return crypto.createHash('md5').update(buf).digest('hex');
}

async function shot(page, x, y, w, h) {
  return page.screenshot({ clip: { x, y, width: w, height: h }, encoding: 'binary' });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function contentType(filePath) {
  switch (path.extname(filePath)) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.wasm':
      return 'application/wasm';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.png':
      return 'image/png';
    case '.svg':
      return 'image/svg+xml';
    case '.ico':
      return 'image/x-icon';
    default:
      return 'application/octet-stream';
  }
}

function createStaticServer(rootDir) {
  return http.createServer((req, res) => {
    const requestUrl = new URL(req.url, 'http://127.0.0.1');
    let pathname = decodeURIComponent(requestUrl.pathname);
    if (pathname === '/') {
      pathname = '/index.html';
    }

    const normalized = path.normalize(path.join(rootDir, pathname));
    if (!normalized.startsWith(rootDir)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    let filePath = normalized;
    if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
      filePath = path.join(rootDir, 'index.html');
    }

    fs.readFile(filePath, (error, data) => {
      if (error) {
        res.writeHead(404);
        res.end('Not found');
        return;
      }

      res.writeHead(200, { 'Content-Type': contentType(filePath) });
      res.end(data);
    });
  });
}

function flattenAccessibility(node, out = []) {
  if (!node) {
    return out;
  }

  out.push(node);
  for (const child of node.children || []) {
    flattenAccessibility(child, out);
  }
  return out;
}

function findNodeInSnapshot(node, matcher, role) {
  if (!node) {
    return null;
  }
  if ((!role || node.role === role) && matchesName(node.name, matcher)) {
    return node;
  }
  for (const child of node.children || []) {
    const match = findNodeInSnapshot(child, matcher, role);
    if (match) {
      return match;
    }
  }
  return null;
}

function nodeHasDescendant(node, matcher, role) {
  if (!node) {
    return false;
  }
  for (const child of node.children || []) {
    if ((!role || child.role === role) && matchesName(child.name, matcher)) {
      return true;
    }
    if (nodeHasDescendant(child, matcher, role)) {
      return true;
    }
  }
  return false;
}

function matchesName(value, matcher) {
  if (!value) {
    return false;
  }
  if (matcher instanceof RegExp) {
    return matcher.test(value);
  }
  return value === matcher;
}

function findAccessibilityNode(nodes, matcher, role) {
  return nodes.find(
    (node) =>
      (!role || node.role === role) &&
      matchesName(node.name, matcher),
  );
}

function findAccessibilityNodes(nodes, matcher, role) {
  return nodes.filter(
    (node) =>
      (!role || node.role === role) &&
      matchesName(node.name, matcher),
  );
}

async function waitForAccessibility(page, predicate, options = {}) {
  const timeout = options.timeout ?? 15000;
  const interval = options.interval ?? 250;
  const deadline = Date.now() + timeout;

  while (Date.now() < deadline) {
    const snapshot = await page.accessibility.snapshot({ interestingOnly: false });
    const nodes = flattenAccessibility(snapshot);
    const text = JSON.stringify(snapshot);
    if (predicate({ snapshot, nodes, text })) {
      return { snapshot, nodes, text };
    }
    await sleep(interval);
  }

  throw new Error('Timed out waiting for accessibility state');
}

async function getNodeCenter(client, backendNodeId) {
  const box = await client.send('DOM.getBoxModel', { backendNodeId });
  const xs = [
    box.model.content[0],
    box.model.content[2],
    box.model.content[4],
    box.model.content[6],
  ];
  const ys = [
    box.model.content[1],
    box.model.content[3],
    box.model.content[5],
    box.model.content[7],
  ];

  return {
    x: (Math.min(...xs) + Math.max(...xs)) / 2,
    y: (Math.min(...ys) + Math.max(...ys)) / 2,
  };
}

async function clickAccessibilityNode(page, client, matcher, options = {}) {
  const role = options.role;
  const timeout = options.timeout ?? 15000;
  const { nodes } = await waitForAccessibility(
    page,
    ({ nodes: current }) => !!findAccessibilityNode(current, matcher, role),
    { timeout },
  );
  const node = findAccessibilityNode(nodes, matcher, role);
  const center = await getNodeCenter(client, node.backendNodeId);
  await page.mouse.click(center.x, center.y);
  return node;
}

async function clickNamedNode(page, client, matcher, options = {}) {
  const roles = options.roles ?? null;
  const index = options.index ?? 0;
  const timeout = options.timeout ?? 15000;
  const { nodes } = await waitForAccessibility(
    page,
    ({ nodes: current }) => {
      const candidates = current.filter(
        (node) =>
          (!roles || roles.includes(node.role)) &&
          matchesName(node.name, matcher),
      );
      return candidates.length > index;
    },
    { timeout },
  );
  const candidates = nodes.filter(
    (node) =>
      (!roles || roles.includes(node.role)) &&
      matchesName(node.name, matcher),
  );
  const node = candidates[index];
  const center = await getNodeCenter(client, node.backendNodeId);
  await page.mouse.click(center.x, center.y);
  return node;
}

async function typeIntoTextbox(page, client, name, value) {
  await clickAccessibilityNode(page, client, name, { role: 'textbox' });
  await sleep(200);
  await page.keyboard.down('Control');
  await page.keyboard.press('a');
  await page.keyboard.up('Control');
  await page.keyboard.press('Backspace');
  if (value.length > 0) {
    await page.keyboard.type(value, { delay: 30 });
  }
}

async function openVault(page, client, baseUrl, options = {}) {
  const dbPath = options.dbPath ?? TEST_DB;
  const password = options.password ?? TEST_PASSWORD;
  const expectedText = options.expectedText ?? null;

  await page.goto('about:blank');
  await page.goto(baseUrl, { waitUntil: 'networkidle2' });
  await page.evaluate(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
  });
  await page.reload({ waitUntil: 'networkidle2' });
  await page.waitForSelector('flt-glass-pane', { timeout: 30000 });
  await waitForAccessibility(
    page,
    ({ nodes }) =>
      !!findAccessibilityNode(nodes, 'Choose KDBX File', 'button') &&
      !!findAccessibilityNode(nodes, 'Master Password', 'textbox') &&
      !!findAccessibilityNode(nodes, 'Unlock Vault', 'button'),
  );

  const chooserPromise = page.waitForFileChooser({ timeout: 10000 });
  await clickAccessibilityNode(page, client, 'Choose KDBX File', {
    role: 'button',
  });
  const chooser = await chooserPromise;
  await chooser.accept([dbPath]);

  await waitForAccessibility(
    page,
    ({ text }) => text.includes(path.basename(dbPath)),
    { timeout: 10000 },
  );

  await typeIntoTextbox(page, client, 'Master Password', password);
  await clickAccessibilityNode(page, client, 'Unlock Vault', {
    role: 'button',
  });

  return waitForAccessibility(
    page,
    ({ nodes, text }) =>
      !!findAccessibilityNode(nodes, 'Lock Vault', 'button') &&
      !!findAccessibilityNode(nodes, 'Search entries...', 'textbox') &&
      (!expectedText || text.includes(expectedText)),
    { timeout: 45000, interval: 500 },
  );
}

function clearDownloadDirectory() {
  fs.rmSync(DOWNLOAD_DIR, { recursive: true, force: true });
  fs.mkdirSync(DOWNLOAD_DIR, { recursive: true });
}

async function waitForDownloadedFile(matcher = /\.kdbx$/) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const names = fs
      .readdirSync(DOWNLOAD_DIR, { withFileTypes: true })
      .filter((entry) => entry.isFile())
      .map((entry) => entry.name)
      .filter((name) => matcher.test(name) && !name.endsWith('.crdownload'));
    if (names.length > 0) {
      names.sort(
        (left, right) =>
          fs.statSync(path.join(DOWNLOAD_DIR, right)).mtimeMs -
          fs.statSync(path.join(DOWNLOAD_DIR, left)).mtimeMs,
      );
      return path.join(DOWNLOAD_DIR, names[0]);
    }
    await sleep(250);
  }

  throw new Error('Timed out waiting for downloaded KDBX file');
}

async function installDownloadCapture(page) {
  await page.evaluate(() => {
    window.__manykeeDownloads = [];
    window.__manykeeBlobBytes = {};
    if (window.__manykeeDownloadPatched) {
      return;
    }

    window.__manykeeDownloadPatched = true;
    const originalCreateObjectURL = URL.createObjectURL;
    URL.createObjectURL = function patchedCreateObjectURL(blob) {
      const url = originalCreateObjectURL.call(this, blob);
      blob.arrayBuffer().then((buffer) => {
        window.__manykeeBlobBytes[url] = Array.from(new Uint8Array(buffer));
      });
      return url;
    };
    const originalClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function patchedClick() {
      if (this.download && this.href && this.href.startsWith('blob:')) {
        const name = this.download;
        const href = this.href;
        const bytes = window.__manykeeBlobBytes[href];
        if (bytes) {
          window.__manykeeDownloads.push({ name, bytes });
        }
      }
      return originalClick.call(this);
    };
  });
}

async function waitForCapturedDownload(page) {
  await page.waitForFunction(
    () =>
      Array.isArray(window.__manykeeDownloads) &&
      window.__manykeeDownloads.length > 0,
    { timeout: 30000 },
  );
  const payload = await page.evaluate(() => window.__manykeeDownloads.shift());
  const filePath = path.join(DOWNLOAD_DIR, payload.name);
  fs.writeFileSync(filePath, Buffer.from(payload.bytes));
  return filePath;
}

async function waitForSavedArtifact(page) {
  await page.waitForFunction(
    () =>
      window.sessionStorage.getItem('manykee_last_download_name') &&
      window.sessionStorage.getItem('manykee_last_download_bytes'),
    { timeout: 30000 },
  );
  const payload = await page.evaluate(() => ({
    name: window.sessionStorage.getItem('manykee_last_download_name'),
    bytes: window.sessionStorage.getItem('manykee_last_download_bytes'),
  }));
  const filePath = path.join(DOWNLOAD_DIR, payload.name);
  fs.writeFileSync(filePath, Buffer.from(payload.bytes, 'base64'));
  return filePath;
}

async function saveAndReopenCurrentVault(
  page,
  client,
  baseUrl,
  password,
  expectedText,
) {
  clearDownloadDirectory();
  await clickNamedNode(page, client, 'Save Vault', { roles: ['button'] });
  await waitForAccessibility(
    page,
    ({ text }) => text.includes('Confirm master password'),
  );
  await typeIntoTextbox(page, client, 'Master password', password);
  await clickNamedNode(page, client, 'Confirm', { roles: ['button'] });
  const saveState = await waitForAccessibility(
    page,
    ({ text }) =>
      text.includes('Vault saved') || text.includes('Could not save vault'),
    { timeout: 30000, interval: 500 },
  );
  if (saveState.text.includes('Could not save vault')) {
    throw new Error(`Save failed: ${saveState.text}`);
  }

  const downloadedPath = await waitForSavedArtifact(page);
  const reopenedState = await openVault(page, client, baseUrl, {
    dbPath: downloadedPath,
    password,
    expectedText,
  });
  return { downloadedPath, reopenedState };
}

async function clickGroupActions(page, client, groupName) {
  const { nodes } = await waitForAccessibility(
    page,
    ({ nodes: current }) =>
      !!findAccessibilityNode(current, groupName) &&
      findAccessibilityNodes(current, 'Group actions', 'button').length > 0,
  );

  const labelNode =
    findAccessibilityNode(nodes, groupName, 'button') ||
    findAccessibilityNode(nodes, groupName, 'group') ||
    findAccessibilityNode(nodes, groupName);
  const labelCenter = await getNodeCenter(client, labelNode.backendNodeId);
  const actionNodes = findAccessibilityNodes(nodes, 'Group actions', 'button');

  let bestMatch = null;
  for (const actionNode of actionNodes) {
    const center = await getNodeCenter(client, actionNode.backendNodeId);
    const isToRight = center.x > labelCenter.x;
    const verticalDistance = Math.abs(center.y - labelCenter.y);
    if (!bestMatch) {
      bestMatch = { center, isToRight, verticalDistance };
      continue;
    }
    if (isToRight && !bestMatch.isToRight) {
      bestMatch = { center, isToRight, verticalDistance };
      continue;
    }
    if (isToRight === bestMatch.isToRight &&
        verticalDistance < bestMatch.verticalDistance) {
      bestMatch = { center, isToRight, verticalDistance };
    }
  }

  if (!bestMatch) {
    throw new Error(`Could not find Group actions button for ${groupName}`);
  }

  await page.mouse.click(bestMatch.center.x, bestMatch.center.y);
}

async function selectDropdownOption(page, client, label, optionText) {
  await clickNamedNode(page, client, label, {
    roles: ['button', 'combobox', 'group', 'text'],
  });
  await clickNamedNode(page, client, optionText, {
    roles: ['menuitem', 'option', 'button', 'group', 'text'],
  });
}

async function openSettings(page, client) {
  await clickNamedNode(page, client, 'Settings', { roles: ['button'] });
  return waitForAccessibility(
    page,
    ({ nodes, text }) =>
      !!findAccessibilityNode(nodes, /Clipboard auto-clear/) &&
      !!findAccessibilityNode(nodes, /Paste-once clipboard/) &&
      text.includes('Biometric unlock') &&
      text.includes('Autofill'),
    { timeout: 10000 },
  );
}

describe('ManyKee Standalone Web Vault', () => {
  let server;
  let baseUrl;
  let browser;
  let page;
  let client;
  const consoleErrors = [];
  let unlockScreenHash;

  beforeAll(async () => {
    if (!fs.existsSync(BUILD_PATH)) {
      throw new Error(
        `Web build not found at: ${BUILD_PATH}\n` +
          'Run: bash scripts/build_extension.sh',
      );
    }

    server = createStaticServer(BUILD_PATH);
    await new Promise((resolve) => {
      server.listen(0, '127.0.0.1', resolve);
    });

    const address = server.address();
    baseUrl = `http://127.0.0.1:${address.port}/${SEMANTICS_QUERY}`;

    browser = await puppeteer.launch({
      headless: HEADLESS_MODE,
      executablePath: process.env.CHROME_PATH || undefined,
      downloadBehavior: {
        policy: 'allow',
        downloadPath: DOWNLOAD_DIR,
      },
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--window-size=1280,1024',
        '--force-renderer-accessibility',
      ],
      defaultViewport: { width: 1280, height: 1024 },
    });
    if (typeof browser.defaultBrowserContext().setDownloadBehavior === 'function') {
      await browser.defaultBrowserContext().setDownloadBehavior({
        policy: 'allow',
        downloadPath: DOWNLOAD_DIR,
      });
    }

    clearDownloadDirectory();
    page = await browser.newPage();
    client = await page.target().createCDPSession();
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });
  }, 120000);

  afterAll(async () => {
    if (browser) {
      await browser.close();
    }
    if (server) {
      await new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    }
  });

  it('loads the standalone web app and renders Flutter', async () => {
    await page.goto(baseUrl, { waitUntil: 'networkidle2' });
    await page.waitForSelector('flt-glass-pane', { timeout: 15000 });
    await waitForAccessibility(
      page,
      ({ nodes }) =>
        !!findAccessibilityNode(nodes, 'Choose KDBX File', 'button') &&
        !!findAccessibilityNode(nodes, 'Master Password', 'textbox') &&
        !!findAccessibilityNode(nodes, 'Unlock Vault', 'button'),
    );

    unlockScreenHash = hash(await page.screenshot({ encoding: 'binary' }));
  });

  it('uploads a KDBX file via file picker', async () => {
    const chooserPromise = page.waitForFileChooser({ timeout: 10000 });
    await clickAccessibilityNode(page, client, 'Choose KDBX File', {
      role: 'button',
    });
    const chooser = await chooserPromise;
    await chooser.accept([TEST_DB]);

    await waitForAccessibility(
      page,
      ({ text }) => text.includes('test_with_entries.kdbx'),
      { timeout: 10000 },
    );
  });

  it('enters password and unlocks vault', async () => {
    await typeIntoTextbox(page, client, 'Master Password', TEST_PASSWORD);
    await clickAccessibilityNode(page, client, 'Unlock Vault', {
      role: 'button',
    });

    const { text } = await waitForAccessibility(
      page,
      ({ nodes, text }) =>
        !!findAccessibilityNode(nodes, 'Lock Vault', 'button') &&
        !!findAccessibilityNode(nodes, 'Search entries...', 'textbox') &&
        text.includes('Sample Entry #2'),
      { timeout: 30000, interval: 500 },
    );

    const after = hash(await page.screenshot({ encoding: 'binary' }));
    expect(after).not.toBe(unlockScreenHash);
    expect(text).toContain('General');
  }, 30000);

  it('shows the three-panel vault layout', async () => {
    const leftOfDivider = await shot(page, 270, 60, 4, 80);
    const divider = await shot(page, 279, 60, 2, 80);
    const rightOfDivider = await shot(page, 284, 60, 4, 80);

    const dividerIsVisible =
      hash(divider) !== hash(leftOfDivider) ||
      hash(divider) !== hash(rightOfDivider);
    expect(dividerIsVisible).toBe(true);
  });

  it('can switch groups and entry list updates', async () => {
    await clickNamedNode(page, client, 'Internet', {
      roles: ['button', 'group', 'text'],
    });

    const internetState = await waitForAccessibility(
      page,
      ({ text }) => !text.includes('Sample Entry #2'),
      { timeout: 10000 },
    );
    expect(internetState.text).not.toContain('Sample Entry #2');

    await clickNamedNode(page, client, 'General', {
      roles: ['button', 'group', 'text'],
    });
    const generalState = await waitForAccessibility(
      page,
      ({ text }) => text.includes('Sample Entry #2'),
      { timeout: 10000 },
    );
    expect(generalState.text).toContain('Sample Entry #2');
  });

  it('clicking an entry shows detail panel', async () => {
    const detailBefore = hash(await shot(page, 750, 300, 450, 300));

    await clickAccessibilityNode(page, client, /Sample Entry #2/, {
      role: 'group',
    });

    const detailState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('Username') &&
        text.includes('Password') &&
        text.includes('URL'),
      { timeout: 10000 },
    );
    const detailAfter = hash(await shot(page, 750, 300, 450, 300));

    expect(detailAfter).not.toBe(detailBefore);
    expect(detailState.text).toContain('Username');
    expect(detailState.text).toContain('Password');
    expect(detailState.text).toContain('URL');
  });

  it('selecting a different entry updates detail panel', async () => {
    await clickAccessibilityNode(page, client, /Sample Entry #2/, {
      role: 'group',
    });
    await waitForAccessibility(
      page,
      ({ text }) => text.includes('Sample Entry #2'),
      { timeout: 10000 },
    );
    const firstDetail = hash(await shot(page, 750, 300, 450, 300));

    await clickAccessibilityNode(page, client, /Sample Entry #3/, {
      role: 'group',
    });
    const secondState = await waitForAccessibility(
      page,
      ({ text }) => text.includes('Sample Entry #3'),
      { timeout: 10000 },
    );
    const secondDetail = hash(await shot(page, 750, 300, 450, 300));

    expect(secondDetail).not.toBe(firstDetail);
    expect(secondState.text).toContain('Sample Entry #3');
  });

  it('can search entries across groups', async () => {
    await typeIntoTextbox(page, client, 'Search entries...', '3210');

    const filteredState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('Sample Entry #3') &&
        !text.includes('Sample Entry #2'),
      { timeout: 10000 },
    );
    expect(filteredState.text).toContain('Sample Entry #3');
    expect(filteredState.text).not.toContain('Sample Entry #2');

    await typeIntoTextbox(page, client, 'Search entries...', '');
    const restoredState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('Sample Entry #2') &&
        text.includes('Sample Entry #3'),
      { timeout: 10000 },
    );
    expect(restoredState.text).toContain('Sample Entry #2');
    expect(restoredState.text).toContain('Sample Entry #3');
  });

  it('locks vault and returns to lock screen', async () => {
    const beforeLock = hash(await page.screenshot({ encoding: 'binary' }));

    await clickAccessibilityNode(page, client, 'Lock Vault', {
      role: 'button',
    });

    const lockState = await waitForAccessibility(
      page,
      ({ nodes, text }) =>
        !!findAccessibilityNode(nodes, 'Unlock Vault', 'button') &&
        !!findAccessibilityNode(nodes, 'Master Password', 'textbox') &&
        text.includes('test_with_entries.kdbx'),
      { timeout: 10000 },
    );
    const afterLock = hash(await page.screenshot({ encoding: 'binary' }));

    expect(afterLock).not.toBe(beforeLock);
    expect(lockState.text).toContain('test_with_entries.kdbx');
  });

  it('re-unlocks after locking the standalone vault', async () => {
    const relockState = await openVault(page, client, baseUrl, {
      expectedText: 'Sample Entry #2',
    });
    expect(relockState.text).toContain('Search entries...');
  }, 60000);

  it('shows web settings for clipboard and stub-provider parity', async () => {
    await openVault(page, client, baseUrl, { expectedText: 'Sample Entry #2' });

    const settingsState = await openSettings(page, client);
    expect(settingsState.text).toContain('Clipboard auto-clear');
    expect(settingsState.text).toContain('Paste-once clipboard');
    expect(settingsState.text).toContain('not supported on this platform');
    expect(settingsState.text).toContain('coming soon');

    await selectDropdownOption(
      page,
      client,
      /Clipboard auto-clear.*30 seconds/,
      '10 seconds',
    );
    await clickNamedNode(page, client, /Paste-once clipboard/, {
      roles: ['switch', 'checkbox', 'button', 'group', 'text'],
    });
    await clickNamedNode(page, client, 'Back', { roles: ['button'] });

    await waitForAccessibility(
      page,
      ({ nodes }) =>
        !!findAccessibilityNode(nodes, 'Search entries...', 'textbox'),
      { timeout: 10000 },
    );

    await clickAccessibilityNode(page, client, /Sample Entry #2/, {
      role: 'group',
    });
    await clickNamedNode(page, client, 'Copy username', { roles: ['button'] });
    const copyState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('Copied. Clears in 10s or when you return to the app.'),
      { timeout: 10000 },
    );
    expect(copyState.text).toContain(
      'Copied. Clears in 10s or when you return to the app.',
    );
  });

  it('E2E-01: creates a new entry in the standalone web vault', async () => {
    await openVault(page, client, baseUrl, { expectedText: 'Sample Entry #2' });

    await clickNamedNode(page, client, 'New Entry', { roles: ['button'] });
    await typeIntoTextbox(page, client, 'Title', 'Web Created Entry');
    await typeIntoTextbox(page, client, 'Username', 'web-user');
    await typeIntoTextbox(page, client, 'Password', 'web-pass');
    await typeIntoTextbox(page, client, 'URL', 'https://created.example');
    await typeIntoTextbox(page, client, 'Notes', 'Created in Puppeteer');
    await clickNamedNode(page, client, 'Create Entry', { roles: ['button'] });

    const createdState = await waitForAccessibility(
      page,
      ({ text }) => text.includes('Web Created Entry'),
      { timeout: 10000 },
    );
    expect(createdState.text).toContain('Web Created Entry');
  });

  it('E2E-02: edits an entry and shows the updated values', async () => {
    await openVault(page, client, baseUrl, { expectedText: 'Sample Entry #2' });

    await clickAccessibilityNode(page, client, /Sample Entry #2/, {
      role: 'group',
    });
    await clickNamedNode(page, client, 'Edit Entry', { roles: ['button'] });
    await typeIntoTextbox(page, client, 'Title', 'Edited Web Entry');
    await typeIntoTextbox(page, client, 'URL', 'https://edited.example');
    await clickNamedNode(page, client, 'Save Entry', { roles: ['button'] });

    const editedState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('Edited Web Entry') &&
        text.includes('https://edited.example'),
      { timeout: 10000 },
    );
    expect(editedState.text).toContain('Edited Web Entry');
    expect(editedState.text).toContain('https://edited.example');
  });

  it('E2E-03: deletes an entry from the list', async () => {
    await openVault(page, client, baseUrl, { expectedText: 'Sample Entry #2' });

    await clickAccessibilityNode(page, client, /Sample Entry #3/, {
      role: 'group',
    });
    await clickNamedNode(page, client, 'Delete Entry', { roles: ['button'] });
    await clickNamedNode(page, client, 'Delete Entry', {
      roles: ['button', 'text'],
    });

    await waitForAccessibility(
      page,
      ({ nodes }) => !findAccessibilityNode(nodes, /Sample Entry #3/, 'group'),
      { timeout: 10000 },
    );
  });

  it('E2E-04: moves an entry to a different group', async () => {
    await openVault(page, client, baseUrl, { expectedText: 'Sample Entry #2' });

    await clickAccessibilityNode(page, client, /Sample Entry #2/, {
      role: 'group',
    });
    await clickNamedNode(page, client, 'Move Entry', { roles: ['button'] });
    await sleep(500);
    await page.keyboard.press('Tab');
    await page.keyboard.press('Space');
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    await clickNamedNode(page, client, 'Move Entry', {
      roles: ['button', 'text'],
    });

    await typeIntoTextbox(page, client, 'Search entries...', 'Sample Entry #2');
    const movedState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('Sample Entry #2') && text.includes('Internet'),
      { timeout: 10000 },
    );
    expect(movedState.text).toContain('Sample Entry #2');
    expect(movedState.text).toContain('Internet');
  });

  it('E2E-05: creates a subgroup in the sidebar', async () => {
    await openVault(page, client, baseUrl, {
      dbPath: RICH_TEST_DB,
      password: RICH_TEST_PASSWORD,
      expectedText: 'CustomFieldsEntry',
    });

    await clickGroupActions(page, client, 'Level1Group');
    await clickNamedNode(page, client, 'New Subgroup', {
      roles: ['menuitem', 'button', 'text'],
    });
    await typeIntoTextbox(page, client, 'Group name', 'Projects');
    await clickNamedNode(page, client, 'Create Group', { roles: ['button'] });

    const createdState = await waitForAccessibility(
      page,
      ({ text }) => text.includes('Projects'),
      { timeout: 10000 },
    );
    expect(createdState.text).toContain('Projects');

    const { reopenedState } = await saveAndReopenCurrentVault(
      page,
      client,
      baseUrl,
      RICH_TEST_PASSWORD,
      'Projects',
    );
    expect(reopenedState.text).toContain('Projects');
  });

  it('E2E-06: renames a group in the sidebar', async () => {
    await openVault(page, client, baseUrl, {
      dbPath: RICH_TEST_DB,
      password: RICH_TEST_PASSWORD,
      expectedText: 'CustomFieldsEntry',
    });

    await clickGroupActions(page, client, 'Level2Group');
    await clickNamedNode(page, client, 'Rename Group', {
      roles: ['menuitem', 'button', 'text'],
    });
    await typeIntoTextbox(page, client, 'Group name', 'Renamed Level2');
    await clickNamedNode(page, client, 'Save Group', { roles: ['button'] });

    const renamedState = await waitForAccessibility(
      page,
      ({ text }) => text.includes('Renamed Level2'),
      { timeout: 10000 },
    );
    expect(renamedState.text).toContain('Renamed Level2');

    const { reopenedState } = await saveAndReopenCurrentVault(
      page,
      client,
      baseUrl,
      RICH_TEST_PASSWORD,
      'Renamed Level2',
    );
    expect(reopenedState.text).toContain('Renamed Level2');
  });

  it('E2E-07: deletes a group from the sidebar', async () => {
    await openVault(page, client, baseUrl, {
      dbPath: RICH_TEST_DB,
      password: RICH_TEST_PASSWORD,
      expectedText: 'CustomFieldsEntry',
    });

    await clickGroupActions(page, client, 'Level2Group');
    await clickNamedNode(page, client, 'Delete Group', {
      roles: ['menuitem', 'button', 'text'],
    });
    await clickNamedNode(page, client, 'Delete Group', {
      roles: ['button', 'text'],
    });

    const deletedState = await waitForAccessibility(
      page,
      ({ text }) => !text.includes('Level2Group'),
      { timeout: 10000 },
    );
    expect(deletedState.text).not.toContain('Level2Group');

    const { reopenedState } = await saveAndReopenCurrentVault(
      page,
      client,
      baseUrl,
      RICH_TEST_PASSWORD,
      null,
    );
    expect(reopenedState.text).not.toContain('Level2Group');
  });

  it('E2E-08: saves a mutation and reopens the downloaded KDBX', async () => {
    clearDownloadDirectory();
    await openVault(page, client, baseUrl, {
      dbPath: RICH_TEST_DB,
      password: RICH_TEST_PASSWORD,
      expectedText: 'CustomFieldsEntry',
    });

    await clickNamedNode(page, client, 'New Entry', { roles: ['button'] });
    await typeIntoTextbox(page, client, 'Title', 'Persisted Web Entry');
    await typeIntoTextbox(page, client, 'Username', 'persisted-user');
    await typeIntoTextbox(page, client, 'Password', 'persisted-pass');
    await clickNamedNode(page, client, 'Create Entry', { roles: ['button'] });
    await waitForAccessibility(
      page,
      ({ text }) => text.includes('Persisted Web Entry'),
      { timeout: 10000 },
    );

    const { reopenedState } = await saveAndReopenCurrentVault(
      page,
      client,
      baseUrl,
      RICH_TEST_PASSWORD,
      'Persisted Web Entry',
    );
    expect(reopenedState.text).toContain('Persisted Web Entry');
  });

  it('persists a moved group after save and reopen', async () => {
    await openVault(page, client, baseUrl, {
      dbPath: RICH_TEST_DB,
      password: RICH_TEST_PASSWORD,
      expectedText: 'CustomFieldsEntry',
    });

    await clickGroupActions(page, client, 'Level1Group');
    await clickNamedNode(page, client, 'New Subgroup', {
      roles: ['menuitem', 'button', 'text'],
    });
    await typeIntoTextbox(page, client, 'Group name', 'Target Parent');
    await clickNamedNode(page, client, 'Create Group', { roles: ['button'] });
    await waitForAccessibility(
      page,
      ({ text }) => text.includes('Target Parent'),
      { timeout: 10000 },
    );

    await clickGroupActions(page, client, 'Level2Group');
    await clickNamedNode(page, client, 'Move Group', {
      roles: ['menuitem', 'button', 'text'],
    });
    await sleep(500);
    await page.keyboard.press('Tab');
    await page.keyboard.press('Space');
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    await clickNamedNode(page, client, 'Move Group', {
      roles: ['button', 'text'],
    });

    await waitForAccessibility(
      page,
      ({ text }) => text.includes('Target Parent'),
      { timeout: 10000 },
    );

    const { reopenedState } = await saveAndReopenCurrentVault(
      page,
      client,
      baseUrl,
      RICH_TEST_PASSWORD,
      'Target Parent',
    );
    expect(reopenedState.text).toContain('Target Parent');
    expect(reopenedState.text).toContain('Level2Group');
  });

  it('E2E-09: shows a live TOTP code for a real web fixture entry', async () => {
    await openVault(page, client, baseUrl, {
      dbPath: RICH_TEST_DB,
      password: RICH_TEST_PASSWORD,
      expectedText: 'CustomFieldsEntry',
    });

    await typeIntoTextbox(page, client, 'Search entries...', 'TOTPEntry');
    await waitForAccessibility(
      page,
      ({ text }) => text.includes('TOTPEntry'),
      { timeout: 10000 },
    );

    await clickNamedNode(page, client, /TOTPEntry/, {
      roles: ['button', 'group', 'text'],
    });
    const totpState = await waitForAccessibility(
      page,
      ({ text }) =>
        text.includes('One-Time Code') &&
        text.includes('Refreshes in '),
      { timeout: 30000, interval: 500 },
    );

    expect(totpState.text).toContain('One-Time Code');
    expect(totpState.text).toContain('Refreshes in ');
  });

  it('completes the standalone flow without critical console errors', () => {
    const critical = consoleErrors.filter(
      (error) =>
        !error.includes('DevTools') &&
        !error.includes('favicon') &&
        !error.includes('Manifest') &&
        !error.includes('service worker') &&
        !error.includes('Service Worker'),
    );

    if (critical.length > 0) {
      console.log('Console errors:', critical);
    }

    expect(critical).toEqual([]);
  });
});
