# Rails 8.1 compatibility candidate — 2026-09-16

This is SDK implementation evidence for independent review, not acceptance of a
consumer installation. The candidate starts at Rails SDK
`da2327dc67796a56595286400779bb4b91d5a079`; both this checkout and the JS reference
`7dfb33f548448f864cf957f19d96f8b5a27bc787` were clean and matched public origin/main
at inspection. No pending Git operation was found. The earlier synchronization
was deferred because the workspace was in use; no reset, stash or Git repair was
needed. The JS checkout, its full-SHA public HTTPS dependency and npm lock remain
unchanged. Intended Rails changes are uncommitted; Handrail owns versioning and
publication of the resulting source commit.

## Changes and supported scope

The gem retains Ruby `>= 2.3` and Rails `>= 4.2`, with its upper Rails bound changed
from `< 8.0` to `< 8.2`. These are admission bounds, not proof of every permitted
combination. The new verified cell is Ruby **3.4.5**, Rails components **8.1.3**,
Rack **3.2.6**, Bundler **2.6.9**, Sprockets **4.4.1** / sprockets-rails **3.5.2**.
The engine now explicitly requires `rails` before `rails/engine`: Rails 8.1's
initializable collection uses `delegate_missing_to`, which was unavailable when
loading the SDK before Rails. The existing before/after-Rails load tests exercise
this defect. No forwarding, authorization or UI behavior was changed.

All 46 non-SDK dependencies are exact pins in `test/compatibility/matrix.json`,
`gemfiles/rails_8_1.gemfile` and its checked-in lock. JSON **2.9.1** is intentional:
initial resolution selected JSON 3.0.2, whose keyword-only `JSON.parse` options
break Rails 8.1.3's positional options call during cookie-session deserialization.
That failure was reproduced with `load_defaults 8.1`; it is not an SDK forwarding
bug. JSON 3.x is outside this verified closure. Match the eventual consumer's
complete dependency lock, not just its Rails version. No consumer was downgraded.

Fixtures optionally load an explicit Rails defaults version. The workflow
fixture defines controllers before boot, so it now applies its existing CSRF
policy after Rails installs inherited defaults. Only public static asset actions
are exempt; session mutations and reporter writes retain real CSRF verification.
Browser subprocesses honor the selected appraisal Gemfile. The lifecycle test
pauses relative to the browser clock rather than racing Node wall time; this
removes a reproduced past-time clock failure without changing polling assertions.
The Turbolinks test waits for its deferred snapshot write before asserting cache
restoration; it still checks the saved host stamp and absence of another request. Plain-Ruby package
checks clear `BUNDLER_SETUP` as well as `BUNDLE_*` to avoid inheriting Bundler 2.6's
startup hook. The original four appraisal cells remain intact; CI adds the fifth
cell and its complete Rake suite. Authored CI is not evidence of a hosted CI run.

## Reproduction

Run from this Rails SDK checkout. A normal Ruby 3.4.5 installation with Bundler
2.6.9 is preferred. On this Debian 12 x86_64 executor, only system Ruby 3.1.2 was
initially available. The optional preparation helper installs the checksum-pinned
ruby/ruby-builder Ubuntu 22.04 x86_64 binary into private temporary storage:

```sh
ruby test/compatibility/prepare_ruby_3_4.rb "$TMPDIR/rails81-runtime"
export PATH="$TMPDIR/rails81-runtime/x64/bin:$PATH"
export BUNDLE_GEMFILE="$PWD/gemfiles/rails_8_1.gemfile"
export BUNDLE_PATH="$TMPDIR/rails81-gems"
export BUNDLE_APP_CONFIG="$TMPDIR/rails81-config"
export BUNDLE_USER_HOME="$TMPDIR/rails81-bundler"
export BUNDLE_FORCE_RUBY_PLATFORM=true
export BUNDLE_FROZEN=true
export HANDRAIL_TEST_RAILS_DEFAULTS=8.1
bundle _2.6.9_ install --jobs 2 --retry 2
bundle _2.6.9_ check
bundle _2.6.9_ exec rake test
npm run setup
npm test
export PLAYWRIGHT_BROWSERS_PATH="$TMPDIR/playwright"
node node_modules/playwright/cli.js install chromium
export STYLE_ARTIFACT_DIR="$TMPDIR/rails81-style"
export LIFECYCLE_ARTIFACT_DIR="$TMPDIR/rails81-lifecycle"
npm run test:browser
ruby scripts/verify_release.rb --git
HANDRAIL_COMPAT_BUNDLE_PATH="$TMPDIR/rails81-gems" ruby test/compatibility/run.rb rails_8_1
```

The preparation archive SHA-256 is
`97246f1170eac708172707f18a87df57746c9bf4b2bc620f5c305f5c53e52154`, obtained from
the ruby/ruby-builder release asset digest and checked before extraction.
Its Ruby is `3.4.5 (2025-07-16 revision 20cda200d3) +PRISM [x86_64-linux]`, with
OpenSSL compiled against 3.0.2. The helper preserves the original binary and
extensions and wraps the relocated toolcache prefix, placing standard libraries
after activated gems and restoring Bundler setup before user code. Initial loader
and default-gem precedence failures are retained as environment preparation
failures, not product failures. C build tools are needed for generic native gems;
no system packages, consumer services or databases were provisioned.

