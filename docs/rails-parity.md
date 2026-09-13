# Rails parity candidate — 2026-09-13

Implementation handoff for `rails-parity`, verification plan
`925051a6-f727-40b2-aa62-61c7484be57e`, work request
`0e42b610-f9c5-462f-b6a1-82b4e07e139f`, repairing independent assessment
`ddd30625-3ba7-4c00-a788-6419a0f0c365` while preserving candidate work from
`b8065182-24b9-413b-aa6d-d632d615f5bd`. This is **not independent QA acceptance or
an adoption recommendation**. The saved correction authorizes SDK repo changes
at policy revision 1; earlier permission/schema blockers are superseded.

## Exact source

- JS reference: public repository `https://github.com/c0x65o/handrail-sdk-bug-reporter-js`,
  clean commit `7dfb33f548448f864cf957f19d96f8b5a27bc787`, package 0.4.50.
  Initial working-tree SHA-256:
  `c1fcaa0ff9536707fe7a3433f40b9a3eefbcf5d2ab28acd5527e8a0170abdbd5`.
- Rails base: `42f70f0a3bedf5573f79988d75789b13e55f8bcd`, 29-file candidate at repair start;
  initial working-tree SHA-256:
  `8bf5e6ccc2c52224b3f42445dc6a520e7420e517ed7d0becd9b9afa696e0241d`.
  The final candidate is this base plus the complete retained patch and editable
  changed files. Final hashes/inventories are in the saved `source-identities.json`;
  embedding that final tree hash in this source document would be self-referential.
- Tree hashing: sort all tracked and nonignored untracked paths; form objects with
  `path` and raw-byte `sha256`; hash compact JSON with sorted object keys. Deleted
  tracked files use null. Excludes Git internals and ignored dependencies/output.
- Rails gem version is 0.4.49; private frontend tooling version 0.4.57 is not a gem
  release. The manifest stays `source_snapshot` with null release commit/ref and
  the current Rails base. Its optional normalized contributor fingerprints are
  distinct from raw-byte hashes retained for every candidate file.
- The shared browser asset is unchanged: 241154 bytes, SHA-256
  `2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`.
  `frontend/upstream.json`, manifest and lock all pin the exact JS reference.
- Worker synchronization was deferred as `main_workspace_in_use`. Inspection
  found the exact existing Rails candidate and clean frozen JS reference, with no
  pending Git operation, lock or conflict to repair.
  No reset, stash, fetch, commit, push or branch change was performed. This review
  binds current checkout bytes, not an assertion that upstream synchronization ran.
  Existing Rails implementation and both unrelated SDK repositories are preserved.

## Source-linked parity matrix

JS links below are immutable reference links. Rails links resolve within the
candidate; the retained inventory binds their exact bytes. “Covered” means source
inspection plus the named implementation checks, not rendered/live acceptance.

