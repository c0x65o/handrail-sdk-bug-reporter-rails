# Configuration and request-scoped transport contract

This foundation references the sibling JS SDK at
`96b293248611594c388d0fab3af63b1b2d1aae5c` (0.4.49). It does not implement
submission, policy, history, payload transformations, routes, or browser behavior.

```ruby
require "handrail/bug_reporter" # Or handrail/bug_reporter/client without Rails.

configuration = Handrail::BugReporter::Configuration.new(
  :api_base_url => "https://handrail.example/prefix/api",
  :project_id => "project-id",
  :environment => "staging",
  :report_token => server_report_token,
  :report_token_header => "authorization", # Or x-handrail-bug-report-token.
  :max_attempts => 1,
  :retry_delay_ms => 250
)
factory = Handrail::BugReporter::Factory.new(configuration,
  :resolve_application_session_token => lambda { |request| resolve_session_token(request) }
)

# Inside each authenticated host request; do not cache this client globally.
client = factory.for_request(request)
# Low-level boundary for the separately implemented operation methods:
result = client.request(:method => "POST", :endpoint => :reports, :body => serialized_body)
```

Configuration is immutable. `status` is `:ready`, `:disabled`, or
`:misconfigured`; `enabled` defaults to true. Read `project_id` and `environment`
from `client.configuration` when constructing downstream payloads and queries:
these are the authoritative trimmed binding, with environment lowercased.
This layer does not rewrite supplied body bytes or normalize operation payloads.
`snapshot` exposes only status, enabled, retry/timeout settings, and token presence.
There is no public report-token reader.

`endpoints` contains frozen absolute URLs keyed by `:reports`, `:policy`, `:mine`,
`:history` (alias for mine), and `:bugs`. Origins, API bases, full intake paths,
path prefixes, and repeated/trailing path slashes normalize consistently.
Relative URLs, userinfo, query/fragment inputs, invalid schemes/ports, backslashes,
and ambiguous traversal/encoded separator paths are misconfigured.

The factory retains configuration, the resolver callback, and a stateless
transport. It never stores clients, request objects, or resolved identity.
The caller must likewise avoid capturing a request in a globally shared resolver
or custom boundary. Each short-lived client holds only its own request. The
resolver runs afresh on every HTTP attempt and every operation; nil, blank,
non-string, unsafe-header values, and StandardError exceptions omit identity.
There is no cookie forwarding or API to supply arbitrary authorization headers.

`Client#request(method:, endpoint: :reports, body: nil, url: nil)` returns an
immutable `Transport::Response` with `status`, `status_code`, `body`, `attempts`,
and `elapsed_ms`. Disabled configuration returns `status: :disabled`, nil body
and status code, and zero attempts, without invoking HTTP or identity resolution.
Success returns `status: :ok` and the successful response body for operation-level
parsing; callers must treat that body as private upstream data. Misconfiguration
and failed requests raise `Handrail::BugReporter::Error`. Optional `url` supports
operation-specific child paths and queries but must remain under the configured
intake on exactly the same scheme/host/port. Operation implementations must use
the configuration binding when building these queries, rather than caller binding.
Supported methods are GET, POST, PUT, DELETE, PATCH, and HEAD.

`Transport.new(configuration, options)` accepts `:http`, `:clock`, and `:sleeper`;
these options may instead be passed to `Factory.new`. The HTTP callable contract:

```ruby
http.call(uri, method, headers, frozen_serialized_body_or_nil, timeouts)
# => { :status => 200, :headers => { "x-request-id" => "id" }, :body => "{}" }
```

