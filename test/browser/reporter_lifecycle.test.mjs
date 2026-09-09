import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, roots, open, send, marker, island, asset, endpoint } from './lifecycle_support.mjs';

test('initial, deferred and post-readiness assets; disabled and marker-free pages', { timeout: 60_000 }, async t => {
  const host = await fixture(t), { page } = host;
  for (const loading of ['initial', 'deferred', 'late']) {
    await host.goto('first', 'ordinary', `?loading=${loading}`);
    if (loading === 'late') {
      assert.equal(await page.evaluate(() => document.readyState), 'complete');
      assert.equal(await page.locator(island).count(), 0);
      await page.addScriptTag({ url: host.origin + asset });
    }
    await roots(page);
    await open(page);
    await page.getByPlaceholder('What is broken?').fill('Unchanged form');
    await page.evaluate(() => { window.originalRails = HandrailBugReporter.rails; window.originalRoot = document.querySelector('[data-handrail-bug-reporter-root]'); });
    await page.addScriptTag({ url: host.origin + asset });
    assert.equal(await page.evaluate(() => originalRails === HandrailBugReporter.rails && originalRoot === document.querySelector('[data-handrail-bug-reporter-root]')), true);
    assert.equal(await page.getByPlaceholder('What is broken?').inputValue(), 'Unchanged form');
    assert.equal(await page.locator('#host-content').textContent(), 'Host content stays owned by the host.');
  }
  for (const variant of ['disabled', 'marker-free']) {
    await host.goto(variant); await roots(page, 0);
    assert.equal(await page.locator(marker).count(), 0);
  }
  // Explicitly disabled data marker also stays inert, then observer sees enable.
  await host.goto('first'); await roots(page);
  await page.evaluate(() => {
    const marker = document.querySelector('[data-handrail-bug-reporter="1"]');
    const options = JSON.parse(marker.dataset.handrailBugReporterOptions);
    options.config.enabled = false;
    marker.dataset.handrailBugReporterOptions = JSON.stringify(options);
  });
  await roots(page, 0);
  await host.finish();
});

for (const navigation of ['ordinary', 'turbo', 'turbolinks']) {
  test(`${navigation}: three real forward/back/cache cycles, single root and history schedule`, { timeout: 90_000 }, async t => {
    const host = await fixture(t), { page } = host;
    await host.goto('first', navigation); await roots(page);
    const documentId = await page.evaluate(() => fixture.documentId);
    for (let cycle = 0; cycle < 3; cycle++) {
      await open(page);
      await page.locator('[data-handrail-bug-view-switch="history"]').click();
      await page.waitForFunction(() => fixture.calls.some(row => row.url.includes('/mine') && row.status === 200));
      assert.equal(await page.evaluate(() => fixture.intervals.size), 1);
      await page.keyboard.press('Escape');
      await page.evaluate(cycle => { document.body.dataset.cacheStamp = String(cycle); }, cycle);
      await page.locator('#next-page').click();
      await page.waitForURL(/\/second\?/); await roots(page);
      await page.getByRole('button', { name: 'Report from second page', exact: true }).waitFor();
      assert.equal(await page.evaluate(() => fixture.intervals.size), 0);
      assert.equal(await page.locator('[role="dialog"]').count(), 0);
      if (navigation !== 'ordinary') assert.equal(await page.evaluate(() => fixture.documentId), documentId, 'Library visit must retain the JavaScript document');
      else assert.notEqual(await page.evaluate(() => fixture.documentId), documentId, 'Ordinary navigation loads a document');
      const documentsBeforeBack = host.network.filter(row => row.path.endsWith('/first')).length;
      await page.goBack(); await page.waitForURL(/\/first$/); await roots(page);
      if (navigation !== 'ordinary') {
        assert.equal(await page.locator('body').getAttribute('data-cache-stamp'), String(cycle), 'Actual snapshot restored host DOM');
        assert.equal(host.network.filter(row => row.path.endsWith('/first')).length, documentsBeforeBack, 'Restoration must use cached HTML');
      }
      await page.goForward(); await page.waitForURL(/\/second\?/); await roots(page);
      await page.goBack(); await page.waitForURL(/\/first$/); await roots(page);
      await page.addScriptTag({ url: host.origin + asset }); await roots(page);
    }
    if (navigation !== 'ordinary') {
      const caches = await page.evaluate(navigation => fixture.events.filter(e => e.name === `${navigation}:before-cache`), navigation);
      assert.ok(caches.length >= 3);
      assert.ok(caches.every(e => e.roots === 0), 'Actual library before-cache removes reporter roots');
    }
    await open(page); await page.locator('[data-handrail-bug-view-switch="history"]').click();
    await page.waitForFunction(() => fixture.intervals.size === 1);
    await page.clock.pauseAt(new Date());
    const calls = () => page.evaluate(() => fixture.calls.filter(row => row.url.includes('/mine')).length);
    const before = await calls();
    await page.clock.runFor(14_999); assert.equal(await calls(), before);
    await page.clock.runFor(1);
    await page.waitForFunction(before => fixture.calls.filter(row => row.url.includes('/mine')).length === before + 1, before);
    assert.equal(await calls(), before + 1);
    await page.evaluate(() => HandrailBugReporter.rails.teardown()); await roots(page, 0);
    assert.equal(await page.evaluate(() => fixture.intervals.size), 0);
    const retired = await calls(); await page.clock.runFor(45_000); assert.equal(await calls(), retired);
    await host.finish();
  });
}

