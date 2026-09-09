# Rails browser asset contract

The delivered `app/assets/javascripts/handrail_bug_reporter.js` is a classic
script exposing `window.HandrailBugReporter`. It bundles the genuine upstream
public React entry: `HandrailBugReporterProvider` from `src/react.ts`, and
`HandrailBugReporterButton` from `src/react-ui.tsx` (which renders the upstream
Dialog). No UI source or CSS is forked. React and ReactDOM 18.3.1 are bundled
privately; no host React, Node, module loader, CDN, or consumer build is needed.
The gemspec includes this prebuilt asset for both gem and Bundler Git packaging.
The asset must be included in Git by the publication workflow, along with the
contributor sources and lockfile; no Git finalization is performed by this item.

Loading the script only defines the API: no UI, listeners, timers, storage, or
network activity. Load it once per page. Helpers and navigation integrations
must explicitly call this API after their own lifecycle/configuration checks.

## API for helper and adapter workers

```js
const element = document.getElementById('bug-reporter');
const reporter = HandrailBugReporter.mount(element, {
  config: {
    transport: 'same-origin',
    apiBaseUrl: '/handrail/api/mobile-bug-reports',
    projectId: 'your-project-id',
    environment: 'production',
    allowScreenshots: true
  },
  initialForm: { route: location.pathname },
  label: 'Report a bug',
  heading: 'Report a bug',
  showHistory: true,
  appearance: {
    themeMode: 'auto', // 'auto', 'light', or 'dark'
    tokens: { accent: '#4f46e5' },
    style: { '--handrail-bug-radius': '12px' }
  }
});

reporter.update({ appearance: { themeMode: 'dark' } });
reporter.unmount();
```

The example forwarding endpoint must be implemented by the separate Rails
routes/adapter items. `config` is passed unchanged to upstream, including
`fetch`, retry, policy deadline, session provider, redaction hooks, and screenshot
settings. Same-origin mode requires `projectId`, `environment`, an absolute-path
API URL, and no report token/session-token provider. The upstream endpoint
normalizer appends `/api/mobile-bug-reports` to base paths; pass a complete
`.../api/mobile-bug-reports` URL when using that exact mounted intake path.
CSRF wrapping and navigation handling belong to the adapter, not this bundle.

| API | Contract |
| --- | --- |
| `mount(element, options)` | Requires a DOM element and `options.config`. Appends one owned child without deleting existing host children. Synchronously renders a closed launcher and returns a handle. Duplicate mounts on the same element throw; separate elements are independent. Policy discovery starts by upstream default after this explicit mount. |
| `handle.update(patch)` / `update(element, patch)` | Shallow-merges top-level options and synchronously renders; returns the same handle. Objects such as `appearance` and `config` are replaced, not deep-merged. Supply fresh immutable values rather than mutating previous objects. |
| Presentation updates | `label`, `heading`, `showHistory`, and `appearance` preserve the open dialog, form, and upstream session state. `appearance` passes `themeMode`, `tokens`, `className`, and scoped CSS variables in `style` directly to upstream. |
| Session updates | Supplying `config` or `initialForm`, even with the same reference, remounts the provider and launcher: closes the dialog and resets policy/history/submission/form state. The merged `initialForm` seeds the new session. This deliberately avoids carrying stale state between identities or routes. |
| `handle.unmount()` / `unmount(element)` | Synchronously unmounts React and removes only the owned child. Idempotent. The element can be mounted again. A stale handle's `update` throws; global `update` for an unmounted element throws. |
| `createBugReporter(config)` | Returns the genuine upstream headless React client; no UI is created. Methods such as `submit`, `discoverPolicy`, and owned history operations retain upstream contracts. It stamps the upstream React/browser identity, not the Rails Git revision. |
| `identity` | Frozen upstream SDK identity, including version, commit, ref, runtime, platform, and report source. |

`initialForm` passes through all upstream fields, including screenshot data,
notification consent, metadata, severity, and route. Provider options
`loadPolicyOnMount` (default true) and `historyPageSize` (upstream default 20,
maximum 50) also pass through. `loadPolicyOnMount: false` suppresses the initial
lookup; `config.enabled: false` disables upstream network behavior. Opening the
Dialog retains upstream policy retry, screenshots, history and notification
behavior, including policy-gated notification eligibility.

Cleanup runs upstream effect cleanup, including aborting mount-time policy
discovery and cancelling dialog animation frames. Removing the owned root also
removes its delegated React listeners from the live document. React retains its
single shared document `selectionchange` listener after first mount; repeated
mounts do not add more. There are no script-load listeners. Upstream submit,
manual refresh, and history requests already in flight are not all universally
cancelled by unmount: unmount is not a cancellation or rollback API. Do not reset
a session during a submission if its result must be presented to the user.

## Contributor build and verification

From this repository, with Node >=18, npm and Git available:

```sh
npm run setup
npm test
git diff --check
```

`setup` runs locked `npm ci --include=dev`, invokes upstream's normal Git prepare
build, then builds the Rails asset. It supplies the frozen commit/ref to the
upstream release generator, because an npm Git preparation checkout can lack
Git metadata. A disposable repository-local npm cache prevents reuse of an
artifact compiled earlier with an empty/stale identity. The cache is deleted
afterward. No separate SDK packaging/publishing step is needed. For wrapper-only
edits after setup, run `npm run build` and `npm test`.

The dependency and lockfile use public HTTPS Git with full SHA
`96b293248611594c388d0fab3af63b1b2d1aae5c` (`v0.4.49`), not a tag dependency.
`frontend/upstream.json` records SHA-256 hashes read from that exact reference
checkout. Before bundling, the build verifies the installed package version,
embedded release identity, both distributed source maps' original SDK sources,
React versions, and the HTTPS lock pin. It rejects missing/wrong identity instead
of substituting the Rails commit. Never use the Rails checkout revision for
`HANDRAIL_BUG_REPORTER_SDK_COMMIT`.

The build compiles JSX into a production IIFE with no external imports, includes
upstream license declarations and the full React/ReactDOM/Scheduler MIT notices,
and produces deterministic bytes. Upstream declares `UNLICENSED`; this work adds
no license grant and leaves the gem's licensing metadata unchanged.

The focused tests run the actual delivered script in a DOM-free VM and JSDOM
without host React, exercise the real provider/Button/Dialog with HTTP boundary
fixtures, verify load-time inactivity, options, session reset, cleanup and
identity on a headless submission, and rebuild for byte equality. A RubyGems
build/install subprocess with empty `PATH` proves the gem includes identical
asset bytes without Node/Git or install extensions. No database is involved.

This is build-contract coverage, not full Rails browser or visual parity.
The script target is ES2020; runtime browser APIs and upstream modern CSS are
preserved without polyfills. Legacy Rails compatibility does not establish
legacy browser support. Appraisals, real-browser workflows, host CSS parity,
helper auto-mounting, and Ruby forwarding remain separate checklist items.
Older Rails asset compressors also need coverage in those compatibility checks;
the pre-minified modern script has not been tested through legacy Uglifier.

Recorded commands, results, and asset identity: [verification.md](verification.md).
