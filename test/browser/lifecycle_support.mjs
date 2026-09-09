import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

export const root = fileURLToPath(new URL('../..', import.meta.url));
export const marker = '[data-handrail-bug-reporter="1"]';
export const island = '[data-handrail-bug-reporter-root]';
export const endpoint = '/fixture/api/mobile-bug-reports';
export const asset = '/javascripts/handrail_bug_reporter.js';
const redact = text => text.replace(/(?:hbr_workflow|workflow)[A-Za-z0-9_-]*sentinel[A-Za-z0-9_-]*/g, '[REDACTED]')
  .replace(/workflow-private-principal/g, '[REDACTED]').replace(/(csrf|cookie|authorization)[^\n]*/gi, '$1 [REDACTED]');

export async function fixture(t, scenario = 'submission') {
  const directory = await mkdtemp(join(tmpdir(), 'rails-lifecycle-'));
  const auditPath = join(directory, 'http.jsonl');
  const artifactDir = process.env.LIFECYCLE_ARTIFACT_DIR || await mkdtemp(join(tmpdir(), 'rails-lifecycle-artifacts-'));
  await mkdir(artifactDir, { recursive: true });
  let server, browser, context, page, output = '', versions;
  const external = [], errors = [], network = [];
  t.after(async () => {
    try {
      if (page && !page.isClosed()) {
        // Screenshots contain fixture data only. Never persist DOM, cookies,
        // bodies, raw headers, or Playwright traces containing session tokens.
        await page.screenshot({ path: join(artifactDir, `${t.name.replace(/\W+/g, '-')}.png`) });
      }
      await writeFile(join(artifactDir, `${t.name.replace(/\W+/g, '-')}.json`),
        JSON.stringify({ test: t.name, passed: t.passed, versions, network, external, errors: errors.map(redact) }, null, 2));
    } finally {
      try { await context?.close(); } finally {
        try { await browser?.close(); } finally {
          if (server?.pid && server.exitCode === null && server.signalCode === null) {
            const exited = once(server, 'exit');
            server.kill('SIGTERM');
            const timer = setTimeout(() => server.kill('SIGKILL'), 5_000);
            try { await exited; } finally { clearTimeout(timer); }
          }
          if (t.passed === false) t.diagnostic(redact(output));
          await rm(directory, { recursive: true, force: true });
          if (server?.pid) assert.equal(server.exitCode, 0, `Fixture/no-network guard exit: ${redact(output)}`);
        }
      }
    }
  });
  server = spawn(process.env.RUBY || 'ruby', ['test/fixtures/workflow/server.rb'], {
    cwd: root, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, BUNDLE_GEMFILE: join(root, 'Gemfile'), BUNDLE_FROZEN: 'true',
      WORKFLOW_SCENARIO: scenario, WORKFLOW_AUDIT: auditPath }
  });
  const ready = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Rails startup exceeded 30s: ${redact(output)}`)), 30_000);
    const fail = error => { clearTimeout(timer); reject(error); };
    server.once('error', fail);
    server.once('exit', code => fail(new Error(`Rails exited ${code}: ${redact(output)}`)));
    server.stderr.on('data', bytes => { output = (output + bytes).slice(-16000); });
    let buffer = '';
    server.stdout.on('data', bytes => {
      buffer += bytes;
      const lines = buffer.split('\n'); buffer = lines.pop();
      for (const line of lines) if (line.startsWith('{')) {
        const row = JSON.parse(line);
        if (row.ready) { clearTimeout(timer); resolve(row); }
      }
    });
  });
  const origin = `http://127.0.0.1:${ready.port}`;
  browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
    args: ['--disable-background-networking'], timeout: 30_000 });
  versions = { node: process.version, chromium: browser.version(), ...ready };
  for (const name of ['playwright', '@hotwired/turbo', 'turbolinks']) {
    versions[name] = JSON.parse(await readFile(join(root, 'node_modules', name, 'package.json'))).version;
  }
  t.diagnostic(JSON.stringify(versions));
  context = await browser.newContext({ serviceWorkers: 'block' });
  await context.route(url => url.origin !== origin, route => {
    external.push(new URL(route.request().url()).origin);
    return route.abort('blockedbyclient');
  });
  page = await context.newPage();
  page.setDefaultTimeout(8_000);
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) errors.push(message.text()); });
  page.on('response', response => network.push({ path: new URL(response.url()).pathname,
    method: response.request().method(), status: response.status() }));
  await page.clock.install();
  await page.addInitScript(() => {
    window.fixture = { documentId: crypto.randomUUID(), calls: [], intervals: new Set(), events: [] };
    const nativeFetch = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const row = { url: String(input?.url || input), method: init?.method || input?.method || 'GET',
        headers: Object.fromEntries(new Headers(init?.headers || input?.headers)),
        credentials: init?.credentials || input?.credentials, body: init?.body, aborted: false };
      window.fixture.calls.push(row);
      init?.signal?.addEventListener('abort', () => { row.aborted = true; }, { once: true });
      try { const response = await nativeFetch(input, init); row.status = response.status; return response; }
      finally { row.settled = true; }
    };
    const set = window.setInterval.bind(window), clear = window.clearInterval.bind(window);
    window.setInterval = (callback, delay, ...args) => {
      const id = set(callback, delay, ...args);
      if (delay === 15000) window.fixture.intervals.add(id);
      return id;
    };
    window.clearInterval = id => { window.fixture.intervals.delete(id); return clear(id); };
    const dispatch = EventTarget.prototype.dispatchEvent;
    EventTarget.prototype.dispatchEvent = function(event) {
      const result = dispatch.call(this, event);
      // Observe after all synchronous library/adapter handlers, not in a
      // microtask which Chromium may run between individual event listeners.
      if (/^(turbo|turbolinks):(load|before-cache)$/.test(event.type)) fixture.events.push({ name: event.type,
        roots: document.querySelectorAll('[data-handrail-bug-reporter-root]').length });
      return result;
    };
  });
  async function audit() {
    return (await readFile(auditPath, 'utf8').catch(() => '')).trim().split('\n').filter(Boolean).map(JSON.parse);
  }
  return { page, origin, network, audit,
    async capture(label) {
      await page.screenshot({ path: join(artifactDir, `${t.name.replace(/\W+/g, '-')}-${label}.png`) });
    },
    async goto(variant = 'first', navigation = 'ordinary', query = '') {
      const response = await page.goto(`${origin}/lifecycle/${navigation}/${variant}${query}`);
      assert.equal(response.status(), 200);
    },
    async finish() {
      assert.deepEqual(external, []); assert.deepEqual(errors, []);
      const unexpected = network.filter(row => row.status >= 400 && !(scenario === 'lifecycle_retry' &&
        ((row.method === 'POST' && row.path === endpoint && row.status === 502) ||
         (row.method === 'PUT' && row.path.endsWith('/archive') && row.status === 403))));
      assert.deepEqual(unexpected, [], 'Only explicitly scripted/rejected responses may fail');
      assert.deepEqual((await audit()).filter(row => row.kind === 'fixture_error'), []);
      t.diagnostic(`Redacted artifacts: ${artifactDir}`);
    }
  };
}

export async function roots(page, count = 1) {
  await page.waitForFunction(({ selector, count }) => document.querySelectorAll(selector).length === count,
    { selector: island, count });
}
export async function open(page, label = 'Report a bug') {
  await page.getByRole('button', { name: label, exact: true }).click();
  await page.getByRole('dialog').waitFor();
  await page.waitForFunction(() => document.querySelector('[role="dialog"]')?.contains(document.activeElement));
}
export async function send(page) {
  const response = page.waitForResponse(r => r.request().method() === 'POST' && new URL(r.url()).pathname.endsWith('/api/mobile-bug-reports') && r.status() === 201);
  await page.getByRole('button', { name: 'Send report', exact: true }).click();
  await response;
  await page.getByRole('heading', { name: 'Thanks for submitting this bug' }).waitFor();
}