test('changed helper options, pathname privacy and explicit context reach mounted Rails', { timeout: 60_000 }, async t => {
  const host = await fixture(t), { page } = host;
  await host.goto('first'); await roots(page); await open(page); await send(page);
  await page.keyboard.press('Escape');
  await page.locator('#next-page').click(); await page.waitForURL(/second/); await roots(page);
  // Environment comes from the host Factory, not a per-helper option. Emulate a
  // changed host config on the fixture marker without mutating the shared Factory.
  await page.evaluate(() => {
    const marker = document.querySelector('[data-handrail-bug-reporter="1"]');
    const options = JSON.parse(marker.dataset.handrailBugReporterOptions);
    options.config.environment = 'development';
    marker.dataset.handrailBugReporterOptions = JSON.stringify(options);
  });
  await open(page, 'Report from second page'); await send(page);
  const request = await page.evaluate(() => fixture.calls.find(row => row.method === 'POST'));
  assert.equal(request.url, '/alternate/api/mobile-bug-reports');
  const body = JSON.parse(request.body);
  assert.equal(body.environment, 'development'); assert.equal(body.route, '/lifecycle/ordinary/second');
  assert.equal(body.app_version, '2.0.0');
  assert.ok(!JSON.stringify(body).includes('sentinel'));
  // Forwarding still enforces the server-owned environment.
  const forwarded = (await host.audit()).filter(row => row.method === 'POST').at(-1).body;
  assert.equal(forwarded.environment, 'staging'); assert.equal(forwarded.route, body.route);
  await host.goto('explicit', 'ordinary', '?query_sentinel=private#fragment_sentinel');
  await roots(page); await open(page); await send(page);
  const explicit = (await host.audit()).filter(row => row.method === 'POST').at(-1).body;
  assert.equal(explicit.route, '/explicit-public-route'); assert.equal(explicit.app_version, '2.0.0');
  assert.ok(!JSON.stringify(explicit).includes('sentinel'));
  await host.finish();
});

test('custom mouse/keyboard launcher ownership, replacements and repeatable teardown/start', { timeout: 60_000 }, async t => {
  const host = await fixture(t), { page } = host;
  await host.goto('custom'); await roots(page);
  const original = await page.locator('#host-help').evaluate(e => e.outerHTML);
  for (const operation of ['mouse', 'Enter', 'Space']) {
    await page.locator('#host-help').focus();
    if (operation === 'mouse') await page.locator('#host-help').click();
    else await page.keyboard.press(operation);
    await page.getByRole('dialog').waitFor();
    await page.keyboard.press('Escape');
    await page.getByRole('dialog').waitFor({ state: 'detached' });
    assert.equal(await page.evaluate(() => document.activeElement.id), 'host-help');
    assert.equal(await page.locator('#host-help').evaluate(e => e.outerHTML), original);
    assert.equal(await page.locator(`${marker} button`).count(), 0, 'No additional launcher');
  }
  assert.equal(await page.evaluate(() => hostClicks), 3);
  await page.evaluate(() => {
    window.oldButton = document.getElementById('host-help');
    oldButton.replaceWith(oldButton.cloneNode(true));
  });
  await roots(page); await page.evaluate(() => oldButton.click());
  assert.equal(await page.evaluate(() => hostClicks), 4, 'Detached host handler survives');
  assert.equal(await page.getByRole('dialog').count(), 0);
  await open(page, 'Host Help'); await page.keyboard.press('Escape');
  await page.evaluate(() => {
    window.savedMarker = document.querySelector('[data-handrail-bug-reporter="1"]');
    savedMarker.remove();
  });
  await roots(page, 0); await page.locator('#host-help').click();
  assert.equal(await page.getByRole('dialog').count(), 0);
  await page.evaluate(() => document.body.append(savedMarker.cloneNode(false))); await roots(page);
  for (let i = 0; i < 3; i++) {
    await page.evaluate(() => {
      HandrailBugReporter.rails.teardown(); HandrailBugReporter.rails.teardown();
      for (const name of ['turbo:load', 'turbolinks:load', 'page:load', 'page:change']) document.dispatchEvent(new Event(name));
      window.dispatchEvent(new Event('pageshow'));
      document.querySelector('[data-handrail-bug-reporter="1"]').append(document.createElement('span'));
    });
    await roots(page, 0); await page.locator('#host-help').click();
    assert.equal(await page.getByRole('dialog').count(), 0);
    await page.evaluate(() => { HandrailBugReporter.rails.start(); HandrailBugReporter.rails.start(); });
    await roots(page); await open(page, 'Host Help'); await page.keyboard.press('Escape');
  }
  // Supplemental synthetic legacy events; these are not legacy runtime cells.
  for (const name of ['page:before-cache', 'page:before-unload', 'turbo:before-cache', 'turbolinks:before-cache', 'pagehide']) {
    await page.evaluate(name => (name === 'pagehide' ? window : document).dispatchEvent(new Event(name)), name);
    await roots(page, 0);
    await page.addScriptTag({ url: host.origin + asset }); await roots(page, 0);
    await page.evaluate(() => window.dispatchEvent(new Event('pageshow'))); await roots(page);
  }
  await host.finish();
});

