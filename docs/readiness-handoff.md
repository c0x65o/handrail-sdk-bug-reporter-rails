# Rails SDK readiness handoff — updated 2026-09-24 UTC

## Current findings — 2026-09-24 UTC

This documentation-only assignment (`c02bb228-6883-4557-b801-313c3b8fd555`, run
`aaa04796-c10c-42a7-b900-1490c8438112`) retains the reconciled SDK evidence for
independent review and the subsequent **Monuvision staging** handoff. The selected
Rails revision is **`d4e2c7f278a971eab8ff8e87299ef8f72149dde9`**; JS remains
`7dfb33f548448f864cf957f19d96f8b5a27bc787`. Both starting checkouts were clean.
Their Git trees are `e0125e6a0f633cd92874f39d2c81c7f4571e0267` and
`955a77c7d91dc4b417288b779246f6330759da91`, respectively.

The attached reconciliation index and byte audit match their supplied SHA-256
values; their original artifact IDs/hashes are in [the evidence index](readiness-evidence.json).
All 101 indexed local source files match the inspected-source hashes. All 23
release runtime hashes, eight build fingerprints and five pinned upstream source
hashes also match. Build fingerprints use the existing `private-contributor-v1`
normalization, which excludes matching private npm version declarations; raw
package hashes are checked separately. The gem remains 0.4.49, private frontend
tooling is 0.4.63 and bundled JS is 0.4.50. The manifest remains `source_snapshot`
with null release commit/ref; it is not a new release attestation.

Reconciliation WR `5c8dd6d5-c7ed-410f-90d0-db5b7850dd8e`, run
`710ad408-ba24-4794-9d12-1dc09af0c44f`, finished
`2026-09-24T10:59:46.769Z`. Its bounded source/evidence pass and validation-log
matrix/index did not update repository documentation or execute runtime tests.
This assignment supplies those documentation changes. No runtime, build, browser,
installation or provider check was rerun here, and no original PNG was inspected.

### Retained results and attribution

The following are separate selections, never additive totals. Native saved
outcomes for `d73fb33e`, `6444b0fe` and `999fa90e` were read through
`get_work_request`; their command logs and original image bytes were not fetched
again. The two attached files are indexes/audits, not the logs they name.

| Record | Retained finding and scope |
| --- | --- |
| Independent parity WR `d73fb33e-8b46-40c2-bbc5-b6250331b6d5`, run `387a0916-9339-435e-8ce4-ae9951bf774c`, completed 2026-09-16T05:44:17.492Z | Passed within the original source/fixture scope: filtered Ruby 199 tests / 7242 assertions; Rails frontend 23; JS 59; browser style/lifecycle/workflow 13/12/7; build/typecheck/release/load. Its package exclusions remain intact. |
| Independent compatibility WR `6444b0fe-1753-4406-9a47-a1a979d90148`, run `86ab1ed9-7689-417e-aa7c-2869c9d04344`, completed 2026-09-16T22:16:00.335Z | Historical `blocked_env`: target Ruby unavailable; existing-runtime full suite 226 tests / 7633 assertions, **9 failures**, 0 errors/skips (missing CA and incomplete exported Git trees). Separately passed Rails 7.2 frontend 24, browser 32, mounted checks, build/release checks; inspected four supplied PNGs. Those passes do not turn the failed full suite into a pass. |
| Preparation WR `538069e0-d4aa-4f6c-914e-438c5297a65a`; independent reproduction WR `bb714316-bded-4e13-906d-df24fa8a8f39` | Later ordinary-worker preparation and independent reproduction resolved the runtime/CA/Git-export gaps. Independent totals are attributed through the final review below: Ruby 3.4.5 / Rails 8.1.3 / Rack 3.2.6 / Bundler 2.6.9 / JSON 2.9.1 full suite **226 / 8406**, and Ruby 3.1.2 / Rails 7.2.3.2 / Rack 3.2.7 / Bundler 2.3.7 full suite **226 / 8406**, each 0 failures/errors/skips. See [reproduction and exact locks](validation-environment.md). |
| Same independent reproduction, separate selections | Target mounted request 18/1080, authorization 7/1872, history 13/2948, subscription 17/2006, accepted response 1/2852; existing package contracts 21/1065. All passed; these overlap the full suites. JSON 2.9.1 installed package/precompile/session-CSRF smoke **1/77** and separate SDK-only JSON 2.21.1 smoke **1/77** passed; neither establishes the entire consumer dependency closure. |
| Final independent review WR `999fa90e-286b-486d-b4a8-51d4553e9e73`, run `a1774862-9876-411e-82d2-ccfc0e0293a6`, completed 2026-09-16T23:12:17.038Z | Passed source/saved-evidence assessment supporting selected Rails `d4e2c7f…`. Verified five delivered artifact hashes, 54 command-output hashes and 18 lock/smoke hashes; reused the independently executed `6fe35a72a689aebb3e5f627f1e56deda0a7f590e` evidence after source/package/dependency equivalence. Two fresh metadata/package checks passed in that review, not fresh Rails 8.1 behavioral or visual tests. |

