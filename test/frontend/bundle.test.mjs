import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';
import { JSDOM } from 'jsdom';
import { buildAsset } from '../../scripts/build.mjs';
import { root, read, upstream, verifyDependency } from '../../scripts/contract.mjs';

const asset = read('app/assets/javascripts/handrail_bug_reporter.js');
const tick = () => new Promise(resolve => setTimeout(resolve, 25));
const plain = value => JSON.parse(JSON.stringify(value));

async function browser(t) {
  const dom = new JSDOM('<!doctype html><body><div id="host"><span>Host content</span></div></body>', {
    url: 'https://host.example.test/page', runScripts: 'outside-only', pretendToBeVisual: true
  });
  const w = dom.window;
  await new Promise(resolve => w.addEventListener('load', resolve, { once: true }));
  t.after(() => w.close());
  const errors = [];
  w.addEventListener('error', event => errors.push(event.error));
  t.after(() => assert.deepEqual(errors, [], 'No uncaught browser errors'));
  for (const name of ['React', 'ReactDOM', 'require', 'module', 'process']) {
    Object.defineProperty(w, name, { get() { throw new Error(`Host dependency accessed: ${name}`); } });
  }
  w.Headers = Headers;
  w.Response = Response;
  w.Request = Request;
  w.fetch = () => { throw new Error('Unexpected network request'); };
  return { w, host: w.document.getElementById('host'), load: () => {
    w.eval(asset);
    return w.HandrailBugReporter;
  } };
}

test('immutable HTTPS dependency, installed source, release identity and reproducible standalone asset', async () => {
  const identity = verifyDependency();
  assert.equal(upstream.commit, '96b293248611594c388d0fab3af63b1b2d1aae5c');
  assert.equal(upstream.version, '0.4.49');
  assert.equal(await buildAsset(), asset, 'Committed asset must match a fresh build');
  const sandbox = {};
  vm.runInNewContext(asset, sandbox); // No DOM, React, require, timers or fetch.
  assert.deepEqual(Object.keys(sandbox), ['HandrailBugReporter']);
  assert.deepEqual(plain(sandbox.HandrailBugReporter.identity), identity);
  assert.match(asset, /UNLICENSED/);
  for (const name of ['react', 'react-dom', 'scheduler']) assert.ok(asset.includes(`${name} `));
  assert.match(asset, /Permission is hereby granted, free of charge/);
});

test('marker-free loading only initializes bounded lifecycle listeners, with no DOM, timer, storage or network effects', async t => {
  const { w, host, load } = await browser(t);
  const before = w.document.documentElement.outerHTML;
  const mutations = [];
  // jsdom lazily installs selector-engine mouse listeners on its first query.
  // Initialize that harness machinery before measuring bundle-owned effects.
  w.document.querySelectorAll('[data-handrail-bug-reporter="1"]');
  const observer = new w.MutationObserver(records => mutations.push(...records));
  observer.observe(w.document, { childList: true, subtree: true, attributes: true });
  const calls = [];
  for (const name of ['addEventListener', 'removeEventListener']) {
    const original = w.EventTarget.prototype[name];
    w.EventTarget.prototype[name] = function(...args) {
      calls.push(`${name}:${args[0]}`);
      return original.apply(this, args);
    };
  }
  for (const name of ['fetch', 'setTimeout', 'setInterval', 'requestAnimationFrame']) {
    w[name] = () => { calls.push(name); throw new Error(`Load side effect: ${name}`); };
  }
  for (const name of ['localStorage', 'sessionStorage', 'XMLHttpRequest', 'WebSocket']) {
    Object.defineProperty(w, name, { get() { calls.push(name); throw new Error(name); } });
  }
  const api = load();
  await tick();
  assert.deepEqual(calls, [
    'addEventListener:turbo:load', 'addEventListener:turbolinks:load',
    'addEventListener:page:load', 'addEventListener:page:change',
    'addEventListener:turbo:before-cache', 'addEventListener:turbolinks:before-cache',
    'addEventListener:page:before-cache', 'addEventListener:page:before-unload',
    'addEventListener:pagehide', 'addEventListener:pageshow', 'addEventListener:unload',
    'removeEventListener:DOMContentLoaded'
  ]);
  calls.length = 0;
  load();
  assert.deepEqual(calls, [], 'Repeated asset execution adds no listeners');
  assert.deepEqual(mutations, []);
  assert.equal(w.document.documentElement.outerHTML, before);
  assert.equal(host.children.length, 1);
  assert.equal(typeof api.mount, 'function');
  observer.disconnect();
});

