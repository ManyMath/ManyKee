import init, * as wasm from './pkg/keepassxc_wasm.js';

async function initialize() {
  await init();
  self.postMessage({ type: 'ready' });
}

const methods = {
  'version': (params) => wasm.version(),
  'open_db': (params) => wasm.open_db(params[0], params[1], params[2] || undefined),
  'open_db_with_challenge_response':(params) => wasm.open_db_with_challenge_response(params[0], params[1], params[2]),
  'close_db': (params) => { wasm.close_db(params[0]); return '{}'; },
  'list_groups': (params) => wasm.list_groups(params[0], params[1]),
  'list_entries': (params) => wasm.list_entries(params[0], params[1]),
  'read_entry_fields': (params) => wasm.read_entry_fields(params[0], params[1]),
  'read_entry_field': (params) => wasm.read_entry_field(params[0], params[1], params[2]),
  'get_totp': (params) => wasm.get_totp(params[0], params[1]),
  'create_entry': (params) => wasm.create_entry(params[0], params[1], params[2] || ''),
  'set_entry_field': (params) => wasm.set_entry_field(params[0], params[1], params[2], params[3], params[4] || false),
  'delete_entry': (params) => { wasm.delete_entry(params[0], params[1]); return '{}'; },
  'move_entry': (params) => { wasm.move_entry(params[0], params[1], params[2]); return '{}'; },
  'create_group': (params) => wasm.create_group(params[0], params[1], params[2]),
  'rename_group': (params) => { wasm.rename_group(params[0], params[1], params[2]); return '{}'; },
  'delete_group': (params) => { wasm.delete_group(params[0], params[1]); return '{}'; },
  'move_group': (params) => { wasm.move_group(params[0], params[1], params[2]); return '{}'; },
  'save_db': (params) => wasm.save_db(params[0], params[1], params[2] || undefined),
  'merge_databases': (params) => wasm.merge_databases(params[0], params[1]),
  'extract_challenge': (params) => wasm.extract_challenge(params[0]),
};

self.onmessage = async (e) => {
  const { id, method, params } = e.data;

  if (typeof method !== 'string') {
    self.postMessage({
      id,
      error: { code: 'INVALID_REQUEST', message: `Invalid or missing method: ${method}` }
    });
    return;
  }

  const isOpenOp = method.startsWith('open_db');
  if (isOpenOp) {
    self.postMessage({ id, type: 'progress', percent: -1 });
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
      self.postMessage({ id, type: 'progress', percent: 100 });
    }
  }
};

initialize().catch((err) => {
  self.postMessage({
    type: 'error',
    error: { code: 'INIT_FAILED', message: err.message || String(err) }
  });
});
