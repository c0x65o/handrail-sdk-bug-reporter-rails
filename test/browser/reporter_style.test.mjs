import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chromium } from 'playwright';
import { upstream } from '../../scripts/contract.mjs';
import { startStyleFixture, fixturePath, endpoint, cases, context } from './reporter_style.fixture.mjs';

const consentName = 'Email me when this bug is fixed';
const dialogSelector = '[data-handrail-bug-reporter-dialog]';
const hostMetrics = page => page.locator('#host-controls').evaluate(root =>
  [...root.querySelectorAll('label, input')].map(element => ({
    width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height,
    css: [...getComputedStyle(element)].map(key => [key, getComputedStyle(element).getPropertyValue(key)]),
    value: element.value, checked: element.checked,
  })));

async function layout(page) {
  return page.getByRole('checkbox', { name: consentName }).evaluate(input => {
    const label = input.closest('label');
    const copy = label.querySelector('span');
    const hint = copy.querySelector('span');
    const box = input.getBoundingClientRect();
    const row = label.getBoundingClientRect();
    const text = copy.getBoundingClientRect();
    const dialog = document.querySelector('[data-handrail-bug-reporter-dialog]');
    const bounds = dialog.getBoundingClientRect();
    const css = getComputedStyle(dialog);
    return {
      width: box.width, height: box.height, gap: text.left - box.right,
      fits: text.right <= row.right + 1, overflow: label.scrollWidth > label.clientWidth + 1,
      wraps: hint.getBoundingClientRect().height > parseFloat(getComputedStyle(hint).lineHeight),
      helperWeight: getComputedStyle(hint).fontWeight, helperSize: getComputedStyle(hint).fontSize,
      helperColor: getComputedStyle(hint).color, titleWeight: getComputedStyle(copy.querySelector('strong')).fontWeight,
      fontFamily: getComputedStyle(hint).fontFamily, accent: getComputedStyle(input).accentColor,
      appearance: getComputedStyle(input).appearance, pseudo: getComputedStyle(label, '::before').content,
      bounds: { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height },
      dialog: { color: css.color, fontFamily: css.fontFamily, background: css.backgroundColor,
        radius: css.borderRadius, radiusToken: css.getPropertyValue('--handrail-bug-radius').trim(),
        surface: css.getPropertyValue('--handrail-bug-surface').trim() },
    };
  });
}

function assertLayout(actual, theme, width) {
  assert.equal(actual.width, 14, 'compact consent width');
  assert.equal(actual.height, 14, 'compact consent height');
  assert.equal(actual.gap, 9, 'consent copy gap');
  assert.equal(actual.fits, true);
  assert.equal(actual.overflow, false);
  assert.equal(actual.wraps, true, 'long recipient hint actually wraps');
  assert.equal(actual.helperWeight, '400');
  assert.equal(actual.helperSize, '11px');
  assert.equal(actual.helperColor, theme === 'dark' ? 'rgb(187, 187, 187)' : 'rgb(102, 102, 102)');
  assert.equal(actual.titleWeight, '700');
  assert.equal(actual.fontFamily, 'Arial, sans-serif');
  assert.equal(actual.accent, 'rgb(200, 62, 8)');
  assert.equal(actual.appearance, 'auto');
  assert.equal(actual.pseudo, 'none');
  assert.equal(actual.dialog.fontFamily, 'Arial, sans-serif');
  assert.equal(actual.dialog.color, theme === 'dark' ? 'rgb(250, 250, 250)' : 'rgb(32, 32, 32)');
  assert.equal(actual.dialog.background, theme === 'dark' ? 'rgb(21, 26, 35)' : 'rgb(255, 255, 255)');
  assert.equal(actual.dialog.surface, theme === 'dark' ? '#151a23' : '#ffffff');
  assert.equal(actual.dialog.radiusToken, '13px');
  // Upstream's <=560px full-screen layout explicitly removes corner rounding.
  assert.equal(actual.dialog.radius, width <= 560 ? '0px' : '13px');
  assert.ok(actual.bounds.width > width / 2);
  assert.ok(actual.bounds.x >= 0 && actual.bounds.x + actual.bounds.width <= width);
  assert.ok(actual.bounds.y >= 0 && actual.bounds.y + actual.bounds.height <= 900);
}

