# Rails host CSS parity fixture

Run from the Rails repository:

```sh
bundle install
npm run setup
npx playwright install chromium
npm run test:browser:style
```

Use `bundle3.1` instead of `bundle` on systems with versioned executables.
Native Ruby dependency installation requires Ruby development headers, a C
compiler and libyaml headers. Playwright requires its normal Chromium system
libraries. Missing browser/runtime dependencies fail the suite; no skips count
as acceptance. The normal `setup` pipeline installs the full-SHA HTTPS SDK
dependency and builds its asset with the pinned release identity.

The repository Bundler configuration installs gems into ignored `vendor/bundle`,
so the managed fixture service can find them without a worker-specific
`BUNDLE_PATH`. Install the bundle in this checkout before starting the dev
service; a bundle installed only in another worker's temporary directory is
not available to the service.

The reference Git checkout defaults to `../handrail-sdk-bug-reporter-js`.
Set `HANDRAIL_JS_REFERENCE_REPO` to another existing checkout if necessary. It
must contain commit `96b293248611594c388d0fab3af63b1b2d1aae5c`. The fixture reads
that commit with `git show`, irrespective of working-tree edits or HEAD, and
checks every source hash in `frontend/upstream.json`. The direct React reference
uses the installed public `@handrail/bug-reporter/react` entry after validating
the HTTPS lock, package version, release identity and embedded source hashes.
It does not call the Rails mount API. The Rails case executes the shipped asset
from `app/assets/javascripts/handrail_bug_reporter.js` and an actual helper-rendered
custom-launcher island, using the existing view rendering fixture's Engine,
controller and Rack request. Both cases must match separately specified props.

For a subsequent browser QA campaign:

```sh
npm run fixture:style
```

Open `http://127.0.0.1:4177/style-fixture?renderer=rails&theme=light&absent=false`.
Switch `renderer=reference`, `theme=dark`, and `absent=true` to inspect comparison
cases. Set `PORT` for another local port. Press Enter on the existing **Help**
button, Tab to consent, use Space or its label, attach a local PNG, and press
Escape to return focus to Help. Use 1280×900 and 390×900 viewports at device scale
1. Stop the server with Ctrl-C. `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` can select
an installed Chromium executable; `PLAYWRIGHT_BROWSERS_PATH` can select its cache.

All browser assets and fake policy responses are local. The helper process
rejects network access and raises if credential resolution or transport runs.
The server has no submission endpoint: unexpected methods/paths are recorded
and fail tests. Browser external requests are aborted and fail tests; console
errors, page errors and CSP violations also fail. No credentials, customer pages,
real submissions, upstream APIs, screenshots of customer data or dev service
are needed. The manual fixture is an ephemeral loopback server.

## Executed evidence — 2026-09-09

Rails checkout began on `main` at `a1f896610d6a3e6b71766a605ffe9c0841980f02`.
Existing and concurrently appearing Ruby, documentation, compatibility,
generator and workflow changes were preserved. Workflow item
`f699bf72-d540-46a9-a75d-5261cb8b1b66` deferred npm dependency wiring to this item;
this item added Playwright 1.61.1 and the browser/style scripts. Workflow added
its own script and owns its Ruby bundle/server changes. No production adapter,
helper, upstream source or packaged asset changes were necessary.

Runtime: Node **22.23.1**, npm **10.9.8**, Playwright **1.61.1**, Chromium
**149.0.7827.55** (revision 1228), Ruby **3.1.2p20**, Bundler **2.3.7**, Rails
**7.2.3.2**, React/ReactDOM **18.3.1**, esbuild **0.25.8**. The explicit font stack
is `Arial, sans-serif`; both renderers use the same local browser/font environment.
Tests compare computed metrics, not machine-dependent screenshot golden files.

The successful run used a scratch copy of the original Gemfile/lock with only
the local gemspec path made absolute. This isolated the run from concurrent
workflow-only WEBrick dependency installation; the Rails dependencies match the
project lock. The initial frozen install failed because `psych 5.5.0` needed
`yaml.h`. The libyaml 0.2.5 header was downloaded into scratch and the installed
system `libyaml-0.so.2` was linked there as `libyaml.so`. Psych installed with
`--with-libyaml-include` and `--with-libyaml-lib` pointing to that scratch path;
the subsequent frozen bundle install passed. No system packages were modified.

Exact validation environment and commands:

```sh
export style_tmp=/opt/handrail/.handrail/codex-runs/3bb66539-1fb2-4d2c-ad41-ed8cece1b8b6/tmp
export BUNDLE_GEMFILE="$style_tmp/Gemfile"
export BUNDLE_PATH="$style_tmp/style-gems"
export PLAYWRIGHT_BROWSERS_PATH="$style_tmp/style-browsers"

npm run test:browser:style > "$style_tmp/reporter-style-results.tap" 2>&1
node --test --test-concurrency=1 --test-name-pattern='immutable HTTPS dependency' test/frontend/bundle.test.mjs
RAILS_ENV=test RACK_ENV=test WITH_SPROCKETS=0 ruby -rbundler/setup -Ilib -Itest -r ./test/support/no_network test/fixtures/views/rendering_checks.rb
node --check test/browser/reporter_style.test.mjs
node --check test/browser/reporter_style.fixture.mjs
ruby -c test/browser/reporter_style.fixture.rb
git diff --check -- package.json package-lock.json
```

Results: **8 matrix cases / 16 actual reporter renders passed** (Node TAP counts
9 tests including the parent), zero failures/skips/external calls/submissions.
The reference JSX compiled with esbuild during the run. The focused asset check
passed (1 test), including byte-for-byte reproducible asset building and pinned
identity verification. Existing real view rendering checks passed (10 tests,
187 assertions, zero failures/errors/skips). Syntax and whitespace checks passed.
The first browser run exposed a fixture expectation error: mobile radius was
incorrectly expected to be 13px. Upstream's explicit `max-width: 560px` rule uses
0px corners for its full-screen layout; the corrected assertion also checks
that the custom 13px token continues to inherit. The final run above passed.

| Assertion | Both Rails and direct pinned React |
| --- | --- |
| Desktop bounds, either theme/context | x=12, y=90, width=1256, height=720 |
| Mobile bounds, either theme/context | x=0, y=0, width=390, height=900 |
| Consent, before/after late hostile CSS | 14×14px, 9px copy gap, long hint wraps without row overflow |
| Typography/tokens | 11px normal hint, 700 title weight, Arial stack; accent rgb(200,62,8); explicit light/dark text, muted and surface colors |
| Host controls | All computed styles, dimensions, values and checked states unchanged through mount, late CSS and dismissal |
| Keyboard | Dialog takes focus, Tab reaches consent, Space toggles; 2px accent focus ring; label toggles; Escape restores existing Help button |
| Screenshot | Uploaded PNG becomes blob URL; `img.decode()` resolves, complete=true, natural size 32×24 under `img-src 'self' data: blob:` |
| Context omitted | Serialized initialForm is empty; UI app version is “Not provided”; current page is pathname `/style-fixture` only, without query/fragment; no invented version/build/commit/flavor/profile values |

The TAP artifact prints comparative metrics for every case. This is local
automated fixture evidence; a linked dev browser acceptance campaign remains
separate. Lifecycle/CSRF workflows, legacy Rails runtimes and customer adoption
are outside this fixture's scope.
