# Focused native feedback history QA

Continuation for outcome `f588b46d-a0d6-41ed-83d9-e07bc1e7751f`, worker
`2f1f7920-c7fb-5140-8857-4b49be4df265`. Main Avery owns campaign launch and
acceptance. Publication already passed at
`f22b012a7629886005300816439845c487fc867b`; do not replay it.

## Existing target and source readiness

SDK project: `0fef581d-d8f7-46fa-a111-fad9ee0c81ae`.
Rails repo: `c1f315e5-c3ee-4734-8473-b802fd4f596e`.
Service: `8317027d-9b3b-4d61-8946-c7c978b1ec39`, `rails-css-parity-fixture`.
Keep its existing command `PORT=4179 npm run fixture:style` and port.
Use the **native scoped QA proxy URL** for `/history-fixture`; login is `/login`.
Do not use the loopback listener as a browser target.

The test-only service now redirects anonymous history requests to a real
username/password form. Login validates private credentials and rotates a
30-minute opaque HttpOnly/SameSite session. GET `/fixture-session` returns only
authenticated state, Alice/Bob persona, a CSRF token and the explicit boundary
label `outer-fixture-login-only`. POST to that route with URL-encoded
`action=logout&csrf=...` revokes the session. It never returns the session token.
Expired, forged and logged-out sessions cannot load history or its fixture JS.
Login rate limiting is 10 attempts/60 seconds per socket peer (deliberately
stricter when multiple clients share the native proxy); no account lockout or
password complexity requirement was added. Missing credentials fail closed.
Existing style fixture behavior and the actual published SDK asset are preserved.

## Private task-bound seed (completed 2026-09-30 UTC)

Continuation worker `32fecb56-bb15-5d0b-bfa0-277d37f11ad5` replaces the previous
unsupported direct dev environment-binding instructions. **Do not bind QA
passwords into service environment rows.** The existing native manual seed path
was available and executed successfully; no owner-only setup fallback is needed.

Exact tested command: `node scripts/seed-history-fixture.mjs`.
Working directory: `.` relative to Rails repo
`/opt/handrail/repos/handrail/handrail-feedback-sdks/handrail-sdk-bug-reporter-rails`.
No CLI arguments. Native task Vault injection supplies `HANDRAIL_QA_LOGIN` and
`HANDRAIL_QA_PASSWORD` only for that invocation. The nonsecret parameter schema is:

```json
[{"name":"persona","type":"string","required":true,"options":["alice","bob"]}]
```

The native task maps `persona` to `HANDRAIL_TASK_PARAM_PERSONA`. No default persona
or password exists. Bob's separately bound task restricts its options to `["bob"]`.
Both tasks use `kind=seed`, `execution_mode=project_workspace`, `allowed_envs=[dev]`,
`vault_login_injection_enabled=true`, `dev_provision_seed_enabled=false`,
`schedule_enabled=false`, no cron, `work_request_trigger_phase=none`, and timeout
60 seconds. Native task authorization handled execution; no CI/deploy was run.

| Persona | Task ID | Vault profile / ID | Successful run |
| --- | --- | --- | --- |
| Alice | `ab4bb917-77d5-4a07-93c0-97bf3ff9e352` | `qa-login-dev` / `b451f0d1-c473-4e2f-a6bc-b535a1c7d9e1` | `7add5783-ad95-49e7-a15e-6f5c5b48455c` |
| Bob | `0093f77d-2c71-4b64-b08d-7bab6d56d27b` | `qa-history-bob-dev` / `faa9ad3d-aaae-44cc-83b5-9e0e3c9ab0cf` | `89d2c2e3-d406-4106-bf69-0e471ff1e193` |

Usernames are `qa-history-alice` and `qa-history-bob`. Alice resolves the canonical
dev profile; Bob's task explicitly binds its auxiliary Vault ID. The auxiliary
password was copied server-side from the same-project canonical dev profile.
Both runs returned exit 0, `credentials updated`, exact Vault injection receipts,
and settled processes. Alice rerun `f9851bb7-a692-4f61-8b2e-c41498153a3b` returned
exit 0, `credentials unchanged`, after Bob was added. Safe local inspection
confirmed both personas and required modes, without printing hashes or passwords.

State location: `<Rails repo>/.history-fixture-private/credentials.json`.
The directory is gitignored, owner-only `0700`; the JSON file is owner-only `0600`.
Each account contains only login, persona, random 32-byte salt and scrypt hash.
The seed locks the read/modify/write, preserves unrelated logins, fsyncs a private
temporary file and atomically renames it. Matching inputs leave bytes and mtime
unchanged. Missing secrets or invalid persona fail before writing. Corrupt state,
symlinks, wrong owner/modes and an occupied seed lock fail closed without resetting
users. Retry an overlapping run after it finishes; after an interrupted run,
inspect native task process settlement before removing only its stale `.seed-lock`
directory. Never delete the credential file to bypass a seed error.

Source evidence: `scripts/seed-history-fixture.mjs` is the real task entrypoint;
`test/browser/history_credentials.fixture.mjs` owns hashing/private atomic state;
`test/browser/history_login.fixture.mjs` verifies those hashes;
`test/browser/reporter_style.fixture.mjs` loads state at startup. The service no
longer reads any QA password environment variables. Missing or unsafe state disables
login, while leaving the existing style health route usable. Restart the existing
service after seed changes; credentials persist, sessions intentionally do not.

The minimal native sequence, now completed through service start, is:

