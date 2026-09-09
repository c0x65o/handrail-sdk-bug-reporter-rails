import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { root, read, upstream, sha256, verifyDependency } from '../../scripts/contract.mjs';

export const fixturePath = '/style-fixture';
export const endpoint = '/feedback/api/mobile-bug-reports';
export const context = { route: '/explicit-context', app_version: 'fixture-1.2.3',
  build_number: '42', commit_sha: 'fixture-commit', app_flavor: 'internal', profile_key: 'fixture-profile' };
export const policy = { schema_version: 1, project_id: 'style-project', environment: 'staging',
  reporter: { identity_verified: true, access_level: 'user', role: 'contributor' }, ask_options: [],
  reporter_notifications: { available: true,
    recipient_hint: `j***@${'long-domain'.repeat(12)}.example.invalid`, lifecycles: ['fixed'] } };
export const cases = ['light', 'dark'].flatMap(theme => [false, true].map(absent => {
  const tokens = { accent: '#c83e08', text: theme === 'dark' ? '#fafafa' : '#202020',
    mutedText: theme === 'dark' ? '#bbbbbb' : '#666666', fontFamily: 'Arial, sans-serif' };
  const options = { endpoint, mode: 'custom-launcher', launcher_id: 'host-bug-button',
    show_history: false, allow_screenshots: true, heading: 'Style fixture',
    appearance: { theme_mode: theme, tokens, style: { '--handrail-bug-radius': '13px' } },
    ...(absent ? {} : { context }) };
  const expected = { config: { transport: 'same-origin', enabled: true, apiBaseUrl: endpoint,
    projectId: 'style-project', environment: 'staging', allowScreenshots: true },
  initialForm: absent ? {} : { route: context.route, appVersion: context.app_version,
    buildNumber: context.build_number, commitSha: context.commit_sha,
    appFlavor: context.app_flavor, profileKey: context.profile_key },
  showHistory: false, loadPolicyOnMount: true, heading: 'Style fixture',
  appearance: { themeMode: theme, tokens, style: options.appearance.style } };
  return { theme, absent, options, expected };
}));

export async function startStyleFixture(port = 0) {
  assert.equal(upstream.version, '0.4.49');
  assert.equal(upstream.commit, '96b293248611594c388d0fab3af63b1b2d1aae5c');
  verifyDependency(); // Pin, lock, installed identity AND source-map hashes.
  const sibling = process.env.HANDRAIL_JS_REFERENCE_REPO || resolve(root, '../handrail-sdk-bug-reporter-js');
  for (const [path, hash] of Object.entries(upstream.sourceSha256)) {
    assert.equal(sha256(execFileSync('git', ['-C', sibling, 'show', `${upstream.commit}:${path}`])), hash);
  }
  const rendered = JSON.parse(execFileSync(process.env.RUBY || 'ruby',
    ['-Ilib', 'test/browser/reporter_style.fixture.rb'], {
      cwd: root, input: JSON.stringify(cases.map(c => c.options)), encoding: 'utf8',
      env: { ...process.env, RAILS_ENV: 'test', RACK_ENV: 'test', WITH_SPROCKETS: '0' },
    }));
  rendered.pages.forEach((html, index) => {
    const dom = new JSDOM(html);
    const document = dom.window.document;
    const marker = document.querySelector('[data-handrail-bug-reporter="1"]');
    assert.ok(marker, 'real Rails helper must emit an island');
    assert.equal(marker.dataset.handrailBugReporterMode, 'custom-launcher');
    assert.equal(marker.dataset.handrailBugReporterLauncherId, 'host-bug-button');
    assert.deepEqual(JSON.parse(marker.dataset.handrailBugReporterOptions), cases[index].expected);
    assert.equal(document.querySelector('script').getAttribute('src'), '/javascripts/handrail_bug_reporter.js');
    assert.ok(!html.includes('fixture-never-serialized'));
    dom.window.close();
  });
  const reference = await build({ absWorkingDir: root,
    entryPoints: ['test/browser/reporter_style.reference.jsx'], bundle: true, write: false,
    platform: 'browser', format: 'iife', define: { 'process.env.NODE_ENV': '"production"' } });
  const assets = new Map([
    ['/javascripts/handrail_bug_reporter.js', ['text/javascript', read('app/assets/javascripts/handrail_bug_reporter.js')]],
    ['/reference.js', ['text/javascript', reference.outputFiles[0].text]],
    ['/host.css', ['text/css', read('test/browser/reporter_style.host.css')]],
  ]);
  const unexpected = [];
  const requests = [];
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    requests.push({ method: req.method, path: url.pathname });
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'");
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET' && url.pathname === `${endpoint}/policy`) {
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify(policy));
    }
    if (req.method === 'GET' && assets.has(url.pathname)) {
      const [type, body] = assets.get(url.pathname);
      res.setHeader('Content-Type', type);
      return res.end(body);
    }
    if (req.method === 'GET' && url.pathname === fixturePath) {
      const index = cases.findIndex(c => c.theme === url.searchParams.get('theme') &&
        c.absent === (url.searchParams.get('absent') === 'true'));
      const renderer = url.searchParams.get('renderer');
      if (index >= 0 && ['rails', 'reference', 'host'].includes(renderer)) {
        const options = cases[index].expected;
        const body = renderer === 'rails' ? rendered.pages[index] :
          `<main id="host-content" class="host-theme">Host content</main><div id="reference-root"></div><button id="host-bug-button" type="button">Help</button>`;
        const script = renderer === 'reference' ?
          `<script id="reference-options" type="application/json">${JSON.stringify({ ...options,
            initialForm: { route: fixturePath, ...options.initialForm } })}</script><script defer src="/reference.js"></script>` : '';
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        return res.end(`<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" href="data:,"><link rel="stylesheet" href="/host.css"></head><body><div id="host-controls"><label>Host checkbox<input type="checkbox"></label><label>Host text<input type="text" value="Host value"></label></div>${body}${script}</body></html>`);
      }
    }
    // There is intentionally no submission endpoint; even local writes fail.
    unexpected.push(`${req.method} ${req.url}`);
    res.writeHead(404).end('Unexpected fixture request');
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
  return { origin: `http://127.0.0.1:${server.address().port}`, unexpected, requests,
    railsVersion: rendered.rails_version, close: () => new Promise(resolve => server.close(resolve)) };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const fixture = await startStyleFixture(Number(process.env.PORT || 4177));
  console.log(`${fixture.origin}${fixturePath}?renderer=rails&theme=light&absent=false`);
  console.log('Use renderer=reference, theme=dark, absent=true for the comparison cases. Ctrl-C stops the local fixture.');
}
