# Rails browser adapter

The packaged `handrail_bug_reporter.js` mounts only
`data-handrail-bug-reporter="1"` elements emitted by the Rails helper. Each root
lives in a disposable child; surrounding host content and custom controls remain
owned by the host. Options are parsed directly from the decoded attribute with
`JSON.parse`. Invalid JSON, unsupported modes, missing custom launchers and
disabled configuration do not mount. A later valid marker/launcher is discovered
by the DOM observer.

## Navigation and ownership

Mounting starts on DOMContentLoaded, or immediately if the document is already
ready. No navigation library is required. The adapter also responds to
`turbo:load`, `turbolinks:load`, legacy `page:load`/`page:change`, and window
`pageshow`. Repeated load events and repeated asset execution reuse one adapter
and one root per marker. Unchanged options retain the active dialog/form.

`turbo:before-cache`, `turbolinks:before-cache`, legacy `page:before-cache` /
`page:before-unload`, and window `pagehide` unmount adapter roots and suspend
mounting until the next load event. React cleanup removes polling and launcher
listeners. The adapter also aborts in-flight transport requests and prevents
retired SDK instances from sending retries. The SDK's bounded retry delay may
finish internally after disposal, but cannot call the host fetch again.

Removed markers, replaced launchers, changed marker attributes, and host morphs
that remove a root are reconciled by the observer. Changed helper options or
pathname start a fresh provider session, including fresh policy discovery when
enabled. Explicit helper context remains authoritative. If `initialForm.route`
is absent, only `location.pathname` is used; query strings, fragments, history
state, cookies, storage, user and session objects are never collected.

Custom hosts can call:

```js
HandrailBugReporter.rails.refresh();  // Reconcile current markers/options/path.
HandrailBugReporter.rails.teardown(); // Unmount adapter roots; remove its listeners/observer.
HandrailBugReporter.rails.start();    // Restart after teardown; safe to repeat.
```

Teardown is repeatable and also runs on window unload. Before-cache retains only
the lifecycle machinery needed to mount the next page. Explicit teardown removes
that machinery too; loading the asset again starts it again. Manual
`mount(element, options)`, `update(element, patch)`, and `unmount(element)` remain
available. Their roots stay caller-owned and require caller cleanup. A manual
mount can supply `launcher: document.getElementById('host-button')` to use the
same public upstream dialog. Use the Rails lifecycle API to tear down helper
markers; manually removing a root while its marker remains active will cause
the adapter to mount it again.

## Request-time CSRF

Helper mounts use a scoped `config.fetch` wrapper. It reads the current
`meta[name="csrf-token"]` content for every same-origin mutating invocation,
including retries, and sets `X-CSRF-Token` on a copied Headers object. A current
meta token replaces any stale caller token. Safe GET/HEAD/OPTIONS/TRACE requests,
foreign origins, missing/empty tokens and unresolvable URLs pass through without
an injected token. Relative URLs use the document base URL; origins include scheme
and port. No global fetch patch or cookie read occurs.

The upstream same-origin credentials remain unchanged. Request body and options
are preserved; lifecycle mounts compose the request's abort signal with their
own cancellation. Manual/headless clients can opt into the standalone wrapper:

```js
const reporter = HandrailBugReporter.createBugReporter({
  transport: 'same-origin',
  apiBaseUrl: '/feedback/api/mobile-bug-reports',
  projectId: 'your-project-id',
  environment: 'development',
  fetch: HandrailBugReporter.createCsrfFetch(window.fetch.bind(window))
});
```

`createCsrfFetch` accepts a caller fetch function and preserves its return value,
receiver, input (string, URL or Request), body, headers, signal and credentials.
It does not add lifecycle cancellation to manual clients. The host layout should
render Rails `csrf_meta_tags`; the helper never serializes a token into options.

## Verification and browser QA handoff

Run the focused build and tests from the Rails checkout:

```sh
node scripts/build.mjs
node --test --test-concurrency=1 test/frontend/rails_adapter.test.mjs test/frontend/bundle.test.mjs
git diff --check
```

The jsdom/node harness uses only HTTP-boundary fakes, with no database or real
network. It covers initial/late DOM load, duplicate scripts, cache/load cycles,
pending policy/history/submission cancellation, polling and listener cleanup,
removed markers/islands, refreshed configuration/context, custom launcher
preservation/replacement, repeatable teardown, CSRF methods/URL/header forms,
token rotation in actual upstream retries, and manual API regressions. Bundle
checks verify byte reproducibility, immutable upstream source and identity, and
gem build/install with no Node or Git. The current dependency is JS v0.4.50 at
`7dfb33f548448f864cf957f19d96f8b5a27bc787`, which isolates reporter field labels
from host CSS. The [style fixture](../test/browser/reporter_style.md) verifies
all fields alongside consent against the pinned direct React renderer.

A linked clean real-browser QA campaign is still required before dispatcher
completion. Extend the existing Rails-mounted workflow fixture task
`f699bf72-d540-46a9-a75d-5261cb8b1b66` with this procedure, using its local test
transport and supported Rails/navigation matrix:

1. Render `csrf_meta_tags` and the helper on two ordinary fixture pages, first
   without Turbo/Turbolinks. Test deferred and post-readiness script loading.
   Verify one root per marker, no root on disabled/marker-free pages, and no
   console errors or changes to host content.
2. Repeat with Turbo and supported Turbolinks versions. Open the dialog and
   history, navigate forward/back at least three times, including browser cache
   restoration. Check one root per marker, one history poll schedule, cancellation
   of pending requests, and no continued requests from departed pages. Execute
   the helper asset twice on one page and repeat.
3. Change the next page's helper label, endpoint, environment and explicit context.
   Inspect the next submitted request for the new values. With no explicit route,
   verify pathname only; include a query/fragment sentinel and confirm it is absent
   from the payload.
4. Render a native custom button with existing content, style and a host listener.
   Open using mouse and keyboard; close with Escape and verify focus restoration.
   Confirm no extra launcher. Replace/remove the button and marker, repeat cache
   cycles, and verify old buttons no longer open a dialog while host handlers work.
5. With the fixture transport, rotate the CSRF meta token between POST/PUT/DELETE
   calls, and return one transient failure before a retry while rotating it again.
   Inspect each attempt's token and same-origin credentials. Cover Request/URL
   inputs, absent/empty tokens, GET, and a foreign-origin fixture URL; foreign
   requests must contain no injected Rails token. Do not send real reports.
6. Call teardown twice; verify all adapter roots/polls/listeners are gone and load
   events no longer mount. Call start twice and verify a single working root per
   marker. Record screenshots, console/network evidence, exact Rails/navigation
   versions and the campaign ID, and link the clean result to adapter item
   `c6925e32-6b71-4892-853d-71a64187a4d7`.

Older Rails hosts need no importmap, Webpacker or framework rewrite. The existing
bundle target remains ES2020 with browser fetch, Headers, URL, AbortController and
MutationObserver support; compatibility with older Rails does not imply support
for obsolete browsers. Actual legacy Rails and visual parity validation belongs
to the existing fixture tasks, not these jsdom results.