test('Rails helper/packaged adapter CSS parity with verified JS v0.4.49', async t => {
  const fixture = await startStyleFixture();
  let browser;
  try {
    browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined });
    t.diagnostic(`Node ${process.version}; Chromium ${browser.version()}; Rails ${fixture.railsVersion}; JS ${upstream.version} ${upstream.commit}`);
    for (const width of [1280, 390]) {
      for (const { theme, absent, expected } of cases) {
        await t.test(`${width}px ${theme}, context ${absent ? 'absent' : 'provided'}`, async cell => {
          const measurements = [];
          const page = await browser.newPage({ viewport: { width, height: 900 },
            deviceScaleFactor: 1, colorScheme: theme, reducedMotion: 'reduce', locale: 'en-US', timezoneId: 'UTC',
            serviceWorkers: 'block' });
          const errors = [];
          const external = [];
          page.on('pageerror', error => errors.push(error.message));
          page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
          await page.route('**/*', route => {
            const url = new URL(route.request().url());
            if (url.origin === fixture.origin) return route.continue();
            external.push(route.request().url());
            return route.abort('blockedbyclient');
          });
          const url = renderer => `${fixture.origin}${fixturePath}?renderer=${renderer}&theme=${theme}&absent=${absent}&private_query=never-collected#private-fragment`;
          try {
            await page.goto(url('host'));
            const hostBefore = await hostMetrics(page);
            for (const renderer of ['reference', 'rails']) {
              const policyBefore = fixture.requests.filter(r => r.path === `${endpoint}/policy`).length;
              const response = await page.goto(url(renderer));
              assert.match(response.headers()['content-security-policy'], /img-src 'self' data: blob:/);
              // Policy is loaded by the mounted provider even while the dialog is closed.
              await page.waitForFunction(() => document.querySelector('#host-bug-button'));
              await assertEventually(() => fixture.requests.filter(r => r.path === `${endpoint}/policy`).length > policyBefore);
              if (renderer === 'rails') {
                const identity = await page.evaluate(() => window.HandrailBugReporter.identity);
                assert.equal(identity.reporter_sdk_commit, upstream.commit);
                assert.equal(identity.reporter_sdk_version, upstream.version);
                assert.deepEqual(await page.locator('[data-handrail-bug-reporter="1"]').evaluate(el =>
                  JSON.parse(el.dataset.handrailBugReporterOptions)), expected);
              }
              assert.deepEqual(await hostMetrics(page), hostBefore, 'mount leaves host controls unchanged');
              // Reach the pre-existing launcher with the keyboard (host controls are still focusable).
              await page.locator('#host-bug-button').focus();
              await page.keyboard.press('Enter');
              const dialog = page.locator(dialogSelector);
              const checkbox = page.getByRole('checkbox', { name: consentName });
              await checkbox.waitFor({ state: 'visible' });
              await page.waitForFunction(selector => document.querySelector(selector)?.contains(document.activeElement), dialogSelector);
              const beforeLateCSS = await layout(page);
              assertLayout(beforeLateCSS, theme, width);
              await page.addStyleTag({ url: `${fixture.origin}/host.css` });
              const afterLateCSS = await layout(page);
              assertLayout(afterLateCSS, theme, width);
              assert.deepEqual(afterLateCSS, beforeLateCSS, 'late hostile rules do not alter SDK metrics');
              assert.deepEqual(await hostMetrics(page), hostBefore, 'SDK reset stays scoped');
              const attached = page.locator('[data-handrail-bug-context] section').first();
              const contextValues = await attached.locator('strong').allTextContents();
              assert.deepEqual(contextValues, [absent ? fixturePath : context.route,
                absent ? 'Not provided' : context.app_version, 'staging']);
              assert.doesNotMatch(await attached.innerText(), /private_query|private-fragment|never-collected/);
              if (absent) {
                assert.deepEqual(expected.initialForm, {});
                for (const value of Object.values(context)) assert.ok(!(await dialog.innerText()).includes(value));
              }
              // Tab through the actual dialog to consent, then operate its native checkbox.
              let reached = false;
              for (let i = 0; i < 30; i++) {
                await page.keyboard.press('Tab');
                if (await checkbox.evaluate(el => el === document.activeElement)) { reached = true; break; }
              }
              assert.ok(reached, 'checkbox is keyboard reachable');
              assert.equal(await checkbox.isChecked(), false);
              await page.keyboard.press('Space');
              assert.equal(await checkbox.isChecked(), true);
              assert.deepEqual(await checkbox.evaluate(el => ({ visible: el.matches(':focus-visible'),
                outline: getComputedStyle(el).outlineWidth, color: getComputedStyle(el).outlineColor })),
              { visible: true, outline: '2px', color: 'rgb(200, 62, 8)' });
              await page.getByText(consentName, { exact: true }).click();
              assert.equal(await checkbox.isChecked(), false);

              // Generate real PNG bytes locally; upload produces a File/Blob through the public UI.
              const png = await page.evaluate(() => {
                const canvas = document.createElement('canvas'); canvas.width = 32; canvas.height = 24;
                const ctx = canvas.getContext('2d'); ctx.fillStyle = '#c83e08'; ctx.fillRect(0, 0, 32, 24);
                return canvas.toDataURL('image/png').split(',')[1];
              });
              await page.getByLabel('Attach screenshot', { exact: true }).setInputFiles({
                name: 'fixture.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
              const preview = page.getByAltText('Bug report screenshot preview');
              await preview.waitFor({ state: 'visible' });
              const decoded = await preview.evaluate(async img => {
                await img.decode();
                return { blob: img.currentSrc.startsWith('blob:'), complete: img.complete,
                  width: img.naturalWidth, height: img.naturalHeight };
              });
              assert.deepEqual(decoded, { blob: true, complete: true, width: 32, height: 24 });
              await checkbox.focus();
              await page.keyboard.press('Escape');
              await dialog.waitFor({ state: 'detached' });
              assert.equal(await page.locator('#host-bug-button').evaluate(el => el === document.activeElement), true);
              assert.deepEqual(await hostMetrics(page), hostBefore, 'dismissal leaves host controls unchanged');
              measurements.push({ beforeLateCSS, afterLateCSS, contextValues, decoded });
            }
            assert.deepEqual(measurements[1], measurements[0], 'Rails and pinned direct React render agree');
            cell.diagnostic(`Both renderers: ${JSON.stringify(measurements[0])}`);
            assert.deepEqual(errors, []);
            assert.deepEqual(external, []);
            assert.deepEqual(fixture.unexpected, []);
          } finally { await page.close(); }
        });
      }
    }
    assert.ok(fixture.requests.every(request => request.method === 'GET'), 'no submissions');
  } finally {
    await browser?.close();
    await fixture.close();
  }
});

async function assertEventually(predicate) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.fail('mounted provider did not request local policy');
}
