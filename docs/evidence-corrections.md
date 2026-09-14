# SDK evidence corrections — 2026-09-13

Developer correction for `f805ff6b-3bf1-409a-9fb1-f908e8e76115`, independent review
`b906468f-a407-4afe-8a50-9f802a0fb971` and saved rework
`3c37abaf-466f-40f4-911b-fdf79114a212`, within the existing `sdk_parity` stage.
**Developer corrections and checks are complete; independent acceptance and owner
direction remain pending. R2 is not resolved.** No concrete runtime defect was
established, so runtime source, shipped asset, tests and prior capture patch are
preserved. This correction changes documentation only.

## Candidate comparison before changes

Both inventories were recomputed using sorted tracked/nonignored paths, raw-byte
SHA-256 and compact sorted-key JSON arrays of `{path,sha256}`. The complete
retained per-file inventory was not separately attached, but the independently
recorded inventory digests and exact patch were available and matched:

| Repository | Frozen base | Files | Initial tree SHA-256 |
| --- | --- | --- | --- |
| Rails | `15cc5a3f299263e6a498613de34a84857ba9c3d4` | 188 | `71f5bb0bde2cf4865a349852f51d4d929e0223691b1d73cd8ab606d7a1e8f1cc` |
| JS | `7dfb33f548448f864cf957f19d96f8b5a27bc787` | 27 | `c1fcaa0ff9536707fe7a3433f40b9a3eefbcf5d2ab28acd5527e8a0170abdbd5` |

The initial Rails diff SHA-256 was
`e524cbb2505c05c1bef1587f315c167353c534caebb736df19447df6038870ed`, exactly the
attached seven-file patch. **No initial candidate drift.** JS was clean; Rails
contained the retained patch. Neither repository had a merge, rebase or index
lock. Automatic synchronization remained deferred (`main_workspace_in_use`); no
fetch/synchronization with unseen upstream state is claimed or needed to preserve
this exact candidate. No reset, stash, Git repair, commit, push or PR occurred.

All three attached artifacts were read in full and hash-verified. All 78 embedded
original log/measurement sections also verify; the final section's trailing visual
inspection narrative is outside its section hash. Original artifacts are retained
unchanged with these source identities:

| Source artifact ID | Artifact | SHA-256 |
| --- | --- | --- |
| `7201483a-ab00-5a4d-a563-05f14722d48e` | Independent readiness review | `ced399483303e54b6cf888db44a60e7eddbb7c43ff4843e97aca134e62eb3680` |
| `184eb2c0-7792-5488-a965-0c6cebcc8813` | Original developer logs | `ee97a2d7d86e55dd7bd50afd6f08bb294a8b5ca24d3026cc5dac46a4c4da2b10` |
| `88d42e8c-d1ee-5d01-a8ed-200bba96143c` | Prior patch | `e524cbb2505c05c1bef1587f315c167353c534caebb736df19447df6038870ed` |

## R1 correction and reliable selection

The original log line 1349 reports the executed passing test
`RubyGems builds and installs the prebuilt asset with no Node or Git available`.
Its callback invoked `test/frontend/package_contract.rb`, which built a gem under
`.asset-package-*` in the checkout and called `Gem::Installer.at(...).install`.
Those temporary build/install effects occurred despite the claimed exclusion.
The helper normally removes its temporary directory; matching current source
hashes do not prove every earlier effect was absent or undone.

Original log line 543 reports the executed passing JS test
`npm pack contains matching metadata and every public export`. It invoked
`npm pack --dry-run --json --silent`, including the package's `prepare` → normal
build pipeline and generated/dist writes. This was **not** itself an SDK archive
installation. Neither test was skipped. Original 24/60 pass totals remain the
actual original totals, not retroactively reduced filtered passes.

The new standalone evidence driver uses full-name positive Node
`--test-skip-pattern` options, explicit file lists, and an inspected name manifest.
Before SDK execution, harmless canaries verified each excluded name's body was
not called. Module initialization and setup were inspected separately: selected
Node imports only read/load definitions; allowed cases use JSDOM, real Rails
bridge subprocesses, in-memory esbuild and service-boundary fakes. Explicit normal
builds write generated output. No SDK installation is performed by this correction.

For Ruby, the driver disables implicit autorun only in its own process, loads the
16 allowed files, enumerates methods, snapshots every class's allowed list before
changing any runnable list, checks that list, then invokes real Minitest verbosely.
Both package files are never loaded. Two packaged view/generator methods are
excluded. All 199 executed names are compared with the preflight selection.

`selection.json` and `setup-side-effects.md` in the evidence contain every selected
and excluded name, file and setup effect. Node actual-name comparison requires
exactly the selected 23 Rails/59 JS names, including two generated mounted cases.
An excluded case is omitted from TAP on Node 22.23.1; zero skips alone is not proof.
The full reproduction driver fails on source drift, selection mismatch, zero Ruby
runs or failed checks. Broad npm/rake checks, the archive helpers and compatibility
synthetic-Git/bootstrap installation runners remain excluded.