test('explicit mount/update/unmount forwards genuine UI options and preserves presentation state', async t => {
  const { w, host, load } = await browser(t);
  const api = load();
  const handle = api.mount(host, {
    config: { transport: 'same-origin', apiBaseUrl: '/rails-bugs',
      projectId: 'project-123', environment: 'staging', allowScreenshots: true,
      fetch: async () => new Response(JSON.stringify({
        schema_version: 1, project_id: 'project-123', environment: 'staging',
        reporter: { identity_verified: true, access_level: 'full_access' },
        reporter_notifications: { available: true, recipient_hint: 'r***@example.com', lifecycles: ['fixed'] },
        ask_options: []
      }), { headers: { 'content-type': 'application/json' } }) },
    initialForm: { title: 'Initial title', description: 'Initial description', notifyOnResolution: true },
    label: 'Tell us', heading: 'Feedback', showHistory: false,
    appearance: { themeMode: 'dark', className: 'custom-dialog',
      tokens: { accent: '#123456' }, style: { '--handrail-bug-radius': '19px' } }
  });
  t.after(() => handle.unmount());
  assert.equal(host.firstElementChild.textContent, 'Host content');
  assert.equal(host.querySelector('[aria-haspopup="dialog"]').textContent, 'Tell us');
  assert.equal(host.querySelector('[role="dialog"]'), null);
  assert.throws(() => api.mount(host, { config: {} }), /already mounted/);
  await tick();
  host.querySelector('button').click();
  await tick();
  const dialog = host.querySelector('[role="dialog"]');
  assert.ok(dialog);
  assert.ok(dialog.classList.contains('custom-dialog'));
  assert.equal(host.querySelector('[data-theme]').getAttribute('data-theme'), 'dark');
  assert.equal(host.querySelector('[data-theme]').style.getPropertyValue('--handrail-bug-radius'), '19px');
  assert.equal(host.querySelector('button').style.getPropertyValue('--handrail-bug-accent'), '#123456');
  assert.equal(host.querySelector('input[placeholder="What is broken?"]').value, 'Initial title');
  assert.equal(host.querySelector('[aria-label="View my bug reports"]'), null);
  assert.equal(host.querySelector('[aria-label="Email me when this bug is fixed"]').checked, true);
  assert.ok(host.querySelector('[aria-label="Attach screenshot"]'));

  assert.equal(handle.update({ label: 'Updated', appearance: { themeMode: 'light' }, showHistory: true }), handle);
  await tick();
  assert.ok(host.querySelector('[role="dialog"]'), 'Presentation updates retain open dialog');
  assert.equal(host.querySelector('input[placeholder="What is broken?"]').value, 'Initial title');
  assert.equal(host.querySelector('[data-theme]').getAttribute('data-theme'), 'light');
  assert.ok(host.querySelector('[aria-label="View my bug reports"]'));
  api.update(host, { appearance: { themeMode: 'auto' } });
  assert.equal(host.querySelector('[data-theme]').getAttribute('data-theme'), 'auto');

  api.update(host, { initialForm: { title: 'Fresh title' } });
  assert.equal(host.querySelector('[role="dialog"]'), null, 'Initial form replacement resets session');
  host.querySelector('button').click();
  await tick();
  assert.equal(host.querySelector('input[placeholder="What is broken?"]').value, 'Fresh title');
  handle.update({ config: { enabled: false } });
  assert.equal(host.querySelector('[role="dialog"]'), null, 'Config replacement resets session');
  api.unmount(host);
  handle.unmount();
  api.unmount(host);
  assert.equal(host.innerHTML, '<span>Host content</span>');
  assert.throws(() => handle.update({ label: 'stale' }), /unmounted/);
  assert.throws(() => api.update(host, {}), /not mounted/);
});

