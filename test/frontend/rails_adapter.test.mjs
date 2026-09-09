import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { read } from '../../scripts/contract.mjs';

const asset = read('app/assets/javascripts/handrail_bug_reporter.js');
const tick = () => new Promise(resolve => setTimeout(resolve, 25));
const rootSelector = '[data-handrail-bug-reporter-root]';
const config = { enabled: true, transport: 'same-origin', apiBaseUrl: '/feedback/api/mobile-bug-reports',
  projectId: 'project-123', environment: 'staging', retry: { maxAttempts: 2, delayMs: 1 } };
const options = { config, loadPolicyOnMount: false, showHistory: false,
  initialForm: { title: 'Initial title', description: 'Details' } };
const response = body => new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' } });

async function browser(t, ready = true) {
  const dom = new JSDOM('<!doctype html><head><meta name="csrf-token" content="first"></head><body><span id="host">Host content</span></body>', {
    url: 'https://host.example.test/first?private=query#secret', runScripts: 'outside-only', pretendToBeVisual: true
  });
  const w = dom.window;
  if (ready) await new Promise(resolve => w.addEventListener('load', resolve, { once: true }));
  w.Headers = Headers;
  w.Request = Request;
  w.Response = Response;
  const errors = [];
  w.addEventListener('error', event => errors.push(event.error));
  w.fetch = () => { throw new Error('Unexpected network request'); };
  Object.defineProperty(w.document, 'cookie', { get() { throw new Error('Cookies must not be read'); } });
  t.after(() => {
    w.HandrailBugReporter?.rails.teardown();
    w.close();
    assert.deepEqual(errors, []);
  });
  return { w, doc: w.document, load() { w.eval(asset); return w.HandrailBugReporter; },
    event(name, target = w.document) { target.dispatchEvent(new w.Event(name)); } };
}

function marker(doc, settings = options, mode = 'launcher', launcherId) {
  const element = doc.createElement('div');
  element.setAttribute('data-handrail-bug-reporter', '1');
  element.setAttribute('data-handrail-bug-reporter-mode', mode);
  element.setAttribute('data-handrail-bug-reporter-options', JSON.stringify(settings));
  if (launcherId) element.setAttribute('data-handrail-bug-reporter-launcher-id', launcherId);
  const host = doc.createElement('span');
  host.textContent = 'Keep me';
  element.appendChild(host);
  doc.body.appendChild(element);
  return element;
}

async function open(element) {
  element.querySelector('[aria-haspopup="dialog"]').click();
  await tick();
  assert.ok(element.querySelector('[role="dialog"]'));
}

test('ordinary DOM readiness and late script loading mount only enabled, valid v1 markers', async t => {
  for (const ready of [false, true]) {
    const { doc, load } = await browser(t, ready);
    const valid = marker(doc);
    const disabled = marker(doc, { ...options, config: { ...config, enabled: false } });
    const malformed = marker(doc);
    malformed.setAttribute('data-handrail-bug-reporter-options', '({ config: {} })');
    const future = marker(doc);
    future.setAttribute('data-handrail-bug-reporter', '2');
    const invalidMode = marker(doc, options, 'other');
    // Hold readiness until after evaluation; awaiting this helper itself can
    // otherwise let jsdom finish parsing before the loading branch is exercised.
    if (!ready) Object.defineProperty(doc, 'readyState', { configurable: true, value: 'loading' });
    load();
    if (!ready) {
      assert.ok(!valid.querySelector(rootSelector));
      delete doc.readyState;
      doc.dispatchEvent(new doc.defaultView.Event('DOMContentLoaded'));
    }
    await tick();
    assert.equal(valid.querySelectorAll(rootSelector).length, 1);
    for (const element of [disabled, malformed, future, invalidMode]) assert.equal(element.innerHTML, '<span>Keep me</span>');
    assert.equal(doc.getElementById('host').textContent, 'Host content');
  }
});

