// Explicit maintenance command, never run by Ruby tests. Reads JS Git objects;
// the sibling working tree, generated release file, and dist remain untouched.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readFileSync, writeFileSync } from "node:fs";

const root = resolve(process.argv[2] || "../handrail-sdk-bug-reporter-js");
const commit = "96b293248611594c388d0fab3af63b1b2d1aae5c";
const releaseRef = "refs/tags/v0.4.49";
const git = (...args) => execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trimEnd();
const source = (path) => execFileSync("git", ["-C", root, "show", `${commit}:${path}`], { encoding: "utf8" });
if (git("rev-parse", `${releaseRef}^{commit}`) !== commit) throw new Error("Pinned v0.4.49 tag mismatch");
const manifest = JSON.parse(source("package.json"));
if (manifest.version !== "0.4.49") throw new Error("Pinned package version mismatch");
const esbuild = createRequire(resolve(root, "package.json"))("esbuild");
const captured = new Map();
const built = await esbuild.build({
  entryPoints: [resolve(root, "src/server.ts")], bundle: true, write: false,
  platform: "node", format: "esm",
  plugins: [{ name: "pinned-git-source", setup(build) {
    build.onLoad({ filter: /\.ts$/ }, ({ path }) => {
      const name = relative(root, path);
      if (name === "src/generated/release.ts") {
        return { loader: "ts", contents: [
          ["NAME", manifest.name], ["VERSION", manifest.version],
          ["COMMIT", commit], ["RELEASE_REF", releaseRef],
        ].map(([key, value]) => `export const GENERATED_PACKAGE_${key} = ${JSON.stringify(value)};`).join("\n") };
      }
      const contents = source(name);
      captured.set(name, createHash("sha256").update(contents).digest("hex"));
      return { loader: "ts", contents };
    });
  } }],
});
const sdk = await import(`data:text/javascript;base64,${Buffer.from(built.outputFiles[0].text).toString("base64")}`);
const base = { title: "  Checkout issue  ", description: "  Cannot complete checkout.  ", eventId: " fixture-event " };
const config = { projectId: " project-123 ", environment: " STAGING " };
const cases = [];
const add = (name, input, hooks = []) => cases.push({ name, input: { ...base, ...input }, hooks });
add("minimal", {});
add("field mapping", { route: "/checkout", appVersion: "1.2", buildNumber: 42, commitSha: "app-sha", appFlavor: "preview", reproducer: "Click Pay", metadata: { count: 0, ok: true, missing: null } });
add("steps alias", { stepsToReproduce: ["Open checkout", "Click Pay"] });
add("reproducer precedence", { reproducer: "Primary", stepsToReproduce: "Secondary" });
add("empty reproducer fallback", { reproducer: "", stepsToReproduce: "Fallback" });
add("empty array reproducer retained", { reproducer: [], stepsToReproduce: "Fallback" });
for (const alias of ["critical", "high", "moderate", "low", "sev1", "sev2", "sev3", "sev4", "medium"]) {
  add(`severity ${alias}`, { severity: alias });
  add(`trimmed uppercase ${alias}`, { severity: ` \t${alias.toUpperCase()}\n` });
}
for (const invalid of [null, "", "unknown", 4, false, {}, []]) add(`invalid severity ${JSON.stringify(invalid)}`, { severity: invalid });
add("impact precedence", { impact: " SEV1 ", severity: "low" });
add("invalid impact fallback", { impact: "unknown", severity: "medium" });
add("unicode trim", { title: "\u00a0Title\ufeff", description: "\u3000Description\u2029", severity: "\u00a0HIGH\ufeff" });
add("nested secrets", { metadata: { authorization: "private", profileKey: "private", nested: [{ accessToken: "private", "api-key": "private", safe: "visible" }], directMessage: "private", "x.session.id": "private" } });
add("intentional profile", { profileKey: " owned-profile ", metadata: { profile_key: "private" } });
add("caller event cap", { eventId: ` ${"x".repeat(170)} ` });
add("reserved injection", { project_id: "foreign", environment: "prod", source: "spoof", platform: "node", automation_requests: { fix: true } }, [{ merge: { project_id: "foreign", environment: "prod", event_id: "spoof", source: "spoof", platform: "node", reporter_sdk_version: "999", profile_key: "spoof", screenshot_base64: "spoof", reporter_notification: { notify_on_resolution: true }, reporter_assertion: { verified: true }, automation_requests: { fix: true }, credentials: "private" } }]);
add("hook secret reintroduction", { metadata: { password: "private" } }, [{ merge: { metadata: { refreshToken: "hook-private", safe: "visible" } } }]);
add("hook field edits", {}, [{ merge: { title: " Hook title ", app_version: "hook-version", severity: "low" } }]);
add("invalid title", { title: " " });
add("invalid description type", { description: 42 });
add("hook removes title", {}, [{ remove: "title" }]);
add("hook blank description", {}, [{ merge: { description: " " } }]);
add("hook error", {}, [{ error: true }]);
for (const fixture of cases) {
  const reporter = sdk.createBugReporter({ ...config, apiBaseUrl: "https://fixture.invalid/api", reportToken: "fixture-token", fetch: () => { throw new Error("Network forbidden"); }, redactionHooks: fixture.hooks.map((step) => (fields) => {
    if (step.error) throw new Error("private hook error");
    const output = { ...fields, ...step.merge };
    if (step.remove) delete output[step.remove];
    return output;
  }) });
  try {
    // TS private is callable in the built artifact. Isolate normalization from
    // transport, screenshot, notification, and subscription sibling contracts.
    fixture.expected = await reporter.buildPayload(fixture.input);
  } catch (error) {
    fixture.error = { code: error.code, message: error.message };
  }
}
const repeated = { safe: "visible" };
const cycle = {}; cycle.self = cycle;
const arrayCycle = []; arrayCycle.push(arrayCycle);
const deep = {}; let cursor = deep;
for (let index = 0; index < 25; index++) { cursor.child = {}; cursor = cursor.child; }
const normalizationCases = [
  { name: "cycles", input: { cycle, arrayCycle } },
  { name: "depth", input: deep },
  { name: "shared reference", input: { repeated: [repeated, repeated] } },
  { name: "numbers and date", input: { nan: NaN, infinity: Infinity, negativeInfinity: -Infinity, time: new Date("2026-09-09T01:02:03.000Z"), number: 42 } },
  { name: "unsupported values", input: { fn: () => {}, symbol: Symbol("omit"), array: [() => {}, Symbol("omit"), null] } },
  { name: "bounded keys", input: { "": "omit", prototype: "omit", constructor: "omit", ["k".repeat(201)]: "bounded", safe: "visible" } },
].map(({ name, input }) => ({ name, expected: sdk.redactSensitiveValues(input) }));
const fixture = {
  provenance: { repository: "https://github.com/c0x65o/handrail-sdk-bug-reporter-js", commit, release_ref: releaseRef, package: manifest.name, version: manifest.version, esbuild: esbuild.version, observed_stale_generated_release: { version: "0.4.48", commit: "e0fcb6bf039032c7a0cac8afd147e5b792c3b5ab", ref: "refs/tags/v0.4.48", note: "Ignored working-tree build output observed 2026-09-09; absent from pinned Git tree and never used for fixtures." }, identity_override: "Only the in-memory generated release module was corrected from the pinned package manifest and verified tag/commit.", source_sha256: Object.fromEntries([...captured].sort()) },
  config, cases, normalization_cases: normalizationCases,
};
const output = resolve(dirname(fileURLToPath(import.meta.url)), "js_v0.4.49_payload.json");
const serialized = JSON.stringify(fixture, null, 2) + "\n";
if (process.argv.includes("--check")) {
  if (readFileSync(output, "utf8") !== serialized) throw new Error("Fixed JS fixtures differ");
  console.log(`Verified ${cases.length} fixed JS v0.4.49 payload cases and ${normalizationCases.length} JSON normalization cases.`);
} else {
  writeFileSync(output, serialized);
  console.log(`Captured ${cases.length} fixed JS v0.4.49 payload cases and ${normalizationCases.length} JSON normalization cases.`);
}
