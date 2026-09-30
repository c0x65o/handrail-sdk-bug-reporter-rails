import assert from 'node:assert/strict';
import test from 'node:test';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { historyFixtureAccounts, historyPasswordMatches, seedHistoryFixture } from '../browser/history_credentials.fixture.mjs';

function workspace(t) {
  const root = mkdtempSync(join(tmpdir(), 'history-seed-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const directory = join(root, '.history-fixture-private');
  const path = join(directory, 'credentials.json');
  const env = { HANDRAIL_QA_LOGIN: 'qa-history-alice', HANDRAIL_QA_PASSWORD: randomBytes(24).toString('hex'),
    HANDRAIL_TASK_PARAM_PERSONA: 'alice' };
  return { root, directory, path, env, seed: (values = env) => seedHistoryFixture({ directory, env: values }) };
}

test('fresh seed, byte-for-byte idempotence, separate salts, reconciliation and unrelated-user preservation', t => {
  const f = workspace(t);
  assert.equal(f.seed(), 'updated');
  const first = readFileSync(f.path, 'utf8'), before = statSync(f.path);
  assert.equal(statSync(f.directory).mode & 0o777, 0o700);
  assert.equal(before.mode & 0o777, 0o600);
  assert.ok(!first.includes(f.env.HANDRAIL_QA_PASSWORD));
  assert.equal(f.seed(), 'unchanged');
  assert.equal(readFileSync(f.path, 'utf8'), first);
  assert.equal(statSync(f.path).ino, before.ino);
  assert.equal(statSync(f.path).mtimeMs, before.mtimeMs);
  const alice = historyFixtureAccounts(f.directory)[0];
  assert.ok(historyPasswordMatches(f.env.HANDRAIL_QA_PASSWORD, alice));
  assert.ok(!historyPasswordMatches('wrong', alice));
  const bob = { ...f.env, HANDRAIL_QA_LOGIN: 'qa-history-bob', HANDRAIL_TASK_PARAM_PERSONA: 'bob' };
  assert.equal(f.seed(bob), 'updated');
  const users = historyFixtureAccounts(f.directory);
  assert.deepEqual(users[0], alice);
  assert.notEqual(users[0].salt, users[1].salt);
  assert.notEqual(users[0].hash, users[1].hash);
  const changed = { ...f.env, HANDRAIL_QA_PASSWORD: randomBytes(24).toString('hex') };
  assert.equal(f.seed(changed), 'updated');
  const updated = historyFixtureAccounts(f.directory);
  assert.deepEqual(updated[1], users[1]);
  assert.equal(updated.length, 2);
  assert.ok(historyPasswordMatches(changed.HANDRAIL_QA_PASSWORD, updated[0]));
  assert.ok(!historyPasswordMatches(f.env.HANDRAIL_QA_PASSWORD, updated[0]));
});

test('missing secrets/persona and production fail without state changes; no password complexity imposed', t => {
  const f = workspace(t);
  for (const key of ['HANDRAIL_QA_LOGIN', 'HANDRAIL_QA_PASSWORD', 'HANDRAIL_TASK_PARAM_PERSONA']) {
    for (const value of [undefined, '', ' ']) assert.throws(() => f.seed({ ...f.env, [key]: value }));
  }
  assert.throws(() => f.seed({ ...f.env, HANDRAIL_TASK_PARAM_PERSONA: 'admin' }));
  assert.throws(() => f.seed({ ...f.env, NODE_ENV: 'production' }));
  assert.deepEqual(historyFixtureAccounts(f.directory), []);
  assert.equal(f.seed({ ...f.env, HANDRAIL_QA_PASSWORD: 'x' }), 'updated');
  const before = readFileSync(f.path, 'utf8');
  assert.throws(() => f.seed({ ...f.env, HANDRAIL_QA_PASSWORD: '' }));
  assert.equal(readFileSync(f.path, 'utf8'), before);
});

test('unsafe modes, symlinks, corrupt state and concurrent seed locks fail closed without clobbering', t => {
  const f = workspace(t);
  f.seed();
  const before = readFileSync(f.path, 'utf8');
  chmodSync(f.path, 0o644);
  assert.deepEqual(historyFixtureAccounts(f.directory), []);
  assert.throws(() => f.seed());
  chmodSync(f.path, 0o600);
  chmodSync(f.directory, 0o755);
  assert.deepEqual(historyFixtureAccounts(f.directory), []);
  assert.throws(() => f.seed());
  chmodSync(f.directory, 0o700);
  mkdirSync(join(f.directory, '.seed-lock'), { mode: 0o700 });
  assert.throws(() => f.seed());
  assert.equal(readFileSync(f.path, 'utf8'), before);
  rmSync(join(f.directory, '.seed-lock'), { recursive: true });
  writeFileSync(f.path, '{broken');
  assert.deepEqual(historyFixtureAccounts(f.directory), []);
  assert.throws(() => f.seed());
  assert.equal(readFileSync(f.path, 'utf8'), '{broken');
  rmSync(f.path);
  const target = join(f.root, 'unrelated');
  writeFileSync(target, before, { mode: 0o600 });
  symlinkSync(target, f.path);
  assert.deepEqual(historyFixtureAccounts(f.directory), []);
  assert.throws(() => f.seed());
  assert.equal(readFileSync(target, 'utf8'), before);
});

test('exact native seed command uses injected environment only and emits no credentials', t => {
  const f = workspace(t);
  // Execute the unchanged entrypoint in a disposable repo-shaped root. Never seed
  // fabricated test credentials into the real service state or a Vault profile.
  for (const dir of ['scripts', 'test/browser']) mkdirSync(join(f.root, dir), { recursive: true });
  for (const file of ['scripts/seed-history-fixture.mjs', 'test/browser/history_credentials.fixture.mjs']) {
    copyFileSync(new URL('../../' + file, import.meta.url), join(f.root, file));
  }
  const run = env => spawnSync(process.execPath, ['scripts/seed-history-fixture.mjs'], {
    cwd: f.root, env, encoding: 'utf8' });
  const missing = run({});
  assert.equal(missing.status, 1);
  assert.match(missing.stderr, /seed failed/);
  for (const expected of ['updated', 'unchanged']) {
    const result = run(f.env);
    assert.equal(result.status, 0);
    assert.equal(result.stdout.trim(), `Private history fixture credentials ${expected}.`);
    assert.equal(result.stderr, '');
    assert.ok(!result.stdout.includes(f.env.HANDRAIL_QA_LOGIN));
    assert.ok(!result.stdout.includes(f.env.HANDRAIL_QA_PASSWORD));
  }
  assert.equal(historyFixtureAccounts(f.directory)[0].identity, 'alice');
});
