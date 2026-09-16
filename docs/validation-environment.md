# Disposable SDK validation environment

This supplements, and does not replace, [the compatibility plan and historical
results](rails-8.1-compatibility.md), [readiness handoff](readiness-handoff.md),
and [evidence corrections](evidence-corrections.md). Work request
`538069e0-d4aa-4f6c-914e-438c5297a65a` prepares reproduction of independent
validation `6444b0fe-1753-4406-9a47-a1a979d90148`. No independent acceptance or
consumer acceptance is conferred by these SDK runs.

## Source and execution route

The registered checkouts were clean at inspection, with no pending Git operation:

| Repository | Frozen commit |
| --- | --- |
| Rails, `c1f315e5-c3ee-4734-8473-b802fd4f596e` | `6fe35a72a689aebb3e5f627f1e56deda0a7f590e` |
| JS reference, `cd564712-6496-4195-9b96-e40af54e33c3` | `7dfb33f548448f864cf957f19d96f8b5a27bc787` |

No initial source drift was present. The deferred workspace synchronization did
not require a reset, stash or repair. The Rails public `main` also matched the
frozen commit when inspected. Reproduction always selects the full frozen SHA,
regardless of later branch movement. The only proposed changes from this work
are test preparation and evidence/documentation; production SDK bytes are intact.

The attached frozen receipt records `/usr/bin/ruby` 3.1.2 rejecting the 3.4.5
Gemfile with exit 18. Its identity-only Rails Git export contains one commit
object, with no tree. The supplied assignment reports the earlier regression as
226 tests / 7,633 assertions with nine failures: three missing CA files and six
clone failures. `regressionInspect.json` is an **inspection**, not that regression
execution log. These are observed executor gaps, not evidence of canonical Git
corruption or SDK defects.

The current broker interface allows command selection and selected Git objects,
but offers no runtime-prefix or trusted-CA mount selection. This preparation uses
the authorized ordinary writable worker route. It does not modify the broker,
platform configuration, databases, queue state, or registered Git history.
Handrail MCP appeared after initial discovery; current scope and all three saved
instruction sources were read. There were no attached memory publications.

## Portable reproduction

Use an ordinary Linux x86_64 worker with system Ruby **3.1.2**, Bundler **2.3.7**
(`bundle3.1`), Git, curl, tar, make, a C/C++ compiler, Ruby development headers,
Node/npm (this run: see receipts), and a trusted PEM CA bundle. Network access to
public HTTPS GitHub, RubyGems, npm and pyyaml.org is needed during preparation.
Do not disable certificate verification. If the trusted bundle is not at
`/etc/ssl/certs/ca-certificates.crt`, set `SSL_CERT_FILE` to the worker's trusted
bundle. The driver copies it into its task directory and propagates it to Ruby,
Bundler, Git and curl, including nested bootstrap/package checks.

From a checkout containing this preparation script (or its saved identical
editable source), outside `bundle exec`:

```sh
# Set this to a new writable directory outside any SDK checkout, without spaces.
validation_work="$(mktemp -d "${TMPDIR:-/tmp}/sdk-validation.XXXXXX")"
ruby test/compatibility/reproduce_validation.rb "$validation_work" target
ruby test/compatibility/reproduce_validation.rb "$validation_work" existing
ruby test/compatibility/reproduce_validation.rb "$validation_work" json
```

Run phases sequentially. Each command's argv, working directory, timestamps,
exit status/signal, log hash and parsed Minitest totals are in `receipts/` under
the chosen directory. Failed preparation stops its phase; failed test selections
are retained and other independent selections continue. A phase with failures
returns nonzero. Existing phase receipts cannot be silently overwritten. Retain
failed receipts before retrying; use a fresh directory for a complete rerun.
The directory lock prevents simultaneous phases. Native builds use two jobs.
No private path from the producing worker is needed for reproduction.

The `target` phase clones both public repositories with complete objects, checks
out the frozen SHAs, runs full `git fsck`, enumerates the actual trees and verifies
a second bare clone suitable for package tests. It invokes the unchanged
checksum-verified `prepare_ruby_3_4.rb`, installs the original frozen target lock,
and checks Ruby/Bundler/Rails/Rack/JSON versions plus loaded gem paths before
tests. It runs normal `npm run setup`, the complete Rake suite, five direct mounted
checks, release verification, and `test/compatibility/run.rb rails_8_1`.

The `existing` phase builds checksum-pinned libyaml **0.2.5** privately, installs
the unchanged root frozen lock under system Ruby 3.1.2/Bundler 2.3.7, probes
Rails **7.2.3.2** and Rack **3.2.7**, then runs the complete suite and the package
contract selection directly. It does not replace system libraries or gems.

The `json` phase creates another disposable clone. Only its target JSON pin and
lock entries change from **2.9.1** to **2.21.1**; every other dependency remains
pinned. Appraisals reads the variant matrix through its existing code. The
variant's frozen bundle, runtime probe and exact matrix check precede the
unchanged installed-package/precompile/session-CSRF smoke. The canonical
`rails_8_1` matrix and lock stay at JSON 2.9.1. The variant is explicitly
**SDK-only**, not a new consumer appraisal or proof of the consumer's full closure.