for (const kind of ['policy', 'history', 'submission']) {
  test(`pending ${kind} is aborted on disposal and cannot retry`, { timeout: 60_000 }, async t => {
    const host = await fixture(t), { page } = host;
    const suffix = kind === 'policy' ? '/policy' : kind === 'history' ? '/mine' : '';
    const url = `${host.origin}${endpoint}${suffix}`;
    // Hold at the actual browser HTTP boundary. Native fetch still owns its
    // AbortSignal; release/abort the intercepted request during bounded cleanup.
    const held = [];
    await page.route(url + (suffix ? '**' : ''), route => { held.push(route); });
    t.after(async () => { for (const route of held) await route.abort().catch(() => {}); });
    await host.goto('first'); await roots(page);
    if (kind !== 'policy') {
      await open(page);
      if (kind === 'history') await page.locator('[data-handrail-bug-view-switch="history"]').click();
      else await page.getByRole('button', { name: 'Send report', exact: true }).click();
    }
    await page.waitForFunction(url => fixture.calls.some(row => new URL(row.url, location.href).href.startsWith(url) && !row.settled), url);
    await page.evaluate(() => HandrailBugReporter.rails.teardown()); await roots(page, 0);
    await page.waitForFunction(url => fixture.calls.some(row => new URL(row.url, location.href).href.startsWith(url) && row.aborted && row.settled), url);
    const before = held.length;
    await page.clock.runFor(60_000);
    assert.equal(held.length, before, 'Retired requests cannot reach HTTP again');
    assert.equal(await page.evaluate(() => fixture.intervals.size), 0);
    await host.finish();
  });
}

test('CSRF wrapper browser boundary matrix preserves caller semantics without external delivery', { timeout: 60_000 }, async t => {
  const host = await fixture(t), { page } = host;
  await host.goto('marker-free');
  const checks = await page.evaluate(async () => {
    const check = (value, message) => { if (!value) throw new Error(message); };
    const meta = document.querySelector('meta[name="csrf-token"]');
    const original = meta.content, originalFetch = window.fetch;
    const receiver = {}, result = Promise.resolve('boundary result');
    let call, count = 0;
    // Intercepts the public caller-supplied HTTP seam before native delivery.
    const wrapped = HandrailBugReporter.createCsrfFetch(function(input, init) { call = { input, init, receiver: this }; count++; return result; });
    const inputs = ['/probe', new URL('/probe', location.href), new Request(location.origin + '/probe', {
      method: 'DELETE', body: 'request body', headers: { 'X-Caller': 'request' }, credentials: 'same-origin' })];
    for (const [i, method] of ['POST', 'PUT', 'DELETE'].entries()) {
      meta.content = `fixture-token-${i}`;
      const headers = i === 0 ? { 'X-Caller': 'keep', 'X-CSRF-Token': 'stale' } : [['X-Caller', 'keep'], ['X-CSRF-Token', 'stale']];
      const controller = new AbortController();
      const init = { method, headers, body: 'caller body', credentials: 'same-origin', signal: controller.signal };
      check(wrapped.call(receiver, inputs[i], init) === result, 'Return value');
      check(call.input === inputs[i] && call.receiver === receiver, 'Input/receiver identity');
      check(call.init.headers.get('x-csrf-token') === meta.content, 'Current token');
      check(call.init.headers.get('x-caller') === 'keep' && new Headers(headers).get('x-csrf-token') === 'stale', 'Copied caller headers');
      check(call.init.credentials === init.credentials && call.init.body === init.body && call.init.signal === init.signal, 'Caller options preserved');
    }
    const request = inputs[2]; wrapped(request);
    check(call.input === request && !request.bodyUsed, 'Request preserved');
    check(call.init.headers.get('x-caller') === 'request', 'Request headers retained');
    check(await new Request(request, call.init).text() === 'request body', 'Request stream retained');
    for (const method of ['GET', 'HEAD', 'OPTIONS', 'TRACE']) {
      const init = { method, headers: new Headers({ 'X-Caller': 'safe' }) };
      wrapped('/probe', init); check(call.init === init && !call.init.headers.has('x-csrf-token'), 'Safe method passthrough');
    }
    for (const input of ['https://foreign.invalid/probe', '//foreign.invalid/probe',
      new URL('https://foreign.invalid/probe'), new Request('https://foreign.invalid/probe', { method: 'POST' }),
      `http://127.0.0.1:${Number(location.port) + 1}/probe`, 'http://[invalid']) {
      const init = { method: 'POST', headers: { 'X-Caller': 'foreign' } };
      wrapped(input, init); check(call.init === init && !new Headers(call.init.headers).has('x-csrf-token'), 'Foreign/unresolved input must not receive Rails token');
    }
    for (const token of ['', null]) {
      if (token === null) meta.remove(); else meta.content = token;
      const init = { method: 'DELETE', headers: new Headers({ 'X-Caller': 'empty' }) };
      wrapped('/probe', init); check(call.init === init && !call.init.headers.has('x-csrf-token'), 'Missing token passthrough');
    }
    meta.content = original; document.head.append(meta);
    check(window.fetch === originalFetch, 'Standalone wrapper leaves global fetch intact');
    return count;
  });
  assert.equal(checks, 16);
  await host.finish();
});

