const fs = require('fs');
const vm = require('vm');
const path = require('path');
const code = fs.readFileSync(path.join(__dirname, '..', 'server', 'db_bridge.js'), 'utf8');
const handlers = {};
const emitted = [];
let mode = 'success';
const oxmysql = {
  query_async: async (sql, params, resource) => {
    if (mode === 'fail') throw new Error('synthetic query failure');
    return [{ sql, params, resource }];
  },
  single_async: async (sql, params, resource) => ({ sql, params, resource }),
  scalar_async: async () => 1,
  insert_async: async () => 42,
  update_async: async () => 3,
  transaction_async: async () => {
    if (mode === 'txfail') throw new Error('synthetic tx failure');
    return true;
  }
};
const context = {
  console,
  setTimeout,
  Promise,
  GetConvar: () => '0',
  GetCurrentResourceName: () => 'nexm_core',
  global: { exports: { oxmysql } },
  on: (name, fn) => { handlers[name] = fn; },
  emit: (name, payload) => { emitted.push({ name, payload }); }
};
vm.createContext(context);
vm.runInContext(code, context, { filename: 'db_bridge.js' });
const requestEvent = 'nexm_core:internal:db:request:v2';
const wait = () => new Promise((resolve) => setTimeout(resolve, 15));
(async () => {
  let pass = 0;
  handlers[requestEvent]({ requestId:'1', token:'t1', operation:'query', owner:'fw', sql:'SELECT 1', params:['x'] });
  await wait(); let x = emitted.shift(); if (!x?.payload?.ok || !Array.isArray(x.payload.result)) throw new Error('query success'); pass++;
  mode='fail'; handlers[requestEvent]({ requestId:'2', token:'t2', operation:'query', owner:'fw', sql:'BAD', params:[] });
  await wait(); x = emitted.shift(); if (x?.payload?.ok !== false || !String(x.payload.error).includes('synthetic query failure')) throw new Error('query error'); pass++;
  mode='success'; handlers[requestEvent]({ requestId:'3', token:'t3', operation:'transaction', owner:'fw', queries:[{query:'SELECT 1',values:[]}], params:[] });
  await wait(); x = emitted.shift(); if (x?.payload?.ok !== true || x.payload.result !== true) throw new Error('transaction success'); pass++;
  handlers[requestEvent]({ requestId:'4', token:'t4', operation:'evil', owner:'fw' });
  await wait(); x = emitted.shift(); if (x?.payload?.ok !== false) throw new Error('invalid operation'); pass++;
  console.log(`RESULT tests=${pass} pass=${pass} fail=0`);
})().catch((e) => { console.error(e); process.exit(1); });