An injected boundary must perform at most one attempt, respect the supplied
timeouts, verify TLS, never follow redirects, and never log or retain credentials.
The default `Transport::NetHTTP` uses standard-library Net::HTTP with certificate
verification, hostname verification, no ambient proxy, and a new connection per
attempt. Every redirect is rejected. Automatic Net::HTTP retries are disabled;
a pre-transport guard also prevents hidden resends on older implementations.
This uses the internal `begin_transport` hook, which needs legacy appraisal
coverage. Ruby 2.3's implementation can be inspected in the
[upstream source](https://github.com/ruby/ruby/blob/v2_3_0/lib/net/http.rb).

Timeout configuration is in seconds: `open_timeout` defaults to 5,
`read_timeout` and `write_timeout` to 10 (each clamped to 0.001–60).
`request_timeout` defaults to 30 (clamped to 0.001–120) and bounds an entire
attempt, including writes on older Rubies without a write-timeout setter and
slow response streams. Invalid/non-finite numeric options use defaults.
The clock callable returns monotonic seconds; the sleeper accepts seconds.

Retries are opt-in via `max_attempts`: default 1, integer values clamped to 1–3.
`retry_delay_ms` defaults to 250 and clamps to 0–30000; sleeps double between
attempts, so maximum sleeps are 30 and 60 seconds. Only 408, 425, 429, 500, 502,
503, 504 and eligible connection/DNS/IO/timeout failures retry. TLS verification,
HTTP protocol, and programming errors are permanent. The body is copied and
frozen once per operation and reused across attempts, including event identity.
Resolved session tokens are tracked only locally to redact final diagnostics,
including credentials from earlier attempts.

Errors have generic messages and no implicit exception cause. Their public fields
are `code`, `status_code`, `upstream_code`, `upstream_message`, and `request_id`.
Only selected JSON diagnostic fields are parsed from error bodies of at most
16384 characters; other body/header fields and raw upstream exceptions are not
retained in public errors. Every field redacts known report/session credentials
before cleanup/truncation; token patterns and Bearer values are also redacted.
Messages are bounded to 500 characters, codes to 120, and request IDs to 200.
Codes/IDs additionally require an identifier-only character set. Invalid/oversized
JSON still permits a sanitized correlation header. Inspection, string conversion,
and Rails/JSON serialization of public objects omit private instance variables.
Use the explicit sanitized error readers if structured diagnostics are needed.
No raw logging is installed.

## Worker verification (2026-09-09)

No database, live service, or real credentials were used. Tests inject only HTTP,
clock, sleeper, and HTTP-connection boundaries. The existing no-network guard
rejects real HTTP and socket access. Source and tests retain Ruby 2.3-compatible
syntax, but actual execution was Ruby 3.1.2 with Minitest 5.27.0 and Rails 7.2.3.2.
Legacy combinations and Bluecotton/Monuvision integration remain unverified and
belong to the existing separate appraisal/application items.

The prerequisite's temporary gem cache was unavailable in this worker. The
existing lockfile was installed into this run's temporary directory:

```sh
export transport_tmp=/opt/handrail/.handrail/codex-runs/c8ccbae1-60ae-4bc9-9325-738fa2d3d6a9/tmp
mkdir -p "$transport_tmp/yaml"
curl --fail --location --silent --show-error https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz --output "$transport_tmp/yaml/source.tar.gz"
tar -xzf "$transport_tmp/yaml/source.tar.gz" -C "$transport_tmp/yaml"
export BUNDLE_USER_HOME="$transport_tmp/bundler"
export BUNDLE_APP_CONFIG="$transport_tmp/bundle-config"
export BUNDLE_PATH="$transport_tmp/gems"
export BUNDLE_BUILD__PSYCH="--with-libyaml-source-dir=$transport_tmp/yaml/yaml-0.2.5"
bundle3.1 install --jobs 2 --retry 2
bundle3.1 exec ruby -Ilib:test -rsupport/no_network -e 'require "active_support"; require "active_support/core_ext/object/json"; require "./test/transport_test"'
bundle3.1 exec ruby -Ilib:test test/scaffold_test.rb
```

Install passed (47 gems). Transport: **19 runs, 492 assertions, zero failures,
errors, or skips**. Scaffold: **4 runs, 12 assertions, zero failures, errors,
or skips**. The explicit `require` form loads ActiveSupport after Bundler setup;
an initial CLI `-ractive_support` invocation failed with LoadError before tests.
Plain standalone transport checks also pass without Rails. Global sibling asset
or payload checks are intentionally outside this item's validation scope.
