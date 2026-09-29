# Rails feedback history bundle delivery

Work request `4adf873c-44f5-5a84-a092-b6aa4065043f`; intended destination is the
Rails SDK's bundled browser UI. This closes the old Bug JS dependency gap for
outcome `f588b46d-a0d6-41ed-83d9-e07bc1e7751f`. Source/build verification passes;
native desktop/mobile rendering remains unverified. No consumer app, customer
sharing setting, production data, registered Git history or deployment changed.

## Exact dependency and artifact

The package and both lock entries use
`git+https://github.com/c0x65o/handrail-sdk-bug-reporter-js.git#48d046430519871c55db84cb7ace7efd364814ab`.
The installed package is Bug JS 0.5.0. `frontend/upstream.json` records that
commit with `commit:48d046430519871c55db84cb7ace7efd364814ab` identity and SHA-256
hashes read from its Git source. The build verifies those against both installed
React source maps. No tag or branch is a dependency. The normal `npm run setup`
performs Git dependency preparation and the bundle build; no separate SDK
packaging job was introduced. npm initially canonicalized its resolved entry to
SSH; normalizing that entry to public HTTPS allowed setup and all identity/source
checks to pass. No unrelated package version changed.

`app/assets/javascripts/handrail_bug_reporter.js` is **243,625 bytes**, SHA-256
`984be06291a23733f596e76de16b97c328a71ffeaa20ef9b33cba241723a7f0e`.
Executing that actual standalone asset reports the exact 0.5.0 upstream identity.
It contains `Mine`, `All users`, `all_users`, `is_owner`, `sessionKey`,
`data-handrail-bug-history`, and `data-handrail-bug-reporter-dialog`.
The Rails manifest remains `source_snapshot`, gem version 0.4.49, null Rails
release commit/ref, with current base `c6706ad47193db67e08b5f41633caac95d97f0bc`.
It does not claim a published Rails revision or live acceptance.

## Verification

All expensive checks ran sequentially. Local evidence is retained in
[verification.json](../artifacts/feedback-history-bundle-20260929/verification.json)
and [check logs](../artifacts/feedback-history-bundle-20260929/checks/).

| Check | Result |
| --- | --- |
| `npm run setup`, then `npm run build` | Pass, identical asset hash |
| `npm test` | 26 passed, 0 failed; includes byte-reproducible build and real bundled UI in JSDOM |
| `bundle3.1 exec rake test` | 228 tests, 8,429 assertions, 0 failures/errors/skips |
| `bundle3.1 exec ruby -Ilib:test test/fixtures/mounted/history_checks.rb` after adding the focused route test | 14 tests, 3,042 assertions, 0 failures/errors/skips; overlaps full suite |
| `tsc --noEmit -p tsconfig.json` in the clean Bug JS checkout at the frozen SHA | Pass |
| `tsc --noEmit -p tsconfig.contracts.json` in that checkout | Pass |
| `ruby scripts/verify_release.rb --git` and `--package` | Pass, 23 runtime files |
| Start existing style fixture library and GET `/history-fixture` | 200, Rails 7.2.3.2, no unexpected requests |
| JS syntax checks and `git diff --check` | Pass |
| Native browser rendering and exact image retention | **Unverified; no images captured** |

New tests execute the rebuilt Rails asset with synthetic responses and prove Mine
by default, conditional All users, discovery immediately before shared list and
headless detail requests, no other-user archive action, no shared image preview,
revocation clearing shared rows and preventing another shared read, and
`sessionKey` switching aborting a held request and discarding its late result.
Anonymous state hides All users. The real mounted Rails route test proves
`audience=all` is forwarded on history GETs only, mutations retain their existing
scope, caller project/environment cannot replace server scope, attachment paths
stay unrouted, and an upstream identity denial stays denied. Existing Ruby tests
also cover strict opt-in policy and fresh per-shared-read discovery.

