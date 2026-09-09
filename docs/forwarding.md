# Opt-in Rails intake and policy forwarding

The engine supports `POST /` and `GET /policy` within an explicit host mount.
Requiring the gem does not mount it or add middleware to the host stack. Configure
one immutable factory at host boot, using server-owned settings:

```ruby
# Host initializer, after requiring "handrail/bug_reporter"
configuration = Handrail::BugReporter::Configuration.new(
  :api_base_url => ENV.fetch("HANDRAIL_BUG_REPORTER_API_URL"),
  :project_id => ENV.fetch("HANDRAIL_BUG_REPORTER_PROJECT_ID"),
  :environment => Rails.env,
  :report_token => ENV.fetch("HANDRAIL_BUG_REPORTER_TOKEN")
)

Rails.application.config.handrail_bug_reporter_factory = Handrail::BugReporter::Factory.new(
  configuration,
  :resolve_application_session_token => lambda do |request|
    # Replace this application-specific example with your existing authenticated
    # principal lookup. Only the host's authentication layer may set this value.
    principal = request.env["my_app.authenticated_principal"]
    principal && principal.handrail_application_session_token
  end
)

# Host config/routes.rb
mount Handrail::BugReporter::Engine => "/api/mobile-bug-reports"
```

The resolver must use authenticated host context, never a caller's Authorization,
report-token, session-token header, arbitrary cookie, or JSON field. It receives
the current Rails request on each transport attempt. No resolver means no upstream
application-session credential. Configure `environment` to the host's actual
Handrail environment binding when that differs from `Rails.env`. The factory also
accepts the existing transport options, including `:http` for an HTTP boundary.

