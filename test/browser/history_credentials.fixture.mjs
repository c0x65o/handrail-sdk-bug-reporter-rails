// Private, test-only local state. Never imported by the SDK or packaged assets.
import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { closeSync, constants, fsyncSync, fstatSync, lstatSync, mkdirSync, openSync,
  readFileSync, renameSync, rmdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const historyStateDirectory = fileURLToPath(new URL('../../.history-fixture-private/', import.meta.url));
const stateName = 'credentials.json';
const privateError = () => new Error('Private fixture state is invalid or unavailable.');

function checkPrivate(stat, directory) {
  if (!(directory ? stat.isDirectory() : stat.isFile()) || stat.uid !== process.getuid() ||
      (stat.mode & 0o777) !== (directory ? 0o700 : 0o600) || (!directory && stat.nlink !== 1)) throw privateError();
}

function validate(state) {
  if (!state || state.version !== 1 || !Array.isArray(state.users) ||
      Object.keys(state).sort().join(',') !== 'users,version') throw privateError();
  const logins = new Set();
  for (const user of state.users) {
    if (!user || Object.keys(user).sort().join(',') !== 'hash,identity,login,salt' ||
        typeof user.login !== 'string' || !user.login.trim() || logins.has(user.login) ||
        !['alice', 'bob'].includes(user.identity) || !/^[a-f0-9]{64}$/.test(user.salt) ||
        !/^[a-f0-9]{64}$/.test(user.hash)) throw privateError();
    logins.add(user.login);
  }
  return state;
}

function readState(directory) {
  checkPrivate(lstatSync(directory), true); // Reject symlinks and permissive directories.
  const fd = openSync(join(directory, stateName), constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    checkPrivate(fstatSync(fd), false);
    return validate(JSON.parse(readFileSync(fd, 'utf8')));
  } finally { closeSync(fd); }
}

export function historyFixtureAccounts(directory = historyStateDirectory) {
  try { return readState(directory).users; }
  catch { return []; } // Missing, corrupt or unsafe state always disables login.
}

export function hashHistoryAccount({ login, password, identity }) {
  const salt = randomBytes(32).toString('hex');
  return { login, identity, salt, hash: scryptSync(password, Buffer.from(salt, 'hex'), 32).toString('hex') };
}

export function historyPasswordMatches(password, user) {
  return timingSafeEqual(scryptSync(password, Buffer.from(user.salt, 'hex'), 32), Buffer.from(user.hash, 'hex'));
}

export function seedHistoryFixture({ env = process.env, directory = historyStateDirectory } = {}) {
  const login = env.HANDRAIL_QA_LOGIN, password = env.HANDRAIL_QA_PASSWORD;
  const identity = env.HANDRAIL_TASK_PARAM_PERSONA;
  if (typeof login !== 'string' || !login.trim() || typeof password !== 'string' || !password.trim()) {
    throw new Error('Native task Vault login injection is required.');
  }
  if (!['alice', 'bob'].includes(identity)) throw new Error('Task persona must be alice or bob.');
  if ([env.NODE_ENV, env.RAILS_ENV, env.RACK_ENV].includes('production')) {
    throw new Error('This fixture seed is development-only.');
  }
  try { mkdirSync(directory, { mode: 0o700 }); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
  checkPrivate(lstatSync(directory), true);
  const lock = join(directory, '.seed-lock');
  // Serialize read/modify/rename; concurrent seeds fail safely and may be retried.
  mkdirSync(lock, { mode: 0o700 });
  let temporary;
  try {
    let state;
    try { state = readState(directory); }
    catch (error) { if (error.code !== 'ENOENT') throw error; state = { version: 1, users: [] }; }
    const index = state.users.findIndex(user => user.login === login);
    const previous = state.users[index];
    if (previous?.identity === identity && historyPasswordMatches(password, previous)) return 'unchanged';
    const user = hashHistoryAccount({ login, password, identity });
    if (index < 0) state.users.push(user); else state.users[index] = user;
    temporary = join(directory, `.credentials-${randomBytes(16).toString('hex')}.tmp`);
    const fd = openSync(temporary, 'wx', 0o600);
    try { writeFileSync(fd, JSON.stringify(state) + '\n'); fsyncSync(fd); }
    finally { closeSync(fd); }
    renameSync(temporary, join(directory, stateName));
    temporary = undefined;
    const dirfd = openSync(directory, constants.O_RDONLY | constants.O_DIRECTORY);
    try { fsyncSync(dirfd); } finally { closeSync(dirfd); }
    return 'updated';
  } finally {
    if (temporary) unlinkSync(temporary);
    rmdirSync(lock);
  }
}