1. Configure the source-proven Alice manual seed task for the exact Rails repo.
2. `handrail_configure_project_qa_login` with SDK project, `env=dev`,
   `vault_profile_only=true`, `seeded_bootstrap_task_id` set to Alice's task,
   username `qa-history-alice`, and `/login`. Receipt: `profile_prepared`,
   `configured_env_vars=[]`; profile preparation alone did not create an account.
3. Run Alice's task with `env=dev`, `params={"persona":"alice"}`.
4. Copy canonical credentials server-side into the Bob auxiliary profile; configure
   the second task with `vault_login_entry_id` set to Bob's ID; run with
   `env=dev`, `params={"persona":"bob"}`. Do not run Bob using Alice's profile.
5. Start service `8317027d-9b3b-4d61-8946-c7c978b1ec39` through native controls.
   At `2026-09-30T00:32:59Z`, native post-action verification reported supervised
   running, owned port 4179, health HTTP 200 and registered private QA route:
   `https://h-8db4e04b77c8e633.dev.handrail-daas.com/history-fixture`.
6. **Main Avery remaining:** `owner_assistant_create_qa_campaign` for SDK project,
   dev, this exact service/proxy target and Alice Vault ID; follow the recipe below,
   then authenticate Bob using his exact auxiliary Vault ID. Check service status
   first: the dev service has an idle TTL and may need a native start.

Do not recreate these tasks/profiles or replay release publication. If reseeding
is necessary, use the existing task IDs and explicit parameters above through
`owner_assistant_run_project_task` (or scoped `run_project_task`). Native login
through the proxy remains unverified until Main's campaign. The runtime source
receipt reports `sdk_dev_source_checkout_dirty`, expected for the authorized
uncommitted fixture changes; it is not a clean-commit provenance claim.
Sanitized native receipts and source hashes are in
`artifacts/feedback-history-seed-20260930/verification.json`.

## Executable native recipe

Main launches **`owner_assistant_create_qa_campaign`**, explicitly targeting the
SDK dev service and its scoped `/history-fixture` URL, using the Alice profile.
The native runner must authenticate via `/login` first. Then, from this checkout:

```sh
node scripts/render-history.mjs
```

Required native inputs are `HANDRAIL_BROWSER_TARGET_URL` (scoped proxy URL ending
in `/history-fixture`), `HANDRAIL_VALIDATION_RUN_DIR` (native artifact directory),
and `HANDRAIL_QA_BROWSER_HELPER` (the supported Handrail
`scripts/qa-campaign-browser-helper.mjs`). Do not supply a separate browser,
listener URL or credential substitution. The script asserts genuine Alice login
before rendering, then checks these at **1440×1000** and **390×844**:

1. OFF: Mine selected, no All users; owned row present.
2. ON: All users visible after fresh discovery; owned and shared rows visible;
   no other-user archive action or history image, dialog within viewport.
3. Later OFF: shared rows clear and fresh policy prevents further shared reads.
4. Hold a response, switch the simulated SDK identity/sessionKey, release it:
   abort signal set, stale shared data discarded, Mine reset.
5. Finally revoke the real outer login via CSRF-protected logout and assert
   `/fixture-session` changes from authenticated to HTTP 401.

The script writes exact PNG bytes to
`screenshots/{desktop,mobile}-{off-mine,on-all-users,revoked,switched-user}.png`
and hashes them in `history-bundle-evidence.json`. Inspect and retain those exact
images through native QA. Afterward, use the native runner with the **Bob** Vault
profile: authenticate through `/login`, check `/fixture-session` reports Bob,
and open `/history-fixture`. Its synthetic Mine is empty and must not show
Alice's old rows. Record this actual logout/login switch separately from step 4.
No expiry control bypass is exposed; expiry is tested locally using the fixture
clock and real cookie gate.

**Evidence boundary:** this genuine outer login enables native QA admission; it
is not Known Users verification. Browser policy/history payloads and the held
UI identity switch remain explicitly synthetic. The actual asset and native
rendering are the subject of this recipe. The separate Handrail disposable
integration executes real Known Users session/resource/SQL verification through
both Bug and Enhancement APIs/SDKs. Neither proves live customer two-user use.
No Flutter history UI is required. No Enhancement native browser host was added.

## Checks and unchanged release contract

Current checks: `npm test` passed all 33 tests, including seven focused seed/login
checks. They cover fresh seed, byte-for-byte idempotence, password reconciliation,
second-user preservation, wrong/missing credentials, modes, unsafe/corrupt state,
lock contention, real HTTP login/logout/CSRF/session expiry, startup failure-closed
behavior and credential persistence across service restart. The exact seed CLI
was also exercised in a disposable repo-shaped root with generated test secrets.
Those test credentials never seeded the real service. `git diff --check` passes.
No typed source changed. The frontend suite includes its normal build contract.
The earlier Ruby results remain in
`artifacts/feedback-history-session-20260930/checks/`; they were not replayed.
HTTP unit probes are not browser QA. Native rendering has **not** run here.

`ruby scripts/verify_release.rb --git --package` passes for 23 runtime files.
Contributor 0.5.0 and gem/manifest 0.4.49 `source_snapshot` are valid independent
versions. Public HTTPS Bug JS pin/lock is
`48d046430519871c55db84cb7ace7efd364814ab` (0.5.0). The unchanged actual asset
SHA256 is `984be06291a23733f596e76de16b97c328a71ffeaa20ef9b33cba241723a7f0e`.
No runtime SDK files, manifest, dependencies or customer applications changed.