Driver development failures are preserved: the initial Ruby inspection failed
before test bodies because Minitest.seed was unset; manual inspection then caught
two missing loop-generated Node names before execution. Two Ruby execution
attempts returned zero tests because a temporary driver override affected
inherited method enumeration. These are invalid verification results, **not
passes**. The final driver snapshots selections first and verifies actual names
and nonzero totals. Its final Ruby run passed below. No SDK source fix resulted.

## Fresh developer results

Complete stdout/stderr, commands, environments, seeds, versions, selection and
exit codes are in `developer-evidence.json`. Successful suites below have zero
failures/errors/skips; no original total was imported as a fresh result.

| Fresh check | Actual result | Counting boundary |
| --- | --- | --- |
| Ruby source | 199 tests / 7242 assertions | Final run only; both zero-run attempts invalid |
| Rails frontend | 23 passing TAP tests | Archive-install callback absent from executed names |
| JS source/React/server/package contracts | 59 passing TAP tests | npm-pack callback absent from executed names |
| Mounted request / accepted-response / authorization | 18/1080; 1/2852; 7/1872 tests/assertions | Direct child reruns overlap Ruby wrappers |
| Mounted subscription / history | 17/2008; 13/2948 | Overlap; subscription total is this log's 2008, not old 2006 |
| Views without / with Sprockets | 11/197; 11/199 | Overlap; seven child runs total 78/11156, not additional unique coverage |
| Rails browser | 32 passing TAP tests | 31 leaf cases: 12 lifecycle, 7 workflow, 12 style cells; one style parent |
| Rails normal asset build | Passed | Reproduced shipped 241154-byte asset |
| JS normal build, source typecheck, contract typecheck | All passed | Existing generate-release/tsup/tsc pipeline |
| Locked bundle check / release verification | Passed | Existing dependencies; 23 runtime files verified; no SDK install |
| Compatibility matrix structure | Four cells passed | Structural only; no legacy runtime/install execution |

Ruby 3.1.2p20; RubyGems 3.3.15; Bundler 2.3.7; Rails 7.2.3.2; Rack 3.2.7;
Sprockets 4.4.1; Minitest 5.27.0. Node 22.23.1; npm 10.9.8; TypeScript 5.9.3;
tsup 8.5.1; esbuild 0.25.8; Playwright 1.61.1; Chromium 149.0.7827.55;
Turbo 8.0.23; Turbolinks 5.2.0. Rails visual comparison fixes React/ReactDOM at
18.3.1; JS unit checks use 19.2.8. Browser setup downloaded the pinned Playwright
Chromium to a temporary cache through the existing documented setup command.
The configured managed service was stopped and was not used or restarted.

These use existing real Rails/CSRF/session harnesses and HTTP-boundary fixtures,
with no database harness or account provisioning. They do not prove durable
provider persistence, storage, deduplication, email or real consumer behavior.
Legacy runtimes, Firefox/WebKit, arbitrary host CSS/CSP, native BFCache and actual
consumer Ruby/lock combinations remain outside current evidence.

The retained public-HTTPS-Git install/precompile is **committed-base evidence**
for Rails `15cc5a3f299263e6a498613de34a84857ba9c3d4`, with matching lock SHA-256
`185e2a760e835e5ef72ba8f482418aa049af7e2a8d58de9b21eb7d727bbee7d9`, 26 package
entries and 2 tests/89 assertions as reviewed. Its original install log is
attached and preserved; the complete old lock and installer were separate earlier
artifacts, not attached here, so their hashes are attributed to the independent
review rather than freshly reverified. Installation was not repeated here. Neither
the prior nor this later uncommitted documentation patch was installed. Runtime
and shipped asset hashes remain identical, supporting reuse within that bound;
they do not turn the patch into a committed install revision. The source Gemfile's
PATH entry and prohibited archive-install success cannot replace that evidence.
Any future SDK install must use public HTTPS Git at its authorized full commit SHA,
matching lockfile and normal build pipeline; frozen revisions must not float.

## Preview comparisons

`browser-captures.json` retains all 48 original PNG byte streams for 24 pairs,
including all six previously missing cells, with SHA-256, dimensions and full
zero-based `(x,y)`/RGBA differences. The editable comparator uses Playwright's
bundled PNG decoder with exact RGBA equality and no tolerance. These are fresh
captures from the preserved disposable harness, not recreated historical images.

