# Mounted owned-history forwarding

The existing factory and mount configuration in `forwarding.md` also exposes:

| Mount-relative request | Configured upstream resource |
| --- | --- |
| `GET /mine` | `endpoints[:history]` |
| `GET /bugs/:bug_id` | `endpoints[:bugs]/:bug_id` |
| `PUT /bugs/:bug_id/archive` | `endpoints[:bugs]/:bug_id/archive` |
| `DELETE /bugs/:bug_id/archive` | `endpoints[:bugs]/:bug_id/archive` |
| `POST /mine/archive-closed` | `endpoints[:history]/archive-closed` |

Every request binds `project_id` and `environment` from configuration. Only
`GET /mine` forwards `limit`, `cursor`, `search`, `status_group`, `sort`, and
`visibility`. Flat query parsing retains the first value for each key, forwards
it only if nonempty, and does not trim values. Thus `cursor=&cursor=later`
forwards no cursor, while `search=+` forwards one space, matching the JS adapter.
Nested parameters and all other query keys are ignored.

The engine guard decodes the escaped path segment once, before Rails route
parameter/format handling, and encodes it for the upstream URL. Dots inside an ID,
Unicode, spaces, and literal plus signs survive. Empty IDs, malformed escapes,
invalid UTF-8, dot segments, and decoded slash, backslash, percent, query/fragment
delimiters, or control bytes are rejected. Repeated slashes are rejected using
Rails' original path, so host route normalization cannot turn `/bugs//archive`
into lookup of a bug named `archive`. No IDs become upstream path traversal.

All archive operations send no upstream body or Content-Type. Archive-closed
requires no report JSON input. The existing intake byte limit and JSON validation
remain restricted to report submission. Mount normally without host middleware
that pre-parses report JSON; host Rack middleware can process form bodies before
the engine receives them.

Archive writes require a Rails session and a valid `X-CSRF-Token`, including when
the host disables forgery protection. Query/body authenticity tokens cannot
replace the header. The same-origin guard and `private, no-store` responses apply
to reads, writes, and failures. Only the host resolver supplies request identity,
using `factory.for_request(request)` and a fresh resolver call on every retry.

Success JSON is validated and forwarded byte-for-byte to the browser, without
Ruby domain parsing or reserialization of versioned status, summary, or journey
fields. History ownership errors preserve upstream 401/403 and use the JS
forwarding contract `{"error":"bug_reporting_rejected"}`. Upstream diagnostics,
credentials, cookies, and response headers are not relayed. Other upstream
failures retain the existing generic 502 behavior. Public Client and Transport
behavior is unchanged; neither file was edited.

## Verification, 2026-09-09

Runtime: Ruby 3.1.2, Rails 7.2.3.2, Rack 3.2.7, Bundler 2.3.7. Ruby >=2.3 and
Rails >=4.2 bounds remain provisional; no legacy runtime matrix was exercised.
The existing lockfile's gems were installed in the run's temporary directory
using the libyaml-source setup documented in `forwarding.md` (two install jobs).
Sibling additions of sprockets/sprockets-rails were installed from their updated
lockfile as well. No dependency declarations were changed by this history task.

```sh
export BUNDLE_PATH=/opt/handrail/.handrail/codex-runs/8b8fcad9-774e-48fb-a09d-dce013bb26ab/tmp/gems
export TMPDIR=/opt/handrail/.handrail/codex-runs/8b8fcad9-774e-48fb-a09d-dce013bb26ab/tmp
RAILS_ENV=test RACK_ENV=test bundle3.1 exec ruby -Ilib -Itest test/fixtures/mounted/history_checks.rb
RAILS_ENV=test RACK_ENV=test bundle3.1 exec ruby -Ilib -Itest test/fixtures/mounted/request_checks.rb
bundle3.1 exec ruby -Ilib -Itest -e 'require "./test/history_routes_test"; require "./test/forwarding_test"; require "./test/forwarding_package_test"'
bundle3.1 exec ruby -Ilib -Itest -rsupport/no_network test/transport_test.rb
git diff --check
```

- Mounted history: 13 tests, 2,961 assertions, zero failures/errors.
- Existing mounted intake/policy: 17 tests, 1,090 assertions, zero failures/errors.
- History/forwarding/extracted-package wrappers: 3 tests, 10 assertions, zero
  failures/errors. The package fixture now checks packaged history reads and
  mandatory archive CSRF as well as existing policy forwarding.
- Transport regression: 19 tests, 492 assertions, zero failures/errors.
- Scoped Ruby syntax checks and whitespace checks: passed.

Fixtures use real Rails routing, signed cookie sessions and CSRF handling, with
stubbed HTTP at the existing transport boundary and the existing no-network
guards. There is no database or persistence behavior in this task.

The first boot encountered an in-progress sibling helper initializer NameError.
It was recorded on helper item `ffb3e9b2-a246-4ec3-822f-678586336841`; the sibling
fixed helper loading, and final checks passed without any preload or workaround.
The existing gemspec missing-license warning remains unrelated to this change.

Shared route/guard/service/controller overlap was recorded on subscription item
`213706e4-54b3-4cec-8225-01549337e8ff` while it was planned. That item should extend
this foundation and retain the archive body/CSRF and ID rules. Subscription work
was not implemented here. All existing uncommitted foundation and sibling work
was preserved; no commit, push, PR, release, deployment, or live API call occurred.
