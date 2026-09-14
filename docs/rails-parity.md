# Rails parity and first-trial readiness — 2026-09-13

Original developer evidence for work request `60c927b3-f9c2-4761-a735-daaa40910f9a`, task
`3792a40e-44d3-47ef-83b9-d7a6e78b8906`, existing `sdk_parity` stage. The retained
implementation results below must be read with the correction and independent
findings in [evidence-corrections.md](evidence-corrections.md). No remaining runtime parity
defect was evidenced, so runtime source and the shipped UI asset are preserved.
This patch corrects stale documentation and adds reproducible comparison-image
retention to the existing browser harness. **Independent review b906468f-a407-4afe-8a50-9f802a0fb971 found
R1 evidence contradictions and R2 unavailable independent reproduction. Acceptance
and owner direction remain pending. This is not permission to integrate a consumer.**

## Exact source and authority

- JavaScript reference: `https://github.com/c0x65o/handrail-sdk-bug-reporter-js.git`,
  commit `7dfb33f548448f864cf957f19d96f8b5a27bc787`, version 0.4.50; clean at start
  and after reference checks.
- Rails candidate base: `https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git`,
  commit `15cc5a3f299263e6a498613de34a84857ba9c3d4`, plus this uncommitted patch.
  Gem version 0.4.49; private contributor package 0.4.59. No candidate commit was
  created. Anonymous public HTTPS `ls-remote HEAD` resolved to this base during
  this run; it was the latest committed revision at the installation check.
- The asset remains 241154 bytes, SHA-256
  `2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`.
  [Upstream metadata](../frontend/upstream.json), package manifest, lockfile,
  source-map hashes and embedded identity agree with the exact JS reference.
- Retained `source-inventory.json` identifies every tracked/nonignored source file
  and its raw-byte SHA-256, base and candidate trees, changed-file hashes and
  package/asset identities. Trees hash compact sorted-key JSON arrays of
  `{path, sha256}` sorted by path; missing files use null. Hashes are recorded
  outside this document to avoid self-reference.
- Worker synchronization was deferred (`main_workspace_in_use`). The original run reported both SDK repos clean. This correction began with
  the retained seven-file Rails patch and clean JS; both inventories and the patch
  exactly matched the review, with no pending merge/rebase/index lock. No repair, reset, stash,
  fetch, branch change, commit, push or PR was needed. The workspace root is a
  directory of separate repos, not itself a Git repo. No synchronization with an
  unseen branch is claimed. Other SDK and consumer repositories were unchanged.
- `handrail_current_context` and `handrail_read_work_request_context` were read.
  All three attached instructions were present, no memories/omissions were listed,
  and project-scoped Coverage Q&A returned zero entries. The attached correction
  preserves the task-wide plan with `workflow=null`; it grants no adoption or
  infrastructure authority. No local AGENTS.md was found in the workspace or
  inspected ancestor paths. The attached DB-testing KB and runtime requirements
  apply: no DB persistence is tested or provisioned; `qa_admin_provisioning` is
  `do_not_manage`. No accounts, credentials or platform configuration were changed.

## Source-linked parity matrix

JS links bind the immutable reference. Relative Rails links bind to the candidate
inventory. “Pass” refers to this worker's checks, not independent acceptance.

