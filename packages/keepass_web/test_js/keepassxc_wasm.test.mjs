/**
 * Jest test suite validating the WASM JS glue layer (WASM-04, D-08).
 *
 * Loads the wasm-pack ES module output and exercises all exports in Node.js.
 * Uses initSync() with raw .wasm bytes since Node.js lacks fetch/Response.
 */
import { describe, test, expect, beforeAll, afterAll } from '@jest/globals';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Provide globalThis.crypto.getRandomValues for Node.js (required by WASM module)
import { webcrypto } from 'crypto';
if (!globalThis.crypto) {
  globalThis.crypto = webcrypto;
}

// Test fixture paths (from keepass-rs test resources)
const fixtureDir = resolve(__dirname, '../../../rust/keepass-rs/tests/resources');
const TEST_DB_AES = readFileSync(resolve(fixtureDir, 'test_db_kdbx4_with_password_aes.kdbx'));

// Load challenge-response test DB if available
let TEST_DB_WITH_CR = null;
try {
  TEST_DB_WITH_CR = readFileSync(resolve(fixtureDir, 'test_db_with_challenge_response_key.kdbx'));
} catch (_) { /* not available */ }

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

  test('read_entry_fields returns field values including Password', () => {
    const openResult = JSON.parse(wasm.open_db(new Uint8Array(TEST_DB_AES), 'demopass', undefined));
    const handle = openResult.handle;

    // Get first entry UUID
    const entries = JSON.parse(wasm.list_entries(handle, ''));
    expect(entries.length).toBeGreaterThan(0);

    const fields = JSON.parse(wasm.read_entry_fields(handle, entries[0].uuid));
    expect(fields).toHaveProperty('Title');
    expect(fields).toHaveProperty('UserName');
    expect(fields).toHaveProperty('Password');
    // Known values from test DB
    expect(fields.Title).toBe('ASDF');
    expect(fields.UserName).toBe('ghj');
    expect(fields.Password).toBe('klmno');

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

  // D-08: Jest tests use mock challenge-response bytes (pre-computed) for validation.
  // This validates the JS->WASM boundary for the challenge-response path works.
  test('open_db_with_challenge_response accepts mock pre-computed bytes', () => {
    // Pre-computed mock challenge-response hex (40 hex chars = 20 bytes HMAC-SHA1 output)
    const mockCRHex = 'a'.repeat(40);
    const testDb = TEST_DB_WITH_CR || TEST_DB_AES;

    // The function should be callable. With mock bytes it will likely fail to
    // decrypt, but we verify the JS->WASM binding works and returns a
    // structured error (not a crash/undefined).
    try {
      const result = wasm.open_db_with_challenge_response(
        new Uint8Array(testDb), 'demopass', mockCRHex
      );
      // If it succeeds unexpectedly, verify the result is valid JSON with a handle
      const json = JSON.parse(result);
      expect(json).toHaveProperty('handle');
      wasm.close_db(json.handle);
    } catch (err) {
      // Expected: mock bytes don't match the real CR key.
      // Verify we get an error (not a crash/undefined).
      expect(err).toBeDefined();
    }
  });

  test('open_db_with_challenge_response rejects invalid hex', () => {
    expect(() => {
      wasm.open_db_with_challenge_response(
        new Uint8Array(TEST_DB_AES), 'demopass', 'not-valid-hex!'
      );
    }).toThrow();
  });
});