| Preview cell | Original differing pixels | Fresh differing pixels | Fresh difference location |
| --- | --- | --- | --- |
| 1280×720 light/provided | 2 | 16 | Right dialog top/bottom rounded border, x=1256–1266, y=19–20 and 700–710 |
| 1280×900 dark/absent | 13 | 0 | Identical fresh pair |
| 1280×900 light/absent | 17 | 2 | Right dialog top border, (1266,101), (1266,102) |
| 1280×900 light/provided | 2 | 0 | Identical fresh pair |
| 390×900 dark/absent | 1 | 0 | Identical fresh pair |
| 390×900 light/absent | 2 | 0 | Identical fresh pair |
| 390×900 dark/provided | 2 | 2 | Attachment top-border corners, (23,724), (366,724) |
| 1280×720 light/absent | 0 | 2 | Right dialog top border, (1266,19), (1266,20) |
| 1280×900 dark/provided | 0 | 13 | Right dialog bottom border, x=1258–1266, y=800–808 |

All 12 fresh form pairs and seven preview pairs are identical. Five previews
differ at 35 pixels total, maximum channel delta 9/255, alpha unchanged. Both
images of all nine table cells were inspected at native viewport dimensions.
Desktop fields, attached context, consent wrapping, thumbnail/actions and footer
remain aligned. Mobile preview is intentionally scrolled to the attachment;
upper context is outside the viewport, while consent, fields, attachment controls
and footer remain readable. No material visual mismatch was observed. Changes
are limited to rounded border rasterization in these captures; the variation
between old and fresh counts is consistent with rasterization variability but
does not establish exact coordinates for unavailable historical PNGs.

Preserve the independent review's mobile finding: its original Rails pixel was
`[52,63,80,255]` versus JS `[53,63,80,255]` at (23,724) and (366,724), with **no
material visual impact**. The fresh pair has those values reversed. This is not
pixel identity, and neither finding justifies changing runtime CSS. The original
counts remain intact and independent review of revised evidence remains pending.

## Four criteria and checkpoint

The exact four saved criteria and complete source-linked matrix remain in
[rails-parity.md](rails-parity.md); none was removed, replaced or weakened.

| Saved criterion | Preserved independent finding | Developer correction and remaining gate |
| --- | --- | --- |
| `sdk_parity_coverage` | PASS — source coverage | Exact matrix, language differences and passing source findings retained |
| `sdk_behavior_and_package` | FAIL — evidence acceptance | R1 documentation corrected; permitted developer runs pass; R2 remains |
| `sdk_browser_parity` | UNVERIFIED overall | Missing fresh comparisons now retained; original mobile finding preserved; R2 remains |
| `readiness_and_consumer_handoff` | FAIL — checkpoint readiness | Corrections available for review; independent acceptance, owner notification/direction pending |

**R2 — blocking independent reproduction capability.** The review worker's shell
contract prohibited fixture/output/state writes. Its supported
`handrail_run_read_only_tests` inspection rejected actual JS reporter/server/React
paths with `Select 1–20 explicit scripts/test-*.mjs files.` No compatible candidate
hash, run/request key or saved test receipt was returned. The full attached review
preserves this exact failed-tool evidence. The separately named raw
`tool-inspection.json` was not supplied to this correction; its contents/hash are
not invented. These developer checks do not resolve R2 and no independent runner
was retried. Resolve the named contract mismatch through existing authorized
controls before another independent test attempt. Do not bypass read-only
restrictions, create replacement platform infrastructure, a managed service, QA
campaign or HTTPS fixture to declare this fixed.

Preserve the seven saved stages exactly: (1) `sdk_parity` — SDK parity/readiness
work; (2) `sdk_review` — independent SDK review; (3) `owner_trial_direction` —
owner notification plus explicit owner direction for Monuvision; (4)
`monuvision_integration` — authorized admin-only Monuvision integration; (5)
`monuvision_trial` — successful Monuvision trial verification; (6)
`bluecotton_integration` — authorized admin-only BlueCotton.com integration,
conditional on successful Monuvision verification; (7) `bluecotton_review` —
independent BlueCotton reporting, placement and admin-access verification,
followed by final owner presentation.
One persistent task keeps coordination, final owner presentation and owner decisions. Both
integrations remain restricted to admin screens and admin users, with host
authorization on every SDK route, not just hidden controls. Resolve consumer
project mappings/permissions through existing plan/setup controls. No consumer
change, notification, publication, deployment, database or queue-state mutation
occurred. A needed release requires a separate exact candidate/environment and
existing authorized CI/CD deployment step.

Reproduce using [test/README.md](../test/README.md#current-sdk_parity-checks-2026-09-13)
and the retained editable scripts. Verify artifact hashes first; extract the
original captures and rerun `compare-images.cjs` for exact coordinates. The final
inventory, revised full patch, original patch, complete evidence, setup inspection
and source instructions are ordinary task artifacts. Staging or worker success
alone does not establish server retention or task acceptance.