Submissions require `Content-Type: application/json`, the host's normal Rails
session cookie, and `X-CSRF-Token` containing a Rails-generated authenticity token
(for example, the token exposed by the host's `csrf_meta_tags`). Verification uses
Rails' exception strategy and remains mandatory even if the host disables its own
forgery checks. The SDK does not change the session store, expose session cookies
to JavaScript, or create a sign-in flow. A host without a usable Rails session
cannot submit. Browser adapter and helper integration are separate tasks.

The engine-local request guard rejects a mismatched Origin or cross-site fetch
metadata for both routes. An absent Origin still requires a valid CSRF token for
POST. It checks declared length and reads at most 28 MiB plus one byte in bounded
chunks, independent of missing, zero, or understated Content-Length. It parses
UTF-8 JSON objects before controller instrumentation and stores them separately
from Rails parameters; request/query parameters are not parsed again or forwarded.
Hosts should mount normally, without middleware or routing constraints that
pre-parse the report body before dispatching to the engine.

The forwarding service accepts already-normalized browser wire objects. It uses
the shared recursive redactor without invoking the Ruby payload builder or
operation-specific Client methods. It preserves browser identity, event ID,
attachments, legitimate fields, and intentional top-level `profile_key`; removes
authentication/session fields and every `automation_requests` field recursively;
and replaces project/environment with configuration. Notification consent requires
literal `true`, with a trimmed consent version or `v1`; this path never initiates a
second subscription. Policy query parameters come exclusively from configuration.
The existing transport owns retries and reuses one frozen serialized body while
resolving fresh session credentials for each attempt.

Responses use `private, no-store`. Unsupported routes/methods, invalid input,
cross-site/CSRF failures, missing configuration, and upstream failures return
generic JSON errors; Rails suppresses the body for HEAD as required by HTTP.
Upstream errors become 502, disabled configuration becomes 404, and missing or
invalid configuration becomes 503. Upstream response headers, cookies, and
authentication are not relayed. History and subscription child routes are not
implemented by this item.

## Focused verification — 2026-09-09

Initial checkout: `main`, `f78ed1554410f4ea5e272357029a37a8488a21aa`, with
`.gitignore` modified and foundational files untracked. That sibling work was
preserved. No Client operation, configuration, transport, or payload implementation
was edited. No commit, push, PR, tag, deployment, or real upstream request occurred.

Verified environment: Ruby `3.1.2p20`, Bundler `2.3.7`, railties/actionpack/actionview/
activesupport `7.2.3.2`, Rack `3.2.7`, Minitest `5.27.0`, Rake `13.4.2`, Psych
`5.5.0`. Ruby >=2.3 and Rails >=4.2,<8 remain provisional bounds. Legacy combinations
and Bluecotton/Monuvision versions were not tested or inferred.

The existing lockfile's gems were absent in this fresh run. Dependencies were
installed into this run's temporary directory, using the scaffold's documented
libyaml-source build setup, without changing dependency requirements:

```sh
export forwarding_tmp=/opt/handrail/.handrail/codex-runs/06f2057d-e8fc-4ad6-8189-3dc2302a1e28/tmp
export BUNDLE_USER_HOME="$forwarding_tmp/bundler"
export BUNDLE_APP_CONFIG="$forwarding_tmp/bundle-config"
export BUNDLE_PATH="$forwarding_tmp/gems"
curl --fail --location --silent --show-error https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz --output "$forwarding_tmp/yaml-0.2.5.tar.gz"
tar -xzf "$forwarding_tmp/yaml-0.2.5.tar.gz" -C "$forwarding_tmp"
export BUNDLE_BUILD__PSYCH="--with-libyaml-source-dir=$forwarding_tmp/yaml-0.2.5"
bundle3.1 install --jobs 2 --retry 2

RAILS_ENV=test RACK_ENV=test bundle3.1 exec ruby -Ilib -Itest test/fixtures/mounted/request_checks.rb
bundle3.1 exec ruby -Ilib -Itest -e 'require "./test/scaffold_test"; require "./test/forwarding_package_test"; require "./test/forwarding_test"'
bundle3.1 exec ruby -Ilib -Itest -e 'require "./test/transport_test"; require "./test/payload_test"'
ruby -e 'paths = %w[lib/handrail/bug_reporter/engine.rb lib/handrail/bug_reporter/forwarding.rb lib/handrail/bug_reporter/forwarding_guard.rb config/routes.rb app/controllers/handrail/bug_reporter/reports_controller.rb handrail-bug-reporter.gemspec test/scaffold_test.rb test/forwarding_test.rb test/forwarding_package_test.rb test/fixtures/mounted/config/application.rb test/fixtures/mounted/config/routes.rb test/fixtures/mounted/request_checks.rb]; paths.each { |path| abort path unless system(RbConfig.ruby, "-c", path) }'
git diff --check
```

Results:

- Dependency installation: passed, 47 gems.
- Mounted request fixture: **17 tests, 1,120 assertions, zero failures/errors**.
  Covers submission/policy, server binding and ignored caller credentials,
  preserved identity/event/profile, nested redaction/automation removal, valid and
  missing/invalid/session-mismatched CSRF, cross-site reads/writes, declared and
  actual byte bounds, exact-limit multibyte acceptance, absent/understated lengths,
  malformed/nonobject JSON, unsupported methods/routes, retry credential freshness
  and identical frozen body, consent without subscription side effects, generic
  HTTP/network/boundary failures, response privacy, and HttpOnly host cookies.
- Scaffold/request/package wrappers: **6 tests, 20 assertions, zero failures/errors**.
  Request fixtures execute in a fresh Rails process. The package check builds and
  extracts the actual gem, boots the extracted engine, verifies an unconfigured
  mount and fake-boundary policy forwarding. Scaffold checks compare the unmounted
  host's routes, middleware, health response, and intake 404 against a no-gem host.
- Existing transport/payload checks: **78 tests, 770 assertions, zero failures/errors**.
- Syntax checks for all 12 touched Ruby/gemspec files and `git diff --check`: passed.

Mounted/scaffold/package processes use the existing no-network guard, including
its at-exit assertion. The sole service fake is the injected HTTP boundary; Rails
controllers, routing, cookie sessions, and authenticity verification are real.
No database or persistence behavior is under test. Validation stayed scoped to
this item while sibling writers could be active.

During development, fixture expectations were corrected for Rails' HEAD body
suppression and root-route representation; the extracted-package fixture caught
an unset configuration accessor, which was fixed to fail closed with 503. Final
checks are green. No unrelated test failures were observed in the scoped checks.
Gem build retains the pre-existing missing-license warning; no license was invented.