| Behavior / required evidence | JS reference | Rails equivalent and current result | Difference or remaining evidence |
| --- | --- | --- | --- |
| Submission, binding, canonical IDs | [submit/buildPayload](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1504) | [Client](../lib/handrail/bug_reporter/client.rb), [Forwarding](../lib/handrail/bug_reporter/forwarding.rb), [submission tests](../test/submission_test.rb), [accepted-response checks](../test/fixtures/mounted/accepted_response_checks.rb): pass. Browser IDs survive forwarding; project/environment come from server config. Only `bug_id` supplies the canonical ID; payload is prepared once and retries reuse event/body bytes. | Native Ruby has its own source-snapshot identity. Browser identity remains JS React/browser. Live canonicalization/deduplication requires provider/consumer evidence. |
| Trusted identity, server credentials, redaction | [server factory/forwarder](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts), [recursive redactor](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L688) | [Payload](../lib/handrail/bug_reporter/payload.rb), [Transport](../lib/handrail/bug_reporter/transport.rb), forwarding, [helper](../app/helpers/handrail/bug_reporter_helper.rb): pass native tests and mounted forged-body/header tests. Resolve trusted host session per attempt; do not serialize the report token or resolver. | Host must supply the real authenticated principal and application-session token. Absence/resolver failure does not establish ownership or admin permission. |
| Authorization and CSRF | [same-origin forwarding guard](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L394) | [Factory#authorized?](../lib/handrail/bug_reporter/client.rb), [controller](../app/controllers/handrail/bug_reporter/reports_controller.rb), [guard](../lib/handrail/bug_reporter/forwarding_guard.rb), [authorization checks](../test/fixtures/mounted/authorization_checks.rb): pass across all eight operations, admin/nonadmin/anonymous/revoked states, forged identity and fail-closed callbacks. Real Rails CSRF remains mandatory even if host checks are disabled. | Rails adds a host callback and framework CSRF token verification. Omitted callback preserves externally guarded legacy mounts; omission alone is not admin restriction. Consumer access has not been verified. |
| Policy, identity hydration, automation | [discoverPolicy/parsePolicy](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1400) | Shared UI discovery plus [Policy](../lib/handrail/bug_reporter/policy.rb) and [tests](../test/policy_test.rb): pass schema/binding/roles, bounded deadlines, hydration retries, risk and consent eligibility. Empty automation choices remain empty; forwarding strips automation requests. | No new automation feature inferred. Actual provider policy/eligibility remains unverified. |
| Owned history and detail | [listBugs/getBug](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1667) | [History](../lib/handrail/bug_reporter/history.rb), [native tests](../test/history_test.rb), [mounted history](../test/fixtures/mounted/history_checks.rb), [browser workflow](../test/browser/reporter_workflow.test.mjs): pass defaults/bounds, search/sort/cursors/status/visibility, ownership failures, detail and versioned projections. | Browser receives upstream JSON bytes. Native Ruby returns Ruby projections. Expanded UI rows use list data; the workflow separately exercises public `getBug`. Real ownership/persistence is not proved by boundary responses. |
| Archive, restore, archive-closed | [archive operations](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1749) | [Routes](../config/routes.rb), [archive tests](../test/history_archive_test.rb), mounted/history browser checks: pass PUT/DELETE/POST, scope, safe IDs, no unwanted body, CSRF and failures. | Live provider mutations and consumer permissions remain later evidence. |
| Attachments/screenshots | [screenshot normalization](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L797), [UI](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react-ui.tsx) | Shared browser File/Blob handling; [Ruby Screenshot](../lib/handrail/bug_reporter/screenshot.rb)/[tests](../test/screenshot_test.rb): pass one PNG/JPEG, 20 MiB bound, explicit permission, signature/MIME/base64/IO failures. Browser workflow verifies invalid claimed PNG, genuine PNG/JPEG, exact forwarded bytes; style capture decodes visible preview. | Ruby accepts bounded IO/bytes/base64, not browser File objects. Neither test proves remote storage. No additional attachment type or automatic capture is inferred. |
| Notification consent | [submit/subscribeToUpdates](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1559) | [Notification](../lib/handrail/bug_reporter/notification.rb), [native tests](../test/notification_test.rb), [child route checks](../test/fixtures/mounted/subscription_checks.rb), frontend/browser workflows: pass unchecked policy-gated consent, literal true, recipient-injection stripping, canonical child ID and saved-parent success after child failure. | No actual email or provider delivery occurred. Child failure warns without replaying parent intake. |
| Errors, retries and success bodies | [forwarding error contract](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L525), [client retries](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L2079) | Transport/controller/native tests plus mounted response matrix: pass original 4xx/5xx statuses, generic sanitized errors, network 502, transient retry list, stable body/event and fresh identity. Empty/malformed 2xx still accepts; valid JSON precision survives forwarding. | Malformed accepted JSON is suppressed to `null` in Rails, whereas JS forwarding returns raw bytes. Native normalization/number/string/nesting semantics differ as described below. |
| Appearance | [public React UI](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react-ui.tsx) | [entry](../frontend/entry.jsx), helper, [style fixture](../test/browser/reporter_style.test.mjs): pass all 12 viewport/theme/context cells against direct upstream React, including hostile late CSS, fields, consent, keyboard focus, context privacy and decoded preview. Representative captures inspected and retained. | Shared bytes/build success alone are not visual proof. Comparison is the same pinned React 18.3.1 fixture, not arbitrary host CSS or React versions. Pixel comparisons and scope below. |
| Mount/unmount and navigation | [React provider](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react.ts) | [Rails adapter](../frontend/rails_adapter.js), [DOM tests](../test/frontend/rails_adapter.test.mjs), [browser lifecycle](../test/browser/reporter_lifecycle.test.mjs): pass initial/deferred/late and duplicate scripts, custom launcher ownership, ordinary/Turbo/Turbolinks navigation, one poll/root, cancellation, retired-retry suppression, token rotation and fresh route context. | Rails adapter adds lifecycle cancellation. Manual mounts remain caller-owned. An aborted request is not a server rollback. Actual browser BFCache and older navigation libraries are unverified. |

## Verification and installation evidence

Original stdout/stderr, command arguments, exit codes, seeds and behavioral JSON
are retained unchanged in `original-verification-results.txt` (the attached
`verification-results.txt`). The independent review also inspected the original
installer, complete install lockfile, source inventory and reproduction container;
those separate files were not attached to this correction, so they are not
claimed freshly reverified here. The review preserves their findings and hashes.
`original-implementation.patch.txt` retains the exact prior patch, and
`revised-implementation.patch.txt` includes the documentation corrections.
`reproduction-scripts.json` now retains the editable correction drivers and current
documents/browser harness, while `developer-evidence.json` retains fresh results.
The initial source-loaded Ruby wrapper suppresses successful
child output, so its child fixtures were also executed directly to retain complete
assertion totals. Those reruns are overlapping evidence, not extra unique coverage.

| Retained original check (not a fresh correction total) | Actual recorded result |
| --- | --- |
| Existing permitted Ruby source suite | 199 tests / 7242 assertions; zero failures/errors/skips. |
| Mounted request / accepted-response / authorization fixtures | Respectively 18/1080, 1/2852 and 7/1872 tests/assertions; all pass. |
| Mounted subscription / history fixtures | 17/2006 and 13/2948; all pass. |
| View fixture without / with Sprockets | 11/197 and 11/199; all pass. |
| Rails frontend / composed JS-through-Rails contracts | 24 tests; all pass, including the archive-install callback incorrectly claimed excluded. |
| Rails ordinary asset build | Pass; exact shipped asset reproduced. |
| JS reference build, TypeScript source and contract compilation | All pass. |
| JS reference unit/React/server/package contracts | 60 tests; all pass, including npm-pack dry-run and its prepare/build effects despite the exclusion claim. |
| Rails browser suites | 32 TAP tests including 12 style cells plus their parent, 12 lifecycle tests and 7 workflow tests; all pass. |
| Final style capture after evidence fixes | 13 TAP tests (12 cells plus parent); all pass. This overlaps the browser total. |
| Release checksum/Git verification | Pass, 23 runtime files, exact JS identity, existing source-snapshot semantics. |
| Compatibility matrix structural check | Pass for all four declared cells; does not execute legacy runtimes. |
| Public HTTPS Git installation and ordinary precompile | Pass at Rails base SHA above; 2 tests / 89 assertions, zero failures/errors/skips. |

The original run omitted Ruby `package_contract_test.rb`,
`forwarding_package_test.rb`, packaged view/generator methods and the compatibility
synthetic-Git runner. However, its Node filters were ineffective: the frontend
`RubyGems builds and installs the prebuilt asset with no Node or Git available`
test **executed**, built a temporary gem and called `Gem::Installer.at(...).install`.
The JS `npm pack contains matching metadata and every public export` test also
**executed** `npm pack --dry-run --json --silent`, triggering prepare/build. That
JS dry-run is not an SDK archive installation. The original 24/60 pass totals and
logs remain intact; they cannot be retroactively described as filtered passes.
Current hashes do not erase those earlier effects. Fresh validated selections,
actual names and independent totals are in [evidence-corrections.md](evidence-corrections.md).

For the Rails install, the temporary driver reuses the existing `test/dummy` host,
`test/compatibility/smoke.rb` and `test/support/no_network.rb`. It substitutes a
public HTTPS/full-SHA dependency for the source Gemfile's `gemspec`, preserves
existing third-party resolution through `bundle3.1 lock`, then runs frozen
`bundle3.1 install --jobs 2 --retry 1`. Only third-party gems are copied into the
isolated cache; an assertion rejects a reused SDK Git cache. Anonymous Git lookup
is checked with global/system Git config and terminal prompting disabled.
The complete resulting lock has SHA-256
`185e2a760e835e5ef72ba8f482418aa049af7e2a8d58de9b21eb7d727bbee7d9` and contains:

```text
GIT
  remote: https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git
  revision: 15cc5a3f299263e6a498613de34a84857ba9c3d4
  ref: 15cc5a3f299263e6a498613de34a84857ba9c3d4
```

Normal `rake assets:precompile --trace` ran through Bundler with no Node/Git on
PATH; source load paths and Engine root must belong to the fetched Git install.
The smoke verifies 26 snapshot entries (gemspec normalized semantically; remaining
package bytes exactly), compiled asset identity, real session/CSRF intake and
invalid-CSRF denial. An added temporary check verifies the public URL/ref and
host authorization denial on installed policy/history/detail routes. These are
SDK trial fixtures, not admin consumer integration. This proves installation of
**the committed base**, not this later uncommitted documentation/test patch.
Runtime files are unchanged; the candidate README differs. The source-loaded
Gemfile.lock is not installation proof and was not changed.

## Browser evidence and recovery

Initial style launch failed because the Playwright Chromium executable was absent.
Before recovery, the check was compared with the supplied `guidance_recovery`
constraint, first-trial milestone and the existing fixture README. A temporary
Playwright Chromium download is the repo's ordinary browser setup; no managed
service, HTTPS fixture, QA campaign, system package, platform repair or provisioning
was added. The failed log and subsequent setup/pass logs remain retained. No
unexpected HTTP 5xx or server exception was observed; intentional fixture 503/422
responses exercise retries/rejection and are not service outages.

The style harness now optionally writes viewport PNGs and matching measurements,
identity, hashes and browser errors through `STYLE_ARTIFACT_DIR` outside source.
Image inspection caught two capture issues: a mobile preview caught mid-scroll,
and mouse coordinates carried from the reference checkbox into the next renderer.
The final harness uses instant scrolling and resets pointer position before
capture; runtime/CSS source was not changed to affect the comparison. Earlier
passing behavior/logs and numerical image comparisons are preserved separately.

Current checked browser scope: Chromium 149.0.7827.55, Playwright 1.61.1,
Node 22.23.1, React/ReactDOM 18.3.1, Turbo 8.0.23 and Turbolinks 5.2.0; viewports
1280x900, 1280x720 and 390x900, light/dark, explicit/absent context. The direct-JS
renderer imports the genuine pinned public React entry without the Rails adapter.
Its installed source-map originals are checked against `git show` at the JS SHA.
The workflow uses real Rails 7.2.3.2 routing, encrypted cookie sessions and CSRF,
with only outbound HTTP replaced by scripted responses. No DB/ActiveRecord,
provider storage, real report, email or consumer account is exercised.

Representative desktop light form and mobile dark preview pairs, plus lifecycle
history/retry-success images, are selected for retention. Mobile dark form pairs
were also inspected; their numerical results are retained but their PNGs are not
among the selected artifacts. Developer
inspection checks readable fields, wrapped consent hint, matching spacing/theme,
visible attachment controls, history empty state and successful-report state.
The full numerical comparison for all 24 form/preview pairs is retained: all 12
form pairs and five preview pairs are pixel-identical. Seven preview pairs differ
by 1–17 pixels; the original retained set did not locate six of those pairs, so
its blanket rounded-edge explanation was unsupported. Fresh full coordinates
and supporting captures are in [evidence-corrections.md](evidence-corrections.md); this is not literal pixel parity for
every preview. The selected mobile dark preview differs by two pixels. Inspected
images show no material layout mismatch; independent review must assess these
residual differences. Selected images do not establish every UI state. The independent reviewer inspected the mobile dark/provided pair and found
its two rounded-border differences had no material visual impact. That passing
finding remains preserved. Independent reviewers must inspect the revised bytes. No Firefox/WebKit, obsolete browser, arbitrary host theme,
native BFCache, real provider notification/deduplication or consumer rendering is
claimed. Boundary tests cover child warnings and history/archive behavior; there
is no corresponding live-delivery or populated-consumer screenshot evidence.

## Compatibility choices and historical reconciliation

[Frontend contract](../frontend/README.md) and [adapter contract](browser_adapter.md)
now point to the actual JS 0.4.50 SHA and permitted filtered checks. Ruby still
allows `>= 2.3`, Rails `>= 4.2, < 8.0`; these are provisional resolver bounds,
not a promise that every allowed pair works. This run verifies Ruby 3.1.2,
Rails 7.2.3.2, Bundler 2.3.7, Rack 3.2.7 and Sprockets 4.4.1. Ruby 2.3/Rails 4.2,
Ruby 2.5/Rails 5.2 and Ruby 2.7/Rails 6.1 are unverified for this candidate; the
legacy runtime/bootstrap paths were not run. The modern third-party lock differs
from the older exact appraisal closure; structural matrix success is not that
closure's runtime acceptance. ES2020 output and modern browser APIs remain required;
legacy Rails support does not imply obsolete browser support. Asset compressors
such as legacy Uglifier and other Rails versions remain unverified.

Comparable practice actually used is the JS repo's public React renderer,
HTTP-boundary response shapes in `test/reporter.test.mjs`/`test/react-ui.test.mjs`,
and its `test/server.test.mjs` forwarding/security contracts. Rails fixtures use
these contracts with actual Rails request/CSRF machinery, not a fake Rails or DB.
The JS reference unit suite uses its own React 19 dependency while Rails bundles
React 18 privately; the browser comparison intentionally holds React 18 constant.
The Rails compatibility dummy/smoke is reused for installation, but its old
synthetic-local-Git driver is replaced only in temporary verification tooling by
the authorized public Git path. These precedents guide implementation/checks;
their historical success does not prove this candidate.

Intentional Ruby differences remain: stricter path/redirect containment, no redirect
following, Ruby IO screenshot input, symbol/string keys and native numeric/string
normalization. Valid browser JSON success bytes are retained without reserialization;
malformed success is `null` at its original 2xx status. Native responses preserve
Ruby numeric precision/parser nesting bounds and do not reproduce JS normalization's
depth-20 circular markers or IEEE-754 rounding. Results may be explicitly read,
while safe inspection excludes them. Empty child success warns unless an active
subscription is returned; the accepted parent is not replayed. See
[payload bounds](payload.md#json-bounds-and-ruby-differences).

The previous parity report at Rails base commit is preserved verbatim in the
retained implementation record and [immutable Git history](https://github.com/c0x65o/handrail-sdk-bug-reporter-rails/blob/15cc5a3f299263e6a498613de34a84857ba9c3d4/docs/rails-parity.md).
It cited Rails `783e3aa...`, 252 Ruby tests/18487 assertions, 24 JS checks, later
33 TAP tests and 54 identical image pairs, and a managed-route 404. None of the
underlying historical saved artifacts is attached to this worker. Those claims
remain attributed historical evidence, not current acceptance; totals are not
imported into this run. Source diff from `783e3aa...` to our base shows seven
README/docs/package-version files, no runtime change. Private tooling advanced
to 0.4.59; runtime provenance remains `source_snapshot` with null release commit/ref
and base `42f70f0a3bedf5573f79988d75789b13e55f8bcd`. No release identity is invented.
The previous report's five criterion names, campaign requirements, attributed
permissions and consumer UUIDs are not the saved four-criterion contract for this
stage. Consumer project bindings are unresolved here and must not be copied from
that text or guessed. The managed-route observation is historical, unprobed and
not a prerequisite added to this SDK milestone.

## Four saved criteria and independent handoff

| Saved criterion | Developer result | Still required |
| --- | --- | --- |
| `sdk_parity_coverage` | Independent source coverage PASS is preserved. Exact-source matrix above accounts for all requested behavior and language differences; current inventories and patch retained. | Independent source/matrix review; resolve any demonstrated mismatch without importing historical authority. |
| `sdk_behavior_and_package` | Original independent evidence acceptance FAIL (R1/R2); corrected developer results are separate. Permitted unit/contract/frontend/build/load checks pass; public Git base installation and lock/precompile verified separately. Exclusions and compatibility bounds explicit. | Independent review of check coverage/exclusions; exact consumer Ruby/lock and later selected committed candidate must be verified before trial. |
| `sdk_browser_parity` | Independent overall UNVERIFIED (R2); inspected mobile border finding preserved. Real disposable browser behavior passes; current direct-JS comparison and representative inspected PNGs retained. | Independent visual/behavior review; missing browser/runtime combinations remain unverified. Shared bytes alone are insufficient. |
| `readiness_and_consumer_handoff` | Independent checkpoint readiness FAIL remains pending resolution. This report identifies review gates, limitations and missing provider/consumer evidence. | Repeat independent acceptance is not performed by this developer worker; owner notification and explicit Monuvision direction remain pending. No consumer trial/adoption is authorized or complete. |

No demonstrated runtime implementation blocker remains in the exercised SDK scope.
The concrete readiness gate includes **R2 — blocking independent reproduction
capability**: the review worker could not execute Ruby/JS/browser checks under its
read-only contract. Its supported inspection rejected the actual test files with
`Select 1–20 explicit scripts/test-*.mjs files.` No run/request key or saved test
receipt exists. The full attached review retains this failed-tool evidence; the
raw `tool-inspection.json` was not attached to this correction. Developer checks
do not resolve R2. Resolve it through existing authorized controls before another
independent attempt; do not bypass read-only restrictions or build infrastructure.
Compatibility limits and unavailable provider/consumer evidence are not silently
waived and are not converted into a default infrastructure prerequisite. If a
reviewer requires an unverified combination, obtain that exact runtime as a scoped
check; do not begin platform repair or broad bootstrap work by inference.

For independent review: verify artifact manifest hashes; inspect the source
inventory and patch against both exact commits; read all command results including
failure/recovery and explicit exclusions; inspect the selected PNG pairs and
behavioral JSON; reproduce commands from [test/README.md](../test/README.md) and the
retained editable scripts with the same locked toolchains. For a fresh install,
resolve the latest public committed SHA; for an upgrade, honor a frozen revision.
Always use full-SHA HTTPS Git, matching normal package-manager lock and ordinary
install/build pipeline. Do not use an uncommitted patch as an install revision.

Preserve the seven saved stages exactly: (1) `sdk_parity` — SDK parity/readiness
work; (2) `sdk_review` — independent SDK review; (3) `owner_trial_direction` —
owner notification plus explicit owner direction for Monuvision; (4)
`monuvision_integration` — authorized admin-only Monuvision integration; (5)
`monuvision_trial` — successful Monuvision trial verification; (6)
`bluecotton_integration` — authorized admin-only BlueCotton.com integration,
conditional on successful Monuvision verification; (7) `bluecotton_review` —
independent BlueCotton reporting, placement and admin-access verification,
followed by final owner presentation.
One persistent task keeps coordination, final owner presentation and owner decisions.
These describe the saved progression, not new dispatches. Resolve exact consumer
project bindings/permissions through the existing plan/setup controls; none is
inferred here. Both placements must be in admin screens **and every SDK route
must be protected by host authorization for authenticated admins**. The Engine
inherits ActionController::Base, so host ApplicationController filters do not
implicitly protect it. Configure `authorize_request` or verify an equivalent
mount-wide guard; hiding a helper is insufficient. Keep CSRF protection enabled.
The generated initializer denies by default until the host supplies its trusted
check. Notification, integration, release, QA acceptance and deployment remain
separate authorized actions. Any release needs its exact candidate/environment and
existing CI/CD approval path; this worker performed none of those actions.
