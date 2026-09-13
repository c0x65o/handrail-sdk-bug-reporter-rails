import assert from 'node:assert/strict';

// Only the disposable workflow host exposes this transition. It uses a real
// encrypted session and CSRF verifier; it never provisions a QA account.
export async function changeSession(page, state) {
  const status = await page.evaluate(async state => {
    const csrf = document.querySelector('meta[name="csrf-token"]').content;
    const response = await fetch('/fixture-session', { method: 'POST',
      headers: { 'content-type': 'application/json', 'x-csrf-token': csrf },
      body: JSON.stringify({ state }) });
    return response.status;
  }, state);
  assert.equal(status, 200);
}

export async function loginAdmin(page, origin) {
  await page.goto(origin);
  assert.equal(await page.locator('[data-handrail-bug-reporter="1"]').count(), 0);
  await changeSession(page, 'admin');
}
