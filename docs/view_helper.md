# Declarative Rails reporter rendering

`handrail_bug_reporter` is available to host controller views when the engine
boots. It renders one empty reporter element and a deferred, external
`handrail_bug_reporter.js` tag, resolved through Rails' `javascript_include_tag`.
The bundle mounts only explicit version-1 helper markers. Marker-free loading
initializes navigation listeners and a DOM observer, but creates no React root,
timer, storage access or network request. The helper executes no inline scripts.
See [browser_adapter.md](browser_adapter.md) for lifecycle and CSRF behavior.

## Host API

Configure the server factory as described in [forwarding.md](forwarding.md), then
explicitly mount the engine with a path ending in `/api/mobile-bug-reports`:

```ruby
mount Handrail::BugReporter::Engine => "/feedback/api/mobile-bug-reports", :as => "reporter"
```

In a host ERB view (normally once in the layout):

```erb
<%= handrail_bug_reporter(
  :endpoint => reporter_path,
  :context => { :route => request.path, :app_version => "1.2.3" },
  :show_history => true,
  :allow_screenshots => true,
  :label => "Report a bug",
  :appearance => {
    :theme_mode => :dark,
    :tokens => { :accent => "#4f46e5" },
    :style => { "--handrail-bug-radius" => "12px" }
  }
) %>
```

