const marker = 'data-handrail-bug-reporter';
const attributes = [marker, `${marker}-mode`, `${marker}-options`, `${marker}-launcher-id`];
const loadEvents = ['turbo:load', 'turbolinks:load', 'page:load', 'page:change'];
const cacheEvents = ['turbo:before-cache', 'turbolinks:before-cache', 'page:before-cache', 'page:before-unload'];

// Wrap only the caller's SDK transport. No global fetch patch or cookie access.
export function createCsrfFetch(fetchImpl, browser = window) {
  return function(input, init) {
    const request = input && typeof input === 'object' && 'url' in input ? input : null;
    const method = String(init?.method || request?.method || 'GET').toUpperCase();
    let url;
    try { url = new browser.URL(request ? request.url : input, browser.document.baseURI); }
    catch { return fetchImpl.call(this, input, init); }
    if (!['GET', 'HEAD', 'OPTIONS', 'TRACE'].includes(method) &&
        url.origin === browser.location.origin) {
      const token = browser.document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
      if (token) {
        const headers = new browser.Headers(init?.headers !== undefined ? init.headers : request?.headers);
        headers.set('X-CSRF-Token', token);
        return fetchImpl.call(this, input, { ...init, headers });
      }
    }
    return fetchImpl.call(this, input, init);
  };
}

// The upstream provider aborts policy discovery on unmount. Also cancel history
// and submission requests, and prevent a retired reporter's retries reaching fetch.
function requestScope(fetchImpl, browser) {
  const csrfFetch = createCsrfFetch(fetchImpl, browser);
  const pending = new Set();
  let disposed = false;
  return {
    async fetch(input, init) {
      if (disposed) throw new browser.DOMException('Reporter unmounted', 'AbortError');
      const controller = new browser.AbortController();
      const signal = init?.signal || input?.signal;
      const abort = () => controller.abort();
      if (signal?.aborted) abort();
      else signal?.addEventListener('abort', abort, { once: true });
      pending.add(controller);
      try {
        return await csrfFetch.call(this, input, { ...init, signal: controller.signal });
      } finally {
        pending.delete(controller);
        signal?.removeEventListener('abort', abort);
      }
    },
    dispose() {
      disposed = true;
      for (const controller of pending) controller.abort();
      pending.clear();
    }
  };
}

export function createRailsAdapter({ mount, isMounted }, browser) {
  const document = browser.document;
  const owned = new Map();
  let started = false;
  let suspended = true;
  let observer;

  function remove(element) {
    const record = owned.get(element);
    if (!record) return;
    owned.delete(element);
    record.scope.dispose();
    record.handle?.unmount();
  }

  function read(element) {
    const raw = element.getAttribute(`${marker}-options`);
    let options;
    try { options = JSON.parse(raw); } catch { return null; }
    if (!options || Array.isArray(options) || !options.config ||
        typeof options.config !== 'object' || Array.isArray(options.config) ||
        options.config.enabled === false || options.enabled === false) return null;
    const mode = element.getAttribute(`${marker}-mode`);
    if (mode !== 'launcher' && mode !== 'custom-launcher') return null;
    const launcherId = element.getAttribute(`${marker}-launcher-id`);
    const launcher = mode === 'custom-launcher' ? document.getElementById(launcherId) : null;
    if (mode === 'custom-launcher' && (!launcher || !/^[A-Za-z][A-Za-z0-9_-]*$/.test(launcherId))) return null;
    return { options, launcher, signature: JSON.stringify([raw, mode, launcherId, browser.location.pathname]) };
  }

  function refresh() {
    if (!started || suspended) return;
    const elements = new Set(document.querySelectorAll(`[${marker}="1"]`));
    for (const element of owned.keys()) if (!elements.has(element)) remove(element);
    for (const element of elements) {
      const next = read(element);
      const previous = owned.get(element);
      if (next && previous?.signature === next.signature && previous.launcher === next.launcher &&
          (previous.failed || (isMounted(element) && previous.island.parentNode === element))) continue;
      remove(element);
      if (!next || isMounted(element)) continue; // Manual mounts retain their owner.
      const scope = requestScope((...args) => browser.fetch(...args), browser);
      const options = {
        ...next.options,
        config: { ...next.options.config, fetch: scope.fetch },
        // Only pathname is inferred. Explicit helper context is authoritative.
        initialForm: { route: browser.location.pathname, ...next.options.initialForm },
        launcher: next.launcher
      };
      try {
        const handle = mount(element, options);
        owned.set(element, { ...next, scope, handle, island: element.lastElementChild });
      } catch {
        scope.dispose(); // Invalid configuration must not break host navigation.
        owned.set(element, { ...next, scope, failed: true });
      }
    }
  }

  function ready() {
    document.removeEventListener('DOMContentLoaded', ready);
    suspended = false;
    refresh();
  }

  function clear() {
    suspended = true; // Observer must not remount a page being cached.
    for (const element of owned.keys()) remove(element);
  }

  const api = Object.freeze({
    refresh,
    start() {
      if (started) return api;
      started = true;
      for (const event of loadEvents) document.addEventListener(event, ready);
      for (const event of cacheEvents) document.addEventListener(event, clear);
      browser.addEventListener('pagehide', clear);
      browser.addEventListener('pageshow', ready);
      browser.addEventListener('unload', api.teardown);
      observer = new browser.MutationObserver(refresh);
      observer.observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: attributes });
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready);
      else ready();
      return api;
    },
    teardown() {
      clear();
      started = false;
      observer?.disconnect();
      observer = undefined;
      document.removeEventListener('DOMContentLoaded', ready);
      for (const event of loadEvents) document.removeEventListener(event, ready);
      for (const event of cacheEvents) document.removeEventListener(event, clear);
      browser.removeEventListener('pagehide', clear);
      browser.removeEventListener('pageshow', ready);
      browser.removeEventListener('unload', api.teardown);
    }
  });
  return api;
}