test('repeated assets and navigation events retain one root; cache/unload cycles abort requests and remove roots', async t => {
  const { w, doc, load, event } = await browser(t);
  const requests = [];
  w.fetch = (url, init) => {
    requests.push({ url, init });
    return new Promise((resolve, reject) => init.signal.addEventListener('abort', () =>
      reject(new w.DOMException('Aborted', 'AbortError')), { once: true }));
  };
  const element = marker(doc, { ...options, loadPolicyOnMount: true });
  const api = load();
  await tick();
  const first = element.querySelector(rootSelector);
  assert.equal(load().rails, api.rails);
  for (const name of ['turbo:load', 'turbolinks:load', 'page:load', 'page:change']) event(name);
  await tick();
  assert.equal(element.querySelector(rootSelector), first);
  assert.equal(requests.length, 1);
  for (const name of ['turbo:before-cache', 'turbolinks:before-cache', 'page:before-unload', 'page:before-cache', 'pagehide']) {
    const old = element.querySelector(rootSelector);
    event(name, name === 'pagehide' ? w : doc);
    await tick();
    assert.equal(requests.at(-1).init.signal.aborted, true);
    assert.equal(old.isConnected, false);
    assert.equal(old.children.length, 0);
    assert.equal(element.innerHTML, '<span>Keep me</span>');
    load();
    await tick();
    assert.equal(element.querySelector(rootSelector), null, 'Cached pages stay unmounted even if the asset executes again');
    event('pageshow', w);
    await tick();
    assert.equal(element.querySelectorAll(rootSelector).length, 1);
  }
  event('unload', w);
  event('turbo:load');
  await tick();
  assert.equal(element.querySelector(rootSelector), null);
});

