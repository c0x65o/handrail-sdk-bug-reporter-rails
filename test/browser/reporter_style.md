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
must contain commit `7dfb33f548448f864cf957f19d96f8b5a27bc787`. The fixture reads
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
Escape to return focus to Help. Use 1280×900, 1280×720 and 390×900 viewports at device scale
1. Stop the server with Ctrl-C. `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` can select
an installed Chromium executable; `PLAYWRIGHT_BROWSERS_PATH` can select its cache.

The fixture snapshots its assets at startup. After changing the dependency or
rebuilding the asset, restart the running fixture before handing it to browser
QA. For the managed dev service, use Handrail's `handrail_dev_service_action`
with `action=restart`, `service_id=rails-css-parity-fixture`.
Check that existing service separately from the suite (which starts a fresh
fixture):

```sh
node test/browser/verify-served-style.mjs http://127.0.0.1:4179
# Optional third argument: directory for initial/after-reload screenshots.
```

This check compares the actual browser asset response with the reviewed asset,
checks runtime version/commit and all ordinary field layouts at 1280×720 before
and after reload, and verifies default Moderate selection and cancellation.
It blocks submissions and requests outside the fixture's expected GET routes.
An asset mismatch fails with an instruction to restart the fixture; passing a
freshly started local matrix alone does not establish the served QA revision.

All browser assets and fake policy responses are local. The helper process
rejects network access and raises if credential resolution or transport runs.
The server has no submission endpoint: unexpected methods/paths are recorded
and fail tests. Browser external requests are aborted and fail tests; console
errors, page errors and CSP violations also fail. No credentials, customer pages,
real submissions, upstream APIs, screenshots of customer data or dev service
are needed. The manual fixture is an ephemeral loopback server.

## Field-label regression verification — 2026-09-09

The campaign exposed a gap in the original consent-only assertions. JS v0.4.50
already fixes ordinary labels and mobile form overflow. Rails now pins that
public HTTPS Git dependency to `7dfb33f548448f864cf957f19d96f8b5a27bc787`
and rebuilds the shipped asset through `npm run setup`. Its source hashes and
release manifest describe that exact revision; Ruby payload reference fixtures
remain at their original v0.4.49 baseline.

`reporter-form-layout.mjs` checks all four fields for absent generated label
content, full readable control widths, headings above controls, scoped typography,
5px gaps, intended optional-text styling and no horizontal overflow. These checks
run alongside consent before/after late host CSS and after screenshot attachment.
Field metrics also participate in the direct React versus Rails comparison.

Before the upgrade, the expanded assertions failed all eight original matrix
cases. After the upgrade, `npm run test:browser:style` passed 12 matrix cases /
24 renders (13 TAP tests including the parent), adding the campaign's 1280×720
viewport to 1280×900 and 390×900. There were no skips, console/page errors,
external calls or submissions. Runtime: Node 22.23.1, Chromium 149.0.7827.55,
Rails 7.2.3.2. The worker installed Playwright Chromium in its temporary directory
and selected it with `PLAYWRIGHT_BROWSERS_PATH`; the initial default-cache launch
failed because that browser executable was absent.

Additional checks passed: `npm run setup` (fresh Git dependency compilation and
asset build), `npm test` (19 frontend tests, including reproducible asset and
gem packaging), `ruby -Itest test/package_contract_test.rb` (12 tests, 468
assertions), and release checksum/Git verification. Desktop 1280×720 and mobile
390×900 screenshots were also inspected: the four headings and controls are
readable, with no injected host label text.

## Served asset regression result — 2026-09-09

Work request `623bb749-a61e-45bb-8d72-b3d8f66a7418` addresses finding
`ef9835c9-6c78-4346-8e92-0141875b5f5c` from campaign
`123e4406-f6db-4b6f-b359-0e998511d094` (campaign run
`9cb4fc7d-8999-46e7-adc3-c3736d381086`). Both supplied screenshots were
reviewed, along with the original browser observations:

- [Reporter after reload](/api/pm/qa-campaign-artifacts/a11188eb-c825-43c9-833c-a81294e42f46/content)
  — SHA-256 `64697cb5ac01e1fe70a16e400d7ac7900fd489f08ceef8a16bd598b867f10266`.
- [Filled reporter preview](/api/pm/qa-campaign-artifacts/8b421034-c3a5-4ccd-b949-57110cb1a29b/content)
  — SHA-256 `b00d53b14c9be4399d8f9748da61572899a0020161a4838815ae9098f2a93f71`.
- [Browser observations](/api/pm/qa-campaign-artifacts/ba36de47-691c-41c8-b4fd-95cd72d33a3d/content)
  — SHA-256 `9f1b05402999e180779556d7d260b97dc26e8b619a0a2b3f655676a43d73b7c2`.

The evidence records v0.4.49 / `96b293248611594c388d0fab3af63b1b2d1aae5c`,
host-generated text on all four ordinary labels, a 59.984375px severity control,
and no writes. It does not establish a defect in v0.4.50. Independent HTTP
inspection of port 4179 confirmed the still-running fixture served an in-memory
v0.4.49 asset with SHA-256
`9c535c29d0d454a49705944b8dc74fb344f600ca55d8855a57b9a09644f84269`,
while the checked-in asset and dependency already contained the reviewed fix.
The failure boundary was the stale dev fixture process; no environment,
dependency or product CSS change was needed.

Handrail restarted `rails-css-parity-fixture` at 18:22 UTC. The actual served
asset then matched the reviewed v0.4.50 asset byte for byte (SHA-256
`2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`).
The served check passed on initial navigation and reload at 1280×720: all four
labels had `none` for both pseudo-elements, 13px/700 typography, a 5px gap,
and full-width controls. Severity measured 194.703125px with Moderate selected;
Steps used 13px text and an 11px optional hint. The after-reload screenshot was
visually inspected and showed readable labels and Moderate. Cancellation closed
the form; no console/page errors, external requests or submissions occurred.

Validation used Node 22.23.1 and Chromium 149.0.7827.55 with the existing Ruby
fixture and local policy HTTP boundary (no database). The served check passed;
`npm run test:browser:style` passed all 12 matrix cases / 24 renders (13 TAP
tests, zero skips); the scoped immutable dependency/reproducible asset test
passed; and the new script passed `node --check`. A temporary loopback server
substituting the historical v0.4.49 asset also confirmed that the served check
fails with the restart diagnostic. The existing HTTPS/full-SHA
dependency and matching lockfile remain unchanged.

Worker synchronization had been deferred because the workspace was in use.
Inspection found both relevant branches aligned with their local origin/main
refs, no merge/rebase/index lock or unmerged entries, and only an existing
`release-manifest.json` edit. That edit was preserved. This result adds the
served-service check and restart guidance, without replacing the reviewed fix.

## Original consent-only evidence — 2026-09-09

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