The first new test incorrectly expected row expansion to fetch a detail; the UI
expands its list record. The corrected test explicitly invokes the bundled
headless detail API. A mounted test initially needed Bundler and an audit-array
reset; retained failure logs and the successful final log distinguish these.
Full-suite packaging tests use disposable synthetic Git objects as existing test
fixtures, never as an SDK installation or publication claim.

## Focused native QA handoff to Main Avery

Cause class: **missing capability in this task worker**. No native QA target,
browser handoff, validation directory or artifact output was supplied. The
installed Playwright library reports its Chromium executable absent. Artifact
persistence is exposed only for QA/Bug Testing, while this request is a task.
The script deliberately requires native inputs; it does not create a parallel
browser/proxy or alter QA/queue configuration.

Use project `0fef581d-d8f7-46fa-a111-fad9ee0c81ae`, dev service
`8317027d-9b3b-4d61-8946-c7c978b1ec39` (`rails-css-parity-fixture`, Rails repo
`c1f315e5-c3ee-4734-8473-b802fd4f596e`). Its existing command is
`PORT=4179 npm run fixture:style`; it was stopped at inspection. Start/restart
through native service controls, then select that service's native QA proxy URL
with **`/history-fixture`** as the target. This reuses the existing fixture service
and serves the actual asset; no new service or customer project is needed.

Run `node scripts/render-history.mjs` from the Rails checkout in native QA with:

- `HANDRAIL_BROWSER_TARGET_URL`: the scoped proxy URL ending in `/history-fixture`.
- `HANDRAIL_VALIDATION_RUN_DIR`: the native run's artifact directory.
- `HANDRAIL_QA_BROWSER_HELPER`: the installed supported
  `scripts/qa-campaign-browser-helper.mjs` path (the inspected copy is
  `/opt/handrail/repos/handrail/handrail/handrail/scripts/qa-campaign-browser-helper.mjs`).
- The native runner's browser/session and artifact access, without manual
  credential or proxy substitutions.

The prepared script is syntax-checked but browser-unverified. It checks 1440×1000
and 390×844, OFF/Mine, ON/All users, owner-only actions, no history images,
revocation, pending-response abort and account switch. It writes the exact native
PNG bytes under `screenshots/{desktop,mobile}-{off-mine,on-all-users,revoked,switched-user}.png`
and hashes them in `history-bundle-evidence.json`. Inspect those images and retain
those exact bytes/metadata through the native QA artifact path, labeling all as
synthetic. Also run the existing style/lifecycle/workflow browser regressions in
their supported QA execution context. Do not treat these synthetic responses as
real application authentication or live server authorization evidence.

After native QA, Main Avery owns publication once through native release controls.
Installed-runtime acceptance remains on the parent outcome: actual approved
Handrail/SDK hosts and two verified accounts must exercise OFF/ON/later-OFF,
private projections and attachment denial with real session verification. The
prior config→API→SDK fixture substituted external session verification, and
release receipts do not replace that check. Do not turn on customer policies,
upgrade consumers or deploy as part of this worker's handoff.

## Files

Preserved the prior worker's `README.md`, `frontend/entry.jsx`, Ruby
`client.rb`, `forwarding_guard.rb`, `history.rb`, `policy.rb`, and
`test/{history,policy}_test.rb` changes. Rebuilt its asset and refreshed its
release manifest without removing that implementation.

This slice additionally changes `package.json`, `package-lock.json`,
`frontend/upstream.json`, `lib/handrail/bug_reporter/release_manifest.rb`, current
version references in README/release/browser documentation, and frozen version
assertions in `test/frontend/bundle.test.mjs` and the style fixture/test.
It adds `test/frontend/history_bundle.test.mjs`,
`test/browser/reporter_history.fixture.mjs`, `scripts/render-history.mjs`, the
mounted history regression, this handoff and retained check artifacts. No other
SDK source was changed.
