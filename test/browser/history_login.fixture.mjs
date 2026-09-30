// Test-only authentication for the existing native QA fixture. No SDK/runtime export.
// Only salted hashes loaded from private seed state reach the server.
import { createHash, randomBytes } from 'node:crypto';
import { hashHistoryAccount, historyPasswordMatches } from './history_credentials.fixture.mjs';

export function createHistoryFixtureLogin(accounts, { now = Date.now } = {}) {
  const users = accounts;
  const dummy = hashHistoryAccount({ password: randomBytes(32) });
  const sessions = new Map(), attempts = new Map();
  const digest = value => createHash('sha256').update(value).digest('hex');
  const cookieName = 'handrail_history_fixture';
  const find = req => {
    const raw = (req.headers.cookie || '').split(';').map(s => s.trim()).find(s => s.startsWith(cookieName + '='))?.slice(cookieName.length + 1);
    return raw ? sessions.get(digest(raw)) : null;
  };
  const reply = (res, status, body, type = 'text/plain; charset=utf-8') => {
    res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'private, no-store' }); res.end(body);
  };
  return async (req, res, path) => {
    const handled = ['/login', '/fixture-session', '/history-fixture', '/history-fixture.js'].includes(path);
    if (!handled) return false;
    for (const [key, value] of sessions) if (value.expires <= now()) sessions.delete(key);
    for (const [key, value] of attempts) if (value.until <= now()) attempts.delete(key);
    let session = find(req);
    if (path === '/login' && req.method === 'GET') {
      if (!users.length) { reply(res, 401, 'Fixture login requires private QA Vault setup.'); return true; }
      const raw = randomBytes(32).toString('base64url');
      session = { csrf: randomBytes(32).toString('hex'), expires: now() + 30 * 60_000, identity: null };
      if (sessions.size >= 1000) sessions.delete(sessions.keys().next().value);
      sessions.set(digest(raw), session);
      // Native dev proxy uses HTTPS; loopback HTTP unit probes retain HttpOnly/SameSite.
      const secure = req.headers['x-forwarded-proto'] === 'https' || req.socket.encrypted;
      res.setHeader('Set-Cookie', `${cookieName}=${raw}; Path=/; HttpOnly; SameSite=Strict; Max-Age=1800${secure ? '; Secure' : ''}`);
      reply(res, 200, `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>SDK fixture login</title><h1>SDK fixture login</h1><form action="/login" method="post"><input type="hidden" name="csrf" value="${session.csrf}"><label>Username<input name="username" autocomplete="username" required></label><label>Password<input type="password" name="password" autocomplete="current-password" required></label><button type="submit">Sign in</button></form>`, 'text/html; charset=utf-8');
      return true;
    }
    if (req.method === 'POST' && ['/login', '/fixture-session'].includes(path)) {
      if (path === '/login') {
        // Socket peer is deliberately stricter behind the proxy; never trust caller IP headers.
        const key = req.socket.remoteAddress;
        const rate = attempts.get(key) || { count: 0, until: now() + 60_000 };
        attempts.set(key, rate);
        if (++rate.count > 10) { reply(res, 429, 'Try again later.'); return true; }
      }
      let body = '';
      for await (const chunk of req) {
        body += chunk;
        if (Buffer.byteLength(body) > 8192) { reply(res, 413, 'Request too large.'); return true; }
      }
      const form = new URLSearchParams(body);
      if (!session || form.get('csrf') !== session.csrf) { reply(res, 403, 'Invalid request.'); return true; }
      if (path === '/fixture-session') {
        if (form.get('action') !== 'logout') { reply(res, 400, 'Invalid request.'); return true; }
        session.identity = null;
        session.csrf = randomBytes(32).toString('hex');
        reply(res, 200, '{}', 'application/json'); return true;
      }
      const user = users.find(u => u.login === form.get('username'));
      const matched = historyPasswordMatches(form.get('password') || '', user || dummy);
      if (!matched || !user) { reply(res, 401, 'Invalid login.'); return true; }
      // Rotate the session after authentication, preventing fixation.
      const raw = randomBytes(32).toString('base64url');
      for (const [key, value] of sessions) if (value === session) sessions.delete(key);
      sessions.set(digest(raw), { identity: user.identity, csrf: randomBytes(32).toString('hex'), expires: now() + 30 * 60_000 });
      const secure = req.headers['x-forwarded-proto'] === 'https' || req.socket.encrypted;
      res.setHeader('Set-Cookie', `${cookieName}=${raw}; Path=/; HttpOnly; SameSite=Strict; Max-Age=1800${secure ? '; Secure' : ''}`);
      res.writeHead(303, { Location: '/history-fixture' }); res.end(); return true;
    }
    if (!session?.identity) {
      if (path === '/history-fixture' && req.method === 'GET') { res.writeHead(303, { Location: '/login' }); res.end(); }
      else reply(res, 401, 'Login required.');
      return true;
    }
    if (path === '/fixture-session' && req.method === 'GET') {
      reply(res, 200, JSON.stringify({ authenticated: true, identity: session.identity, csrf: session.csrf,
        boundary: 'outer-fixture-login-only' }), 'application/json'); return true;
    }
    req.historyFixtureIdentity = session.identity;
    return false;
  };
}
