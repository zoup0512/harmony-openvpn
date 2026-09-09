/* Run with node entry/src/test/vpn-logs.cjs. Loads production ETS, not copied logic. */
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.TYPESCRIPT_PATH || 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../main/ets');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'vpn-log-tests-'));
const locks = new Set();
let failIO = false;
const adapter = {
  OpenMode: { READ_WRITE: 1, CREATE: 2 },
  accessSync: fs.existsSync,
  statSync: fs.statSync,
  readTextSync: p => fs.readFileSync(p, 'utf8'),
  openSync: p => {
    if (failIO) throw Error('permission denied');
    return { p, held: false, tryLock() {
      if (locks.has(p)) throw Error('lock busy');
      locks.add(p); this.held = true;
    }};
  },
  closeSync: f => { if (f.held) locks.delete(f.p); }
};
function runtime(extraStubs = {}) {
  const cache = new Map();
  const stubs = {
    '@ohos.file.fs': { default: adapter },
    '@ohos.hilog': { default: { info() {}, warn() {}, error() {}, debug() {} } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => require('node:crypto').randomUUID() } },
    '../common/FileUtil': { FileUtil: { writeTextAtomic(p, text) {
      if (failIO) throw Error('permission denied');
      fs.writeFileSync(p + '.tmp', text); fs.renameSync(p + '.tmp', p);
    }, writeText: (p, t) => fs.writeFileSync(p, t) } },
    './VpnTrafficStore': { VpnTrafficStore: { recordSample() {} } }
  };
  function load(name, parent = root) {
    if (extraStubs[name]) return extraStubs[name];
    if (stubs[name]) return stubs[name];
    const file = path.resolve(parent, name) + '.ets';
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} }; cache.set(file, module);
    const source = fs.readFileSync(file, 'utf8');
    const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020 } }).outputText;
    vm.runInThisContext('(function(require,module,exports){' + code + '\n})', { filename: file })(
      n => load(n, path.dirname(file)), module, module.exports);
    return module.exports;
  }
  return { status: load('./core/VpnStatus').VpnStatus, load };
}
let checks = 0;
function test(name, fn) { fn(); checks++; console.log('PASS ' + name); }
(async () => {
try {
  const writer = runtime(), ui = runtime();
  const { LogItem, LogLevel } = writer.load('./core/LogItem');
  const ctx = { filesDir: temp };
  fs.writeFileSync(path.join(temp, 'vpn_status_snapshot.json'), JSON.stringify({ timestamp: 1,
    connectedVPNProfile: 'A', logs: [{ level: 2, message: 'legacy\tline\\n\n中文', logtime: 1 }] }));
  writer.status.setPersistenceContext(ctx);
  ui.status.setPersistenceContext(ctx);
  const a1 = writer.status.beginLogSession('A');
  a1.logMessage(LogLevel.INFO, 'A1');
  const b1 = writer.status.beginLogSession('B');
  b1.logMessage(LogLevel.INFO, 'B1');
  const a2 = writer.status.beginLogSession('A');
  a2.logMessage(LogLevel.INFO, 'A2');
  test('two profiles / multiple sessions / latest session', () => {
    assert.deepEqual(writer.status.getlogbuffer('A').map(e => e.message), ['A2']);
    assert.equal(writer.status.getLogSessions('A').length, 2);
    assert.equal(writer.status.getlogbuffer('B')[0].message, 'B1');
  });
  test('late closure keeps original ownership; stale state cannot replace current state', () => {
    a2.updateStateString('CONNECTED', 'A2 connected');
    a1.logMessage(LogLevel.INFO, 'late A1');
    b1.updateStateString('AUTH_FAILED', 'late B1 failure');
    assert.equal(writer.status.lastState, 'CONNECTED');
    assert(writer.status.getlogbuffer('A', a1.identity.sessionId).some(e => e.message === 'late A1'));
    assert(!writer.status.getlogbuffer('A').some(e => e.message === 'late A1'));
    assert(writer.status.getlogbuffer('B').some(e => e.message.includes('late B1 failure')));
  });
  test('legacy snapshot survives stale timestamp, without inferred profile ownership', () => {
    const legacy = writer.status.getlogbuffer().find(e => e.message.startsWith('legacy'));
    assert.equal(legacy.profileUuid, ''); assert.equal(legacy.sessionId, '');
    const half = LogItem.fromJson({ profileUuid: 'A', message: 'no session' });
    assert.equal(half.profileUuid, '');
  });
  test('UI clear isolates profile and writer reload does not resurrect cleared entries', () => {
    ui.status.restoreFromSnapshot();
    assert(ui.status.clearLog('A'));
    a2.logMessage(LogLevel.INFO, 'after clear');
    ui.status.restoreFromSnapshot();
    assert.deepEqual(ui.status.getlogbuffer('A').map(e => e.message), ['after clear']);
    assert.equal(ui.status.getlogbuffer('A', a1.identity.sessionId).length, 0);
    assert(ui.status.getlogbuffer('B').length > 0);
    assert(ui.status.getlogbuffer().some(e => e.message.startsWith('legacy')));
  });
  test('running clear preserves latest identity even when older callback arrives', () => {
    assert(ui.status.clearLog('A'));
    a1.logMessage(LogLevel.INFO, 'late after clear');
    ui.status.restoreFromSnapshot();
    assert.equal(ui.status.getlogbuffer('A').length, 0);
    a2.logMessage(LogLevel.INFO, 'still running');
    assert.equal(writer.status.getlogbuffer('A')[0].message, 'still running');
  });
  test('serialize / fresh-process reload preserves Unicode, escapes and history', () => {
    a2.logMessage(LogLevel.INFO, '中文\tvalue\\n\nsecond line');
    const fresh = runtime(); fresh.status.setPersistenceContext(ctx);
    assert.deepEqual(fresh.status.getlogbuffer().map(e => e.toJson()), writer.status.getlogbuffer().map(e => e.toJson()));
    assert.equal(fresh.status.getLogSessions('A').length, 2);
  });
  test('global diagnostics API remains compatible and global clear persists', () => {
    writer.status.logMessage(LogLevel.INFO, 'global');
    assert.equal(writer.status.getlogbuffer().find(e => e.message === 'global').profileUuid, '');
    assert(ui.status.clearLog());
    writer.status.restoreFromSnapshot(); assert.equal(writer.status.getlogbuffer().length, 0);
  });
  test('lock contention and permissions never throw into VPN and clear reports failure', () => {
    locks.add(path.join(temp, 'vpn_logs.lock').replace(/\\/g, '/'));
    // production uses a forward slash appended to the supplied directory
    locks.add(temp + '/vpn_logs.lock');
    assert.equal(writer.status.clearLog('A'), false);
    assert.doesNotThrow(() => a2.logMessage(LogLevel.INFO, 'busy'));
    locks.clear(); failIO = true;
    assert.equal(ui.status.clearLog('B'), false);
    assert.doesNotThrow(() => a2.updateStateString('CONNECTED', 'connected despite IO'));
    failIO = false;
  });
  test('actual per-session logger redacts password, OTP and cookie values', () => {
    a2.protectSecrets(['secret-password', '928174', 'raw-cookie']);
    a2.logMessage(LogLevel.INFO, 'secret-password 928174 raw-cookie');
    a2.logMessage(LogLevel.INFO, 'CRV1:credential');
    const text = writer.status.getlogbuffer('A').map(e => e.message).join('\n');
    for (const value of ['secret-password', '928174', 'raw-cookie', 'CRV1:credential']) assert(!text.includes(value));
  });
  test('bounded retention uses production archive and bounds message length', () => {
    const { VpnLogArchive, VpnLogIdentity } = writer.load('./core/VpnLogArchive');
    const archive = new VpnLogArchive();
    for (let i = 0; i < 100; i++) archive.begin(new VpnLogIdentity('A', 's' + i, i));
    for (let i = 0; i < 2100; i++) archive.append(new LogItem(LogLevel.INFO, 'x'.repeat(5000)));
    assert.equal(archive.sessions.length, 64); assert.equal(archive.entries.length, 2000);
    assert.equal(archive.entries[0].message.length, 4096);
    assert.equal(VpnLogArchive.parse(archive.serialize()).entries.length, 2000);
  });
  const callbacks = [];
  const core = runtime({
    '@ohos.net.vpnExtension': { default: { createVpnConnection: () => ({
      protectProcessNet: async () => {}, destroy: async () => {}
    }) } },
    'libovpnexec.so': { attach: cb => callbacks.push(cb), startTunnel: () => ({ ok: true }),
      stopTunnel() {}, getTunStats: () => ({ ok: false }) },
    '../core/AuthChallenge': { AuthChallengeManager: { clear() {} } },
    '../vpn/VpnController': { VpnController: { clearPendingAuthChallenge() {} } }
  });
  core.status.setPersistenceContext(ctx);
  const { OvpnEngine, EngineOptions } = core.load('./vpnservice/OvpnEngine');
  const oldLogger = core.status.beginLogSession('engine-A');
  const oldEngine = new OvpnEngine({}, oldLogger);
  await oldEngine.start(new EngineOptions());
  await oldEngine.stop();
  const newLogger = core.status.beginLogSession('engine-B');
  const newEngine = new OvpnEngine({}, newLogger);
  try {
    await newEngine.start(new EngineOptions());
    callbacks[1]({ type: 'event', name: 'CONNECTED', info: 'B connected' });
    callbacks[0]({ type: 'log', name: '', info: 'old native callback' });
    callbacks[0]({ type: 'done', name: 'ok', info: 'old done' });
    test('actual OvpnEngine attach closures preserve late Native ownership and state', () => {
      assert.equal(core.status.lastState, 'CONNECTED');
      assert(core.status.getlogbuffer('engine-A').some(e => e.message.includes('old native callback')));
      assert(!core.status.getlogbuffer('engine-B').some(e => e.message.includes('old native callback')));
    });
  } finally { await newEngine.stop(); }
  console.log(`${checks} production-code regression tests passed`);
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
