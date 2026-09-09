import assert from 'node:assert/strict';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { chromium } from 'playwright';
import { read, sha256, upstream } from '../../scripts/contract.mjs';
import { assertReporterFormLayout } from './reporter-form-layout.mjs';

// Check the existing QA service, rather than starting a fresh fixture that can
// hide an old in-memory asset. Only local fixture GETs are allowed.
const origin = new URL(process.argv[2] || 'http://127.0.0.1:4177').origin;
const output = process.argv[3] && resolve(process.argv[3]);
const expectedAsset = read('app/assets/javascripts/handrail_bug_reporter.js');
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
});
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 },
    deviceScaleFactor: 1, serviceWorkers: 'block' });
  const errors = [];
  const blocked = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.origin === origin && request.method() === 'GET' && [
      '/style-fixture', '/host.css', '/javascripts/handrail_bug_reporter.js',
      '/feedback/api/mobile-bug-reports/policy',
    ].includes(url.pathname)) return route.continue();
    blocked.push(`${request.method()} ${request.url()}`);
    return route.abort('blockedbyclient');
  });
  if (output) mkdirSync(output, { recursive: true });
  for (const stage of ['initial', 'after-reload']) {
    const assetResponse = page.waitForResponse(response =>
      new URL(response.url()).pathname === '/javascripts/handrail_bug_reporter.js');
    const response = stage === 'initial'
      ? await page.goto(`${origin}/style-fixture?renderer=rails&theme=light&absent=false`)
      : await page.reload();
    assert.equal(response.status(), 200);
    const asset = await assetResponse;
    assert.equal(asset.status(), 200);
    assert.equal(sha256(await asset.body()), sha256(expectedAsset),
      'Served asset differs from the reviewed asset; restart the fixture service');
    const identity = await page.evaluate(() => window.HandrailBugReporter.identity);
    assert.equal(identity.reporter_sdk_version, upstream.version);
    assert.equal(identity.reporter_sdk_commit, upstream.commit);
    await page.getByRole('button', { name: 'Help', exact: true }).click();
    await page.getByRole('checkbox', { name: 'Email me when this bug is fixed' }).waitFor();
    const fields = await assertReporterFormLayout(page);
    assert.equal(await page.getByLabel('Bug severity', { exact: true }).inputValue(), 'moderate');
    if (output) await page.screenshot({ path: resolve(output, `reporter-${stage}.png`) });
    console.log(JSON.stringify({ stage, identity, assetSha256: sha256(expectedAsset), fields }));
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.locator('[data-handrail-bug-reporter-dialog]').waitFor({ state: 'detached' });
  }
  assert.deepEqual(errors, [], 'no console or page errors');
  assert.deepEqual(blocked, [], 'no submissions or external requests');
} finally {
  await browser.close();
}
