// Synthetic data only: exercises the actual Rails asset, not installed authentication.
export const historyHtml = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="icon" href="data:,"></head><body><p>Synthetic Rails SDK fixture · No live customer data</p><div id="history-root"></div><script src="/javascripts/handrail_bug_reporter.js"></script><script src="/history-fixture.js"></script></body></html>`;
export const historyScript = `
const fixture = window.historyFixture = { allowed: false, identity: 'alice', requests: [], pending: [], hold: false };
const reply = body => new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' } });
const bug = owner => ({ id: owner ? 'alice-bug' : 'bob-bug', title: owner ? 'My checkout report' : 'Shared checkout report',
  environment: 'dev', severity: 'sev3', impact: 'moderate', status: 'reported', status_group: 'in_progress',
  status_rollup: { stage: 'submitted', label: 'Submitted', terminal: false, raw_status: 'reported', updated_at: '2026-09-29T10:00:00Z' },
  occurrence_count: 1, reporter_occurrence_count: owner ? 1 : 0, is_owner: owner, archived: false,
  created_at: '2026-09-29T10:00:00Z', updated_at: '2026-09-29T10:00:00Z' });
const config = { transport: 'same-origin', apiBaseUrl: '/feedback/api/mobile-bug-reports', projectId: 'history-fixture', environment: 'dev', allowScreenshots: true,
  fetch: async (input, init) => {
    const url = new URL(input, location.origin);
    fixture.requests.push({ path: url.pathname, query: url.search, method: init.method, identity: fixture.identity });
    if (url.pathname.endsWith('/policy')) return reply({ schema_version: 1, project_id: 'history-fixture', environment: 'dev',
      reporter: { identity_verified: fixture.identity !== 'anonymous', access_level: 'user', role: 'contributor' }, ask_options: [], history: { all_users: fixture.allowed } });
    const shared = url.searchParams.get('audience') === 'all';
    if (shared && !fixture.allowed) return new Response('{}', { status: 403 });
    if (url.pathname.includes('/bugs/')) return reply({ contract_version: 'v1', bug: bug(!shared) });
    if (!url.pathname.endsWith('/mine') || init.method !== 'GET') throw new Error('Unexpected fixture operation');
    const body = { contract_version: 'v1', bugs: shared ? [bug(true), bug(false)] : fixture.identity === 'alice' ? [bug(true)] : [], pagination: { limit: 20, has_more: false, next_cursor: null } };
    if (shared && fixture.hold) return new Promise(resolve => fixture.pending.push({ resolve: () => resolve(reply(body)), signal: init.signal }));
    return reply(body);
  } };
fixture.reporter = HandrailBugReporter.createBugReporter(config);
fixture.handle = HandrailBugReporter.mount(document.getElementById('history-root'), { config, sessionKey: fixture.identity, heading: 'Synthetic Rails feedback', label: 'Open feedback' });
fixture.switchIdentity = identity => { fixture.identity = identity; fixture.handle.update({ sessionKey: identity }); };
`;
