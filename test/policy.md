# Policy discovery verification

`Client#discover_policy(timeout_ms: nil)` returns an immutable `Policy` or `nil`.
Its readers use Ruby snake_case names; optional automation metadata and notification
metadata are frozen hashes with symbol keys. There is no policy cache or
`current_policy` state. Each discovery refreshes request identity, and discovery
failure does not alter ordinary `Client#request` behavior.

The default overall timeout is 5000 ms. Finite Integer/Float overrides are rounded
and clamped to 1–30000 ms; other values use the default. One request-local transport
deadline covers identity resolution, HTTP, JSON/policy parsing, configured transport
retries, and the JS identity hydration delays of 100 ms and 250 ms. Per-attempt HTTP
timeouts are capped by the remaining budget. A Ruby Timeout watchdog interrupts
stalled resolvers and boundaries; the interruption bypasses ordinary StandardError
recovery and is handled by discovery. Injected clocks and sleepers also have explicit
deadline checks, including when a backoff exceeds the remaining budget.

`fixtures/js_v0.4.49_policy.json` copies `validPolicy` from
`test/reporter.test.mjs` at JS commit
`96b293248611594c388d0fab3af63b1b2d1aae5c` (v0.4.49). The implementation follows
`discoverPolicy`, `parsePolicy`, and `normalizedPolicyDiscoveryTimeout` in that
revision's `src/reporter.ts`. Fixed mutations cover rejected shapes, exact project
binding, normalized environment, strict identity verification, role/access rules,
empty asks including legacy fix/deploy options, optional schema-3 risks, and strict
notification eligibility and lifecycle filtering. No Known Users request is made.

The service-boundary harness uses injected HTTP, resolver, clock and sleeper calls.
Tests prove identity hydration, resolver failures, HTTP failure exhaustion, one
deadline across both retry layers, expiry after each parsing boundary, a truncated
identity backoff, and real watchdog interruption with a static injected clock.
Concurrent request clients share neither policy nor resolved credentials, and
ordinary POST requests still work after fallback. No database or network is used.

Recorded on 2026-09-09 from the Rails repository root, Ruby 3.1.2:

```sh
ruby -Ilib test/policy_test.rb
# 22 runs, 274 assertions, 0 failures, 0 errors, 0 skips (seed 37312)
ruby -Ilib test/transport_test.rb
# 19 runs, 492 assertions, 0 failures, 0 errors, 0 skips (seed 58140)
ruby -c lib/handrail/bug_reporter/policy.rb
ruby -c lib/handrail/bug_reporter/client.rb
ruby -c lib/handrail/bug_reporter/transport.rb
ruby -c test/policy_test.rb
git diff --check
```

Source retains Ruby >=2.3-compatible syntax. The provisional Ruby >=2.3 and
Rails >=4.2, <8.0 gem bounds are unchanged; this focused run does not verify the
legacy Ruby/Rails runtime matrix. Global scaffold/browser tests are outside this
item and were not run during concurrent sibling work. No unrelated test failures
were encountered in the scoped checks.
