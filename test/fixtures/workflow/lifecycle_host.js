// Real host listener, deliberately independent of reporter lifecycle ownership.
document.getElementById('host-help')?.addEventListener('click', () => {
  window.hostClicks = (window.hostClicks || 0) + 1;
});
