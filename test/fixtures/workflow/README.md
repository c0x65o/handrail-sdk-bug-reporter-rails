# Rails workflow browser fixture

From the Rails repository root, with the locked Ruby/Node dependencies installed:

```sh
bundle install
node node_modules/playwright/cli.js install chromium
npm run test:browser:workflow
```

Use the repository's `npm run setup` when installing Node dependencies from
scratch (it preserves the pinned SDK build identity). `RUBY`, `BUNDLE_PATH`,
`PLAYWRIGHT_BROWSERS_PATH`, and `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` can select
locally installed runtimes. Missing gems or Chromium fail the file; no tests skip.

The file starts a fresh Rails/WEBrick process on an ephemeral loopback port and a
fresh browser context for each of exactly three journeys. It renders the real
helper, CSRF metadata, and an authenticated encrypted HttpOnly cookie session,
then serves the packaged asset from the Rails controller. Only the static asset
action is exempt from the host controller's JavaScript CSRF restriction; all
Engine routes retain their real guards and Rails CSRF verifier.

Only the `Factory` outbound HTTP seam is scripted. Responses use the notification,
tracked-bug, history, and cursor shapes from upstream JS `test/react-ui.test.mjs`
and `test/reporter.test.mjs`; the executable override follows
`test/browser/notification-opt-in.test.mjs`. Execution does not read the sibling
checkout. Scenario state consists of HTTP response selectors, not a database or
fake repository. Sentinels and the HTTP audit stay server-side/in temporary files.
Browser external requests are blocked, CSP restricts connections to the host,
and the existing Ruby no-network support rejects outbound sockets even if a
future change bypasses the HTTP seam. Teardown checks the server's exit status
so a swallowed network attempt cannot pass.

Journeys:

1. A file claiming PNG with invalid bytes fails before HTTP. Real `pixel.png`
   bytes and explicit consent produce one accepted report, one subscription to
   its canonical bug ID, and the thank-you screen.
2. Real `pixel.jpg` bytes are accepted; a deterministic subscription 422 displays
   the saved-report warning and the same canonical bug remains in My Bugs.
3. Search, status, sort, cursor paging, detail, archive/restore, and submission
   refresh use the protected mounted routes. The selected full history query is
   retained after reporting. Clock advancement of 14,999 ms then 1 ms proves the
   15-second refresh without sleeping for that interval.

The real browser path intentionally normalizes and validates screenshots in the
packaged JS SDK, then uses Ruby `Forwarding`, `Payload.redact_sensitive_values`,
and `Client#request`. It does not call the separate Ruby `Client#submit` or
`Screenshot.normalize` API. Assertions inspect the exact decoded image bytes,
normalized payload, identity headers, and methods/query values at the HTTP seam.

Two pinned UI contracts matter: expanding a detail row renders the list
projection, so the third journey also calls the packaged public browser
`createBugReporter().getBug()` with the real `createCsrfFetch` to exercise GET
detail; and an opaque pagination cursor carries the query, so pagination sends
only scope, limit, and cursor. Switching Active/Archived deliberately clears the
status filter; the journey reselects it before testing submission refresh.

Startup and browser launch each have 30-second limits, each journey has a
60-second limit, and server teardown escalates after 5 seconds. Browser/server
cleanup also runs on failure. Failure diagnostics show local server logs and
HTTP methods/URLs. The intentionally unmounted minimal scaffold is unchanged.

## Local acceptance evidence (2026-09-09)

Exact command used in the queued worker:

```sh
BUNDLE_PATH=/opt/handrail/.handrail/codex-runs/9c6f87ba-2635-4f32-8dd0-7898c50452db/tmp/workflow-bundle PLAYWRIGHT_BROWSERS_PATH=/opt/handrail/.handrail/codex-runs/9c6f87ba-2635-4f32-8dd0-7898c50452db/tmp/workflow-browsers npm run test:browser:workflow
```

Node 22.23.1, Playwright 1.61.1, Chromium 149.0.7827.55, Ruby 3.1.2,
Bundler 2.3.7, Rails 7.2.3.2, Rack 3.2.7, WEBrick 1.9.2.

```text
ok 1 - report with validated screenshot and consent reaches thank-you
ok 2 - subscription failure preserves accepted report and displays warning
ok 3 - My Bugs query, cursor, detail, archive/restore and current-query refresh
# tests 3
# pass 3
# fail 0
# cancelled 0
# skipped 0
# duration_ms 6121.43116
```

The worker needed libyaml development headers to build its already-locked Psych
dependency. Debian `libyaml-dev_0.2.5-1_amd64.deb` was extracted under the run's
temporary directory and passed to Bundler using `BUNDLE_BUILD__PSYCH` include/lib
flags. No system package or application configuration changed. Playwright and
its lockfile were added by the concurrent CSS task before this task added its
dedicated script. This task added only WEBrick to the Ruby development bundle.

