window.assetReadiness = {
  state: document.readyState,
  loaded: Boolean(window.HandrailBugReporter?.rails),
  roots: document.querySelectorAll('[data-handrail-bug-reporter-root]').length
};
