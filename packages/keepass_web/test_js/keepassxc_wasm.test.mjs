/**
 * Jest test suite validating the WASM JS glue layer (WASM-04, D-08).
 *
 * Loads the wasm-pack ES module output and exercises all exports in Node.js.
 * Uses initSync() with raw .wasm bytes since Node.js lacks fetch/Response.
 */
import { describe, test, expect, beforeAll, afterAll } from '@jest/globals';
import { existsSync, readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Provide globalThis.crypto.getRandomValues for Node.js (required by WASM module)
import { createHmac, webcrypto } from 'crypto';
if (!globalThis.crypto) {
  globalThis.crypto = webcrypto;
}

// Test fixture paths (from keepass-rs test resources)
const fixtureDir = resolve(__dirname, '../../../rust/keepass-rs/tests/resources');
const TEST_DB_AES = readFileSync(resolve(fixtureDir, 'test_db_kdbx4_with_password_aes.kdbx'));

// Challenge-response fixture and the HMAC-SHA1 secret its YubiKey slot was
// programmed with; see open_kdbx4_with_challenge_response_key in
// rust/keepass-rs/tests/file_read_tests.rs.
const TEST_DB_WITH_CR = readFileSync(resolve(fixtureDir, 'test_db_with_challenge_response_key.kdbx'));
const TEST_CR_PASSWORD = 'demopass';
const TEST_CR_SECRET_HEX = '0102030405060708090a0b0c0d0e0f1011121314';

/** Runs fn, expects it to throw, and returns the parsed {code, message}. */
function structuredError(fn) {
  let thrown;
  try {
    fn();
  } catch (err) {
    thrown = err;
  }
  if (thrown === undefined) {
    throw new Error('expected the call to throw');
  }
  const raw = typeof thrown === 'string' ? thrown : thrown.message;
  return JSON.parse(raw);
}

// WASM module reference, initialized in beforeAll
let wasm;

describe('keepassxc-wasm JS module', () => {
  beforeAll(async () => {
    // Load the wasm-pack ES module
    const wasmModule = await import(resolve(__dirname, '../web/pkg/keepassxc_wasm.js'));

    // Load .wasm bytes and initialize synchronously (Node.js has no fetch)
    const wasmBytes = readFileSync(resolve(__dirname, '../web/pkg/keepassxc_wasm_bg.wasm'));
    wasmModule.initSync({ module: wasmBytes });

    wasm = wasmModule;
  });

  test('version() returns a non-empty string', () => {
    const v = wasm.version();
    expect(typeof v).toBe('string');
    expect(v.length).toBeGreaterThan(0);
  });

  test('create_db returns a handle for a fresh empty database', () => {
    const result = wasm.create_db();
    const json = JSON.parse(result);
    expect(json).toHaveProperty('handle');
    expect(typeof json.handle).toBe('number');

    const groups = JSON.parse(wasm.list_groups(json.handle, ''));
    expect(groups).toEqual([]);

    wasm.close_db(json.handle);
  });

  test('create_db output can be saved and reopened', () => {
    const created = JSON.parse(wasm.create_db());
    const hex = wasm.save_db(created.handle, 'a-new-password', undefined);
    wasm.close_db(created.handle);

    const bytes = new Uint8Array(hex.match(/.{1,2}/g).map((b) => parseInt(b, 16)));
    const reopened = JSON.parse(wasm.open_db(bytes, 'a-new-password', undefined));
    expect(typeof reopened.handle).toBe('number');
    wasm.close_db(reopened.handle);
  });

  test('open_db returns a handle for valid KDBX', () => {
    const result = wasm.open_db(new Uint8Array(TEST_DB_AES), 'demopass', undefined);
    const json = JSON.parse(result);
    expect(json).toHaveProperty('handle');
    expect(typeof json.handle).toBe('number');
    // Clean up
    wasm.close_db(json.handle);
  });

  test('open_db throws for wrong password', () => {
    expect(() => {
      wasm.open_db(new Uint8Array(TEST_DB_AES), 'wrongpass', undefined);
    }).toThrow();
  });

  test('open_db throws for invalid bytes', () => {
    expect(() => {
      wasm.open_db(new Uint8Array([0, 1, 2, 3]), 'demopass', undefined);
    }).toThrow();
  });

  test('list_groups returns JSON array for root group', () => {
    const openResult = JSON.parse(wasm.open_db(new Uint8Array(TEST_DB_AES), 'demopass', undefined));
    const handle = openResult.handle;

    const groupsJson = wasm.list_groups(handle, '');
    const groups = JSON.parse(groupsJson);
    expect(Array.isArray(groups)).toBe(true);

    wasm.close_db(handle);
  });

  test('list_entries returns JSON array with entry fields', () => {
    const openResult = JSON.parse(wasm.open_db(new Uint8Array(TEST_DB_AES), 'demopass', undefined));
    const handle = openResult.handle;

    const entriesJson = wasm.list_entries(handle, '');
    const entries = JSON.parse(entriesJson);
    expect(Array.isArray(entries)).toBe(true);
    expect(entries.length).toBeGreaterThan(0);
    expect(entries[0]).toHaveProperty('uuid');
    expect(entries[0]).toHaveProperty('title');
    expect(entries[0]).toHaveProperty('username');
    expect(entries[0]).toHaveProperty('url');

    wasm.close_db(handle);
  });

  test('read_entry_fields returns field values and protected metadata', () => {
    const openResult = JSON.parse(wasm.open_db(new Uint8Array(TEST_DB_AES), 'demopass', undefined));
    const handle = openResult.handle;

    // Get first entry UUID
    const entries = JSON.parse(wasm.list_entries(handle, ''));
    expect(entries.length).toBeGreaterThan(0);

    const fields = JSON.parse(wasm.read_entry_fields(handle, entries[0].uuid));
    expect(fields).toHaveProperty('fields');
    expect(fields).toHaveProperty('protected');
    expect(fields.fields).toHaveProperty('Title');
    expect(fields.fields).toHaveProperty('UserName');
    expect(fields.fields).toHaveProperty('Password');
    // Known values from test DB
    expect(fields.fields.Title).toBe('ASDF');
    expect(fields.fields.UserName).toBe('ghj');
    expect(fields.fields.Password).toBe('');
    expect(fields.protected.Password).toBe(true);

    const password = wasm.read_entry_field(handle, entries[0].uuid, 'Password');
    expect(password).toBe('klmno');

    wasm.close_db(handle);
  });

  test('close_db invalidates handle', () => {
    const openResult = JSON.parse(wasm.open_db(new Uint8Array(TEST_DB_AES), 'demopass', undefined));
    const handle = openResult.handle;
    wasm.close_db(handle);

    expect(() => {
      wasm.list_groups(handle, '');
    }).toThrow();
  });

  test('invalid handle throws structured error', () => {
    expect(() => {
      wasm.list_groups(99999, '');
    }).toThrow();
  });

  test('open_db_with_challenge_response opens the fixture with the real response', () => {
    const challengeHex = wasm.extract_challenge(new Uint8Array(TEST_DB_WITH_CR));
    expect(challengeHex).toMatch(/^[0-9a-f]{64}$/);

    // What the programmed YubiKey slot would answer.
    const responseHex = createHmac('sha1', Buffer.from(TEST_CR_SECRET_HEX, 'hex'))
      .update(Buffer.from(challengeHex, 'hex'))
      .digest('hex');

    const { handle } = JSON.parse(
      wasm.open_db_with_challenge_response(
        new Uint8Array(TEST_DB_WITH_CR), TEST_CR_PASSWORD, responseHex
      )
    );
    try {
      const entries = JSON.parse(wasm.list_entries(handle, ''));
      expect(entries).toHaveLength(2);
    } finally {
      wasm.close_db(handle);
    }
  });

  test('open_db_with_challenge_response rejects a wrong response', () => {
    const error = structuredError(() =>
      wasm.open_db_with_challenge_response(
        new Uint8Array(TEST_DB_WITH_CR), TEST_CR_PASSWORD, 'a'.repeat(40)
      )
    );
    expect(error.code).toMatch(/^OPEN_ERROR$/);
    expect(typeof error.message).toBe('string');
  });

  test('open_db_with_challenge_response rejects invalid hex', () => {
    const error = structuredError(() =>
      wasm.open_db_with_challenge_response(
        new Uint8Array(TEST_DB_AES), 'demopass', 'not-valid-hex!'
      )
    );
    expect(error.code).toMatch(/^PARSE_ERROR$/);
    expect(error.message).toMatch(/Invalid hex in challenge_response/);
  });
});

//: Cross-surface smoke for the official KeePassXC 2.7.12
// fixtures via the WASM JS glue. Canonical password matches
// `rust/keepassxc/tests/bidirectional_parity.rs::FIXTURE_PASSWORD`.
const OFFICIAL_FIXTURE_DIR = resolve(
  __dirname,
  '../../../fixtures/compat/official/keepassxc/2.7.12'
);
const OFFICIAL_FIXTURE_PASSWORD = 'manykee-fixture-password';
const wasmPkgJs = resolve(__dirname, '../web/pkg/keepassxc_wasm.js');
const wasmPkgBg = resolve(__dirname, '../web/pkg/keepassxc_wasm_bg.wasm');
const officialBasic = resolve(OFFICIAL_FIXTURE_DIR, 'keepassxc-password-basic.kdbx');
const officialRichcontent = resolve(OFFICIAL_FIXTURE_DIR, 'keepassxc-richcontent.kdbx');

const wasmPkgPresent = existsSync(wasmPkgJs) && existsSync(wasmPkgBg);
const officialBasicPresent = existsSync(officialBasic);
const officialRichcontentPresent = existsSync(officialRichcontent);

const requireOfficial = process.env.MANYKEE_REQUIRE_OFFICIAL_TOOLS === '1';
const officialSkipReason = !wasmPkgPresent
  ? `skipped: WASM pkg missing under ${dirname(wasmPkgJs)}: run \`wasm-pack build rust/keepassxc-wasm --target web --out-dir ../../packages/keepass_web/web/pkg\``
  : !officialBasicPresent
    ? `skipped: official fixture missing at ${officialBasic}`
    : null;

if (requireOfficial && officialSkipReason !== null) {
  throw new Error(`MANYKEE_REQUIRE_OFFICIAL_TOOLS=1 but ${officialSkipReason}`);
}

const officialDescribe = officialSkipReason === null ? describe : describe.skip;

officialDescribe('keepassxc-wasm official KeePassXC 2.7.12 fixtures', () => {
  let officialWasm;

  beforeAll(async () => {
    const wasmModule = await import(wasmPkgJs);
    const wasmBytes = readFileSync(wasmPkgBg);
    wasmModule.initSync({ module: wasmBytes });
    officialWasm = wasmModule;
  });

  test('keepassxc-password-basic.kdbx opens and lists entries', () => {
    const db = readFileSync(officialBasic);
    const openResult = officialWasm.open_db(
      new Uint8Array(db),
      OFFICIAL_FIXTURE_PASSWORD,
      undefined
    );
    const handle = JSON.parse(openResult).handle;
    try {
      const entries = JSON.parse(officialWasm.list_entries(handle, ''));
      const groups = JSON.parse(officialWasm.list_groups(handle, ''));
      expect(Array.isArray(entries)).toBe(true);
      expect(Array.isArray(groups)).toBe(true);
      expect(entries.length + groups.length).toBeGreaterThan(0);
    } finally {
      officialWasm.close_db(handle);
    }
  });

  (officialRichcontentPresent ? test : test.skip)(
    'keepassxc-richcontent.kdbx opens and lists entries',
    () => {
      const db = readFileSync(officialRichcontent);
      const openResult = officialWasm.open_db(
        new Uint8Array(db),
        OFFICIAL_FIXTURE_PASSWORD,
        undefined
      );
      const handle = JSON.parse(openResult).handle;
      try {
        const entries = JSON.parse(officialWasm.list_entries(handle, ''));
        const groups = JSON.parse(officialWasm.list_groups(handle, ''));
        expect(Array.isArray(entries)).toBe(true);
        expect(Array.isArray(groups)).toBe(true);
        expect(entries.length + groups.length).toBeGreaterThan(0);
      } finally {
        officialWasm.close_db(handle);
      }
    }
  );
});

if (officialSkipReason !== null) {
  // Surface the skip reason in test output so maintainers know why the
  // official-fixture suite was bypassed.
  // eslint-disable-next-line no-console
  console.warn(`[official-fixture-suite] ${officialSkipReason}`);
}
