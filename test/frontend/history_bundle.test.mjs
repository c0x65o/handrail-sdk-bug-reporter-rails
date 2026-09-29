import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { read } from '../../scripts/contract.mjs';
import { historyHtml, historyScript } from '../browser/reporter_history.fixture.mjs';
const tick = () => new Promise(resolve => setTimeout(resolve, 30));

async function fixture(t) {
  const dom = new JSDOM(historyHtml, { url: 'https://fixture.invalid/history-fixture', runScripts: 'outside-only', pretendToBeVisual: true });
  const w = dom.window;
  t.after(() => { w.historyFixture?.handle.unmount(); w.close(); });
  Object.assign(w, { Headers, Request, Response });
  w.eval(read('app/assets/javascripts/handrail_bug_reporter.js'));
  w.eval(historyScript);
  const button = text => [...w.document.querySelectorAll('button')].find(b => b.textContent === text);
  const click = async text => { assert.ok(button(text), text); button(text).click(); await tick(); };
  const open = async () => { await tick(); await click('Open feedback'); w.document.querySelector('[data-handrail-bug-view-switch="history"]').click(); await tick(); };
  return { w, state: w.historyFixture, button, click, open, text: () => w.document.body.textContent };
}

test('real Rails asset: Mine default, conditional All users, fresh policy, private shared detail and revocation', async t => {
  const f = await fixture(t);
  await f.open();
  assert.ok(f.button('Mine'));
  assert.equal(f.button('All users'), undefined);
  assert.match(f.text(), /My checkout report/);
  f.state.allowed = true;
  f.state.switchIdentity('alice'); // Reopen with fresh policy.
  await f.open();
  await f.click('All users');
  assert.match(f.text(), /Shared checkout report/);
  assert.ok(f.w.document.querySelector('[aria-label="Archive My checkout report"]'));
  assert.equal(f.w.document.querySelector('[aria-label="Archive Shared checkout report"]'), null);
  f.w.document.querySelector('[aria-label="View Shared checkout report"]').click();
  await tick();
  assert.equal(f.w.document.querySelector('[data-handrail-bug-history] img'), null, 'No shared attachment preview');
  await f.state.reporter.getBug('bob-bug', { audience: 'all' });
  const shared = f.state.requests.filter(r => r.query.includes('audience=all'));
  assert.ok(shared.some(r => r.path.includes('/bugs/')));
  for (const request of shared) {
    const index = f.state.requests.indexOf(request);
    assert.ok(f.state.requests[index - 1].path.endsWith('/policy'), 'Fresh discovery before every shared read');
  }
  f.state.allowed = false;
  const reads = shared.length;
  await f.click('All users');
  assert.doesNotMatch(f.text(), /Shared checkout report/);
  assert.equal(f.state.requests.filter(r => r.query.includes('audience=all')).length, reads, 'Revoked discovery prevents the shared read');
  assert.ok(f.state.requests.every(r => r.method === 'GET'), 'Shared history made no mutation');
});

test('real Rails asset: sessionKey switch aborts shared requests and discards late results', async t => {
  const f = await fixture(t);
  f.state.allowed = true;
  await f.open();
  f.state.hold = true;
  await f.click('All users');
  assert.equal(f.state.pending.length, 1);
  const pending = f.state.pending[0];
  f.state.switchIdentity('bob');
  assert.equal(pending.signal.aborted, true);
  pending.resolve();
  await f.open();
  assert.doesNotMatch(f.text(), /Shared checkout report|My checkout report/);
  assert.equal(f.button('Mine').getAttribute('aria-pressed'), 'true');
  f.state.switchIdentity('anonymous');
  await f.open();
  assert.equal(f.button('All users'), undefined);
  assert.doesNotMatch(f.text(), /Shared checkout report|My checkout report/);
});