`projectId` and `environment` come exclusively from the host-configured factory's
public `configuration.project_id` and `configuration.environment` readers. Supply
the host environment in that server configuration; the helper does not infer it
from Rails.env or request parameters. It never constructs a request client or
reads/resolves credentials. The endpoint is an explicit local Rails mount path,
never the factory's upstream URL. Use a Rails path helper, including the host
`SCRIPT_NAME` when deployed under a subdirectory. Validation checks the POST route
resolves to the reporter intake. Absolute URLs (even the host's own origin),
protocol-relative URLs, queries, fragments, percent escapes, backslashes, dot
segments, duplicate slashes and nonmatching mounts raise `ArgumentError`.
The complete suffix prevents the bundled upstream URL normalizer from silently
appending another intake path. Host mounts with request-specific constraints
must also be recognizable by Rails' `recognize_path` API.

All top-level and context option keys are Ruby symbols. Unsupported keys/types
raise `ArgumentError` without inspecting or printing the supplied values.

| Option | Public contract |
| --- | --- |
| `enabled` | Boolean, default true. False, a missing factory, or disabled server configuration emits an empty string: no island or asset tag. A helper cannot override server disablement. |
| `endpoint` | Required when enabled; complete local mounted intake path. |
| `mode` | `launcher` (default) or `custom-launcher`, string or symbol. |
| `launcher_id` | Required only for custom mode; existing host element ID matching `[A-Za-z][A-Za-z0-9_-]*`. |
| `context` | Explicit public strings: `route`, `app_version`, `build_number`, `commit_sha`, `app_flavor`, `title`, `description`, `reproducer`, `profile_key`. Converted to the bundle's camelCase `initialForm` fields. No automatic URL/query, user, session, metadata or request serialization. |
| `show_history` | Boolean, default true; becomes `showHistory`. |
| `allow_screenshots` | Boolean, default false; becomes `config.allowScreenshots`. |
| `load_policy_on_mount` | Boolean, default true; becomes `loadPolicyOnMount`. Rendering itself never discovers policy. |
| `history_page_size` | Optional integer 1–50; becomes `historyPageSize`. Omission leaves the bundle default. |
| `label`, `heading` | Optional strings; omission leaves bundle defaults. |
| `appearance` | Hash with `theme_mode` (`auto`, `light`, `dark`), `class_name` string, `tokens`, and `style`. Serialized only for this reporter; never applied to the host DOM. |

`tokens` accepts string/symbol keys matching the bundled UI: `accent`, `accentText`,
`surface`, `surfaceMuted`, `text`, `mutedText`, `border`, `overlay`, `dangerSurface`,
`dangerText`, `successSurface`, `successText`, `warningSurface`, `warningText`,
`infoSurface`, `infoText`, `radius`, `fontFamily`. Values are strings. `style` accepts
only the corresponding `--handrail-bug-*` CSS variables (camelCase converted to
kebab-case), with string or finite numeric values. Arbitrary layout properties
and global styles are intentionally outside this public helper API.

Only supply public data in these explicit fields. Configuration/Factory objects,
report tokens, session callbacks, fetch implementations and credentialed upstream
endpoints are not helper options and are never copied into browser configuration.

## DOM contract for the browser adapter

Each call emits a distinct empty `<div>` with:

| Attribute | Value |
| --- | --- |
| `data-handrail-bug-reporter` | Contract version `1`. |
| `data-handrail-bug-reporter-mode` | `launcher` or `custom-launcher`. |
| `data-handrail-bug-reporter-options` | Escaped JSON object matching bundle mount options: `config`, `initialForm`, `showHistory`, `loadPolicyOnMount`, `appearance`, optional `label`, `heading`, `historyPageSize`. |
| `data-handrail-bug-reporter-launcher-id` | Custom mode only; host element ID, not a selector or JavaScript. |

`config` contains exactly `transport: "same-origin"`, `enabled: true`,
`apiBaseUrl`, `projectId`, `environment`, and `allowScreenshots`. Parse the options
attribute using `JSON.parse(element.getAttribute(...))`; DOM attribute decoding
has already removed HTML escaping. Never use `eval`, `innerHTML`, or a second HTML
decode. Quotes/ampersands/HTML/closing-script text and Unicode separators round
trip as data. Strings passed as Rails-safe buffers still go through JSON and
attribute escaping. The helper does not change caller hashes or surrounding host
content, classes or styles.

For custom mode, the host renders its own button, for example
`<button id="host-bug-button" type="button">Help</button>`, and passes
`:mode => "custom-launcher", :launcher_id => "host-bug-button"`. The adapter uses
the upstream public provider and dialog with a removable click listener on that
host element. It preserves the host control and renders no second launcher.
Use a native button for keyboard activation. Mode/launcher ID remain adapter
attributes; they are not upstream React options.

The engine adds only this helper to host controller views and conditionally adds
the JS logical name to Sprockets' precompile list. No Sprockets dependency is
required at runtime. Without an asset pipeline, a host must serve the packaged
asset at the URL resolved by its Rails asset helpers. Fingerprints and asset hosts
remain Rails' responsibility; no hardcoded CDN, Webpacker or importmap is needed.

## Verification

The dedicated `test/fixtures/views` host uses actual Rails view rendering, route
recognition and asset helpers, with no database. It boots with and without the
Sprockets railtie. The Sprockets case disables runtime compilation and reads a
fixture fingerprint manifest with an asset host. Package coverage builds/extracts
the gem, compares helper and bundle bytes, and repeats rendering with the extracted
engine. Child processes use the existing no-network guard; credential and HTTP
boundary callbacks fail if invoked during rendering.

The development Gemfile includes Sprockets for these tests; the gemspec still has
only `railties` as a runtime dependency. Verified runtime is Ruby 3.1.2, Rails
7.2.3.2, Sprockets Rails 3.5.2 / Sprockets 4.4.1. Source uses Ruby >=2.3 / Rails
>=4.2 interfaces, but legacy runtime combinations remain untested. The helper
checks below do not establish browser workflow or visual parity. Adapter jsdom
coverage and the remaining real-browser procedure are in
[browser_adapter.md](browser_adapter.md).

### Recorded worker checks — 2026-09-09

Initial and final HEAD: `f78ed1554410f4ea5e272357029a37a8488a21aa`. Existing
untracked prerequisites and `.gitignore` edits were preserved. Changes owned by
this item are the helper, additive engine/gemspec registration, development
Gemfile/lock entries, `test/view_helper_test.rb`, `test/fixtures/views/*`, and this
document. The shared bundle, forwarding code and routes were not edited.

The fresh worker installed 49 development gems in its temporary directory using
the existing libyaml-source build setup. Final validation used the repository's
Gemfile and matching lockfile with these environment variables:

```sh
export view_tmp=/opt/handrail/.handrail/codex-runs/1dbcbee6-5fa0-475e-b4ec-02d705c66bf8/tmp
export BUNDLE_USER_HOME="$view_tmp/bundler"
export BUNDLE_APP_CONFIG="$view_tmp/bundle-config"
export BUNDLE_PATH="$view_tmp/gems"

bundle3.1 check
bundle3.1 exec ruby -Ilib -Itest test/view_helper_test.rb
WITH_SPROCKETS=1 RAILS_ENV=test RACK_ENV=test bundle3.1 exec ruby -Ilib -Itest -r support/no_network test/fixtures/views/rendering_checks.rb
WITH_SPROCKETS=0 RAILS_ENV=test RACK_ENV=test bundle3.1 exec ruby -Ilib -Itest -r support/no_network test/fixtures/views/rendering_checks.rb
bundle3.1 exec ruby -Ilib -Itest -e 'require "./test/scaffold_test"; require "./test/forwarding_package_test"'
bundle3.1 exec ruby -Ilib -Itest test/scaffold_test.rb -n '/gemspec|entry_point/'
ruby -e 'paths = %w[app/helpers/handrail/bug_reporter_helper.rb lib/handrail/bug_reporter/engine.rb handrail-bug-reporter.gemspec Gemfile test/view_helper_test.rb test/fixtures/views/config/application.rb test/fixtures/views/config/routes.rb test/fixtures/views/rendering_checks.rb]; paths.each { |path| abort path unless system(RbConfig.ruby, "-c", path) }'
git diff --check
git diff --no-index --check /dev/null app/helpers/handrail/bug_reporter_helper.rb
git diff --no-index --check /dev/null docs/view_helper.md
sha256sum app/assets/javascripts/handrail_bug_reporter.js
```

Results:

- Dependency check passed.
- Helper/package wrappers: **3 runs, 13 assertions, zero failures/errors**. These
  execute all rendering cases in three fresh processes, including the extracted gem.
- Sprockets rendering: **10 runs, 189 assertions, zero failures/errors**.
- No-Sprockets rendering: **10 runs, 187 assertions, zero failures/errors**.
- Scaffold/forwarding package regression: **5 runs, 12 assertions, one failure**.
  `ScaffoldTest#test_real_host_boot_is_unchanged_by_engine` expects the engine's
  entire route list to equal `["/", "/policy"]`. A concurrent sibling added
  `/mine`, `/bugs/:bug_id`, archive and archive-closed routes during this worker's
  run. The existing exact-route assertion is stale; it was left to that work's
  scope. The forwarding package check passed. This does not block helper rendering.
- Isolated scaffold gemspec/entry-point checks: **3 runs, 6 assertions, zero
  failures/errors**.
- All eight Ruby/Gemfile/gemspec syntax checks and whitespace checks passed.
- Bundle SHA-256 remained
  `4deb4b79ae9335ec6d3c32974a0aaac63240b64f3b39d32019aff034cc98f022`.

Gem builds emit the existing missing-license warning. No commit, push, PR,
deployment, runtime configuration change, database or real upstream request occurred.
