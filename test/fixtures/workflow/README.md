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