The compatibility runner uses the established disposable bare clone, synthetic
package snapshot, exact dependency closure, empty executable PATH and blocked
outbound network during boot/precompile/requests. Its temporary Git source and
built/installed test gem archives are **SDK harnesses only**. No `git commit`,
`git push`, registered-checkout Git mutation, package publication or deployment
is part of this procedure. Synthetic `commit-tree` objects exist only inside
those disposable fixtures. They must never be supplied as consumer revisions.

## Results and retained evidence

| Executed check | Result |
| --- | --- |
| Ruby 3.4.5 / Rails 8.1.3, full `bundle exec rake test`, `load_defaults 8.1` | 226 tests / 8,406 assertions; zero failures/errors/skips |
| `npm run setup` (normal pinned Git install + build) | Passed; asset unchanged |
| `npm test` (all frontend tests) | 24 passed; zero failures/skips |
| `npm run test:browser` (style, workflow, lifecycle) | 32 passed; zero failures/skips |
| Target installed snapshot, actual Node-free Sprockets precompile and session/CSRF smoke | 1 test / 77 assertions; zero failures/errors/skips |
| Ruby 3.1.2 / Rails 7.2.3.2, unchanged root dependency closure, full Rake suite | 226 tests / 8,406 assertions; zero failures/errors/skips |
| Rails 7.2 frontend regression (`npm test`) | 24 passed; zero failures/skips |
| Release contract, exact matrix/CI declarations and online generic-gem dependency metadata | Passed |

Final totals and source-linked receipts are retained with this work request's
saved-deliverable manifest. Ruby runs include all repository Rake test selections
(package/release contracts included), not the older filtered parity selection.
Nested mounted checks overlap their parent Ruby tests and must not be added to
the parent count. HTTP boundaries are scripted; Rails routing, cookie sessions,
CSRF, controllers, helpers, generators and Sprockets are real. The SDK does not
persist to a local database, so no database substitute was introduced.

The five mounted scripts were also executed directly on the target runtime:
request 18/1,080; authorization 7/1,872; history 13/2,948; subscription 17/2,006;
accepted response 1/2,852 (tests/assertions). Each passed with zero failures,
errors and skips. These are overlapping checks, not additional suite totals.

The unchanged built reporter is 241,154 bytes, SHA-256
`2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`.
Browser provenance is Node 22.23.1, Playwright 1.61.1 and Chromium 149.0.7827.55.
Inspected original 1280×720 light form and 390×900 dark attachment-preview
captures for both Rails and the pinned JS renderer. The desktop pair is byte
identical; the mobile pair has consistent readable layout, consent wrapping,
attachment controls and footer with no observed new defect. Computed geometry
checks cover all 12 style combinations. Arial resolves to Liberation Sans in
this executor, so these captures do not establish native Arial typography.

Historical Ruby 199/7242, frontend 23, JS 59 and browser 32 results remain historical
only. This request does not rerun the separate JS repository's suite or alter its
source. The initial Rails 8.1 bound rejection, runtime setup failures, JSON 3.0.2
session failure and fixture static-JavaScript rejection are retained alongside
successful reruns; no failed or unavailable check is represented as passing.

## Review and consumer handoff

Independent SDK review and saved-artifact retention/acceptance remain required.
After Handrail records the reviewed source commit, the already-directed Monuvision
**development** trial must install from
`https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git` at that exact full
commit SHA with a matching `Gemfile.lock`, using its normal install/asset-build
pipeline. The uncommitted candidate and synthetic fixture SHA are not installable
public revisions. No consumer installation is proved here.

Check Monuvision's complete lock against the verified closure, especially JSON,
and test the actual admin screen, authenticated-admin route authorization,
server credentials, upstream persistence and notification delivery. Hiding the
launcher alone is insufficient. BlueCotton follows only after a successful
Monuvision trial. Rails 8.0, other 8.1 patches, Rails 8.2+, Propshaft, other OS/CPU
combinations, real provider email/storage and consumer integration are not proved
by this cell. The fresh Rails 7.2 regression uses Ruby 3.1.2, Rack 3.2.7 and Bundler 2.3.7
from the existing root lock; only its SDK dependency bound changed. Rails 4.2,
5.2 and 6.1 were not rerun. Their evidence retains its historical runtime limits;
no legacy cell or declared lower bound was removed.

The historical assessment reference is artifact
`a882d324-7d4f-54af-a2be-c8fa42388878`, supplied SHA-256
`f8a754992ace28ababf92de25ce8d984bc22d2d60e1d1867b6c8ece26f403f7a`.
Its source identity and prior discovery are inherited context, not new runtime
proof. This worker received its metadata with a null file path, not retrievable
assessment bytes; it does not claim a new hash verification. Handrail MCP tools
were initially absent from discovery and became available later; current context
and all three complete saved instruction sources were then read. No attached
memory publications or additional owner decisions were present.
