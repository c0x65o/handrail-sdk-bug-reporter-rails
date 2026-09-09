import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { root, upstream } from './contract.mjs';

// npm's cached Git prepare artifacts can contain a missing/stale release
// identity. Use a fresh cache and supply identity to upstream's own generator.
const cache = mkdtempSync(join(root, '.frontend-install-'));
try {
  const result = spawnSync(process.platform === 'win32' ? 'npm.cmd' : 'npm',
    ['ci', '--include=dev', '--no-audit', '--no-fund', '--cache', cache], {
      cwd: root, stdio: 'inherit',
      env: { ...process.env,
        HANDRAIL_BUG_REPORTER_SDK_COMMIT: upstream.commit,
        HANDRAIL_BUG_REPORTER_SDK_REF: upstream.ref }
    });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exitCode = result.status || 1;
} finally {
  rmSync(cache, { recursive: true, force: true });
}
