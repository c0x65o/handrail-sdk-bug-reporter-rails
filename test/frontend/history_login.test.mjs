import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHistoryFixtureLogin } from '../browser/history_login.fixture.mjs';
import { hashHistoryAccount, seedHistoryFixture } from '../browser/history_credentials.fixture.mjs';

async function fixture(t, accounts) {
  let time = Date.now();
  const login = createHistoryFixtureLogin(accounts.map(hashHistoryAccount), { now: () => time });
  const server = createServer(async (req, res) => {
    try {
      if (await login(req, res, new URL(req.url, 'http://test').pathname)) return;
      res.writeHead(200).end(req.historyFixtureIdentity || 'public');
    } catch { res.writeHead(400).end('Invalid fixture request'); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const request = (path, options = {}) => fetch(origin + path, { redirect: 'manual', ...options });
  const prepare = async () => {
    const r = await request('/login');
    const cookie = r.headers.get('set-cookie');
    assert.match(cookie, /HttpOnly; SameSite=Strict/);
    const html = await r.text();
    assert.match(html, /type="password"/);
    return { cookie: cookie.split(';')[0], csrf: html.match(/name="csrf" value="([a-f0-9]+)"/)[1] };
  };
  const post = (path, session, fields) => request(path, { method: 'POST',
    headers: { cookie: session.cookie, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ csrf: session.csrf, ...fields }) });
  return { request, prepare, post, advance: ms => { time += ms; } };
}

test('private fixture login: real password, rotated HttpOnly session, CSRF, two accounts, expiry and revocation', async t => {
  const accounts = ['alice', 'bob'].map(identity => ({ login: `qa-history-${identity}`, identity, password: randomBytes(24).toString('base64url') }));
  const f = await fixture(t, accounts);
  assert.equal((await f.request('/history-fixture')).status, 303);
  assert.equal((await f.request('/history-fixture.js')).status, 401);
  assert.equal((await f.request('/fixture-session')).status, 401);
  for (const account of accounts) {
    const pre = await f.prepare();
    assert.equal((await f.post('/login', pre, { username: account.login, password: account.password, csrf: 'invalid' })).status, 403);
    assert.equal((await f.post('/login', pre, { username: account.login, password: 'invalid' })).status, 401);
    const logged = await f.post('/login', pre, { username: account.login, password: account.password });
    assert.equal(logged.status, 303);
    const cookie = logged.headers.get('set-cookie').split(';')[0];
    assert.notEqual(cookie, pre.cookie);
    assert.equal((await f.request('/fixture-session', { headers: { cookie: pre.cookie } })).status, 401);
    const session = await (await f.request('/fixture-session', { headers: { cookie } })).json();
    assert.equal(session.identity, account.identity);
    assert.equal(session.authenticated, true);
    assert.equal(session.boundary, 'outer-fixture-login-only');
    assert.equal(await (await f.request('/history-fixture.js', { headers: { cookie } })).text(), account.identity);
    assert.ok(!JSON.stringify(session).includes(account.password));
    assert.equal((await f.post('/fixture-session', { cookie, csrf: 'invalid' }, { action: 'logout' })).status, 403);
    assert.equal((await f.post('/fixture-session', { cookie, csrf: session.csrf }, { action: 'logout' })).status, 200);
    assert.equal((await f.request('/fixture-session', { headers: { cookie } })).status, 401);
  }
  const pre = await f.prepare();
  const r = await f.post('/login', pre, { username: accounts[0].login, password: accounts[0].password });
  const cookie = r.headers.get('set-cookie').split(';')[0];
  f.advance(30 * 60_000 + 1);
  assert.equal((await f.request('/fixture-session', { headers: { cookie } })).status, 401);
});

test('fixture login fails closed without private setup and rate limits at 10 per minute', async t => {
  const empty = await fixture(t, []);
  assert.equal((await empty.request('/login')).status, 401);
  const f = await fixture(t, [{ login: 'qa-history-alice', password: randomBytes(24).toString('hex'), identity: 'alice' }]);
  const pre = await f.prepare();
  for (let i = 0; i < 10; i++) assert.equal((await f.post('/login', pre, { username: 'unknown', password: 'invalid' })).status, 401);
  assert.equal((await f.post('/login', pre, {})).status, 429);
  f.advance(60_001);
  assert.equal((await f.post('/login', pre, {})).status, 401);
});

test('existing style service protects history and serves the published asset after login', async t => {
  const { startStyleFixture } = await import('../browser/reporter_style.fixture.mjs');
  const { sha256 } = await import('../../scripts/contract.mjs');
  const account = { login: 'qa-history-bob', password: randomBytes(24).toString('hex'), identity: 'bob' };
  const stateDirectory = mkdtempSync(join(tmpdir(), 'history-service-'));
  t.after(() => rmSync(stateDirectory, { recursive: true, force: true }));
  let service = await startStyleFixture(0, { stateDirectory });
  t.after(() => service.close());
  const request = (path, options = {}) => fetch(service.origin + path, { redirect: 'manual', ...options });
  assert.equal((await request('/history-fixture')).status, 303);
  assert.equal((await request('/login')).status, 401);
  await service.close();
  seedHistoryFixture({ directory: stateDirectory, env: { HANDRAIL_QA_LOGIN: account.login,
    HANDRAIL_QA_PASSWORD: account.password, HANDRAIL_TASK_PARAM_PERSONA: account.identity } });
  service = await startStyleFixture(0, { stateDirectory });
  const pre = await request('/login');
  const cookie = pre.headers.get('set-cookie').split(';')[0];
  const csrf = (await pre.text()).match(/name="csrf" value="([a-f0-9]+)"/)[1];
  const login = await request('/login', { method: 'POST', headers: { cookie, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ username: account.login, password: account.password, csrf }) });
  assert.equal(login.status, 303);
  const headers = { cookie: login.headers.get('set-cookie').split(';')[0] };
  assert.match(await (await request('/history-fixture', { headers })).text(), /Synthetic Rails SDK fixture/);
  assert.match(await (await request('/history-fixture.js', { headers })).text(), /identity: 'bob'/);
  const bytes = Buffer.from(await (await request('/javascripts/handrail_bug_reporter.js')).arrayBuffer());
  assert.equal(sha256(bytes), '984be06291a23733f596e76de16b97c328a71ffeaa20ef9b33cba241723a7f0e');
  assert.deepEqual(service.unexpected, []);
  // Restart reloads persistent hashes; old in-memory sessions do not survive.
  await service.close();
  service = await startStyleFixture(0, { stateDirectory });
  assert.equal((await request('/fixture-session', { headers })).status, 401);
  const again = await request('/login');
  const againCookie = again.headers.get('set-cookie').split(';')[0];
  const againCsrf = (await again.text()).match(/name="csrf" value="([a-f0-9]+)"/)[1];
  const relogin = await request('/login', { method: 'POST',
    headers: { cookie: againCookie, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ username: account.login, password: account.password, csrf: againCsrf }) });
  assert.equal(relogin.status, 303);
  const currentCookie = relogin.headers.get('set-cookie').split(';')[0];
  const current = await (await request('/fixture-session', { headers: { cookie: currentCookie } })).json();
  assert.equal(current.identity, 'bob');
  assert.equal((await request('/fixture-session', { method: 'POST',
    headers: { cookie: currentCookie, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ action: 'logout', csrf: current.csrf }) })).status, 200);
  assert.equal((await request('/fixture-session', { headers: { cookie: currentCookie } })).status, 401);
});