Acceptance is this file only. No QA campaign, database, live Handrail call,
customer integration, product UI edit, or Git finalization is involved.

## Adapter lifecycle/CSRF harness

`npm run test:browser:lifecycle` runs `test/browser/reporter_lifecycle.test.mjs`
against this same Rails server and HTTP seam. The original three workflow
journeys and the separate CSS suite are preserved. No upstream/product bundle,
customer host application, deployment configuration or database is changed.

Fixture-only routes `/lifecycle/:navigation/:variant` provide `first`, `second`,
`explicit`, `custom`, `disabled`, and `marker-free` pages. Navigation is `ordinary`,
`turbo`, or `turbolinks`. `?loading=initial` loads a blocking head asset while the
document is parsing; the default is deferred; `?loading=late` waits for the test
to insert the asset after readiness. A separate probe records real readyState;
the suite never overrides document.readyState or synthesizes DOMContentLoaded.

The fixture serves **Turbo 8.0.23** and **Turbolinks 5.2.0** from exact, locked
development dependencies on loopback, with no CDN at browser runtime. These are
the only navigation library versions covered here. The libraries' own link
interception and browser history restoration execute: see the upstream
[Turbo Drive documentation](https://turbo.hotwired.dev/handbook/drive) and
[Turbolinks navigation/cache contract](https://github.com/turbolinks/turbolinks).
This does not establish support for every version of either library.

The twelve tests assert:

1. Blocking, deferred and late mounts; one root after duplicate asset execution;
   unchanged dialog/form identity; disabled helpers, marker-free pages and a
   disabled data marker; unchanged host content.
2. Three forward/back/forward/back cycles each for ordinary navigation, Turbo
   and Turbolinks. Ordinary visits prove new documents. Library visits prove a
   retained JS document, restored host DOM cache stamps, and no HTML request on
   back restoration. Each library's actual before-cache event leaves zero roots.
   Restored pages have one root and one history interval; 14,999 ms plus 1 ms
   proves the single 15-second poll. Teardown clears it through another 45 seconds.
3. Changed helper label and mounted endpoint, fresh provider options, pathname-only
   inferred route and preserved explicit route/app version. Query and fragment
   sentinels never appear in submitted bodies. Environment is a Factory setting,
   not a helper option: this fixture changes the data marker's environment to
   model refreshed host configuration and asserts it at the browser boundary.
   Real Rails forwarding still imposes its authoritative `staging` environment.
4. Custom button mouse, Enter and Space opening; automatic focus entry, Escape,
   focus restoration; unchanged host HTML/style/listener; no extra launcher;
   replacement launcher and marker reconciliation, including a detached old
   button whose host handler survives but whose SDK handler is removed.
5. Three teardown/start repetitions, each invoked twice; lifecycle events and
   DOM mutations after teardown cannot remount. Supplemental **synthetic** legacy
   `page:*`, Turbo/Turbolinks before-cache and window pagehide/pageshow events
   exercise suspension separately. These do not count as real legacy navigation.
6. Pending policy cancellation on actual Turbo navigation, pending history
   cancellation on actual Turbolinks navigation, and pending submission
   cancellation on explicit teardown. Browser routing holds only the selected
   HTTP request while native fetch carries the actual AbortSignal; all are
   released/aborted at cleanup. Advancing 60 seconds proves no departed request
   retries. Another test disposes immediately after a transient response and
   proves the already queued SDK retry cannot reach HTTP.
7. Sixteen invocations at the public `createCsrfFetch` caller HTTP seam in a real
   browser: string/URL/Request, POST/PUT/DELETE, object/tuple/Headers forms,
   current token replacement, copied caller headers, credentials/body/signal,
   receiver/return/input identity and Request stream preservation. GET, HEAD,
   OPTIONS, TRACE, absent/empty tokens, foreign origins/ports and an invalid URL
   pass through without injection. Foreign inputs are intercepted **before
   native fetch**, with no external delivery. TRACE is a seam assertion because
   browsers forbid native TRACE fetches; it is not a Rails route integration.
8. Mounted submission fails once at the Ruby HTTP seam with 503 (mapped by the
   existing forwarding contract to browser 502), then succeeds with the exact
   same body/credentials and a newly issued Rails CSRF token on the SDK retry.
   Protected `POST /lifecycle/rotate` resets the real session's token and commits
   Rails' new token normally. PUT/DELETE rotate again and succeed. A stale token
   is rejected with the Engine's 403 `invalid_authenticity_token` before reaching
   the outbound seam. No CSRF verifier is skipped for rotation or Engine routes.

Each test starts a fresh loopback process and browser context. Existing server
no-network guards, browser external-request blocking and CSP remain active.
HTTP failures are accepted only for the explicitly scripted 502 and stale-token
403 in retry scenarios. Startup/browser launch are bounded by 30 seconds,
individual tests by 60 seconds (navigation: 90), and server shutdown escalates
after 5 seconds. Cleanup runs even on assertion failures and checks server exit.

Set `LIFECYCLE_ARTIFACT_DIR` to an absolute directory **outside source** to retain
screenshots and JSON results. Otherwise each test prints its retained temporary
artifact directory. JSON includes runtime versions, HTTP path/method/status,
redacted console errors, and pass/fail; screenshots contain fixture data only.
Cookies, CSRF values, raw request/response bodies and server identity headers are
never written to these artifacts. Raw seam audits are private temporary files
deleted during cleanup. No HAR/trace/DOM dumps are retained.

## Harness validation and clean browser QA handoff (2026-09-09)

Run from the Rails checkout after `npm run setup`, locked `bundle install`, and
`node node_modules/playwright/cli.js install chromium`. Keep the suites sequential:

```sh
export BUNDLE_PATH=/opt/handrail/.handrail/codex-runs/db135213-47ba-48c8-950c-7ef2bbfb6864/tmp/bundle
export PLAYWRIGHT_BROWSERS_PATH=/opt/handrail/.handrail/codex-runs/db135213-47ba-48c8-950c-7ef2bbfb6864/tmp/browsers
export LIFECYCLE_ARTIFACT_DIR=/opt/handrail/.handrail/codex-runs/db135213-47ba-48c8-950c-7ef2bbfb6864/tmp/lifecycle-artifacts
npm run test:browser:lifecycle
npm run test:browser:workflow
```

Those are the worker runtime selections; substitute installed paths in another
worker. This shared checkout acquired `.bundle/config` during execution;
Bundler's local `vendor/bundle` setting took precedence over `BUNDLE_PATH` in the
successful runs. No Bundler setting was edited by this task. An earlier isolated
gem install failed on missing `yaml.h`; libyaml development headers were
downloaded/extracted under this run's temporary directory, without a system
package install. Node dev dependencies were installed with `--include=dev`.

Observed runtime: Node **22.23.1**, Playwright **1.61.1**, Chromium
**149.0.7827.55**, Ruby **3.1.2**, Bundler **2.3.7**, Rails **7.2.3.2**, Rack
**3.2.7**, WEBrick **1.9.2**; Turbo **8.0.23**, Turbolinks **5.2.0**.
Legacy Rails runtime cells, Turbolinks 2/3, other Turbo releases, Firefox/WebKit
and native browser BFCache restoration were **not validated**. Actual library
snapshot caches were validated; ordinary back/forward traversal does not claim
native BFCache use. No CSS parity campaign was run as part of this task.

Development failures are retained in `lifecycle-first.tap`, `lifecycle-second.tap`
and `lifecycle-third.tap` under the run's temporary directory: an ERB regexp
escaping error; waits that observed URL changes before restored DOM; a polling
clock paused too late, then an autofocus wait while paused; a before-cache
observer running between event listeners; and initial expectations of upstream
503/422 instead of the Engine's existing 502/403. Those harness issues were fixed;
no product code was changed to make an assertion pass. The fourth run passed
12/12; final output is `lifecycle-final.tap` (12/12, zero failures/skips,
22,872.12265 ms). Workflow regression output is `workflow-regression.tap`
(3/3, zero failures/skips, 6,067.809122 ms). Node/Ruby syntax checks and
`git diff --check` also passed. Screenshots and redacted HTTP summaries
are in `lifecycle-artifacts/`; `lifecycle-source-sha256.txt` identifies tested
source, including the packaged asset and navigation lockfile.

The shared checkout advanced to `a6f8360` while this worker was active, including
an intermediate harness snapshot; use the recorded file hashes and final working
files, not that commit alone. This worker performed no Git finalization.

This establishes **harness readiness only**, not a linked QA campaign. The QA
operator should rerun both commands from a clean, identified candidate, inspect
the history/custom-dialog/retry-success screenshots and redacted network results,
and attach the clean campaign ID and source hashes to selected item
`9bfce760-bf14-479c-b22e-77cf09835f96`, referencing adapter item
`c6925e32-6b71-4892-853d-71a64187a4d7` and fixture item
`f699bf72-d540-46a9-a75d-5261cb8b1b66`. Keep unavailable matrix cells explicitly
unvalidated. The campaign must use this local fixture; no staging target,
deployment, customer application changes or real report sends are needed.
