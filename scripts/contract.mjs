import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const read = (path) => readFileSync(resolve(root, path), 'utf8');
export const json = (path) => JSON.parse(read(path));
export const upstream = json('frontend/upstream.json');
export const sha256 = (data) => createHash('sha256').update(data).digest('hex');
export const dependency = `git+https://github.com/c0x65o/handrail-sdk-bug-reporter-js.git#${upstream.commit}`;

export function verifyDependency() {
  const manifest = json('package.json');
  const lock = json('package-lock.json');
  assert.equal(manifest.dependencies[upstream.package], dependency);
  assert.equal(lock.packages[''].dependencies[upstream.package], dependency);
  assert.equal(lock.packages[`node_modules/${upstream.package}`].resolved, dependency);
  const installed = json(`node_modules/${upstream.package}/package.json`);
  assert.equal(installed.name, upstream.package);
  assert.equal(installed.version, upstream.version);
  assert.equal(installed.license, 'UNLICENSED');
  assert.equal(installed.peerDependencies.react, '>=18 <20');
  for (const name of ['react', 'react-dom']) {
    assert.equal(manifest.dependencies[name], '18.3.1');
    assert.equal(lock.packages[`node_modules/${name}`].version, '18.3.1');
    assert.equal(json(`node_modules/${name}/package.json`).version, '18.3.1');
  }
  const require = createRequire(import.meta.url);
  const { SDK_IDENTITY } = require('@handrail/bug-reporter/react');
  assert.equal(SDK_IDENTITY.reporter_sdk_package, upstream.package);
  assert.equal(SDK_IDENTITY.reporter_sdk_version, upstream.version);
  assert.equal(SDK_IDENTITY.reporter_sdk_commit, upstream.commit,
    'Upstream identity mismatch: install with npm run setup, never stamp the Rails commit');
  assert.equal(SDK_IDENTITY.reporter_sdk_ref, upstream.ref);
  // Git prepare ships dist and source maps, not src. Compare the original
  // embedded sources against hashes read from the immutable reference checkout.
  for (const format of ['cjs', 'js']) {
    const map = json(`node_modules/${upstream.package}/dist/react.${format}.map`);
    for (const [path, hash] of Object.entries(upstream.sourceSha256)) {
      const index = map.sources.indexOf(`../${path}`);
      assert.ok(index >= 0, `Missing upstream source: ${path}`);
      assert.equal(sha256(map.sourcesContent[index]), hash, `Modified upstream source: ${path}`);
    }
  }
  return SDK_IDENTITY;
}
