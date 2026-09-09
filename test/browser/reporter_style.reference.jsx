import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { HandrailBugReporterProvider, HandrailBugReporterDialog } from '@handrail/bug-reporter/react';

// Direct public upstream React API, independently of the Rails mount/adapter.
const options = JSON.parse(document.getElementById('reference-options').textContent);
function Reference() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const launcher = document.getElementById('host-bug-button');
    const show = () => setOpen(true);
    launcher.addEventListener('click', show);
    return () => launcher.removeEventListener('click', show);
  }, []);
  return <HandrailBugReporterProvider config={options.config} initialForm={options.initialForm}
    loadPolicyOnMount={options.loadPolicyOnMount}>
    <HandrailBugReporterDialog open={open} onClose={() => setOpen(false)}
      heading={options.heading} showHistory={options.showHistory} appearance={options.appearance} />
  </HandrailBugReporterProvider>;
}
createRoot(document.getElementById('reference-root')).render(<Reference />);
