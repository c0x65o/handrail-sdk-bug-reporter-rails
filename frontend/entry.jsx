import { createRailsAdapter } from './rails_adapter';
export { createCsrfFetch } from './rails_adapter';

// Keep roots and lifecycle ownership across repeated helper asset execution.
// React stays lazy until a manual mount or an explicit version-1 helper marker.
const stateKey = Symbol.for('handrail.bug-reporter.rails.v1');
const state = typeof window === 'undefined' ? {} : (window[stateKey] ||= {});
const mounts = state.mounts ||= new WeakMap();

export const identity = Object.freeze(__HANDRAIL_IDENTITY__);

export function createBugReporter(config) {
  return require('@handrail/bug-reporter/react').createBugReporter(config);
}

function optionsWithConfig(options) {
  if (!options || typeof options !== 'object' || !options.config ||
      typeof options.config !== 'object') {
    throw new TypeError('HandrailBugReporter requires options.config');
  }
  return { ...options };
}

export function mount(element, options) {
  if (!element || element.nodeType !== 1 || !element.ownerDocument) {
    throw new TypeError('HandrailBugReporter.mount requires a DOM element');
  }
  if (mounts.has(element)) {
    throw new Error('HandrailBugReporter is already mounted on this element');
  }
  let current = optionsWithConfig(options);
  const React = require('react');
  const { createRoot } = require('react-dom/client');
  const { flushSync } = require('react-dom');
  const { HandrailBugReporterProvider, HandrailBugReporterButton, HandrailBugReporterDialog } =
    require('@handrail/bug-reporter/react');
  function CustomLauncher({ launcher, ...props }) {
    const [open, setOpen] = React.useState(false);
    React.useEffect(() => {
      const show = event => { event.preventDefault(); setOpen(true); };
      launcher.addEventListener('click', show);
      return () => launcher.removeEventListener('click', show);
    }, [launcher]);
    return <HandrailBugReporterDialog {...props} open={open} onClose={() => setOpen(false)} />;
  }
  // Own a disposable child: host siblings survive and React's delegated
  // root listeners leave the document with the removed island on unmount.
  const island = element.ownerDocument.createElement('div');
  island.setAttribute('data-handrail-bug-reporter-root', '');
  element.appendChild(island);
  const root = createRoot(island);
  let generation = 0;
  let active = true;

  function render() {
    flushSync(() => root.render(
      <HandrailBugReporterProvider key={generation}
        config={current.config} initialForm={current.initialForm}
        loadPolicyOnMount={current.loadPolicyOnMount}
        historyPageSize={current.historyPageSize}>
        {current.launcher ? <CustomLauncher launcher={current.launcher}
          heading={current.heading} showHistory={current.showHistory}
          appearance={current.appearance} /> : <HandrailBugReporterButton label={current.label}
          heading={current.heading} showHistory={current.showHistory}
          appearance={current.appearance} />}
      </HandrailBugReporterProvider>
    ));
  }

  const handle = Object.freeze({
    update(patch) {
      if (!active) throw new Error('HandrailBugReporter mount has been unmounted');
      if (!patch || typeof patch !== 'object') throw new TypeError('Expected an options patch');
      const next = optionsWithConfig({ ...current, ...patch });
      // Configuration/form replacement starts a fresh session. Presentation
      // updates keep the upstream form, open dialog, and submission state.
      if (Object.prototype.hasOwnProperty.call(patch, 'config') ||
          Object.prototype.hasOwnProperty.call(patch, 'initialForm')) generation += 1;
      current = next;
      render();
      return handle;
    },
    unmount() {
      if (!active) return;
      active = false;
      try { root.unmount(); }
      finally {
        island.remove();
        mounts.delete(element);
      }
    }
  });
  mounts.set(element, handle);
  try { render(); }
  catch (error) { handle.unmount(); throw error; }
  return handle;
}

export function update(element, patch) {
  const handle = mounts.get(element);
  if (!handle) throw new Error('HandrailBugReporter is not mounted on this element');
  return handle.update(patch);
}

export function unmount(element) {
  mounts.get(element)?.unmount();
}

export const rails = typeof window === 'undefined' ? null :
  (state.rails ||= createRailsAdapter({ mount, isMounted: element => mounts.has(element) }, window));
rails?.start();
