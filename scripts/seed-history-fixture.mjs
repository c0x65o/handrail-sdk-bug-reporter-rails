// Manual dev seed task: secrets come only from native per-run Vault injection.
import { seedHistoryFixture } from '../test/browser/history_credentials.fixture.mjs';

try {
  if (process.argv.length !== 2) throw new Error('Parameters must use native task injection.');
  const result = seedHistoryFixture();
  console.log(`Private history fixture credentials ${result}.`);
} catch {
  // Never serialize inputs, filesystem contents, or exception details into task logs.
  console.error('Private history fixture seed failed. Check Vault injection, persona and private state permissions/lock.');
  process.exitCode = 1;
}
