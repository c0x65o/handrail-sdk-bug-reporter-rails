// Run only in native QA, using its scoped proxy target and artifact output.
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const target = process.env.HANDRAIL_BROWSER_TARGET_URL;
const runDir = process.env.HANDRAIL_VALIDATION_RUN_DIR;
const helper = process.env.HANDRAIL_QA_BROWSER_HELPER;
assert.ok(target && runDir && helper,
  'Native QA must supply HANDRAIL_BROWSER_TARGET_URL (/history-fixture), HANDRAIL_VALIDATION_RUN_DIR and HANDRAIL_QA_BROWSER_HELPER.');
const { openValidationPage } = await import(pathToFileURL(resolve(helper)).href);
const session = await openValidationPage({ targetUrl: target, viewport: '1440x1000', forceReload: true });
const { page } = session;
const artifacts = [];
const errors = [];
page.on('pageerror', error => errors.push(error.message));
const screenshotDir = resolve(runDir, 'screenshots');
await mkdir(screenshotDir, { recursive: true });
async function capture(name) {
  const path = resolve(screenshotDir, name + '.png');
  await page.screenshot({ path, fullPage: true });
  const bytes = await readFile(path);
  artifacts.push({ path: 'screenshots/' + name + '.png', sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, synthetic: true });
}
async function openHistory() {
  await page.getByRole('button', { name: 'Open feedback', exact: true }).click();
  await page.locator('[data-handrail-bug-view-switch="history"]').click();
  await page.getByRole('button', { name: 'Mine', exact: true }).waitFor();
}
try {
  for (const [width, height, size] of [[1440, 1000, 'desktop'], [390, 844, 'mobile']]) {
    await page.setViewportSize({ width, height });
    await page.goto(target);
    const login = await page.evaluate(async () => {
      const response = await fetch('/fixture-session', { credentials: 'same-origin' });
      return response.ok ? response.json() : null;
    });
    assert.equal(login?.authenticated, true, 'Native QA must authenticate through the real fixture login using its same-project dev Vault profile.');
    assert.equal(login.identity, 'alice', 'Run the focused rendering recipe with the Alice QA profile.');
    await openHistory();
    assert.equal(await page.getByRole('button', { name: 'All users', exact: true }).count(), 0);
    await page.getByRole('button', { name: 'View My checkout report', exact: true }).waitFor();
    await capture(size + '-off-mine');
    await page.evaluate(() => { historyFixture.allowed = true; historyFixture.switchIdentity('alice'); });
    await openHistory();
    await page.getByRole('button', { name: 'All users', exact: true }).click();
    await page.getByRole('button', { name: 'View Shared checkout report', exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Archive Shared checkout report', exact: true }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Archive My checkout report', exact: true }).count(), 1);
    assert.equal(await page.locator('[data-handrail-bug-history] img').count(), 0);
    const bounds = await page.locator('[data-handrail-bug-reporter-dialog]').boundingBox();
    assert.ok(bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= width + 1 && bounds.y + bounds.height <= height + 1);
    await capture(size + '-on-all-users');
    await page.evaluate(() => { historyFixture.allowed = false; });
    await page.getByRole('button', { name: 'All users', exact: true }).click();
    await page.getByRole('button', { name: 'View Shared checkout report', exact: true }).waitFor({ state: 'detached' });
    await capture(size + '-revoked');
    await page.evaluate(() => { historyFixture.allowed = true; historyFixture.switchIdentity('alice'); });
    await openHistory(); // Rediscover after OFF before beginning the held-response scenario.
    await page.evaluate(() => { historyFixture.hold = true; });
    await page.getByRole('button', { name: 'All users', exact: true }).click();
    await page.waitForFunction(() => historyFixture.pending.length === 1);
    assert.equal(await page.evaluate(() => {
      const pending = historyFixture.pending[0];
      historyFixture.switchIdentity('bob');
      pending.resolve();
      return pending.signal.aborted;
    }), true);
    await openHistory();
    assert.equal(await page.getByRole('button', { name: 'View Shared checkout report', exact: true }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Mine', exact: true }).getAttribute('aria-pressed'), 'true');
    await capture(size + '-switched-user');
  }
  assert.deepEqual(errors, []);
  const identity = await page.evaluate(() => HandrailBugReporter.identity);
  assert.equal(identity.reporter_sdk_commit, '48d046430519871c55db84cb7ace7efd364814ab');
  const logout = await page.evaluate(async () => {
    const state = await (await fetch('/fixture-session', { credentials: 'same-origin' })).json();
    const response = await fetch('/fixture-session', { method: 'POST', credentials: 'same-origin',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ action: 'logout', csrf: state.csrf }) });
    return { logout: response.status, after: (await fetch('/fixture-session', { credentials: 'same-origin' })).status };
  });
  assert.deepEqual(logout, { logout: 200, after: 401 });
  await writeFile(resolve(runDir, 'history-bundle-evidence.json'), JSON.stringify({
    observedAt: new Date().toISOString(), target, identity, synthetic: true, outerLogin: { persona: 'alice', logout },
    limitation: 'Genuine outer fixture login; policy/history and UI identity switching remain synthetic. Known Users verification is covered separately by the disposable Handrail SQL integration, not by this login.', artifacts, errors,
  }, null, 2) + '\n');
} finally {
  await session.browser.close();
}