| Behavior | Current JS evidence | Rails coverage / current result |
| --- | --- | --- |
| Submission and canonical IDs | [reporter.ts, submit/buildPayload](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1504) | Browser uses the same JS payload/UI through [entry.jsx](../frontend/entry.jsx). [Forwarding](../lib/handrail/bug_reporter/forwarding.rb) preserves browser identity/event IDs and configured project/environment. [Client](../lib/handrail/bug_reporter/client.rb) and [submission tests](../test/submission_test.rb) cover native Ruby canonical IDs, single preparation, stable retries, and disabled/malformed cases. Covered. |
| Redaction and trusted identity | [server handler](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L290) | [Payload](../lib/handrail/bug_reporter/payload.rb), [forwarding](../lib/handrail/bug_reporter/forwarding.rb), and [transport](../lib/handrail/bug_reporter/transport.rb) strip nested credentials, keep tokens server-only, resolve sessions per attempt and prohibit cross-origin/path-escape upstream requests. Mounted forged-header/body cases and interleaved native-client tests pass. Covered. |
| Host authorization and CSRF | [JS same-origin check and trusted resolver](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L359); admin authorization is a host responsibility | Added [Factory#authorized?](../lib/handrail/bug_reporter/client.rb) and [controller gate](../app/controllers/handrail/bug_reporter/reports_controller.rb) for all eight routes, plus [helper suppression](../app/helpers/handrail/bug_reporter_helper.rb). [Generated initializer](../lib/generators/handrail/bug_reporter/templates/initializer.rb.tt) defaults to deny. [Real Rails authorization checks](../test/fixtures/mounted/authorization_checks.rb) cover admin, nonadmin, anonymous, forged identity, revoked/raising/truthy callbacks, upstream failures and mandatory CSRF. Covered; actual consumer auth remains unverified. |
| Policy and identity hydration | [discoverPolicy](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1400), [parsePolicy](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1953) | Same JS browser discovery; [Ruby Policy](../lib/handrail/bug_reporter/policy.rb)/[tests](../test/policy_test.rb) validate binding/schema/roles, empty asks, risk policy, consent eligibility, bounded discovery deadlines and hydration retries. Covered. |
| Automation selection | [AUTOMATION_OPTIONS is empty](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L33) | Rails correctly removes automation requests and exposes no selectable asks. Older generic forwarding branches do not imply current support. No automation feature was added. Covered. |
| Owned history and detail | [listBugs/getBug](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1667) | [History](../lib/handrail/bug_reporter/history.rb), [native tests](../test/history_test.rb), [mounted tests](../test/fixtures/mounted/history_checks.rb) cover query defaults/bounds, ownership 401/403, first duplicate query value, detail, status rollups, journey and versioned fields. Browser receives unreserialized wire JSON. Covered. |
| Archive, restore, archive-closed | [archive operations](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1749) | [Routes](../config/routes.rb), [history archive tests](../test/history_archive_test.rb) and mounted history tests cover PUT/DELETE/POST, binding, no unwanted request body, safe IDs, auth and CSRF. Covered. |
| Attachments/screenshots | [buildPayload attachment handling](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1935) | Shared browser UI supports one PNG/JPEG up to 20 MiB with explicit screenshot opt-in. [Ruby screenshot implementation](../lib/handrail/bug_reporter/screenshot.rb)/[tests](../test/screenshot_test.rb) cover MIME/signature/base64/IO, exact limit, failure and explicit permission. Preview rendering remains unverified this run. |
| Notification consent | [subscribeToUpdates](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1603), [UI](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react-ui.tsx) | Shared UI owns unchecked policy-gated consent. [Notification](../lib/handrail/bug_reporter/notification.rb), [native tests](../test/notification_test.rb), [mounted subscription checks](../test/fixtures/mounted/subscription_checks.rb) require explicit true, strip recipient/credential injection, preserve saved-report success and warn on child failure without replaying intake. Covered at implementation boundaries; rendered flow pending. |
| Appearance and lifecycle | [React provider](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react.ts), [React UI](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react-ui.tsx) | Exact shared JS React UI, privately bundled React 18.3.1. [Helper](../app/helpers/handrail/bug_reporter_helper.rb) passes themes/tokens/context; [adapter](../frontend/rails_adapter.js) handles Turbo/Turbolinks, custom launchers, cleanup and current CSRF token. 18 frontend DOM/build tests pass; no new rendered parity claim. |
| Errors, retries and success bytes | [JS response contract](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L586) | Fixed [controller](../app/controllers/handrail/bug_reporter/reports_controller.rb): preserve upstream 4xx/5xx with generic `bug_reporting_rejected`; network/unavailable errors use `bug_reporting_unavailable`. Empty success and numeric wire precision are retained. [Mounted checks](../test/fixtures/mounted/request_checks.rb) plus every-route 422/503 tests prove permanent/transient handling. Updated lifecycle expectations from old mapped 502 to actual 503. |

## Compatibility choices and remaining differences

The additive authorizer preserves existing externally guarded mounts when the
option is omitted. That default is **not** an admin restriction: Handrail consumer
integration must provide this callback or a verified equivalent guard covering
all routes. Supplied nil/noncallable/truthy/raising callbacks deny. Native Ruby
clients remain trusted server APIs; the route gate does not restrict unrelated
server jobs. Host authentication must populate the principal; the SDK provisions
no users and never derives authorization from report JSON or incoming auth headers.

Ruby retains stricter input/path/redirect validation than the generic JS proxy:
redirects are not followed and encoded path escapes are rejected. Accepted
malformed JSON now yields `null` at the original 2xx status; the JS proxy forwards
raw malformed bytes. Suppression of potentially private diagnostics is an
intentional wire-level difference with equivalent submission acceptance semantics.
Valid success JSON is forwarded without reserialization, preserving precision.
Empty subscription successes retain their status; an active result is still needed
by either client, so empty child results warn without replaying the parent.
Native Ruby accepts empty/malformed success as nil and primitives/arrays as parsed
immutable values. Canonical IDs are read only from object `bug_id`, never another ID.
Ruby keeps its existing JSON parser nesting limit (over-limit success becomes nil),
raw result fields and numeric representation; it does not implement JS response
normalization's depth-20 `[Circular]`, key truncation/redaction or IEEE-754 rounding.
Native response data remains explicitly accessed; safe result inspection omits it.
Ruby string/integer/type normalization differences are documented in
[payload.md](payload.md#json-bounds-and-ruby-differences). These are compatibility
limits, not literal cross-language equivalence.
Resolver exceptions/absence outside discovery fall back to no application-session
token as in JS. This does not establish ownership, notification eligibility or
host admin authorization. Real upstream policy remains independently unverified.
No currently selectable automation or additional attachment product is inferred.

## Verification and installation limits

The saved repair test report binds exact commands, named assertions and final
results to the revised inventory. New checks exercise all eight mounted operations
across 200/201/202/204/205, empty/malformed/primitive/precise JSON, single upstream
calls and stable event IDs. Native submission checks compare empty/primitive
semantics; a JS client composed through the real mounted Rails workflow proves
known acceptance is submitted once with retries enabled. That composition runs
over stdin/Rack without browser rendering or network sockets. It is boundary
retry-prevention evidence, **not live deduplication/persistence evidence**.

The workflow fixture now starts anonymous and uses explicit CSRF-protected fixture
session transitions for admin, nonadmin, anonymous and revoked states. Its Factory
supplies a literal admin authorizer; no page automatically creates a principal.
Executed composed checks verify all eight routes (including valid-CSRF nonadmin
writes), denial before identity/HTTP and absence of reporter markup/assets on
unauthorized pages. Existing tests cover nil/noncallable/truthy/raising authorizers,
omitted compatibility behavior, resolver fallback and revocation across requests.
Browser workflow assertions also cover these states and accepted malformed/empty
intake plus empty subscription. Browser and lifecycle assertions are **authored but
unexecuted**: Chromium remains absent, and no known prelaunch failure was rerun.
Historical browser launch failures are not current test failures or passes.

Repairs R1/R2 are verified at native/proxy/composed client boundaries; R3 fixture
coverage is verified through real Rack/CSRF requests, with browser rendering pending;
R4 remains an upstream identity integration requirement; R5 environment/payload
instructions are reconciled. R6 (independent rendered and final installation QA)
remains unresolved. The shared browser asset is unchanged after normal `npm run
build`; installed-candidate evidence still requires the separate public Git step.

Real Rails 7.2.3.2 / Ruby 3.1.2 request tests use the existing no-network harness,
actual routing/cookie sessions/CSRF and narrow outbound HTTP boundary fakes.
No ActiveRecord or database is loaded; no persistence behavior is claimed.
Legacy Ruby/Rails records remain historical, not reverified here.
Package archive installs and synthetic-commit compatibility tests were excluded.
No new SDK installation occurred. The existing npm dependency/lock pair is public
HTTPS Git at full JS SHA and its installed source maps/build were checked.
The source-loaded Rails test Gemfile is not a consumer installation lockfile.

README tag-based advice, anonymous generated-mount guidance, stale browser-load
claims and release-fingerprint documentation were corrected against actual source.
Historical v0.4.50 Rails tag still declares gem 0.4.49; neither that tag nor old
acceptance reports establishes this candidate's readiness. A separately authorized
maintainer must finalize/publish the reviewed source before a full public Git SHA
can identify it. Subsequent QA must bind the actual installed revision and matching
lockfile, using the normal install/build pipeline without a separate packaging step.

## Independent QA handoff and owner gate

Lead must commission independent functional and rendered QA under the saved plan.
Read-only service status found `rails-css-parity-fixture`, service
`8317027d-9b3b-4d61-8946-c7c978b1ec39`, stopped with no listener or QA browser route.
Its declared command remains `PORT=4179 npm run fixture:style`, port 4179, health
path `/style-fixture?renderer=rails&theme=light&absent=false`. No configuration,
resource or service-state changes were made. Supported browser availability and
fixture runtime access/action authorization are exact dependencies for the lead.

Bind final candidate/reference hashes first. Compare Rails/reference light/dark,
context present/absent, mobile/desktop, hostile host CSS, long consent hints, form
validation, screenshot preview/replacement/removal, consent eligibility/checked
state, submit success, child-subscription warning, policy/unavailable/retry states,
owned history/detail/archive/restore, and ordinary/Turbo/Turbolinks navigation.
Retain and inspect actual screenshots at their viewport sizes and assertion-level
browser logs. The style fixture uses boundary responses and is not a complete
Rails HTTP integration fixture; also exercise the real mounted-host workflow.
Prove anonymous/nonadmin denial on all eight routes, authenticated-admin success,
forged identity rejection, fresh identity after changes, CSRF invalid/stale/rotated
cases, same-origin enforcement and no secret leakage. Do not treat authored tests,
old screenshots, source equality or this report as independent QA acceptance.

Permission scope remains SDK project `0fef581d-d8f7-46fa-a111-fad9ee0c81ae`,
`repo_changes`, dev only. No configuration, provisioning, operational runbook,
commit/push/PR, deployment or consumer integration is authorized. QA credential
profiles are unresolved; project `qa_admin_provisioning=do_not_manage` applies.
Do not seed users or request/disclose secrets. There are no Kubernetes targets.

Only after independent verified parity should Avery notify the owner and pause.
Explicit continuation is required before Monuvision
`ebde1505-74c9-424c-998d-3d9e1d98ccb9`; successful Monuvision verification must precede
BlueCotton `d388bd26-d291-4979-9e51-7d7b728d7a0b`. Each needs its own source/config/
release permissions, exact Ruby/lockfile/runtime evidence, and separate deployment
and QA steps. Both integrations are restricted to admin screens and authenticated
admin users. This worker result does not satisfy or waive those gates.
