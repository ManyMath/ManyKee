// Web Worker entry point: loads keepassxc WASM module and bridges postMessage RPC.
//
// Protocol (D-09):
//   Request:  { id: number, method: string, params: any[] }
//   Response: { id: number, result: string }  (result is JSON string from WASM)
//   Error:    { id: number, error: { code: string, message: string } }
//   Progress: { type: 'progress', percent: number }  (-1 = indeterminate)
//   Ready:    { type: 'ready' }

import init, * as wasm from './pkg/keepassxc_wasm.js';

async function initialize() {
  await init();
  self.postMessage({ type: 'ready' });
}

// Map of method names to WASM function references.
// Params are spread as positional arguments matching wasm_bindgen signatures.
const methods = {
  'version':                        (params) => wasm.version(),
  'open_db':                        (params) => wasm.open_db(params[0], params[1], params[2] || undefined),
  'open_db_with_challenge_response':(params) => wasm.open_db_with_challenge_response(params[0], params[1], params[2]),
  'close_db':                       (params) => { wasm.close_db(params[0]); return '{}'; },
  'list_groups':                    (params) => wasm.list_groups(params[0], params[1]),
  'list_entries':                   (params) => wasm.list_entries(params[0], params[1]),
  'read_entry_fields':              (params) => wasm.read_entry_fields(params[0], params[1]),
  'merge_databases':                (params) => wasm.merge_databases(params[0], params[1]),
  'extract_challenge':              (params) => wasm.extract_challenge(params[0]),
};

self.onmessage = async (e) => {
  const { id, method, params } = e.data;

  // Send indeterminate progress for open_db operations (Argon2 KDF)
  // Per Pitfall 5: rust-argon2 has no progress callback, so we signal
  // "started" before and "complete" after.
  const isOpenOp = method.startsWith('open_db');
  if (isOpenOp) {
    self.postMessage({ type: 'progress', percent: -1 });
  }

  try {
    const handler = methods[method];
    if (!handler) {
      self.postMessage({
        id,
        error: { code: 'UNKNOWN_METHOD', message: `Unknown method: ${method}` }
      });
      return;
    }

    const result = handler(params);
    self.postMessage({ id, result });
  } catch (err) {
    // WASM errors from wasm_bindgen come as strings or Error objects.
    // Try to parse as JSON (our structured error format from D-11).
    let error;
    const errMsg = err.message || String(err);
    try {
      error = JSON.parse(errMsg);
    } catch (_) {
      error = { code: 'WASM_ERROR', message: errMsg };
    }
    self.postMessage({ id, error });
  } finally {
    if (isOpenOp) {
      self.postMessage({ type: 'progress', percent: 100 });
    }
  }
};

initialize().catch((err) => {
  self.postMessage({
    type: 'error',
    error: { code: 'INIT_FAILED', message: err.message || String(err) }
  });
});
