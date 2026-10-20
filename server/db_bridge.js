// NEXM Core internal DB bridge (hotfix.9)
//
// Purpose: keep oxmysql asynchronous callbacks/promises entirely in JavaScript.
// Lua never passes a callback function reference to oxmysql. Results cross back
// to Lua only as plain local-event data, removing the live CFX rawQuery callback
// function-reference boundary while preserving the NEXM.DB public API.

const REQUEST_EVENT = 'nexm_core:internal:db:request:v2';
const RESULT_EVENT = 'nexm_core:internal:db:result:v2';
const ALLOWED = new Set(['query', 'single', 'scalar', 'insert', 'update', 'transaction']);

function debugEnabled() {
  try {
    return Number(GetConvar('nexm_debug_migrations', '0')) === 1;
  } catch (_) {
    return false;
  }
}

function diag(stage, request, success) {
  if (!debugEnabled()) return;
  const operation = request && request.operation ? String(request.operation) : '<none>';
  const owner = request && request.owner ? String(request.owner) : '<none>';
  const id = request && request.requestId ? String(request.requestId) : '<none>';
  console.log(`[DB BRIDGE DIAG] stage=${stage} operation=${operation} owner=${owner} request=${id} success=${String(success)}`);
}

function safeError(error) {
  let message = 'Unknown database bridge error';
  if (error && typeof error.message === 'string') message = error.message;
  else if (typeof error === 'string') message = error;
  else if (error != null) message = String(error);
  if (message.length > 2048) message = message.slice(0, 2048);
  return message;
}

async function callOxmysql(request) {
  const operation = request.operation;
  const resource = GetCurrentResourceName();
  const ox = global.exports && global.exports.oxmysql;
  if (!ox) throw new Error('oxmysql exports are unavailable');

  const asyncName = `${operation}_async`;
  const method = ox[asyncName];
  if (typeof method !== 'function') {
    throw new Error(`oxmysql async export unavailable: ${asyncName}`);
  }

  if (operation === 'transaction') {
    if (!Array.isArray(request.queries)) throw new Error('transaction queries must be an array');
    return await method(request.queries, request.params || [], resource);
  }

  if (typeof request.sql !== 'string' || request.sql.length === 0) {
    throw new Error('database SQL must be a non-empty string');
  }
  return await method(request.sql, request.params || [], resource);
}

on(REQUEST_EVENT, (request) => {
  // The event callback never awaits. It validates synchronously, schedules the
  // async JS work, and returns to CFX immediately.
  if (!request || typeof request !== 'object') return;
  const requestId = request.requestId;
  const token = request.token;
  const operation = request.operation;

  if (typeof requestId !== 'string' || requestId.length === 0 || requestId.length > 256) return;
  if (typeof token !== 'string' || token.length === 0 || token.length > 512) return;
  if (typeof operation !== 'string' || !ALLOWED.has(operation)) {
    emit(RESULT_EVENT, {
      requestId,
      token,
      ok: false,
      error: 'Invalid database bridge operation',
    });
    return;
  }

  diag('request_received', request, undefined);

  Promise.resolve()
    .then(() => callOxmysql(request))
    .then((result) => {
      diag('oxmysql_resolved', request, true);
      // Defer the Lua result event one JS turn as well; the oxmysql async export
      // has fully unwound before Lua is resumed.
      setTimeout(() => {
        emit(RESULT_EVENT, { requestId, token, ok: true, result });
      }, 0);
    })
    .catch((error) => {
      const message = safeError(error);
      diag('oxmysql_rejected', request, false);
      setTimeout(() => {
        emit(RESULT_EVENT, { requestId, token, ok: false, error: message });
      }, 0);
    });
});
