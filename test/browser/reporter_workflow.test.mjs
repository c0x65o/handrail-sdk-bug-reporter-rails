import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const root = fileURLToPath(new URL('../..', import.meta.url));
const endpoint = '/fixture/api/mobile-bug-reports';
const bugId = 'bug-canonical.123';
const sentinels = ['hbr_workflow_server_only_sentinel',
  'workflow_application_session_server_only_sentinel', 'workflow-private-principal',
  'workflow-cookie-signing-sentinel'];
const consent = { notify_on_resolution: true, consent_version: 'v1' };
const now = new Date('2026-08-14T18:00:00Z');

function publicOnly(value) {
  const text = JSON.stringify(value);
  for (const secret of sentinels) assert.ok(!text.includes(secret), `Private sentinel leaked: ${secret}`);
  assert.ok(!text.includes('automation_requests'), 'Automation requests must be absent');
}

async function fixture(t, scenario) {
  const directory = await mkdtemp(join(tmpdir(), 'rails-workflow-'));
  const auditPath = join(directory, 'http.jsonl');
  let server, browser, context;
  let output = '';
  t.after(async () => {
    try {
      await context?.close();
    } finally {
      try { await browser?.close(); }
      finally {
        if (server?.pid && server.exitCode === null && server.signalCode === null) {
          const exited = once(server, 'exit');
          server.kill('SIGTERM');
          const timeout = setTimeout(() => server.kill('SIGKILL'), 5_000);
          try { await exited; } finally { clearTimeout(timeout); }
        }
        if (t.passed === false) {
          t.diagnostic(output);
          const audit = await readFile(auditPath, 'utf8').catch(() => '');
          for (const line of audit.trim().split('\n').filter(Boolean)) {
            const row = JSON.parse(line);
            if (row.kind === 'http') t.diagnostic(`${row.method} ${row.url}`);
          }
        }
        await rm(directory, { recursive: true, force: true });
        // Also fail if the Ruby no-network guard recorded a swallowed attempt.
        if (server?.pid) assert.equal(server.exitCode, 0, `Rails fixture did not exit cleanly\n${output}`);
      }
    }
  });
  server = spawn(process.env.RUBY || 'ruby', ['test/fixtures/workflow/server.rb'], {
    cwd: root, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, BUNDLE_GEMFILE: join(root, 'Gemfile'), BUNDLE_FROZEN: 'true',
      WORKFLOW_SCENARIO: scenario, WORKFLOW_AUDIT: auditPath },
  });
  const ready = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Rails startup exceeded 30s\n${output}`)), 30_000);
    const fail = error => { clearTimeout(timeout); reject(error); };
    server.once('error', fail);
    server.once('exit', code => fail(new Error(`Rails exited (${code})\n${output}`)));
    server.stderr.on('data', bytes => { output = (output + bytes).slice(-32_000); });
    let lines = '';
    server.stdout.on('data', bytes => {
      output = (output + bytes).slice(-32_000);
      lines += bytes;
      for (const line of lines.split('\n').slice(0, -1)) {
        if (!line.startsWith('{')) continue;
        const value = JSON.parse(line);
        if (value.ready) { clearTimeout(timeout); resolve(value); }
      }
      lines = lines.split('\n').at(-1);
    });
  });
  const origin = `http://127.0.0.1:${ready.port}`;
  // Same executable override convention as upstream notification-opt-in.test.mjs.
  browser = await chromium.launch({
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
    args: ['--disable-background-networking'], timeout: 30_000,
  });
  t.diagnostic(`Node ${process.version}; Playwright ${JSON.parse(await readFile(join(root, 'node_modules/playwright/package.json'))).version}; Chromium ${browser.version()}; ${JSON.stringify(ready)}`);
  context = await browser.newContext({ serviceWorkers: 'block' });
  const external = [], errors = [], requests = [], responses = [], pending = [];
  await context.route(url => url.origin !== origin, route => {
    external.push(route.request().url());
    return route.abort('blockedbyclient');
  });
  const page = await context.newPage();
  page.setDefaultTimeout(8_000);
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => pending.push((async () => {
    requests.push({ url: request.url(), method: request.method(),
      headers: await request.allHeaders(), body: request.postData() });
  })()));
  page.on('response', response => {
    const url = new URL(response.url());
    if (url.pathname.startsWith(endpoint)) responses.push({ url: response.url(),
      status: response.status(), headers: response.headers() });
  });
  await page.clock.install({ time: now });
  await page.clock.pauseAt(now);
  const document = await page.goto(origin);
  assert.equal(document.status(), 200);
  publicOnly(await document.text());
  await page.getByRole('button', { name: 'Report a bug', exact: true }).click();
  await page.getByRole('checkbox', { name: 'Email me when this bug is fixed' }).waitFor();
  const config = await page.locator('[data-handrail-bug-reporter="1"]').getAttribute('data-handrail-bug-reporter-options');
  publicOnly(config);
  assert.equal(JSON.parse(config).config.allowScreenshots, true);
  assert.equal(JSON.parse(config).config.transport, 'same-origin');
  const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content');
  assert.ok(csrf);
  assert.ok((await context.cookies()).some(cookie => cookie.name === '_workflow_host' && cookie.httpOnly));
  assert.equal(await page.evaluate(() => document.cookie), '');

  async function audit() {
    return (await readFile(auditPath, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
  }
  async function finish() {
    await Promise.all(pending);
    assert.deepEqual(external, []);
    assert.deepEqual(errors, []);
    publicOnly(requests);
    publicOnly(await page.content());
    const calls = (await audit()).filter(row => row.kind === 'http');
    assert.deepEqual((await audit()).filter(row => row.kind === 'fixture_error'), []);
    const resolved = (await audit()).filter(row => row.kind === 'identity');
    assert.equal(resolved.length, calls.length);
    assert.ok(resolved.every(row => row.principal === 'workflow-private-principal'));
    for (const call of calls) {
      assert.equal(call.headers.authorization, `Bearer ${sentinels[0]}`);
      assert.equal(call.headers['x-handrail-application-session-token'], sentinels[1]);
      publicOnly(call.body);
      if (call.body && new URL(call.url).pathname.endsWith('/mobile-bug-reports')) {
        assert.equal(call.body.project_id, 'project-123');
        assert.equal(call.body.environment, 'staging');
      } else {
        const query = new URL(call.url).searchParams;
        assert.equal(query.get('project_id'), 'project-123');
        assert.equal(query.get('environment'), 'staging');
      }
    }
    const protectedRequests = requests.filter(row => new URL(row.url).pathname.startsWith(endpoint));
    assert.equal(calls.length, protectedRequests.length, 'Each browser request crosses the real Rails client boundary once');
    for (const request of protectedRequests) {
      assert.equal(new URL(request.url).origin, origin);
      assert.match(request.headers.cookie, /_workflow_host=/);
      assert.equal(request.headers.authorization, undefined);
      assert.equal(request.headers['x-handrail-application-session-token'], undefined);
      if (request.method !== 'GET') {
        assert.equal(request.headers['x-csrf-token'], csrf);
        assert.equal(request.headers.origin, origin);
      }
    }
    for (const response of responses) {
      assert.equal(response.headers['cache-control'], 'private, no-store');
      publicOnly(response);
      const failure = scenario === 'subscription_failure' && new URL(response.url).pathname.endsWith('/subscription');
      assert.equal(response.status, failure ? 422 : new URL(response.url).pathname === endpoint ? 201 : 200);
    }
    assert.ok(requests.some(row => new URL(row.url).pathname === '/javascripts/handrail_bug_reporter.js'));
    assert.ok(protectedRequests.some(row => row.method === 'GET' && new URL(row.url).pathname === `${endpoint}/policy`));
    return { calls, requests: protectedRequests, responses };
  }
  return { page, audit, finish, origin };
}

async function fillReport(page, image = 'pixel.png') {
  await page.getByPlaceholder('What is broken?').fill('  Checkout fails  ');
  await page.getByPlaceholder('Describe what you expected and what happened instead. You can paste a screenshot here.').fill('  Expected checkout to finish.  ');
  await page.locator('input[type="file"]').setInputFiles(join(root, 'test/fixtures/screenshots', image));
  await page.getByRole('checkbox', { name: 'Email me when this bug is fixed' }).check();
}

async function submit(page) {
  const [accepted] = await Promise.all([
    page.waitForResponse(response => new URL(response.url()).pathname === endpoint && response.request().method() === 'POST'),
    page.getByRole('button', { name: 'Send report', exact: true }).click(),
  ]);
  assert.equal(accepted.status(), 201);
  assert.equal((await accepted.json()).bug_id, bugId);
  await page.getByRole('heading', { name: 'Thanks for submitting this bug' }).waitFor();
}

function submissionContracts(result, expectedImage) {
  const intake = result.calls.filter(call => call.method === 'POST' && new URL(call.url).pathname === '/api/mobile-bug-reports');
  assert.equal(intake.length, 1, 'Accepted report must not be replayed');
  const body = intake[0].body;
  assert.equal(body.title, 'Checkout fails');
  assert.equal(body.description, 'Expected checkout to finish.');
  assert.equal(body.platform, 'browser');
  assert.equal(body.reporter_sdk_runtime, 'react');
  assert.ok(body.event_id);
  assert.deepEqual(body.reporter_notification, consent);
  assert.deepEqual(Buffer.from(body.screenshot_base64, 'base64'), expectedImage);
  const subscription = result.calls.filter(call => new URL(call.url).pathname.endsWith('/subscription'));
  assert.equal(subscription.length, 1);
  assert.equal(subscription[0].method, 'POST');
  assert.equal(new URL(subscription[0].url).pathname, `/api/mobile-bug-reports/bugs/${bugId}/subscription`);
  assert.deepEqual(subscription[0].body, { reporter_notification: consent });
  assert.ok(!JSON.stringify(result.calls).includes('intake-not-a-bug-id'));
}

test('report with validated screenshot and consent reaches thank-you', { timeout: 60_000 }, async t => {
  const host = await fixture(t, 'submission');
  await fillReport(host.page);
  // Same journey: a file claiming PNG with invalid bytes must fail before HTTP.
  await host.page.locator('input[type="file"]').setInputFiles({ name: 'invalid.png', mimeType: 'image/png', buffer: Buffer.from('not a PNG') });
  await host.page.getByRole('button', { name: 'Send report', exact: true }).click();
  await host.page.getByText('The screenshot must be one PNG or JPEG image no larger than 20 MiB.', { exact: true }).waitFor();
  assert.equal((await host.audit()).filter(row => row.method === 'POST').length, 0);
  await fillReport(host.page);
  await submit(host.page);
  await host.page.getByText(/Email updates are enabled/).waitFor();
  submissionContracts(await host.finish(), await readFile(join(root, 'test/fixtures/screenshots/pixel.png')));
});

test('subscription failure preserves accepted report and displays warning', { timeout: 60_000 }, async t => {
  const host = await fixture(t, 'subscription_failure');
  await fillReport(host.page, 'pixel.jpg');
  await submit(host.page);
  await host.page.getByRole('alert').filter({ hasText: 'Your bug is saved, but email updates could not be enabled.' }).waitFor();
  await host.page.locator('[data-handrail-bug-view-switch="history"]').click();
  await host.page.getByRole('button', { name: `View Bug ${bugId}`, exact: true }).waitFor();
  submissionContracts(await host.finish(), await readFile(join(root, 'test/fixtures/screenshots/pixel.jpg')));
});

test('My Bugs query, cursor, detail, archive/restore and current-query refresh', { timeout: 60_000 }, async t => {
  const host = await fixture(t, 'history');
  const { page } = host;
  const mine = predicate => page.waitForResponse(response => {
    const url = new URL(response.url());
    return url.pathname === `${endpoint}/mine` && predicate(url.searchParams);
  });
  await page.locator('[data-handrail-bug-view-switch="history"]').click();
  await page.getByRole('button', { name: `View Bug ${bugId}`, exact: true }).waitFor();
  let response = mine(query => query.get('search') === 'checkout');
  await page.getByRole('searchbox', { name: 'Search my bugs' }).fill('checkout');
  await page.clock.runFor(350);
  await response;
  response = mine(query => query.get('status_group') === 'in_progress');
  await page.getByRole('group', { name: 'Filter bugs by status' }).getByRole('button', { name: /^Working/ }).click();
  await response;
  response = mine(query => query.get('sort') === 'oldest');
  await page.getByLabel('Bug sort order').selectOption('oldest');
  await response;
  response = mine(query => query.get('cursor') === 'opaque-page-2+cursor=');
  await page.getByRole('button', { name: /^Show more/ }).click();
  await response;
  await page.getByRole('button', { name: 'View Bug bug-page.2', exact: true }).waitFor();
  await page.getByRole('button', { name: `View Bug ${bugId}`, exact: true }).click();
  await page.locator('[data-handrail-bug-history-detail="true"]').getByText(bugId, { exact: true }).waitFor();
  // The pinned UI expands the list projection. Exercise its public client for
  // the separate detail endpoint, with the actual packaged CSRF fetch adapter.
  const detail = await page.evaluate(async id => {
    const options = JSON.parse(document.querySelector('[data-handrail-bug-reporter="1"]').dataset.handrailBugReporterOptions);
    const client = HandrailBugReporter.createBugReporter({ ...options.config,
      fetch: HandrailBugReporter.createCsrfFetch(window.fetch.bind(window)) });
    return client.getBug(id);
  }, bugId);
  assert.equal(detail.id, bugId);
  let mutation = page.waitForResponse(response => response.request().method() === 'PUT');
  await page.getByRole('button', { name: `Archive Bug ${bugId}`, exact: true }).click();
  assert.equal((await (await mutation).json()).bug_id, bugId);
  response = mine(query => query.get('visibility') === 'archived');
  await page.getByRole('tab', { name: 'Archived', exact: true }).click();
  await response;
  mutation = page.waitForResponse(response => response.request().method() === 'DELETE');
  await page.getByRole('button', { name: `Restore Bug ${bugId}`, exact: true }).click();
  assert.equal((await (await mutation).json()).bug_id, bugId);
  response = mine(query => query.get('visibility') === 'active');
  await page.getByRole('tab', { name: 'Active', exact: true }).click();
  await response;
  // Switching visibility intentionally clears the status filter in the pinned
  // UI. Select it again so submission must preserve a non-default full query.
  response = mine(query => query.get('status_group') === 'in_progress' && query.get('visibility') === 'active');
  await page.getByRole('group', { name: 'Filter bugs by status' }).getByRole('button', { name: /^Working/ }).click();
  await response;

  await page.locator('[data-handrail-bug-view-switch="report"]').click();
  await fillReport(page);
  await submit(page);
  response = mine(query => query.get('search') === 'checkout' && query.get('status_group') === 'in_progress' && query.get('sort') === 'oldest');
  await page.locator('[data-handrail-bug-view-switch="history"]').click();
  const refreshed = await response;
  assert.equal(new URL(refreshed.url()).searchParams.has('cursor'), false);
  await page.getByRole('button', { name: `View Bug ${bugId}`, exact: true }).waitFor();
  const count = async () => (await host.audit()).filter(row => row.kind === 'http' && new URL(row.url).pathname.endsWith('/mine')).length;
  const before = await count();
  await page.clock.runFor(14_999);
  assert.equal(await count(), before);
  response = mine(query => query.get('search') === 'checkout' && query.get('status_group') === 'in_progress' && query.get('sort') === 'oldest');
  await page.clock.runFor(1);
  await response;
  assert.equal(await count(), before + 1, '15-second refresh uses the selected query');

  const result = await host.finish();
  submissionContracts(result, await readFile(join(root, 'test/fixtures/screenshots/pixel.png')));
  const queries = result.requests.filter(row => new URL(row.url).pathname.endsWith('/mine')).map(row => new URL(row.url).searchParams);
  const cursor = queries.find(query => query.has('cursor'));
  assert.equal(cursor.get('limit'), '1');
  assert.equal(cursor.get('cursor'), 'opaque-page-2+cursor=');
  for (const key of ['search', 'status_group', 'sort', 'visibility']) assert.equal(cursor.has(key), false, 'Opaque cursor carries the query');
  assert.ok(queries.some(query => query.get('search') === 'checkout' && query.get('status_group') === 'in_progress' && query.get('sort') === 'oldest' && query.get('visibility') === 'active'));
  for (const [method, suffix] of [['GET', ''], ['PUT', '/archive'], ['DELETE', '/archive']]) {
    const path = `${endpoint}/bugs/${bugId}${suffix}`;
    assert.equal(result.requests.filter(row => row.method === method && new URL(row.url).pathname === path).length, 1);
    assert.equal(result.calls.filter(row => row.method === method && new URL(row.url).pathname === path.replace('/fixture', '')).length, 1);
  }
});
