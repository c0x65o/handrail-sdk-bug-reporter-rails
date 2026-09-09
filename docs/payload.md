# Ruby payload contract

`Handrail::BugReporter::Payload` prepares one report without Rails, Git, HTTP,
or runtime environment lookups. Require it explicitly; the shared gem entry
point is owned by the configuration/client work.

```ruby
require "handrail/bug_reporter/payload"

payload = Handrail::BugReporter::Payload.new(
  { :title => "Checkout fails", :description => "Clicking Pay shows an error",
    :impact => "High", :steps => ["Open checkout", "Click Pay"],
    :metadata => { :cart_size => 2 }, :event_id => "trusted-operation-id" },
  :project_id => configuration.project_id,
  :environment => configuration.environment,
  :redaction_hooks => [lambda { |fields| fields }]
)
body = payload.to_json
```

Use the configuration sibling's `project_id` and `environment` readers, as above.
Both must be nonblank strings. Project is trimmed; environment is trimmed and
lowercased. Caller/hook fields cannot override either value. Credentials never
enter this API. The client and transport integration remain separate tasks.

Reuse the same payload instance for retries. `to_h` and `as_json` return its
deeply frozen snapshot; `to_json` serializes that snapshot. Hooks and event ID
generation run only at construction. A trusted `event_id` is trimmed and limited
to 160 characters, otherwise a UUID is generated. The optional `profile_key`
is an intentional trusted argument, trimmed and isolated from hooks. Server
adapters must decide which caller may supply these two arguments; do not blindly
promote arbitrary browser request fields into trusted arguments.

## Fields and hooks

Inputs accept string or symbol keys. String keys win over symbol keys of the
same spelling; Ruby spellings win over JS aliases when both are present.

| Input | Wire field |
| --- | --- |
| `title`, `description` | Trimmed nonblank strings, required before and after hooks |
| `impact`, otherwise `severity` | `severity`: critical/high/moderate/low; trimmed, case-insensitive sev1–sev4 and medium aliases |
| `route` | `route` |
| `app_version` / `appVersion` | `app_version` |
| `build_number` / `buildNumber` | `build_number` |
| `commit_sha` / `commitSha` | `commit_sha` |
| `app_flavor` / `appFlavor` | `app_flavor` |
| `reproducer`, otherwise `steps_to_reproduce` / `stepsToReproduce` / `steps` | `reproducer` |
| `metadata` | Nested JSON, never promoted into top-level wire fields |
| `event_id` / `eventId` | Trusted event ID, outside hook fields |
| `profile_key` / `profileKey` | Trusted profile key, outside hook fields |

Absent/invalid severity becomes `null`. An invalid impact falls back to severity.
Other absent optional caller fields also become `null`, matching JS's conversion
of undefined input values. Reproducer fallback follows JS truthiness (including
retaining empty arrays/hashes). Hooks receive normalized wire names, including
severity; as in JS, allowed hook field edits are retained.

Built-in redaction clones the caller graph before the first hook and after each
hook. Sensitive keys match the JS camelCase/separator-aware patterns, including
credentials, authorization, passwords, tokens, sessions, profile keys, private
messages and payment fields. Their values become `[REDACTED]`. Text under safe
keys is not scanned for embedded secrets; application-specific text redaction
belongs in a hook. Hooks receive no configured identity, credentials, event ID,
or intentional profile key.

Only JS `CALLER_REPORT_FIELDS` survive each hook: title, description, severity,
route, app_version, build_number, commit_sha, app_flavor, reproducer and metadata.
Reserved output (including reporter assertions, SDK identity, screenshots,
notification fields and automation_requests) is removed before the next hook
and final serialization. A reserved-looking key in metadata has no top-level
authority; sensitive metadata keys are still redacted.

Hook exceptions abort with `Payload::Error`, code `redaction_failed`, and a fixed
message without the original exception/cause. Invalid required fields produce
`invalid_report`. Unlike JS's final-only required-field/allowlist checks, Ruby
validates required fields before hooks and after every hook and filters reserved
fields between hooks. A later hook cannot repair an invalid report or reuse a
previous hook's reserved-field injection.

## JSON bounds and Ruby differences

Hashes/arrays are cloned recursively. Symbols work as hash keys; symbol values,
callables and unsupported objects are omitted (also omitted from arrays, like JS
functions/symbols). Custom `to_json`/`as_json` methods are never invoked during
normalization. Nil and nonfinite floats become null. Time/DateTime become UTC
ISO-8601 strings with milliseconds; Ruby Date becomes UTC midnight. Integers
retain Ruby integer precision; use an explicit string when representing a JS
BigInt or an identifier that must not lose precision in downstream JavaScript.