The final review's source comparison found four preparation/documentation additions
and private npm version changes (0.4.62 → 0.4.63) after `6fe35a7…`, with no
production/rendering/dependency-pin drift. This checkout confirms that comparison.
Earlier R1/R2 failures, failed 226/7633 regression, missing-result run
`74b45ab0-b487-4626-8424-3f660e1f87c3` and the original development
`follow_up_required` remain historical outcomes. They are not current demands to
repeat SDK implementation or the superseded executor route.

Declared bounds are Ruby `>= 2.3` and railties `>= 4.2, < 8.2`, as in the
[gemspec](../handrail-bug-reporter.gemspec). The older `< 8.0` statement is
superseded. Bounds do not prove every admitted Ruby/Rails combination. Retain the
[compatibility record](rails-8.1-compatibility.md) and its exact runtime/lock limits:
JSON 3.0.2 session failure, untested Rails 8.0/other 8.1 patches/8.2+, Propshaft,
other OS/CPU combinations and current legacy-runtime gaps are not cleared.

Historical browser behavior and selected visual findings remain usable only in
their recorded fixtures. Older Arial requests rendered as FreeMono; later Rails
8.1 captures used Liberation Sans. Native Arial equivalence, arbitrary consumer
CSS/CSP, Firefox/WebKit and native BFCache remain unverified. Preserve the pixel
differences and intentional Ruby semantics in the [parity matrix](rails-parity.md#source-linked-parity-matrix).
Unchanged assets alone do not prove consumer visual parity.

### Selected consumer installation and security contract

The future authorized consumer installation must use this exact public HTTPS Git
dependency, a matching consumer `Gemfile.lock` Git revision/ref, and normal
`bundle install` plus the application's ordinary install/asset-build pipeline:

```ruby
gem "handrail-bug-reporter",
    git: "https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git",
    ref: "d4e2c7f278a971eab8ff8e87299ef8f72149dde9"
```

A later documentation commit or automatic private tooling version bump does not
change this selected consumer SDK revision. Do not select a newer HEAD merely
because documentation was finalized. No branch/tag, registry, tarball, file/PATH
or workspace dependency, separate packaging/publishing step or bound bypass is
an acceptable substitute. Historical public installation at `15cc5a3…` (2/89),
source-loaded PATH locks and synthetic fixture installation do not prove current
public fetch or consumer installation at `d4e2c7f…`.

The host must place the reporter only on admin screens and enforce authenticated
admin authorization on **every** reporter route, including policy, history,
detail, archive/restore and subscription. `ReportsController` inherits
`ActionController::Base`; host `ApplicationController` filters do not implicitly
protect it. Configure a fail-closed `authorize_request` callback or independently
verify an equivalent mount-wide server guard. `Factory#authorized?` returns true
when that callback is omitted for legacy mounts; omission is not admin-safe.
`Transport#fresh_session_token` can return nil; missing/invalid identity does not
inherently deny a route. Require a trusted, valid current application session and
tenant on each request/attempt, expiry/revocation enforcement and real Rails CSRF.
Keep dedicated bug report credentials server-only; never use browser identity as
authority or reuse enhancement tokens. SDK fixtures do not establish these host
requirements in either consumer.

### Remaining Monuvision staging outcome

Saved owner notification/direction and prior SDK reviews must be preserved, not
asked for again. The former development selection is superseded for the immediate
trial by request **`f1aa63c0-0a30-4be7-b11e-66bfea091b61`**, selecting **staging**.
This documentation work clears no human/native gate and makes no stage-acceptance
decision. The existing Task owns continuation; Avery supervises and independently
inspects the result. Consumer obligations remain:

1. Prepare an idempotent QA Site Admin seed task allowed only in dev/staging, with
   no schedule, actual tenant/immutable user identity and real app authentication;
   prevent duplicate sites and customer-user changes. Scope `qa-login-dev` and
   `qa-login-staging` Vault profiles by project/environment; inject secrets only
   into the seed process, never ordinary service environment rows. Retain one
   native staging seed execution and independent authenticated-login evidence.
2. Verify current staging schema and effective app database binding. When needed,
   use normal ordered `bundle exec rails db:migrate`, including earlier pending
   migrations. Never build/restart/publish the cancelled selective executor.
   Historical development migration failures are not current staging facts.
   Verify Known Users against actual immutable users, independently mapped email
   and active status, SHA-256 reporter session digests, expiry and revocation.
   Keep reporting disabled until schema, identity, mapping and dedicated server
   credentials are verified. Preserve resources, volumes, data and sessions.
3. Verify the selected SDK pin, matching full consumer lock and normal install/build;
   deploy necessary changes through native CI/CD to the exact existing staging
   web **and worker** roles. Resolve node, namespace, immutable image and
   environment/volume bindings; retain preview-bound configuration/deployment and
   migration/resource/runbook receipts. Preparation and rollout alone are not
   independent application acceptance.
4. Independently inspect actual staging admin UI/login, anonymous/nonadmin denial,
   session/tenant/revocation boundaries, CSRF, attachments, consent and history.
   Preserve the recorded verificationPlan; retain current native assertions,
   inspected browser images and provider receipts. Missing checks stay unverified.
5. Only after prerequisites and independent browser preflight pass, submit exactly
   one report titled **[NO-OP TEST] Monuvision staging Bugs SDK smoke test**. Its
   body must say test only, no defect, no code change requested, with marker
   `f1aa63c0-0a30-4be7-b11e-66bfea091b61`. Check existing submission/history before
   submission or any uncertain retry. Cover attachments/consent within that single
   report where applicable; retain provider ID, staging/project/user attribution,
   rendered success and history. Read-only QA does not itself submit the report.

No consumer edit, service setup, deployment, seed, report submission or historical
recovery occurred in this assignment. Production is excluded. BlueCotton remains
conditional on verified Monuvision success and later authorized adoption with its
own compatibility, installation and admin-only acceptance evidence.

Original run `04ac09d6-3092-441b-afaf-cc818b6d5551` / WR
`492217b7-70e9-43f1-bdd7-53e3f40cb2bf` remains unsettled. Preserve the separate
runner/evidence maintainer dependency for authentic launch attribution and
independent non-survival proof/native fencing; no assigned maintainer or settlement
is asserted here. Staging planning does not recover that run. Preserve original
receipts, cancellations, holds, optional historical diagnostics and unpublished
conflicting repair candidates; do not replay terminal profiles or weaken guards.

## Historical handoff — 2026-09-16 UTC

Everything below records the earlier workers' source, results and then-pending
gates. “Current”, “fresh”, “this worker” and “pending” within that record refer to
its original date. The dated findings above supersede its current-status and
installation guidance; original receipts and test selections remain unchanged.

Current runtime work: [Rails 8.1 compatibility candidate](rails-8.1-compatibility.md).
This earlier parity handoff retains its historical scope and exclusions.

Task `61ce47fd-96c9-4942-ae9d-573da0eae084`; documentation follow-up
`ce707792-5681-4be2-a6eb-2e474920f035` to development work request
`585ce275-b440-4c90-acb2-55f44d42fa20`. This bounded handoff enables the separate
`sdk_review` stage. It does not accept SDK readiness or authorize consumer work.
Runtime implementation and JS source are unchanged; no broad tests were rerun.

## Historical canonical validation — 2026-09-16 UTC

The planner reports action `0a4dae06-b47d-4673-8a61-6fe526b3685f` settled.
Validation work request `a648bc8f-75a2-469e-844e-d075e72140e7`, run
`c146ca6b-1061-4f72-a18b-7cb461aadcde`, completed
`2026-09-16T04:37:29.344Z` with evidence-mode status **passed**. Its report
confirms matching inventories and all 23 runtime hashes; independent Ruby
199 tests / 7242 assertions, Rails frontend 23, JS 59, browser 32 TAP tests,
and build/typecheck/load checks passed. Executor visibility and independent
execution receipts have therefore been obtained; obtaining them again is not a
remaining handoff requirement.

| Planner-supplied evidence | Identity |
| --- | --- |
| Rails native receipt | `ee51869136890847a5701dbd5be073e0ba03a8f42ef0f5a13a9397ae6597c869` |
| JS native receipt | `cfeeb7faee32f7a6309b7f745578db8b344737a84bcf6851fb9e020a3bf0b5b4` |
| Browser native receipt | `f897927b424ce0ad7f60ce4ac8d9db38e0ed55f5dc422cb403902c5a2e0bfaa4` |
| Retained `inspection-report.md` | Evidence `5e5a9a19-b08d-4e51-b2e5-12e671387990`; SHA-256 `302b85c376a9084e8e5bbcc45ec1fbb12f1464f050e46f86c528e7c595b34642` |
| Retained `result.json` | Evidence `8534513e-bee3-4bd6-a367-f7b360089bb2`; SHA-256 `db9ee590342fd1b505e376f34d53600af2239df893a4275e7d69b6d8b62fd0a4` |

These are canonical findings supplied by the planner, not tests rerun or receipt
bytes inspected by this documentation worker. Exact limits remain
`validation_verified=false`, `verification_scope=source_or_saved_evidence`, and
native assertions `[]`. The reported Ruby assertion count is a test result, not
populated native assertions. Browser execution used fallback fonts: requested
Arial rendered as FreeMono. Typography equivalence remains unverified; passing
browser execution does not establish it.

The earlier missing-result run `74b45ab0-b487-4626-8424-3f660e1f87c3` remains
inconclusive. The original development result remains `follow_up_required`.
Neither historical record is rewritten by this handoff or the later validation.
The separate `sdk_review` stage must assess the evidence and remaining limits;
SDK acceptance and owner trial direction remain pending.

## This follow-up's source comparison

All three supplied attachment SHA-256 values were verified. The attached
`source-inventory.json` final trees match the starting workspace exactly: Rails
191 files and JS 27 files, including the existing documentation edits. All five
sections of attached `readiness-documentation.md` match their repository files.
The attached evidence index matches `docs/readiness-evidence.json` except its
additional saved-deliverable hashes and final-tree metadata. Input artifact IDs
and hashes are retained in the revised index and updated inventory.

Both HEADs below were rechecked. All 23 release runtime hashes and dependency
locks match the supplied inventory. Changes from its initial Rails tree are the
four existing documentation edits and two added handoff files; there is no
runtime drift. This follow-up changes only this handoff, `docs/rails-parity.md`,
`test/README.md` and `docs/readiness-evidence.json`. The saved inventory records
before/after hashes; the focused diff starts from the preserved incoming edits.
Automatic synchronization remains deferred (`main_workspace_in_use`); inspection
found no merge/rebase/cherry-pick/revert or index lock requiring repair. No unseen
remote state is claimed. Current scope and saved instructions were read through
Handrail MCP; there were no attached memories or omitted instructions.

The following developer results and observations are retained history from
2026-09-15, reused within their exact source/runtime limits. They are not new
executions or personal visual inspections by this follow-up worker.

## Source identity and drift — original 2026-09-15 record

| Item | Inspected identity |
| --- | --- |
| Rails repository | `c1f315e5-c3ee-4734-8473-b802fd4f596e`, HEAD `7df0290f23159884178c888f2d5e4c8ec380d723`, initially clean |
| Historical Rails base | `15cc5a3f299263e6a498613de34a84857ba9c3d4` |
| JS reference | `cd564712-6496-4195-9b96-e40af54e33c3`, HEAD `7dfb33f548448f864cf957f19d96f8b5a27bc787`, clean and unchanged |
| Versions | Ruby gem 0.4.49; private Rails frontend tooling 0.4.60; bundled JS 0.4.50 |
| Shipped asset | 241154 bytes; SHA-256 `2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f` |
| Initial Rails tree | 189 tracked/nonignored files; `982a22c7dd6a1fac06c2ff8fea88156172de10f9f5075d469285d3f7f8683840` |
| Initial JS tree | 27 tracked/nonignored files; `c1fcaa0ff9536707fe7a3433f40b9a3eefbcf5d2ab28acd5527e8a0170abdbd5` |

Tree digests hash compact, sorted-key JSON arrays of `{path,sha256}`, sorted by
path. The saved inventory retains individual raw-byte hashes, initial/final trees,
package files, ignored development locks, and the exact tested source. The saved
diff separates base-to-HEAD drift from this assignment's documentation patch.

There is exactly one commit after the historical base. Its ten changed files are
README, five other documentation files plus `docs/evidence-corrections.md`,
`package.json`, `package-lock.json`, and `test/browser/reporter_style.test.mjs`.
The manifests only advance private tooling from 0.4.59 to 0.4.60; dependency pins
are unchanged. The style test adds PNG/measurement retention, pointer reset and
instant preview scrolling. All 23 release-manifest runtime files, including the
shipped asset, equal the historical base byte-for-byte. The JS tree digest also
matches the historical correction's recorded digest. No claim is made that the
unavailable historical seven-file patch itself was fetched or hash-verified.

Automatic synchronization was deferred because the main workspace was in use.
Both SDK checkouts were clean with no pending Git operation or lock, so no repair
was necessary before these focused edits. No fetch or synchronization with unseen
remote state is claimed. No reset, stash, commit, push, PR, deployment, consumer
change, database mutation or queue mutation was performed. Saved instructions and
current scope were read through Handrail MCP; no attached memories were listed.

## Parity matrix: current attribution

Use the [source-linked matrix](rails-parity.md#source-linked-parity-matrix) for
immutable JS links and Rails implementation links. The table below identifies
which **fresh developer selections** support each row. Test names and explicit
files are retained in the logs and reproduction bundle. No row is an independent
verdict. Provider persistence, email and actual consumer behavior are not exercised.

| Behavior | Inspected source and fresh check selection | Intentional distinction / remaining limit |
| --- | --- | --- |
| Submission/canonical IDs | `client.rb`, `forwarding.rb`; Ruby submission/accepted-response tests; frontend mounted acceptance; workflow | Browser identity/event survives forwarding; native Ruby stamps its own source-snapshot identity. Provider canonicalization/deduplication remains unverified. |
| Trusted identity | Factory/transport resolver; Ruby transport and authorization; frontend mounted acceptance | Host must resolve trusted application-session identity on each attempt; browser-supplied identity is not authority. Actual consumer principal mapping is pending. |
| Credentials/redaction | Configuration, payload, forwarding, helper; Ruby payload/transport and mounted tests | Report/session tokens remain server-side. Key redaction does not remove secrets in arbitrary free text; trusted hooks cover that need. |
| Authorization/CSRF | Engine controller, guard, generator; Ruby authorization/forwarding/generator; mounted frontend and workflow; lifecycle token rotation | Engine inherits ActionController::Base. Every route needs host admin authorization; hiding a launcher is insufficient. Generated callback denies by default; omitted callback preserves externally guarded legacy mounts. Real Rails CSRF is required. |
| Policy | `policy.rb`, client discovery; Ruby policy; JS core/React and frontend | Bounded discovery, binding and hydration checks; no added automation choices. Real eligibility is provider-owned. |
| History/detail | `history.rb`, routes/forwarding; Ruby history/routes; JS core/React; workflow | Ruby uses frozen projections; browser forwards JSON. UI expanded rows use list data; workflow separately calls getBug. No durable ownership/persistence proof. |
| Archive/restore | History and guard; Ruby history_archive/routes; frontend and workflow | PUT/DELETE/POST, safe IDs and CSRF covered at HTTP boundary. Real provider mutations remain later verification. |
| Attachments | `screenshot.rb`, shared UI; Ruby screenshot; workflow PNG/JPEG and style previews | One opt-in PNG/JPEG, 20 MiB bound. Ruby accepts IO/bytes/base64; browser accepts File/Blob. Storage is unverified. |
| Notification consent | `notification.rb`, forwarding; Ruby notification/subscription; frontend and workflow | Literal true, policy-gated UI, recipient stripping and child failure without replaying accepted parent. No email delivery proof. |
| Retries/errors | Transport/controller; Ruby transport/accepted-response; JS core/server; workflow/lifecycle | Stable body/event with fresh identity; sanitized failures. Ruby defaults to one attempt (configurable 1–3). Rails suppresses malformed accepted JSON to null while preserving 2xx; JS forwarding preserves raw bytes. |
| Appearance | Shared pinned React entry and real helper; style suite | 12 viewport/theme/context cells, field/consent/focus/host-CSS/preview checks. PNG analysis is separate from behavioral assertions; see fresh results below. Arbitrary host CSS/CSP remains unverified. |
| Lifecycle | `rails_adapter.js`; frontend adapter/bundle; lifecycle suite | Ordinary, Turbo 8.0.23 and Turbolinks 5.2.0; cancellation, token refresh, one root/poll, custom launchers. Manual mounts remain caller-owned; abort is not server rollback. Native BFCache is unverified. |

Ruby differences are preserved: stricter path containment and no redirect
following; string/symbol keys, bounded IO, native integer precision and string
normalization; required fields checked before/after hooks. Payload normalization
**does** use depth-20/circular markers. Parsed success responses instead retain
Ruby JSON precision/nesting semantics; they do not pass through payload
normalization. Rails forwards valid accepted JSON bytes without reserialization.
The source-linked historical report's response distinction must not be read as
claiming Ruby payload normalization has no circular/depth handling.

## Developer checks and environment — original 2026-09-15 record

The disposable preparation copies both tracked source trees and existing locked
Node/Ruby dependencies into sibling scratch directories. It copies local Git
objects/refs for identity checks without host Git config/hooks; it creates no
commits. The supplied development `Gemfile.lock` uses a PATH source and is **not**
consumer installation proof. No dependency ranges or locks were changed. Browser
setup downloads only the existing Playwright version's Chromium into scratch.

Ruby 3.1.2p20, RubyGems 3.3.15, Bundler 2.3.7, Rails 7.2.3.2, Rack 3.2.7,
Sprockets 4.4.1 and Minitest 5.27.0; Node 22.23.1, npm 10.9.8, TypeScript 5.9.3,
tsup 8.5.1, esbuild 0.25.8, Playwright 1.61.1. Rails uses React/ReactDOM 18.3.1;
JS checks use 19.2.8. Exact dependency locks and runtime output are retained.

| Check | Fresh result |
| --- | --- |
| Ruby selected source suite | 199 tests / 7242 assertions, zero failures/errors/skips |
| Rails `test/frontend/*.test.mjs` | 23 passing tests; archive-install callback excluded |
| JS `test/*.test.mjs` | 59 passing tests; npm-pack/prepare callback excluded |
| Rails normal build | Passed; exact shipped asset reproduced |
| JS normal build, source and contract typechecks | Passed |
| Bundle/load and release verification | Passed; all 23 runtime files verified |
| Compatibility matrix | Four structural cells passed; no fresh legacy execution |
| Browser | Style 13 TAP tests (12 cells + parent), lifecycle 12, workflow 7; 32 total / 31 leaf cases, zero failures/skips |

The Ruby selector loads 16 named files, never loads `package_contract_test.rb` or
`forwarding_package_test.rb`, and removes exactly the packaged view/generator
methods before enumeration. It records all 199 names, requires the expected
nonzero count, and invokes real Minitest verbosely with seed 61047. Node positive
full-name skip patterns are exercised with throwing canaries before SDK tests;
executed names and totals are checked. Node 22 omits excluded names from TAP.

Setup inspection: test imports register definitions/read assets or use in-memory
esbuild; callbacks use JSDOM, real Rails processes, session/CSRF harnesses and
HTTP-boundary fixtures. Generator/view checks write disposable hosts and asset
outputs. Normal builds write generated JS/dist and the Rails asset only in the
copies. Browser tests start loopback servers and retain PNGs/measurements outside
source. There is no database harness, fake persistence layer, account provisioning,
provider submission or email. Installed dependency reuse does not prove a fresh
anonymous public Git fetch. A managed service, HTTPS fixture and QA campaign are
not SDK prerequisites.

Five direct mounted child reruns passed: request 18/1080, accepted-response
1/2852, authorization 7/1872, subscription 17/2006, history 13/2948
(tests/assertions). These overlap the Ruby wrapper suite and are not added to its
unique count. The subscription count is this run's 2006; the prior correction's
2008 remains its own historical result. Package inventory/load and complete
`npm ls --all --json` checks also passed.

All 48 style PNGs were decoded at their native viewport dimensions. Exact RGBA
comparison found all 12 form pairs and four preview pairs identical. Eight preview
pairs differ at 54 pixels total, with at most 17 pixels in one pair and maximum
channel delta 9/255; alpha is unchanged. Coordinates/colors are retained for every
differing pixel. Desktop differences fall on dialog corner borders; mobile
ones fall on the attachment top corners. This is not literal pixel identity.

Both images of desktop light 1280×900 provided-context form, desktop light
1280×720 absent-context preview, and mobile dark 390×900 provided-context preview
were visually inspected. Fields, consent wrapping, attachment controls and footer
align with no material mismatch observed. The mobile preview intentionally scrolls
the upper context outside the viewport. Lifecycle history and retry-success PNGs
were also inspected. Other cells have automated comparison/layout evidence, not
an additional claimed manual visual inspection. Chromium is 149.0.7827.55;
Firefox/WebKit, actual native BFCache and arbitrary consumer CSS/CSP remain unverified.
The two preview pairs are standalone deliverables; all original style captures
and selected lifecycle captures are embedded losslessly in `browser-captures.json`.

Failures are preserved: initial browser launch had no Chromium executable; the
ordinary scratch download resolved it. The first evidence collector failed on
Python regex-group slicing after a successful Ruby subprocess. Its stdout/stderr,
original collector and earlier checks remain in the evidence, separate from the
final verified rerun. Neither failed collection nor a zero-run test counts as pass.

## Reproduction reference and historical executor continuation

The saved `reproduction-scripts.json` contains exact editable `prepare.py`,
`run.py`, `ruby-selection.rb`, image comparator, setup observations and explicit
argv arrays. Extract to `$TMPDIR/sdk-readiness`; from the multi-repo workspace:

```sh
python3 "$TMPDIR/sdk-readiness/prepare.py"
python3 "$TMPDIR/sdk-readiness/run.py" checks
python3 "$TMPDIR/sdk-readiness/run.py" browser-setup
python3 "$TMPDIR/sdk-readiness/run.py" browser
python3 "$TMPDIR/sdk-readiness/run.py" supplemental
node "$TMPDIR/sdk-readiness/compare.cjs"
node "$TMPDIR/sdk-readiness/retain-lifecycle.cjs"
```

Use a fresh scratch directory and verify retained source hashes before running.
Do not overwrite earlier evidence. The collector stores separate mode results
and stdout/stderr. Within the disposable Rails copy, the critical commands are:

```sh
bundle3.1 check
bundle3.1 exec ruby -Ilib -Itest "$TMPDIR/sdk-readiness/ruby-selection.rb"
npm run build
node --test --test-reporter=tap --test-concurrency=1 '--test-skip-pattern=^RubyGems builds and installs the prebuilt asset with no Node or Git available$' test/frontend/bundle.test.mjs test/frontend/mounted_acceptance.test.mjs test/frontend/rails_adapter.test.mjs
ruby scripts/verify_release.rb --git
ruby test/compatibility/check_matrix.rb
node --test --test-reporter=tap --test-concurrency=1 test/browser/reporter_style.test.mjs
node --test --test-reporter=tap --test-concurrency=1 test/browser/reporter_lifecycle.test.mjs
node --test --test-reporter=tap --test-concurrency=1 test/browser/reporter_workflow.test.mjs
```

Set `PLAYWRIGHT_BROWSERS_PATH` to the scratch cache and `STYLE_ARTIFACT_DIR` /
`LIFECYCLE_ARTIFACT_DIR` outside the source copy, as the driver does. The ordinary
browser preparation is `node node_modules/playwright/cli.js install chromium`.
In the disposable JS copy, run `npm run build`, `npm run typecheck`,
`node node_modules/typescript/bin/tsc --noEmit -p tsconfig.contracts.json`, then:

```sh
node --test --test-reporter=tap --test-concurrency=1 '--test-skip-pattern=^npm pack contains matching metadata and every public export$' test/package-contracts.test.mjs test/react-ui.test.mjs test/react.test.mjs test/reporter.test.mjs test/server.test.mjs
```

Use the saved argv list as authoritative if a checkout's filenames differ; a
changed selection needs review and new expected counts. Broad npm/rake tests,
archive installation helpers and synthetic-commit compatibility runners are
excluded. Explicit child fixture reruns, when listed, overlap the Ruby wrappers.

### Historical executor record — 2026-09-15 (superseded)

The following original continuation is preserved as dated history. The canonical
validation above settles its visibility/receipt requests; it is not a current
instruction to rerun them.

Current `handrail_run_read_only_tests profile=sdk` supports real Node paths,
Ruby/Minitest, builds/load and Playwright in a writable disposable candidate with
locked dependencies read-only. The early inspect probe returned exactly
`This tool requires its own active read-only validation work request.` This
writable development assignment cannot produce its independent receipt. The old
`Select 1–20 explicit scripts/test-*.mjs files.` rejection is preserved history,
not proof of a current path restriction or a need for owner enablement.

In the existing `sdk_review` stage, inspect the exact candidate and use the
returned candidate_sha256 plus a unique request_key for run. Supply `work` Git
identity and the pinned JS reference via `git_references`, including the five
`frontend/upstream.json` source paths. Configure `HANDRAIL_JS_REFERENCE_REPO` to
that reference mount. First actually execute `git rev-parse HEAD` for Rails and
`git -C <reference> show <JS-SHA>:src/reporter.ts` with a SHA-256 assertion; inspection
alone is not visibility proof. Then run the explicit selections/build/load checks
and retain receipts/counts/images. Run JS tests as a separate JS candidate with
its own `work` Git reference. Dependencies/browser binaries must be prepared
before the read-only executor, which cannot download them. Executor mount
visibility and those receipts remain unverified in this worker; the rejected
probe request/response is retained. No platform development is requested.

## Historical evidence and installation boundary

The R1 correction is preserved: original Rails/JS totals were 24/60, including
the archive-install and npm-pack callbacks despite the old exclusion claim.
The later recorded totals were 23/59 and Ruby 199/7242. Original failed attempts
and the historical independent PASS / FAIL / UNVERIFIED / FAIL criterion verdicts
remain attributed to the repository's report; the saved review/log artifacts
were **not supplied or inspected as bytes here**. Fresh developer results do not
reverse those verdicts or establish independent acceptance.

The retained repository legacy evidence was actually read and hashed: three
`test/compatibility/evidence/rails_*‑2026-09-10` sets include acceptance JSON,
locks, snapshots and smoke logs with 1 test / 77 assertions each, plus compressed
assets that decode to their recorded hashes. These are synthetic local Git
fixtures at their recorded Ruby/Rails versions. Nine package files differ from
today's candidate in each snapshot (including controller/helper/client,
authorization templates, notification and release metadata). Their passing
results cannot establish current-candidate legacy acceptance. No legacy runtime
or synthetic installation was rerun.

Public HTTPS Git installation reports for `783e3aa...` and
`15cc5a3f299263e6a498613de34a84857ba9c3d4` remain **historical attribution**.
The latter reports 2 tests / 89 assertions and lock SHA-256
`185e2a760e835e5ef72ba8f482418aa049af7e2a8d58de9b21eb7d727bbee7d9`.
The full historical lock/installer/log were not supplied. No new SDK installation
or anonymous fetch was performed; existing dependency identity/source-map checks
passed. A current install receipt is a bounded replacement when the selected
committed candidate is installed for review/trial; no repeated request for missing
parent artifacts is needed.

For a new authorized install, resolve the latest public committed Rails SHA and
review any runtime drift; honor a frozen SHA for an upgrade. Use the README's
HTTPS Git Gemfile form with the selected **40-character commit**, retain a matching
Gemfile.lock Git revision, and run normal `bundle install` and the host's ordinary
asset pipeline. No tag/branch/path/archive/registry substitution, dependency-bound
bypass, separate package publication or uncommitted patch as an install revision.
The current working documentation patch is not a published install reference.

The historical [BlueCotton fixture limitation](../test/compatibility/BLUECOTTON_BLOCKER.md)
belongs to that old consumer assignment, not SDK first-trial prerequisites. Its
unavailable captured consumer lock and Ruby discrepancy are not resolved by generic
legacy cells. Do not revive the cancelled fixture/campaign work. Current consumer
Ruby, lock, CSS/CSP, fetch/install, admin route authorization and actual provider
workflow remain consumer verification, initially development only.

## Review and adoption gates

`sdk_parity_coverage`: updated source-linked attribution is ready for review.
`sdk_behavior_and_package`: independent selected checks/build/typecheck/load passed
per the canonical validation above; package exclusions still apply. Current
selected-commit public HTTPS Git installation with a matching lockfile remains
pending and is separate from source/build evidence. `sdk_browser_parity`:
independent browser execution passed within its fixture/runtime scope; Arial used
FreeMono and typography equivalence remains unverified. The separate `sdk_review`
stage still owns the readiness conclusion and assessment of visual/behavioral
limits. `readiness_and_consumer_handoff`: this documentation assignment is complete
when its files and checks are finished; it does not grant SDK or trial acceptance.
Current consumer compatibility, installation, real admin authorization and
provider persistence/email remain pending.

Preserve SDK readiness → independent `sdk_review` → owner notification and explicit
Monuvision trial direction/environment → successful Monuvision verification →
conditional BlueCotton adoption and independent review. Both consumers must limit
placement to admin screens **and** enforce authenticated-admin authorization on
every SDK route. The persistent task owns owner presentation and decisions. If
staging/production is selected, revise the plan first with separate deployment
stages and required action approvals; use only the existing CI/CD path.