test('repeated mounts dispose islands, abort policy discovery and do not multiply document listeners', async t => {
  const { w, host, load } = await browser(t);
  const api = load();
  const registrations = [];
  const add = w.document.addEventListener.bind(w.document);
  w.document.addEventListener = (type, listener, options) => {
    registrations.push(type);
    return add(type, listener, options);
  };
  const requests = [];
  let afterFirst;
  for (let i = 0; i < 3; i++) {
    const handle = api.mount(host, { config: {
      transport: 'same-origin', apiBaseUrl: '/reporter', projectId: 'project-123', environment: 'staging',
      fetch: (url, init) => {
        requests.push({ url, signal: init.signal });
        return new Promise((resolve, reject) => init.signal.addEventListener('abort', () => {
          reject(new w.DOMException('Aborted', 'AbortError'));
        }, { once: true }));
      }
    } });
    await tick();
    assert.equal(requests.length, i + 1);
    assert.match(requests[i].url, /\/policy\?/);
    assert.equal(requests[i].signal.aborted, false);
    const island = host.querySelector('[data-handrail-bug-reporter-root]');
    handle.unmount();
    await tick();
    assert.equal(requests[i].signal.aborted, true);
    assert.equal(island.isConnected, false);
    assert.equal(island.children.length, 0);
    assert.equal(host.innerHTML, '<span>Host content</span>');
    if (i === 0) afterFirst = registrations.length;
    else assert.equal(registrations.length, afterFirst);
  }
});

test('headless factory forwards config and stamps actual submitted payload with upstream identity', async t => {
  const { load } = await browser(t);
  const api = load();
  const requests = [];
  const reporter = api.createBugReporter({ transport: 'same-origin', apiBaseUrl: '/rails-bugs',
    projectId: 'project-123', environment: 'staging',
    retry: { maxAttempts: 1 }, fetch: async (url, init) => {
      requests.push({ url, init });
      return new Response(JSON.stringify({ ok: true, bug_id: 'bug-1' }), {
        status: 200, headers: { 'content-type': 'application/json' }
      });
    }
  });
  assert.equal(requests.length, 0, 'Factory itself performs no request');
  await reporter.submit({ title: 'A bug', description: 'Details', impact: 'moderate' });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, '/rails-bugs/api/mobile-bug-reports');
  const payload = JSON.parse(requests[0].init.body);
  for (const [key, value] of Object.entries(api.identity)) assert.equal(payload[key], value, key);
  assert.equal(payload.title, 'A bug');
});

test('invalid mounts leave host content intact and independent hosts remain independent', async t => {
  const { w, host, load } = await browser(t);
  const api = load();
  assert.throws(() => api.mount('#host', { config: {} }), /DOM element/);
  assert.throws(() => api.mount(host, {}), /options.config/);
  assert.equal(host.innerHTML, '<span>Host content</span>');
  const second = w.document.createElement('div');
  w.document.body.appendChild(second);
  const firstHandle = api.mount(host, { config: { enabled: false }, label: 'First' });
  const secondHandle = api.mount(second, { config: { enabled: false }, label: 'Second' });
  firstHandle.unmount();
  assert.equal(second.querySelector('button').textContent, 'Second');
  assert.throws(() => secondHandle.update({ config: null }), /options.config/);
  secondHandle.unmount();
});

test('RubyGems builds and installs the prebuilt asset with no Node or Git available', () => {
  const ruby = spawnSync('ruby', ['-rrbconfig', '-e', 'print RbConfig.ruby'], { encoding: 'utf8' });
  assert.equal(ruby.status, 0, ruby.stderr);
  const result = spawnSync(ruby.stdout, ['test/frontend/package_contract.rb'], {
    cwd: root, encoding: 'utf8', env: { ...process.env, PATH: '' }
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /Asset packaged and installed without Node or Git/);
});
