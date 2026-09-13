# Rails parity candidate — 2026-09-13

Documentation reconciliation for `rails-parity`, verification plan
`925051a6-f727-40b2-aa62-61c7484be57e`, work request
`e7d7b751-6acc-43f2-9176-ae74957fe046`. Preserves implementation repair
`0e42b610-f9c5-462f-b6a1-82b4e07e139f` and candidate work
`b8065182-24b9-413b-aa6d-d632d615f5bd`, with independent source/install evidence
from `7208c879-38de-412e-a6a6-7c2a0f5a4fae` and later attributed browser evidence
below. This is **not independent QA acceptance or an adoption recommendation**.
The saved correction authorizes SDK documentation changes at policy revision 1;
earlier permission/schema blockers are superseded.

## Exact source

- JS reference: public repository `https://github.com/c0x65o/handrail-sdk-bug-reporter-js`,
  clean commit `7dfb33f548448f864cf957f19d96f8b5a27bc787`, package 0.4.50.
  Initial working-tree SHA-256:
  `c1fcaa0ff9536707fe7a3433f40b9a3eefbcf5d2ab28acd5527e8a0170abdbd5`.
- Rails verified source commit: `783e3aa0321a7e0b6bec1143d75c780e3f955b25`.
  At documentation-correction start, all 188 files match the attached independent
  inventory, SHA-256
  `4f09180a5b5ba6ebe6031982a9911ad1d9cad7d55a431386c9732e00b2a251a5`.
  The historical repair base remains `42f70f0a3bedf5573f79988d75789b13e55f8bcd`.
  The review candidate is the verified commit plus the retained documentation
  patch; it is not represented as installed by that commit. Final hashes and
  complete inventories are in the saved `source-identities.json`; embedding the
  final tree hash here would be self-referential.
- Tree hashing: sort all tracked and nonignored untracked paths; form objects with
  `path` and raw-byte `sha256`; hash compact JSON with sorted object keys. Deleted
  tracked files use null. Excludes Git internals and ignored dependencies/output.
- Rails gem version is 0.4.49; private frontend tooling version is 0.4.58.
  The earlier repair inventory used private version 0.4.57. Independent QA found
  only the two contributor JSON files differed from that repair, solely in their
  three version declarations. Those historical and committed trees have different
  raw hashes but equivalent runtime bytes; neither private version is a gem release.
  The unchanged manifest stays `source_snapshot` with null release commit/ref and
  historical base `42f70f0a3bedf5573f79988d75789b13e55f8bcd`. Its
  `private-contributor-v1` fingerprints normalize those private versions and are
  distinct from raw-byte hashes retained for every candidate file. A containing
  public Git commit can be installed without changing these provenance semantics.
- The shared browser asset is unchanged: 241154 bytes, SHA-256
  `2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`.
  `frontend/upstream.json`, manifest and lock all pin the exact JS reference.
- Worker synchronization was deferred as `main_workspace_in_use`. Inspection
  found the clean verified Rails commit and clean frozen JS reference, with no
  pending Git operation, lock or conflict to repair.
  No reset, stash, fetch, commit, push or branch change was performed. This review
  binds current checkout bytes, not an assertion that upstream synchronization ran.
  Existing Rails implementation and both unrelated SDK repositories are preserved.

## Source-linked parity matrix

JS links below are immutable reference links. Rails links resolve within the
candidate; the retained inventory binds their exact bytes. “Covered” means source
inspection plus the named implementation checks, not rendered/live acceptance.
Source/install results below were read in the hash-verified ordinary QA report;
later browser results are attributed to validation work and Main Avery, whose
canonical report and media are not attached to this documentation worker.

