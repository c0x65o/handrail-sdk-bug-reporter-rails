# handrail-sdk-bug-reporter-rails

Rails engine, request-scoped Ruby client and packaged Handrail bug reporter UI.
The browser uses the JS reporter through protected, same-origin Rails routes;
the host keeps upstream credentials on the server. See [capability evidence](#capability-evidence)
and [compatibility smoke coverage](#compatibility-smoke-coverage) for verified scope.

## Installation and release identity

Public HTTPS Bundler Git **tag syntax template only — not currently installable**:
replace `<VERIFIED_RAILS_RELEASE_TAG>` only after verifying an actual matching
Rails distribution tag, gem version and package provenance.

```ruby
# Gemfile — placeholder, not an existing release recommendation
gem 'handrail-bug-reporter',
    git: 'https://github.com/c0x65o/handrail-sdk-bug-reporter-rails.git',
    tag: '<VERIFIED_RAILS_RELEASE_TAG>',
    require: 'handrail/bug_reporter'
```

For Handrail-owned application installations, dependency policy requires the
public HTTPS repository pinned by **full commit SHA**, with a matching lockfile.
Use `ref: '<VERIFIED_FULL_40_CHARACTER_RAILS_COMMIT_SHA>'` in place of `tag:`;
that value is also a placeholder, not an installable revision. Resolve and verify
the intended committed SDK revision when an installation is owner-directed.

After selecting a real revision, run the host's normal `bundle install`.
`Gemfile.lock` records the Git source's resolved `revision` SHA, even when the
Gemfile uses a tag. Retain and review that lockfile with the Gemfile; subsequent
installs use its revision until an intentional dependency update. A tag name
alone is not immutable release evidence.

The current [release manifest](release-manifest.json) records Rails gem version
**0.4.49** with `source_snapshot` provenance and null Rails release `commit`/`ref`.
Its base commit is not a release of the current working-tree implementation.
The local `v0.4.50` tag's `version.rb` declares **0.4.49**; it is not a verified
matching release and is not recommended here. The gem version is independent of
the bundled **JS v0.4.50**, `refs/tags/v0.4.50`, at
`7dfb33f548448f864cf957f19d96f8b5a27bc787` in the JS repository.

The original parity baseline was **JS v0.4.49**, `refs/tags/v0.4.49`, at
`96b293248611594c388d0fab3af63b1b2d1aae5c`, recorded in `frontend/upstream.json`
at Rails commit `a6f83605c217f37ac0caa4afa982379206f6288f`. The
[historical payload proof](docs/payload.md#fixed-js-v0449-fixtures) still compares
Ruby normalization with that fixed JS server-entry baseline; it does not verify
the current browser bundle. Rails commit `bb1a4f86bb48f63e5a2ade43a1565c4625c58334`
upgraded the bundle to JS v0.4.50. The [current release manifest](release-manifest.json)
and [upstream identity](frontend/upstream.json) record that current mapping.

See the [release contract](docs/release-contract.md) for checksum, source and
distribution-tag verification. Real Rails release tagging and installation into
Bluecotton or Monuvision are later owner-directed operations.

## Generate server configuration and mount

Once the gem is installed:

```sh
bin/rails generate handrail:bug_reporter:install
```

This creates `config/initializers/handrail_bug_reporter.rb`, preserving an existing
initializer even with `--force`. Review the
[initializer template](lib/generators/handrail/bug_reporter/templates/initializer.rb.tt)
and [generated instructions](lib/generators/handrail/bug_reporter/templates/instructions.txt).
Set these values in the **host server environment before boot**:

| Variable | Purpose |
| --- | --- |
| `HANDRAIL_API_URL` | Upstream Handrail HTTP(S) API base URL, without embedded credentials. |
| `HANDRAIL_PROJECT_ID` | Handrail project binding. |
| `HANDRAIL_BUG_REPORT_TOKEN` | Server report credential; never expose it in a view, asset or browser config. |

The initializer explicitly maps `development`, `test`, `staging` and `production`
Rails environments to the corresponding Handrail environment strings. Review
each binding and add explicit mappings for custom environments. An unmapped
environment or missing required value leaves forwarding misconfigured (503)
without preventing host boot; there is no fallback to production.

It stores a `Handrail::BugReporter::Factory` at
`Rails.application.config.handrail_bug_reporter_factory`. Its
`resolve_application_session_token` callback defaults to `nil` for anonymous
reporting, subject to upstream policy. For Known User reporting, replace that
callback with the host's trusted authentication lookup returning the current
Handrail application-session token, or `nil` when signed out. The template's
principal lookup is an application integration example, not an SDK-provided
authentication API. Resolution is request-local and repeated for each transport
attempt. Never derive this token from an email/user ID or trust browser headers,
JSON, parameters or arbitrary cookies as identity. Normal authenticated host
sessions may identify the principal on the server; the application-session token
and report token remain server-only. History ownership and notification
eligibility are enforced upstream; anonymous reporting does not grant them.

Engine mounting is opt-in:

```sh
bin/rails generate handrail:bug_reporter:install --mount
```

The generator adds this route only when no existing reporter route reference is
found. Alternatively, add it deliberately to the host's `config/routes.rb`:

```ruby
mount Handrail::BugReporter::Engine => "/handrail/api/mobile-bug-reports",
  :as => "handrail_bug_reporter"
```

Custom mounts must be local paths ending in `/api/mobile-bug-reports`; use their
own path helpers, including any host subdirectory prefix. The browser endpoint
is this local mount, never `HANDRAIL_API_URL`. The engine exposes POST intake,
GET policy, owned history/detail, subscription and archive routes; see
[forwarding](docs/forwarding.md), [history routes](docs/history-forwarding.md)
and the [route definitions](config/routes.rb).

## Place the browser reporter

The generator does not edit layouts or insert launchers. Deliberately place
`<%= csrf_meta_tags %>` in the host layout's `<head>`, keep Rails CSRF protection
enabled, and retain the host's normal session cookies (including for anonymous
visitors). Place the helper once in the chosen view/layout:

```erb
<%= handrail_bug_reporter(
  :endpoint => handrail_bug_reporter_path,
  :context => { :route => request.path, :app_version => "1.2.3" },
  :allow_screenshots => true,
  :show_history => true,
  :appearance => {
    :theme_mode => :auto,
    :tokens => { :accent => "#4f46e5" },
    :style => { "--handrail-bug-radius" => "12px" }
  }
) %>
```

The version and context above are example public application data; supply your
own or omit them. Helper context accepts symbol keys with string values:
`route`, `app_version`, `build_number`, `commit_sha`, `app_flavor`, `title`,
`description`, `reproducer`, `profile_key`. It does not serialize a request,
session or user. With no supplied route, the browser adapter uses only
`location.pathname`, excluding query and fragment. Other context is not collected
automatically. Project/environment come from the server factory's public binding;
credentials and callbacks are never helper options.

Helper options also include `enabled`, `label`, `heading`, `load_policy_on_mount`
(default true) and `history_page_size` (1–50). `show_history` defaults to true;
`allow_screenshots` defaults to false. `appearance` accepts `theme_mode`
(`auto`, `light`, `dark`), `class_name`, string-valued `tokens`, and `style` limited
to supported `--handrail-bug-*` variables with string/finite numeric values.
Tokens cover accent/text, surfaces, borders, overlay, status colors, radius and
font family; the exact allowlist and validation are in the
[helper API](docs/view_helper.md#host-api). Styling applies to the reporter.

To reuse an existing host button, use this **instead of** the default launcher:

```erb
<button id="host-bug-button" type="button">Help</button>
<%= handrail_bug_reporter(
  :endpoint => handrail_bug_reporter_path,
  :mode => "custom-launcher", :launcher_id => "host-bug-button"
) %>
```

The adapter preserves the host button and adds no second launcher. The helper
emits an empty marker and deferred external `handrail_bug_reporter.js` asset tag,
with no inline script. Sprockets hosts use the engine's precompile registration
and the host's normal asset build. Without an asset pipeline, serve the
[packaged asset](app/assets/javascripts/handrail_bug_reporter.js) at the URL resolved
by `javascript_include_tag`. No importmap or Webpacker migration is required.

Screenshots require explicit opt-in (`allow_screenshots: true` for the helper,
`allowScreenshots: true` for browser config). Attachments are one PNG or JPEG,
up to 20 MiB. For previews, allow `data:` and `blob:` in CSP `img-src`, for example
`img-src 'self' data: blob:`. Also allow the served asset and local connection
origin. The [workflow fixture's CSP](test/fixtures/workflow/config/application.rb)
uses `script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'`
alongside that image directive: the bundled UI uses inline styling, so a stricter
host style policy needs validation. The [style fixture](test/browser/reporter_style.md)
records successful blob preview decoding under this image policy.

### Manual and headless browser use

Load the asset with `<%= javascript_include_tag "handrail_bug_reporter", :defer => true %>`
and execute host JavaScript after it and the DOM are ready. These examples use
the actual [bundle exports](frontend/entry.jsx) and
[Rails CSRF wrapper](frontend/rails_adapter.js). Replace `your-project-id` and
the environment with the same public binding as the server initializer.
Keep the layout's CSRF metadata and session cookies; the wrapper reads the current
meta token on each same-origin write, including retries, without reading cookies
or patching global fetch.

```js
const config = {
  transport: 'same-origin',
  apiBaseUrl: '/handrail/api/mobile-bug-reports',
  projectId: 'your-project-id',
  environment: 'development',
  allowScreenshots: false,
  fetch: HandrailBugReporter.createCsrfFetch(window.fetch.bind(window))
};
```

For a manual UI, render `<div id="manual-reporter"></div>` and the existing
`host-bug-button` button, without a helper marker on this mount:

```js
const element = document.getElementById('manual-reporter');
const handle = HandrailBugReporter.mount(element, {
  config,
  launcher: document.getElementById('host-bug-button'),
  initialForm: { route: '/checkout', appVersion: '1.2.3' },
  showHistory: true,
  appearance: { themeMode: 'light', tokens: { accent: '#4f46e5' } }
});
// Later, during host presentation updates:
handle.update({ heading: 'Report a problem' });
// On removal/navigation, the host must call handle.unmount().
```

Omit `launcher` for the bundled button. `HandrailBugReporter.update(element, patch)`
and `HandrailBugReporter.unmount(element)` are also exported. Manual roots are
caller-owned. Helper roots instead receive automatic navigation/cache cleanup;
`HandrailBugReporter.rails.refresh()`, `.teardown()` and `.start()` manage their
adapter lifecycle. See [browser adapter behavior](docs/browser_adapter.md).

For a headless submission, reuse `config` without mounting a UI. Call this from
the host's deliberate report action; handle the returned promise/result there:

```js
const reporter = HandrailBugReporter.createBugReporter(config);
async function submitCheckoutBug() {
  return reporter.submit({
    title: 'Checkout fails',
    description: 'Clicking Pay shows an error.',
    impact: 'high',
    route: '/checkout'
  });
}
```

## Report from Ruby

Inside a host request, use the generated factory with the current `request`:

```ruby
factory = Rails.application.config.handrail_bug_reporter_factory
client = factory.for_request(request)
result = client.submit({
  :title => "Checkout fails",
  :description => "Clicking Pay shows an error.",
  :impact => "high",
  :route => "/checkout",
  :metadata => { :cart_size => 2 }
})
result.submitted? # true on accepted submission; false when disabled
result.bug_id     # canonical upstream bug_id, or nil when absent
```

`Client#submit(input, redaction_hooks: [], allow_screenshots: false)` accepts a
hash with string/symbol keys and requires nonblank title/description. Configuration
owns project/environment. The immutable result exposes `status` (`:submitted` or
`:disabled`), `status_code`, `bug_id`, parsed `response`, `notification_subscription`
and `notification_warning`. Invalid input/configuration, upstream rejection,
transport failure or malformed success raises `Handrail::BugReporter::Error`;
handle its bounded `code`, `status_code` and `request_id` in the host. Successful
Ruby responses must be JSON objects, a deliberately stricter rule than JS.

Built-in redaction covers sensitive keys, not secrets embedded in arbitrary text;
use trusted `redaction_hooks` for application-specific text redaction. Submission
prepares one payload/event ID for retries. Ruby transport defaults to one attempt;
set `max_attempts` in `Configuration` (bounded to 1–3) to opt into retries.
Ruby attachments use `input[:screenshot]` plus the separate trusted
`allow_screenshots: true` keyword; see [payload](docs/payload.md) and
[screenshot formats](docs/screenshots.md).

When the reporter explicitly consents, Ruby input may include
`:notification => { :notify_on_resolution => true }`. An accepted report remains
submitted if its follow-up subscription fails; inspect `notification_warning`.
Do not fabricate consent or recipients. The same client exports
`discover_policy(timeout_ms: nil)` (validated policy or best-effort `nil`),
`list_bugs(options = {})`, `get_bug(bug_id)`, `archive_bug(bug_id)`,
`restore_bug(bug_id)` and `archive_closed_bugs`. History uses validated, frozen
server projections and upstream ownership checks.

## Capability evidence

These links identify focused coverage, not a claim that every suite or QA campaign
has passed in this checkout. Ruby normalization has documented differences from
JS; the Rails browser asset reuses the pinned JS UI.

| Capability | Local proof and supporting contract |
| --- | --- |
| Submission, canonical IDs, redaction and stable retries | [submission tests](test/submission_test.rb), [payload tests](test/payload_test.rb), [transport tests](test/transport_test.rb); [payload contract and recorded results](docs/payload.md). |
| Policy validation, identity hydration and bounded fallback | [policy tests](test/policy_test.rb); [client API](lib/handrail/bug_reporter/client.rb). |
| Notification consent and saved-report warnings | [notification tests](test/notification_test.rb), [mounted subscription tests](test/subscription_route_test.rb), [workflow browser tests](test/browser/reporter_workflow.test.mjs). |
| Owned history, detail and resolution receipts/journey projections | [history tests](test/history_test.rb), including timing/version/next-step projections; [mounted history tests](test/history_routes_test.rb) and [forwarding contract](docs/history-forwarding.md). |
| Archive, restore and bulk archive-closed | [Ruby archive tests](test/history_archive_test.rb), [route tests](test/history_routes_test.rb), [workflow browser tests](test/browser/reporter_workflow.test.mjs). |
| Screenshot validation and previews | [Ruby screenshot tests](test/screenshot_test.rb), [screenshot contract/results](docs/screenshots.md), [workflow tests](test/browser/reporter_workflow.test.mjs), [style tests](test/browser/reporter_style.test.mjs). |
| Helper, custom/manual UI, lifecycle, CSRF and appearance | [view helper tests](test/view_helper_test.rb), [adapter tests](test/frontend/rails_adapter.test.mjs), [bundle/manual API tests](test/frontend/bundle.test.mjs), [style tests](test/browser/reporter_style.test.mjs); [helper contract/results](docs/view_helper.md). |

The original local acceptance records from 2026-09-09 include
[three workflow browser journeys](test/fixtures/workflow/README.md#local-acceptance-evidence-2026-09-09)
with no failures/errors/skips, and
[eight consent-only style matrix cases / sixteen reporter renders](test/browser/reporter_style.md#original-consent-only-evidence--2026-09-09)
with zero failures/skips. These used Ruby 3.1.2 / Rails 7.2.3.2 and local transport
fixtures, not live Handrail or customer integrations. The original style coverage
did not verify all ordinary form labels; the later
[v0.4.50 field-label regression record](test/browser/reporter_style.md#field-label-regression-verification--2026-09-09)
reports twelve matrix cases / twenty-four renders against the upgraded bundle.
Historical payload and original browser results do not establish current browser
acceptance. The linked lifecycle/CSRF QA campaign and CSS parity acceptance
campaign remain separate checklist items; local passes do not establish campaign
acceptance.

## Compatibility smoke coverage

The Ruby `>= 2.3` / Rails `>= 4.2, < 8.0` bounds are provisional. The scoped
[Git-install smoke harness](test/README.md#legacy-appraisal-smoke) verifies gem
loading, installed Sprockets assets and real cookie-session/CSRF requests without
ActiveRecord, a database, Node or live upstream HTTP.

| Target | Ruby | Rails components | Bundler | Recorded worker result |
| --- | --- | --- | --- | --- |
| `rails_4_2` | 2.3.8 | 4.2.11.3 | 2.3.26 | Passed 2026-09-10: 77 assertions, zero failures/errors/skips |
| `rails_5_2` | 2.5.9 | 5.2.8.1 | 2.3.26 | Passed 2026-09-10: 77 assertions, zero failures/errors/skips |
| `rails_6_1` | 2.7.8 | 6.1.7.10 | 2.4.22 | Passed 2026-09-10: 77 assertions, zero failures/errors/skips |
| `rails_7_2` | 3.1.2 | 7.2.3.2 | 2.3.7 | Passed 2026-09-09: 74 assertions, zero skips |

Every dependency patch is pinned in [matrix.json](test/compatibility/matrix.json)
and the [appraisal gemfiles](gemfiles). With the selected Ruby and Bundler installed,
run `ruby test/compatibility/run.rb rails_7_2` (substitute the target cell).
See the test README for commands, installation/precompile evidence and limitations.
For Rails 4.2, `ruby test/compatibility/bootstrap_rails_4_2.rb` builds the pinned
runtime in private scratch space and runs the smoke without Docker or system
runtime changes. The [retained acceptance record](test/compatibility/evidence/rails_4_2-2026-09-10/README.md)
includes source/package hashes, the exact lockfile and execution artifacts.
For Rails 5.2, `ruby test/compatibility/bootstrap_rails_5_2.rb` uses the same shared
bootstrap with Ruby 2.5.9; its [retained acceptance record](test/compatibility/evidence/rails_5_2-2026-09-10/README.md)
proves the current Git-installed package, exact lock, Node-free precompilation
and real cookie-session/CSRF behavior.
For Rails 6.1, `ruby test/compatibility/bootstrap_rails_6_1.rb` builds Ruby 2.7.8
and installs Bundler 2.4.22 with cell-specific checksum pins. Its
[retained acceptance record](test/compatibility/evidence/rails_6_1-2026-09-10/README.md)
verifies the current Git-installed package, exact dependency lock, Node-free
Sprockets 4.2.1 precompilation and real cookie-session/CSRF behavior.
The authored compatibility workflow has not been executed on hosted CI.

Neither Bluecotton nor Monuvision is verified compatible: their actual
`Gemfile.lock` and Ruby versions must be supplied and matched before adoption.
These smoke results do not establish browser workflow or CSS parity.

Ruby **2.3.8 / Rails 4.2.11.3**, **2.5.9 / Rails 5.2.8.1**,
**2.7.8 / Rails 6.1.7.10** and **3.1.2 / Rails 7.2.3.2** have recorded matrix runtime
acceptance (77, 77, 77 and 74 assertions respectively, zero failures/errors/skips).
Other combinations within the declared dependency bounds remain unverified;
authored CI is not executed support evidence. Exact Bluecotton and Monuvision
versions were unavailable; compare each application's Ruby version and
`Gemfile.lock` before adoption.

Older Rails support does not imply obsolete-browser support. The bundle targets
ES2020 and requires browser `fetch`, `Headers`, `URL`, `AbortController` and
`MutationObserver`; see [browser requirements](docs/browser_adapter.md).