Cycles and containers at depth 20 become `[Circular]`; repeated references that
are not cycles are cloned independently. Keys are capped at 200 characters;
empty keys and `__proto__`, `prototype`, `constructor` are omitted. Ruby caps
count complete characters, while JS `.slice` counts UTF-16 code units; astral
characters remain intact in Ruby IDs/keys. Whitespace trimming matches JS,
including NBSP/BOM. These Ruby type/character differences are deliberate.

## Identity and release provenance

The deeply immutable `Identity::SDK_IDENTITY` preserves
`source=node_web_bug_reporter`, the existing web-intake contract. Its isolated
`RUNTIME` and `PLATFORM` constants are both `ruby`. Backend acceptance of these
values still needs compatibility verification; Ruby is never labeled Node.

The package is `handrail-bug-reporter`; its version comes from the same
`BugReporter::VERSION` used by the gemspec, currently `0.4.49`. `release.rb`
captures immutable static gem release metadata. `reporter_sdk_commit` and
`reporter_sdk_ref` are JSON null because these new Rails sources are uncommitted
and untagged. A release task must supply truthful static provenance when known.
The current Rails HEAD is only the scaffold base and is not claimed to contain
this implementation. Construction never shells out or consults Git/network/env.

The reused browser JS identity is separate: `platform=browser`,
`reporter_sdk_runtime=browser` (or `react` for the React entry), package
`@handrail/bug-reporter`, and that JS artifact's own release commit/ref. The fixed
normalization fixtures use the JS server entry (`node`/`node`); Ruby tests compare
all shared wire fields, including source and version, while asserting Rails'
deliberate platform/runtime/package/commit/ref differences separately.

## Fixed JS v0.4.49 fixtures

`test/fixtures/js_v0.4.49_payload.json` contains 45 captured report cases and six
JSON normalization cases. The generator reads committed TypeScript with
`git show` from **96b293248611594c388d0fab3af63b1b2d1aae5c**, verifies that
`refs/tags/v0.4.49` resolves to that full SHA and that package.json says 0.4.49,
and records source SHA-256 hashes and the esbuild version (0.25.12).

The inspected JS working tree's ignored `src/generated/release.ts` was stale:
0.4.48, commit e0fcb6bf039032c7a0cac8afd147e5b792c3b5ab, refs/tags/v0.4.48.
That file is absent from the committed Git tree. The generator supplies only the
generated release module in memory from the verified 0.4.49 manifest/tag/commit.
All other TS comes from pinned Git objects. No JS source, generated file, dist
output, dependency, or lockfile is changed. The compiled `buildPayload` method is
invoked directly to isolate normalization from transport; a rejecting fetch
boundary prevents HTTP. Ruby tests consume the fixed JSON and require no Node.

To verify the capture without rewriting it (JS checkout needs its existing
esbuild installation):

```sh
node test/fixtures/generate_js_payload.mjs ../handrail-sdk-bug-reporter-js --check
```

Omit `--check` only for intentional fixture maintenance. The SHA is fixed in the
script; changing the sibling HEAD cannot silently change expected behavior.

## Worker validation (2026-09-09)

Runtime: Ruby 3.1.2, Minitest 5.15.0, Node 22.23.1. Implementation uses Ruby
2.3-compatible syntax and does not change the provisional gem bounds. Ruby 2.3
and a legacy Rails support matrix were **not executed** in this worker.

- `ruby -Ilib:test test/payload_test.rb`: 59 runs, 278 assertions, zero failures,
  errors or skips. Includes configuration-reader integration and offline runtime.
- `node test/fixtures/generate_js_payload.mjs ../handrail-sdk-bug-reporter-js --check`:
  exact match for 45 payload and six JSON normalization fixtures.
- Scoped `ruby -c` checks for payload, identity, release and payload tests: pass.
- `ruby -Ilib:test test/scaffold_test.rb`: four runs, five assertions, three
  failures caused by unavailable `rails`, `rails/engine`, and `rack/mock` gems.
  The standalone gemspec test passes. This worker does not have the previous
  scaffold worker's temporary bundle. No framework boot result is claimed.
- `ruby -Ilib:test test/scaffold_test.rb -n test_gemspec_evaluates_without_rails_from_another_directory`:
  one run, two assertions, zero failures/errors/skips. A separate gemspec check
  confirms that all three new payload/identity/release libraries are packaged
  and that the existing version and Ruby bounds remain unchanged.
- `git diff --check`: pass (tracked changes); scoped new files were also checked
  for trailing whitespace. JS status remains clean.

Shared entry-point, version, gemspec, configuration/transport, browser asset and
packaging files are left to their sibling tasks. No client operations,
screenshots, notifications, routes, subscriptions, UI or consumer integrations
are implemented here. Dispatcher/convergence reassessment remains necessary.
