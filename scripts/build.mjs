import { build } from 'esbuild';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { root, read, json, upstream, sha256, verifyDependency } from './contract.mjs';

export async function buildAsset() {
  const identity = verifyDependency();
  const notices = [
    `Handrail Rails browser asset. Upstream ${upstream.package} ${upstream.version}\n` +
    `${upstream.ref} / ${upstream.commit}\n` +
    'Upstream declares UNLICENSED. No license grant is added by this bundle.',
    ...['react', 'react-dom', 'scheduler'].map(name =>
      `${name} ${json(`node_modules/${name}/package.json`).version}\n` +
      read(`node_modules/${name}/LICENSE`).trim())
  ].join('\n\n');
  const result = await build({
    absWorkingDir: root, entryPoints: ['frontend/entry.jsx'],
    bundle: true, platform: 'browser', format: 'iife',
    globalName: 'HandrailBugReporter', target: ['es2020'],
    minify: true, legalComments: 'inline', write: false, metafile: true,
    define: { 'process.env.NODE_ENV': '"production"',
      __HANDRAIL_IDENTITY__: JSON.stringify(identity) },
    banner: { js: `/*!\n${notices}\n*/` }
  });
  const imports = Object.values(result.metafile.outputs).flatMap(output => output.imports);
  if (imports.length) throw new Error(`Unexpected external imports: ${JSON.stringify(imports)}`);
  if (!Object.keys(result.metafile.inputs).includes('node_modules/@handrail/bug-reporter/dist/react.cjs')) {
    throw new Error('Build must include the upstream public React entry');
  }
  return result.outputFiles[0].text;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const asset = await buildAsset();
  mkdirSync(resolve(root, 'app/assets/javascripts'), { recursive: true });
  writeFileSync(resolve(root, 'app/assets/javascripts/handrail_bug_reporter.js'), asset);
  console.log(`handrail_bug_reporter.js: ${Buffer.byteLength(asset)} bytes; SHA-256 ${sha256(asset)}`);
}
