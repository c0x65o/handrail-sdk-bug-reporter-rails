# Browser asset verification — 2026-09-09

Selected item: `f404084e-3c21-44d8-b78d-85a7c09610ee`.

Rails HEAD remained `f78ed1554410f4ea5e272357029a37a8488a21aa`.
The read-only JS reference HEAD and `v0.4.49` tag both resolved to
`96b293248611594c388d0fab3af63b1b2d1aae5c`; its worktree remained clean.
Existing scaffold and sibling work were preserved. Shared edits are only the
gemspec's explicit asset path and `.gitignore` entries for frontend dependencies
and disposable install caches. No Ruby libraries, scaffold tests, Gemfile,
Gemfile.lock, Rakefile, or root README were edited by this item.

Environment: Node `v22.23.1`, npm `10.9.8`, Ruby `3.1.2p20`, RubyGems `3.3.15`.

Executed from the Rails repository:

```sh
npm run setup
npm test
git diff --check
ruby -c handrail-bug-reporter.gemspec
ruby -c test/frontend/package_contract.rb
node --check scripts/build.mjs
node --check scripts/install.mjs
node --check scripts/contract.mjs
```

- `npm run setup`: passed; fresh locked install added 47 packages, upstream Git
  prepare compiled its SDK, and the focused JSX/browser build passed. The asset
  matched the previous build byte-for-byte. npm emitted the transitive
  `whatwg-encoding` deprecation notice; installation succeeded.
- `npm test`: **7 tests passed, 0 failures, 0 skipped**, approximately 1.2 seconds,
  one test worker. Includes an independent in-memory rebuild for byte equality,
  installed source/version/commit/ref checks, DOM-free classic-script execution,
  instrumented zero load effects, real UI options and session updates, repeated
  cleanup and policy aborts, headless payload identity, and independent mounts.
- The seventh test launches `test/frontend/package_contract.rb` using an absolute
  Ruby executable and **empty PATH**. RubyGems builds and installs a real local
  archive, verifies the asset's bytes, excludes contributor dependencies/build
  scripts, and asserts no install extensions. Node and Git are unavailable in
  that subprocess. Runtime Rails dependencies are intentionally not installed
  there; this test proves packaging, not Rails host boot.
- All listed syntax checks and `git diff --check`: passed.
- The gem retains its intentional missing-license warning. Full bundled
  React/ReactDOM/Scheduler license notices are embedded in the asset.

Asset: `app/assets/javascripts/handrail_bug_reporter.js`, **236,024 bytes**.

SHA-256:
`4deb4b79ae9335ec6d3c32974a0aaac63240b64f3b39d32019aff034cc98f022`

Embedded identity:

```json
{
  "source": "node_web_bug_reporter",
  "platform": "browser",
  "reporter_sdk_runtime": "react",
  "reporter_sdk_package": "@handrail/bug-reporter",
  "reporter_sdk_version": "0.4.49",
  "reporter_sdk_commit": "96b293248611594c388d0fab3af63b1b2d1aae5c",
  "reporter_sdk_ref": "refs/tags/v0.4.49"
}
```

The initial plain npm installation exposed an empty upstream embedded commit
and npm's SSH lock normalization. The final setup path supplies the identity
to upstream's own generator, uses a fresh preparation cache, and preserves the
HTTPS SHA lock. Initial test fixture mistakes (implicit input type, required
upstream config fields, and normalized endpoint expectations) were corrected;
the final complete focused run passes. No unrelated pre-existing failures were
observed; global/sibling tests were not run during this convergence wave.

The public API and reset/cleanup semantics are in [README.md](README.md).
JSDOM and HTTP boundary fixtures do not establish full Rails browser, visual,
or legacy asset-compressor parity. Those already have separate checklist items.
No QA campaign was linked. No commits, pushes, tags, PRs, deployments, or CI/CD
mutations were performed. Publication remains with the gated workflow.