test('real Rails token rotation across POST/PUT/DELETE and an actual SDK transient retry', { timeout: 60_000 }, async t => {
  const host = await fixture(t, 'lifecycle_retry'), { page } = host;
  await host.goto('first'); await roots(page);
  // Configure a short bounded SDK retry; retain mounted adapter scoped fetch.
  await page.evaluate(() => {
    const marker = document.querySelector('[data-handrail-bug-reporter="1"]');
    const options = JSON.parse(marker.dataset.handrailBugReporterOptions);
    options.config.retry = { maxAttempts: 2, delayMs: 1000 };
    marker.dataset.handrailBugReporterOptions = JSON.stringify(options);
    const native = window.fetch;
    window.rotateFixtureToken = async () => {
      const meta = document.querySelector('meta[name="csrf-token"]');
      const response = await native('/lifecycle/rotate', { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-Token': meta.content } });
      if (response.status !== 200) throw new Error('Protected fixture rotation failed');
      const { token } = await response.json(); meta.content = token; return token;
    };
    window.fetch = async (input, init) => {
      const response = await native(input, init);
      if (response.status === 503 && init?.method === 'POST') await rotateFixtureToken();
      return response;
    };
  });
  await open(page); await send(page);
  const result = await page.evaluate(async () => {
    const posts = fixture.calls.filter(row => row.url === '/fixture/api/mobile-bug-reports' && row.method === 'POST');
    const retryValid = posts.length === 2 && posts[0].status === 503 && posts[1].status === 201 &&
      posts[0].headers['x-csrf-token'] !== posts[1].headers['x-csrf-token'] &&
      posts.every(row => row.credentials === 'same-origin') && posts[0].body === posts[1].body;
    const wrapped = HandrailBugReporter.createCsrfFetch(window.fetch.bind(window));
    const old = document.querySelector('meta[name="csrf-token"]').content;
    await rotateFixtureToken();
    // Negative control proves genuine Rails session-token invalidation.
    const rejected = await fetch('/fixture/api/mobile-bug-reports/bugs/bug-canonical.123/archive', {
      method: 'PUT', credentials: 'same-origin', headers: { 'X-CSRF-Token': old } });
    const statuses = [], tokens = [];
    for (const method of ['PUT', 'DELETE']) {
      const token = await rotateFixtureToken(); tokens.push(token);
      const response = await wrapped('/fixture/api/mobile-bug-reports/bugs/bug-canonical.123/archive', {
        method, credentials: 'same-origin', headers: { 'X-Caller': 'keep' } });
      statuses.push(response.status);
      const call = fixture.calls.filter(row => row.method === method && row.headers['x-caller'] === 'keep').at(-1);
      if (call.headers['x-csrf-token'] !== token || call.credentials !== 'same-origin') throw new Error('Mutation boundary token/options mismatch');
    }
    return { retryValid, rejected: rejected.status, statuses, rotated: tokens[0] !== tokens[1] };
  });
  assert.deepEqual(result, { retryValid: true, rejected: 422, statuses: [200, 200], rotated: true });
  const calls = (await host.audit()).filter(row => row.kind === 'http');
  assert.equal(calls.filter(row => row.method === 'POST').length, 2);
  assert.equal(calls.filter(row => row.method === 'PUT').length, 1, 'Stale token rejected before outbound seam');
  await host.finish();
});