test('removed markers and disabled updates dispose work; late inserted markers mount', async t => {
  const { w, doc, load } = await browser(t);
  const signals = [];
  w.fetch = (url, init) => {
    signals.push(init.signal);
    return new Promise((resolve, reject) => init.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  };
  load();
  const first = marker(doc, { ...options, loadPolicyOnMount: true });
  const second = marker(doc, { ...options, loadPolicyOnMount: true });
  await tick();
  assert.equal(doc.querySelectorAll(rootSelector).length, 2);
  first.remove();
  second.setAttribute('data-handrail-bug-reporter-options', JSON.stringify({ config: { enabled: false } }));
  await tick();
  assert.equal(doc.querySelectorAll(rootSelector).length, 0);
  assert.equal(first.querySelector(rootSelector), null);
  assert.ok(signals.every(signal => signal.aborted));
});

test('navigation refreshes configuration, explicit context and pathname fallback without query/session serialization', async t => {
  const { w, doc, load, event } = await browser(t);
  const requests = [];
  w.fetch = async (url, init) => { requests.push({ url, init }); return response({ ok: true, bug_id: 'bug-1' }); };
  const element = marker(doc);
  load();
  await open(element);
  const first = element.querySelector(rootSelector);
  w.history.pushState({}, '', '/next?sensitive=value#private');
  const text = 'Quotes " & <script>not executable</script> \u2028';
  element.setAttribute('data-handrail-bug-reporter-options', JSON.stringify({ ...options,
    config: { ...config, apiBaseUrl: '/new/api/mobile-bug-reports', environment: 'production' },
    initialForm: { title: text, description: 'Next page', appVersion: '2.0' }, label: 'New label'
  }));
  event('turbo:load');
  await tick();
  assert.notEqual(element.querySelector(rootSelector), first);
  assert.equal(first.children.length, 0);
  assert.equal(element.querySelector('[role="dialog"]'), null);
  await open(element);
  assert.equal(element.querySelector('input[placeholder="What is broken?"]').value, text);
  element.querySelector('form').dispatchEvent(new w.Event('submit', { bubbles: true, cancelable: true }));
  await tick();
  assert.equal(requests[0].url, '/new/api/mobile-bug-reports');
  const payload = JSON.parse(requests[0].init.body);
  assert.equal(payload.route, '/next');
  assert.equal(payload.environment, 'production');
  assert.equal(payload.app_version, '2.0');
  assert.equal(JSON.stringify(payload).includes('sensitive'), false);
  assert.equal(new Headers(requests[0].init.headers).get('x-csrf-token'), 'first');
  assert.equal(requests[0].init.credentials, 'same-origin');
  element.setAttribute('data-handrail-bug-reporter-options', JSON.stringify({ ...options,
    initialForm: { ...options.initialForm, route: '/explicit-public-route' } }));
  event('turbolinks:load');
  await open(element);
  element.querySelector('form').dispatchEvent(new w.Event('submit', { bubbles: true, cancelable: true }));
  await tick();
  assert.equal(JSON.parse(requests.at(-1).init.body).route, '/explicit-public-route');
});

test('custom launcher uses public dialog, preserves host control and removes listeners and history polling', async t => {
  const { w, doc, load, event } = await browser(t);
  const button = doc.createElement('button');
  button.id = 'host-button';
  button.type = 'button';
  button.className = 'host-style';
  button.innerHTML = '<span>Host Help</span>';
  doc.body.appendChild(button);
  const original = button.outerHTML;
  let hostClicks = 0;
  button.addEventListener('click', () => hostClicks++);
  const listeners = new Set();
  const add = button.addEventListener.bind(button);
  const remove = button.removeEventListener.bind(button);
  button.addEventListener = (type, listener, opts) => { if (type === 'click') listeners.add(listener); add(type, listener, opts); };
  button.removeEventListener = (type, listener, opts) => { if (type === 'click') listeners.delete(listener); remove(type, listener, opts); };
  const intervals = new Set();
  const set = w.setInterval.bind(w);
  const clear = w.clearInterval.bind(w);
  w.setInterval = (...args) => { const id = set(...args); intervals.add(id); return id; };
  w.clearInterval = id => { intervals.delete(id); clear(id); };
  const requests = [];
  w.fetch = (url, init) => {
    requests.push(init);
    return new Promise((resolve, reject) => init.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  };
  const element = marker(doc, { ...options, showHistory: true }, 'custom-launcher', button.id);
  const api = load();
  for (let i = 0; i < 3; i++) {
    event('turbo:load');
    load();
    await tick();
    assert.equal(listeners.size, 1);
    assert.equal(element.querySelector('button'), null, 'No extra upstream launcher');
    button.focus();
    button.click();
    await tick();
    assert.ok(element.querySelector('[role="dialog"]'));
    element.querySelector('[aria-label="View my bug reports"]').click();
    await tick();
    assert.equal(intervals.size, 1);
    event('turbo:before-cache');
    await tick();
    assert.equal(intervals.size, 0);
    assert.equal(listeners.size, 0);
    assert.equal(requests.at(-1).signal.aborted, true);
    assert.equal(button.outerHTML, original);
    assert.equal(doc.activeElement, button);
  }
  assert.equal(hostClicks, 3);
  api.rails.teardown();
  api.rails.teardown();
  button.click();
  assert.equal(element.querySelector('[role="dialog"]'), null);
  assert.equal(hostClicks, 4);
});

test('explicit teardown removes adapter listeners/observer, is repeatable and leaves manual mounts owned by callers', async t => {
  const { w, doc, load, event } = await browser(t);
  const registrations = new Map();
  const originalAdd = w.EventTarget.prototype.addEventListener;
  const originalRemove = w.EventTarget.prototype.removeEventListener;
  w.EventTarget.prototype.addEventListener = function(type, listener, opts) {
    if (/^(turbo|turbolinks|page:|pagehide|pageshow|unload|DOMContentLoaded)/.test(type)) registrations.set(listener + type, type);
    return originalAdd.call(this, type, listener, opts);
  };
  w.EventTarget.prototype.removeEventListener = function(type, listener, opts) {
    registrations.delete(listener + type);
    return originalRemove.call(this, type, listener, opts);
  };
  const api = load();
  const manual = doc.createElement('div');
  doc.body.appendChild(manual);
  const handle = api.mount(manual, options);
  const element = marker(doc);
  await tick();
  assert.equal(doc.querySelectorAll(rootSelector).length, 2);
  api.rails.teardown();
  api.rails.teardown();
  assert.equal(registrations.size, 0);
  marker(doc);
  event('turbo:load');
  await tick();
  assert.equal(doc.querySelectorAll(rootSelector).length, 1);
  load().update(manual, { label: 'Still manual' });
  assert.equal(manual.querySelector('button').textContent, 'Still manual');
  await tick();
  assert.equal(element.querySelectorAll(rootSelector).length, 1, 'Asset reexecution explicitly starts a torn-down adapter');
  handle.unmount();
});

test('CSRF wrapper reads current token per POST/PUT/DELETE, handles URL/header forms, and preserves caller behavior', async t => {
  const { w, doc, load } = await browser(t);
  const api = load();
  const calls = [];
  const originalFetch = w.fetch;
  const receiver = {};
  const sentinel = Promise.resolve('caller result');
  const wrapped = api.createCsrfFetch(function(input, init) { calls.push({ input, init, receiver: this }); return sentinel; });
  const controller = new w.AbortController();
  const base = doc.createElement('base');
  base.href = '/nested/';
  doc.head.appendChild(base);
  const inputs = ['relative', new w.URL('/endpoint', w.location.href), '//host.example.test/endpoint'];
  const headers = [{ 'X-Caller': 'keep' }, [['X-Caller', 'keep']], new Headers({ 'X-Caller': 'keep', 'X-CSRF-Token': 'stale' })];
  for (const [index, method] of ['POST', 'PUT', 'DELETE'].entries()) {
    doc.querySelector('meta').content = `token-${index}`;
    const init = { method, headers: headers[index], body: 'original body', signal: controller.signal, credentials: 'same-origin' };
    assert.equal(wrapped.call(receiver, inputs[index], init), sentinel);
    const call = calls.at(-1);
    assert.equal(call.input, inputs[index]);
    assert.equal(call.receiver, receiver);
    assert.equal(call.init.body, init.body);
    assert.equal(call.init.signal, init.signal);
    assert.equal(call.init.credentials, 'same-origin');
    assert.equal(call.init.headers.get('x-caller'), 'keep');
    assert.equal(call.init.headers.get('x-csrf-token'), `token-${index}`);
    assert.equal(new Headers(init.headers).get('x-csrf-token'), index === 2 ? 'stale' : null);
  }
  const request = new Request('https://host.example.test/request', { method: 'POST', headers: { 'X-Original': 'request' }, body: 'stream body' });
  wrapped(request);
  assert.equal(calls.at(-1).input, request);
  assert.equal(calls.at(-1).init.headers.get('x-original'), 'request');
  assert.equal(request.bodyUsed, false);
  assert.equal(await new Request(request, calls.at(-1).init).text(), 'stream body');
  wrapped(new Request('https://host.example.test/request', { method: 'GET' }), { method: 'PATCH', headers: [['X-Override', 'yes']] });
  assert.equal(calls.at(-1).init.headers.get('x-override'), 'yes');
  assert.equal(calls.at(-1).init.headers.get('x-csrf-token'), 'token-2');
  assert.equal(w.fetch, originalFetch, 'Global fetch is not replaced');
});

test('safe methods, foreign URLs, absent tokens and malformed URLs are passed through without token injection', async t => {
  const { w, doc, load } = await browser(t);
  const calls = [];
  const wrapped = load().createCsrfFetch((input, init) => { calls.push({ input, init }); });
  for (const method of ['GET', 'HEAD', 'OPTIONS', 'TRACE']) {
    const init = { method, headers: { Accept: 'application/json' } };
    wrapped('/endpoint', init);
    assert.equal(calls.at(-1).init, init);
  }
  for (const input of ['https://foreign.test/endpoint', '//foreign.test/endpoint',
    'http://host.example.test/endpoint', 'https://host.example.test:444/endpoint',
    new w.URL('https://foreign.test/endpoint'), new Request('https://foreign.test/endpoint', { method: 'POST' }), 'http://[invalid']) {
    const init = { method: 'POST', headers: [['X-Caller', 'keep']] };
    wrapped(input, init);
    assert.equal(calls.at(-1).init, init);
  }
  const base = doc.createElement('base');
  base.href = 'https://foreign.test/';
  doc.head.appendChild(base);
  const init = { method: 'DELETE' };
  wrapped('relative', init);
  assert.equal(calls.at(-1).init, init, 'Relative requests respect foreign base URL');
  base.remove();
  for (const token of ['', null]) {
    if (token === null) doc.querySelector('meta').remove();
    else doc.querySelector('meta').content = token;
    wrapped('/endpoint', init);
    assert.equal(calls.at(-1).init, init);
  }
});

test('genuine SDK retry observes token rotation without recreating the reporter', async t => {
  const { doc, load } = await browser(t);
  const api = load();
  const tokens = [];
  const reporter = api.createBugReporter({ ...config, fetch: api.createCsrfFetch(async (url, init) => {
    tokens.push(init.headers.get('x-csrf-token'));
    assert.equal(init.credentials, 'same-origin');
    if (tokens.length === 1) {
      doc.querySelector('meta').content = 'rotated';
      return new Response('{}', { status: 503 });
    }
    return response({ ok: true, bug_id: 'bug-1' });
  }) });
  await reporter.submit({ title: 'Retry me', description: 'Details', impact: 'moderate' });
  assert.deepEqual(tokens, ['first', 'rotated']);
});

test('navigation cancels a pending submission and prevents its retry reaching the host fetch', async t => {
  const { w, doc, load, event } = await browser(t);
  const calls = [];
  w.fetch = (url, init) => {
    calls.push(init);
    return new Promise((resolve, reject) => init.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  };
  const element = marker(doc);
  load();
  await open(element);
  element.querySelector('form').dispatchEvent(new w.Event('submit', { bubbles: true, cancelable: true }));
  await tick();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].method, 'POST');
  event('turbo:before-cache');
  await tick();
  assert.equal(calls[0].signal.aborted, true);
  assert.equal(calls.length, 1, 'Disposed SDK cannot send its queued retry');
  assert.equal(element.querySelector(rootSelector), null);
});

test('host morphs that remove an island retire its requests and restore exactly one root', async t => {
  const { w, doc, load } = await browser(t);
  const signals = [];
  w.fetch = (url, init) => {
    signals.push(init.signal);
    return new Promise((resolve, reject) => init.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  };
  const element = marker(doc, { ...options, loadPolicyOnMount: true });
  load();
  await tick();
  const old = element.querySelector(rootSelector);
  old.remove();
  await tick();
  assert.equal(old.children.length, 0);
  assert.equal(signals[0].aborted, true);
  assert.equal(signals.length, 2);
  assert.equal(element.querySelectorAll(rootSelector).length, 1);
});

test('missing and replaced custom launchers are reconciled without retaining the old host listener', async t => {
  const { doc, load } = await browser(t);
  const element = marker(doc, options, 'custom-launcher', 'late-button');
  load();
  assert.equal(element.querySelector(rootSelector), null);
  const button = doc.createElement('button');
  button.id = 'late-button';
  button.type = 'button';
  button.textContent = 'Help';
  doc.body.appendChild(button);
  await tick();
  assert.equal(element.querySelectorAll(rootSelector).length, 1);
  const replacement = button.cloneNode(true);
  button.replaceWith(replacement);
  await tick();
  button.click();
  await tick();
  assert.equal(element.querySelector('[role="dialog"]'), null);
  replacement.click();
  await tick();
  assert.ok(element.querySelector('[role="dialog"]'));
  assert.equal(replacement.outerHTML, button.outerHTML);
});
