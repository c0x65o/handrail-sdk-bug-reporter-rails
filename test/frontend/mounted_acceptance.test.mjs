import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { createBugReporter } from '@handrail/bug-reporter';
import { createSameOriginBugReporterHandler } from '@handrail/bug-reporter/server';

const origin = 'http://127.0.0.1';
const endpoint = '/fixture/api/mobile-bug-reports';
const operations = [['POST', ''], ['GET', '/policy'], ['GET', '/mine'],
  ['GET', '/bugs/bug-canonical.123'], ['POST', '/bugs/bug-canonical.123/subscription'],
  ['PUT', '/bugs/bug-canonical.123/archive'], ['DELETE', '/bugs/bug-canonical.123/archive'],
  ['POST', '/mine/archive-closed']];

async function host(t, scenario) {
  const child = spawn(process.env.RUBY || 'ruby', ['test/fixtures/workflow/rack_bridge.rb', scenario],
    { env: { ...process.env, BUNDLE_FROZEN: 'true' }, stdio: ['pipe', 'pipe', 'pipe'] });
  const lines = createInterface({ input: child.stdout })[Symbol.asyncIterator]();
  let errors = '', cookie = '', csrf = '', last;
  child.stderr.on('data', bytes => { errors += bytes; });
  t.after(async () => {
    child.stdin.end();
    const [code] = await once(child, 'exit');
    assert.equal(code, 0, errors);
  });
  async function request(method, path, body = '', extra = {}) {
    child.stdin.write(JSON.stringify({ method, path, body, headers: {
      'content-type': 'application/json', origin, cookie, 'x-csrf-token': csrf, ...extra } }) + '\n');
    const next = await lines.next();
    assert.equal(next.done, false, errors);
    last = JSON.parse(next.value);
    const setCookie = last.headers['set-cookie'];
    if (setCookie) cookie = (Array.isArray(setCookie) ? setCookie[0] : setCookie).split(';')[0];
    const token = last.body.match(/name="csrf-token" content="([^"]+)"/);
    if (token) csrf = token[1];
    assert.equal(last.audit.some(row => row.kind === 'fixture_error'), false);
    return last;
  }
  async function session(state) {
    const response = await request('POST', '/fixture-session', JSON.stringify({ state }));
    assert.equal(response.status, 200);
  }
  assert.equal((await request('GET', '/')).status, 200);
  return { request, session, audit: () => last.audit,
    fetch: async (url, init) => {
      const response = await request(init.method, url, init.body || '');
      return new Response([204, 205].includes(response.status) ? null : response.body,
        { status: response.status, headers: { 'content-type': 'application/json' } });
    } };
}

for (const [scenario, status, raw] of [['accepted_malformed', 201, 'accepted but not JSON'], ['accepted_empty', 204, null]]) {
  test(`JS client through mounted Rails: ${scenario} is submitted once`, async t => {
    const rails = await host(t, scenario);
    await rails.session('admin');
    const input = { title: 'Accepted report', description: 'Do not replay', eventId: 'accepted-browser-event',
      notification: { notifyOnResolution: true } };
    const config = { transport: 'same-origin', apiBaseUrl: endpoint, projectId: 'project-123',
      environment: 'staging', retry: { maxAttempts: 3, delayMs: 0 } };
    const result = await createBugReporter({ ...config, fetch: rails.fetch }).submit(input);
    let referenceCalls = 0;
    const handler = createSameOriginBugReporterHandler({ apiBaseUrl: 'https://upstream.example/api',
      projectId: 'project-123', environment: 'staging', reportToken: 'fixture-only', routeBasePath: endpoint,
      fetch: async () => { referenceCalls++; return new Response(raw, { status }); } });
    const reference = await createBugReporter({ ...config, fetch: (url, init) =>
      handler(new Request(origin + url, init)) }).submit(input);
    assert.deepEqual(result, reference);
    assert.equal(result.status, 'submitted');
    assert.equal(result.statusCode, status);
    assert.equal(result.response, null);
    assert.equal(result.bugId, null);
    assert.ok(result.notificationWarning);
    assert.equal(referenceCalls, 1);
    const calls = rails.audit().filter(row => row.kind === 'http');
    assert.equal(calls.length, 1);
    assert.equal(calls[0].body.event_id, 'accepted-browser-event');
  });
}

test('mounted Rails empty subscription preserves accepted parent and warns with one child call', async t => {
  const rails = await host(t, 'subscription_empty');
  await rails.session('admin');
  const result = await createBugReporter({ transport: 'same-origin', apiBaseUrl: endpoint,
    projectId: 'project-123', environment: 'staging', retry: { maxAttempts: 3, delayMs: 0 },
    fetch: rails.fetch }).submit({ title: 'Accepted report', description: 'Empty child',
    notification: { notifyOnResolution: true } });
  assert.equal(result.status, 'submitted');
  assert.equal(result.bugId, 'bug-canonical.123');
  assert.equal(result.notificationSubscription, null);
  assert.ok(result.notificationWarning);
  const calls = rails.audit().filter(row => row.kind === 'http');
  assert.deepEqual(calls.map(row => new URL(row.url).pathname),
    ['/api/mobile-bug-reports', '/api/mobile-bug-reports/bugs/bug-canonical.123/subscription']);
});

test('workflow admin, nonadmin, anonymous and revoked states gate all eight operations before identity/HTTP', async t => {
  const rails = await host(t, 'submission');
  const body = JSON.stringify({ title: 'Fixture', description: 'Fixture', reporter_notification: { notify_on_resolution: true } });
  for (const state of ['admin', 'nonadmin', 'anonymous', 'admin', 'revoked']) {
    await rails.session(state);
    const page = await rails.request('GET', '/');
    assert.equal(page.body.includes('data-handrail-bug-reporter="1"'), state === 'admin');
    assert.equal(page.body.includes('/javascripts/handrail_bug_reporter.js'), state === 'admin');
    for (const [method, path] of operations) {
      const before = rails.audit().filter(row => ['identity', 'http'].includes(row.kind)).length;
      const response = await rails.request(method, endpoint + path, body);
      assert.equal(response.status, state === 'admin' ? path === '' ? 201 : 200 : 403, `${state} ${method} ${path}`);
      if (state !== 'admin') assert.equal(JSON.parse(response.body).error, 'bug_reporting_forbidden');
      assert.equal(rails.audit().filter(row => ['identity', 'http'].includes(row.kind)).length - before, state === 'admin' ? 2 : 0);
    }
  }
});

test('frozen JS reference accepts empty and primitive success values with one upstream call', async () => {
  for (const [body, expected] of [[null, null], ['', null], ['malformed', null], ['false', false],
    ['true', true], ['42', 42], ['"accepted"', 'accepted'], ['[]', []], ['null', null]]) {
    let calls = 0;
    const handler = createSameOriginBugReporterHandler({ apiBaseUrl: 'https://upstream.example/api',
      projectId: 'project-123', environment: 'staging', reportToken: 'fixture-only',
      fetch: async () => { calls++; return new Response(body, { status: 202 }); } });
    const result = await createBugReporter({ transport: 'same-origin', apiBaseUrl: '/api/mobile-bug-reports',
      projectId: 'project-123', environment: 'staging', retry: { maxAttempts: 3, delayMs: 0 },
      fetch: (url, init) => handler(new Request(origin + url, init)) }).submit({ title: 'Fixture', description: 'Fixture' });
    assert.equal(result.status, 'submitted');
    assert.equal(result.statusCode, 202);
    assert.deepEqual(result.response, expected);
    assert.equal(result.bugId, null);
    assert.equal(calls, 1);
  }
});