| Behavior | Current JS evidence | Rails coverage / current result |
| --- | --- | --- |
| Submission and canonical IDs | [reporter.ts, submit/buildPayload](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1504) | Browser uses the same JS payload/UI through [entry.jsx](../frontend/entry.jsx). [Forwarding](../lib/handrail/bug_reporter/forwarding.rb) preserves browser identity/event IDs and configured project/environment. [Client](../lib/handrail/bug_reporter/client.rb) and [submission tests](../test/submission_test.rb) cover native Ruby canonical IDs, single preparation, stable retries, and disabled/malformed cases. Covered. |
| Redaction and trusted identity | [server handler](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L280) | [Payload](../lib/handrail/bug_reporter/payload.rb), [forwarding](../lib/handrail/bug_reporter/forwarding.rb), and [transport](../lib/handrail/bug_reporter/transport.rb) strip nested credentials, keep tokens server-only, resolve sessions per attempt and prohibit cross-origin/path-escape upstream requests. Mounted forged-header/body cases and interleaved native-client tests pass. Covered. |
| Host authorization and CSRF | [JS same-origin check](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L394) and [trusted resolver](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/server.ts#L525); admin authorization is a host responsibility | Added [Factory#authorized?](../lib/handrail/bug_reporter/client.rb) and [controller gate](../app/controllers/handrail/bug_reporter/reports_controller.rb) for all eight routes, plus [helper suppression](../app/helpers/handrail/bug_reporter_helper.rb). [Generated initializer](../lib/generators/handrail/bug_reporter/templates/initializer.rb.tt) defaults to deny. [Real Rails authorization checks](../test/fixtures/mounted/authorization_checks.rb) cover admin, nonadmin, anonymous, forged identity, revoked/raising/truthy callbacks, upstream failures and mandatory CSRF. Covered; actual consumer auth remains unverified. |
| Policy and identity hydration | [discoverPolicy](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1400), [parsePolicy](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1953) | Same JS browser discovery; [Ruby Policy](../lib/handrail/bug_reporter/policy.rb)/[tests](../test/policy_test.rb) validate binding/schema/roles, empty asks, risk policy, consent eligibility, bounded discovery deadlines and hydration retries. Covered. |
| Automation selection | [AUTOMATION_OPTIONS is empty](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L40) | Rails correctly removes automation requests and exposes no selectable asks. Older generic forwarding branches do not imply current support. No automation feature was added. Covered. |
| Owned history and detail | [listBugs/getBug](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1667) | [History](../lib/handrail/bug_reporter/history.rb), [native tests](../test/history_test.rb), [mounted tests](../test/fixtures/mounted/history_checks.rb) cover query defaults/bounds, ownership 401/403, first duplicate query value, detail, status rollups, journey and versioned fields. Browser receives unreserialized wire JSON. Covered. |
| Archive, restore, archive-closed | [archive operations](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1749) | [Routes](../config/routes.rb), [history archive tests](../test/history_archive_test.rb) and mounted history tests cover PUT/DELETE/POST, binding, no unwanted request body, safe IDs, auth and CSRF. Covered. |
| Attachments/screenshots | [buildPayload attachment handling](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1935) | Shared browser UI supports one PNG/JPEG up to 20 MiB with explicit screenshot opt-in. [Ruby screenshot implementation](../lib/handrail/bug_reporter/screenshot.rb)/[tests](../test/screenshot_test.rb) cover MIME/signature/base64/IO, exact limit, failure and explicit permission. Independent composed checks pass actual PNG/JPEG and invalid-byte cases. Later preview evidence is attributed below; full independent media inspection remains pending. |
| Notification consent | [subscribeToUpdates](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/reporter.ts#L1603), [UI](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react-ui.tsx) | Shared UI owns unchecked policy-gated consent. [Notification](../lib/handrail/bug_reporter/notification.rb), [native tests](../test/notification_test.rb), [mounted subscription checks](../test/fixtures/mounted/subscription_checks.rb) require explicit true, strip recipient/credential injection, preserve saved-report success and warn on child failure without replaying intake. Independent parent/child call-count checks pass. Later browser results are attributed below; live delivery remains unverified. |
| Appearance and lifecycle | [React provider](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react.ts), [React UI](https://github.com/c0x65o/handrail-sdk-bug-reporter-js/blob/7dfb33f548448f864cf957f19d96f8b5a27bc787/src/react-ui.tsx) | Exact shared JS React UI, privately bundled React 18.3.1. [Helper](../app/helpers/handrail/bug_reporter_helper.rb) passes themes/tokens/context; [adapter](../frontend/rails_adapter.js) handles Turbo/Turbolinks, custom launchers, cleanup and current CSRF token. Independent DOM/build checks pass; later validation reports 33 TAP tests and 54 identical image pairs plus separate scrolled previews. These disposable-fixture results require full independent media inspection and do not establish managed-route or consumer acceptance. |
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

## Verification and installation evidence

The documentation worker read all three attached ordinary artifacts and verified
these SHA-256 identities. Their original bytes and historical limitations are
retained unchanged with the documentation handoff:

| Artifact | Saved work_artifact ID | SHA-256 |
| --- | --- | --- |
| Independent source/install QA report | `91ad3a35-18dc-51f0-ae3c-877515537072` | `41bf5270f9a3635a6597af731e093cf28e3052f13e2eb3f8d2376052524cfc0d` |
| Installation manifest, lockfile and command results | `65cf8d5e-202c-5ea1-a36c-68704dc694cb` | `7c289d10d9d48e164c1756223196b384a97bb70f68fc9648c0918a8f55dda67d` |
| Candidate/reference inventories and reconciliation | `7df7fed7-8d20-5f0b-ae68-e967cefdbaa8` | `988df7b42b2f7c6cc98a0c1d7e0373bc2e662db52ddaf2c229cf93647d6193b7` |

Independent work `7208c879-38de-412e-a6a6-7c2a0f5a4fae` reports **252 Ruby tests /
18,487 assertions and 24 JavaScript checks passing**, plus scoped JS TypeScript
compilation and Rails asset compilation. These are reused results, not suites
rerun by this documentation worker. The report identifies commands and retained
assertion logs; those separate raw logs are not attached here.

The request checks exercise all eight mounted operations across
200/201/202/204/205 and ten body variants, retaining acceptance for malformed/empty
success, valid JSON precision and single-call behavior. Composed JS-through-Rails
checks verify PNG/JPEG handling, child-subscription failures, history/archive and
stable retry event IDs. Admin/nonadmin/anonymous/revoked sessions and forged
identity are checked against actual Rails routing, encrypted cookie sessions and
CSRF verification, with narrow outbound HTTP boundary fakes. The workflow fixture
starts anonymous; only explicit CSRF-protected transitions establish its synthetic
admin principal. Unauthorized pages omit the helper and asset. No ActiveRecord
or database is loaded and no persistence behavior is claimed. Live ownership,
notification delivery and deduplication remain unverified.

The same independent report establishes anonymous public HTTPS Git availability
and a full-SHA installation of Rails
`783e3aa0321a7e0b6bec1143d75c780e3f955b25`. The attached
`installation-results.json` embeds the complete disposable-host Gemfile and
matching Gemfile.lock, including this SDK selection:

```ruby
gem "handrail-bug-reporter", git: "https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git", ref: "783e3aa0321a7e0b6bec1143d75c780e3f955b25", require: false
```

```text
GIT
  remote: https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git
  revision: 783e3aa0321a7e0b6bec1143d75c780e3f955b25
  ref: 783e3aa0321a7e0b6bec1143d75c780e3f955b25
```

The lock excerpt identifies the SDK; use the complete retained lockfile when
inspecting that QA installation. `bundle3.1 lock`, frozen `bundle3.1 install
--jobs 2 --retry 1`, and normal `bundle3.1 exec rake assets:precompile --trace`
all exited zero. Existing third-party gems were reused in an isolated BUNDLE_PATH;
Bundler freshly fetched the SDK from public HTTPS Git. The installed-host check
contributes 398 assertions to the Ruby total above, checking the Git URL/revision,
187 installed files byte-for-byte plus normalized gemspec semantics, manifest,
compiled asset, successful intake, invalid CSRF and revoked authorization.
Ruby 3.1.2 / Rails 7.2.3.2 / Bundler 2.3.7 / Sprockets 4.4.1 were exercised.

This is installation proof for the committed source snapshot, not an accepted
release, proof of installation of this later documentation patch, or consumer
integration. The source-loaded Rails Gemfile is not a consumer installation
lockfile. For each new installation resolve the latest committed SDK revision;
for upgrades honor any frozen revision. Retain matching package-manager locks
and compile in the normal install/build pipeline. Do not use registry, tarball,
local-path, workspace, branch or tag SDK substitutions, synthetic commits or a
separate packaging/publication step. Historical legacy-runtime and package
records remain historical; they are not current-candidate acceptance.

### Later browser evidence and fixture status

Validation work `8d33d1fb-30a6-46d7-9683-31ce5789553e` reports **33 passing TAP
tests**, **54 pixel-identical Rails/direct-JS image pairs** across **1280x900,
1280x720 and 390x900**, light/dark themes, plus separate scrolled mobile previews
differing by **zero/two pixels**. Main Avery reports reading and hash-verifying
canonical report `c30bc27e-3007-46bc-a359-66e49e5a05fb`, SHA-256
`237fae36c7d1523c3615b4d5f87d5d5831bed77f90c9d6bd2c9ca3693c364375`.
This attribution supersedes the ordinary report's earlier missing-browser and
missing-rendered-evidence limitation. It does not retroactively change that
report's observations. Canonical validation files and images are not attached to
this worker; no canonical paths, image hashes, assertion breakdown or independent
visual inspection are inferred. Main Avery's reported partial mobile-dark image
inspection is not complete corresponding-media inspection or acceptance.

The earlier repair's stopped-service observation is historical. The attached
independent report later observed `rails-css-parity-fixture`, service
`8317027d-9b3b-4d61-8946-c7c978b1ec39`, supervised/running at the verified launch
SHA with host health 200, while the scoped managed HTTPS request returned 404
`[handrail-proxy] dev host not available`. Disposable-fixture browser passes do
not resolve that managed-route limitation or establish current service status.
No service/proxy operation or fresh probe occurred for this documentation patch.

The actual disposable-fixture procedures are [docs/browser_adapter.md](browser_adapter.md)
and [test/fixtures/workflow/README.md](../test/fixtures/workflow/README.md).
The earlier `docs/HANDRAIL.md` reference was mistaken. The
[style fixture](../test/browser/reporter_style.md) compares renderers using boundary
responses; the mounted workflow/lifecycle fixtures exercise the real Rails host.
Neither proves live Handrail ownership, delivery, deduplication or consumer access.

## Five-criterion evidence index and independent handoff

All five criteria of saved plan `925051a6-f727-40b2-aa62-61c7484be57e` remain in
scope. This table records evidence and remaining work, not canonical acceptance.
The retained `evidence-index.md` additionally maps the deliverables and exact
candidate/changed-file hashes for normal submission and independent inspection.

| Saved criterion | Evidence and remaining limitation |
| --- | --- |
| current-source-parity | Matrix above maps the exact frozen JS reference to Rails submission, policy, history, screenshots, consent, appearance and errors. All initial bytes match independent source inventories; only documentation changes follow. Intentional Ruby differences and live-policy limitations remain explicit. |
| rails-integration-and-security | Independent real-Rails and installed-host checks pass failure, identity, all-route authorization, same-origin and CSRF boundaries. Later browser results are attributed above. Complete independent browser evidence review and live ownership/delivery remain unverified; host integration is not established. |
| rendered-ui-parity | Later disposable validation reports 33 TAP tests and 54 identical image pairs plus separate zero/two-pixel scrolled previews. Canonical media is not attached here; full corresponding-media inspection remains for independent review. Managed HTTPS 404 remains unresolved. |
| installation-and-retained-candidate | Public HTTPS/full-SHA installation, complete matching lockfile and normal precompile are retained with the original QA report. The final documentation patch, complete base-to-candidate patch, edited documents, parity matrix and raw inventories are retained separately. Canonical rendered files must be inspected through their saved validation records; this patch is not an installed or accepted release. |
| owner-notification-and-adoption-gates | Results and limitations return to Avery for independent readiness review and normal submission. After independently verified parity Avery must notify the owner and pause for explicit continuation. Notification, acceptance and consumer adoption are not claimed by this worker. Monuvision must succeed before BlueCotton; both remain admin-screen/authenticated-admin only. |

Bind final candidate/reference hashes before reuse. Independently inspect the
complete corresponding retained media and named assertion logs against the saved
plan: desktop/mobile light/dark, context present/absent, hostile host CSS, consent
and form validation, screenshot preview/replacement/removal, success and child
warnings, policy/error/retry, history/detail/archive/restore, navigation and CSRF
rotation. Preserve any missing state as unverified; do not infer coverage solely
from totals. Reuse passed source/install/browser results unless actual drift or
a demonstrated gap justifies scoped checks. Do not rerun suites to repair metadata.

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