The established smoke runner replaces the SDK path dependency with a synthetic
full-SHA Git package snapshot inside a disposable bare clone. It verifies all 46
non-SDK dependency versions, installs the package, removes executables from PATH,
blocks outbound networking during actual Sprockets precompilation and requests,
and checks real cookie sessions, valid CSRF forwarding and invalid CSRF rejection.
The temporary Git source and synthetic revision are test fixtures only, never
consumer installation instructions. The HTTP boundary is scripted; Rails routing,
controllers, helpers, sessions and asset compilation are real. No datastore or
database substitute is used.

## Evidence and remaining gates

Fresh ordinary-worker results on 2026-09-16 (all commands exited 0):

| Selection | Tests / assertions | Failures / errors / skips |
| --- | --- | --- |
| Target Ruby 3.4.5, full suite, JSON 2.9.1 | 226 / 8,406 | 0 / 0 / 0 |
| Target mounted request | 18 / 1,080 | 0 / 0 / 0 |
| Target mounted authorization | 7 / 1,872 | 0 / 0 / 0 |
| Target mounted history | 13 / 2,948 | 0 / 0 / 0 |
| Target mounted subscription | 17 / 2,006 | 0 / 0 / 0 |
| Target mounted accepted response | 1 / 2,852 | 0 / 0 / 0 |
| Target installed package/precompile/session-CSRF, JSON 2.9.1 | 1 / 77 | 0 / 0 / 0 |
| Existing Ruby 3.1.2 / Rails 7.2.3.2 full suite | 226 / 8,406 | 0 / 0 / 0 |
| Existing runtime package contracts (overlaps full suite) | 21 / 1,065 | 0 / 0 / 0 |
| Separate SDK-only installed package/precompile/session-CSRF, JSON 2.21.1 | 1 / 77 | 0 / 0 / 0 |

Both smoke runs verified 26 installed package snapshot entries, actual Sprockets
precompilation, valid session/CSRF forwarding (201, one boundary call) and invalid
CSRF rejection (403, no additional call). The normal `npm run setup` (Node
22.23.1/npm 10.9.8) and release verifier passed. The unchanged 241,154-byte asset
has SHA-256 `2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`.
The verifier preserved the existing source-snapshot manifest (Ruby gem version
0.4.49, base commit `da2327dc67796a56595286400779bb4b91d5a079`); this is not a
new release seal. The tested source identity is the full frozen commit above.

The original target lock SHA-256 is
`9a93b9f808113642c41a938722be557f666a29746b01c7d6c2e6ca083f8ddbfc`;
the root regression lock is
`00a62427471478375fb83c4c22deb669ec4cc2102b6b4e587441a5ec15ab253d`.
Both stayed byte-identical. The supplemental JSON lock is retained at
`test/compatibility/evidence/validation_6444b0fe/json-2.21.1.gemfile.lock`.
It is a fixture lock to copy over `gemfiles/rails_8_1.gemfile.lock` only in the
disposable variant alongside its changed pin; it is not a standalone Gemfile or
consumer lock. Its only differences from the original are the two JSON entries.

The saved handoff contains exact commands, logs, locks, source/runtime provenance,
and a SHA-256 index. Paths in original receipts identify the producing execution;
use the commands above to create fresh paths. Generated smoke host locks contain
local fixture URLs intentionally; use the retained baseline/variant source locks
for reproduction, not those host URLs as consumer dependencies.

Historical independent source reconciliation, four inspected PNGs, 24 frontend
tests, 32 browser tests, mounted security/forwarding checks, normal asset build
and release checksums remain credited only within their recorded source/runtime
limits. This work does not repeat unchanged browser evidence or claim fresh PNG
inspection. The original images are not attached to this request. Direct mounted
and package counts overlap their parent full-suite counts and must not be added.

The planner inspected the full Monuvision `Gemfile.lock` from repository
`864e877e-9cf6-41f5-b3d7-8e9ee270d433` at commit
`88a9a81e64640f5f6365948c0dea00a2df084bdf`; its working-file bytes exactly
matched that commit's Git blob. The planner supplied SHA-256
`852e7a5dddde0aa8e55d3732288a1c4793b14d609bd085462a1c24a741c99b1c`
and exact entries `json (2.21.1)`, `rails (8.1.3)`, `railties (8.1.3)`,
`rack (3.2.6)`, `RUBY VERSION ruby 3.4.5p51` and `BUNDLED WITH 2.6.9`.
This is **planner source inspection**, not independent inspection of consumer
lock bytes by this SDK worker. It supersedes the earlier missing-attribution
statement. The separate JSON 2.21.1 smoke remains SDK-only: neither this source
attribution nor the smoke proves compatibility with the consumer's entire
dependency closure. Neither consumer was changed or downgraded.

Independent review must recheck the prepared SDK evidence before dependent
installation. Preserve SDK readiness → owner notification and explicit trial
direction (saved: Monuvision development) → successful Monuvision verification →
conditional BlueCotton adoption. Both applications require authenticated-admin
route authorization and admin-screen placement; launcher visibility is not
authorization. Consumer installs use public HTTPS Git at the final full reviewed
commit SHA, matching package-manager locks and the ordinary install/build path.
No deployment, publishing, consumer modification, workflow acceptance or broader
runtime support claim is part of this preparation.
