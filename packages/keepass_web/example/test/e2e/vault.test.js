const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');

const BUILD_PATH = path.resolve(__dirname, '../../build/web');
const TEST_DB = path.resolve(__dirname, 'fixtures/test_with_entries.kdbx');
const TEST_PASSWORD = 'demopass';
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
    await clickAccessibilityNode(page, client, 'Internet', { role: 'button' });

    const internetState = await waitForAccessibility(
      page,
      ({ text }) => !text.includes('Sample Entry #2'),
      { timeout: 10000 },
    );
    expect(internetState.text).not.toContain('Sample Entry #2');

    await clickAccessibilityNode(page, client, 'General', { role: 'group' });
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
