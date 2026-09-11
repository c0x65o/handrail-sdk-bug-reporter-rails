# Bluecotton fixture: required campaign inputs unavailable

Recorded 2026-09-10 for work request `f43e0444-9d00-4ee9-85a6-214d0142a54f`.
This is a blocked implementation handoff, **not compatibility acceptance**.

The requested consumer cell targets observed Ruby **2.6.10-p210**, locked Rails
5.2.8.1, Bundler 1.17.2, Rack 2.2.9, Sprockets 3.7.3, sprockets-rails 3.4.2,
and the recorded Terser 1.2.5 compression configuration. Ruby **2.6.7** remains
a separate declared-version question. The campaign reports 15 differences
among the generic Rails 5.2 cell's 25 pins; that cell cannot supply the missing
consumer pins.

## Required provenance

Owner goal: `510c196e-deb4-44b1-91dc-ef577f5b1fc7`.
Campaign: `214a5a85-d291-4ab6-8635-efeddcdb0792`.
Finding: `9cb32928-c0ff-4b3f-9020-b9c4c702858b`.
Completed assessment work: `e94390eb-370f-42a4-8c00-7f62bceadcc1`.
Assessed consumer revision: `4ed05912be6c27bca4148f5dc3f4140e320fe8fd`.

The following references and hashes came from
`get_goal_completed_work_result` metadata, not from downloaded file bytes:

| Captured file | Campaign artifact ID | Completed-work artifact ID | Reported SHA-256 |
| --- | --- | --- | --- |
| `source/Gemfile.lock` | `203dbe7e-2e7c-4080-9069-de50cd94c4bf` | `c70b16fc-e990-424e-b685-323f8d989a78` | `d1b68f10701712f77f0ea359d66dd1a1d768e7a873a824e3a562dbe23494d2a0` |
| `compatibility-assessment.md` | `075f011f-eca3-4414-a548-756aa33a614c` | `3b973d96-4d7b-4e13-9ad9-3904496838e9` | `8cab28216b386828e6b96c57308a768f9d41ba6901eb5b1e0ce54c2e25287e9f` |
| `source/config/application.rb` | `650c27b0-b8e4-406f-bbf9-1d58c7b88231` | `db93abd4-bd9e-442b-9fda-8a5d46f1fee3` | `40d183a01b197d07e05ed60522d9c0cf42d34fc351d184bd4b3d24e1efc3399a` |
| `source/config/environments/production.rb` | `48a20ce8-cba0-4d9d-aab2-4f29bc53b72b` | `4739933e-dd2a-4dec-a645-7b18929257bf` | `6288db0b0aa0e71f28593d31925a244092de3a289754d56c63d68cb5cfcf90bd` |

## Retrieval failure

`handrail_current_context` confirmed this work request is running in Handrail
Feedback SDKs and the campaign is completed. Campaign and completed-work
metadata reads succeed. Content reads using the returned IDs fail with
`artifact_not_found_or_not_linked`:

- Campaign lock: audit `8828f7e1-eae1-4c32-859b-2d29dc7f0271`.
- Campaign assessment: audit `4b45b1c0-8560-4ed8-a250-2d666f8f50ce`.
- Campaign application config: audit `cb3030d2-806b-4f01-a103-b90a57aedb79`.
- Completed-work assessment: audit `db99cf71-bb35-49ab-9238-43665e217d36`.
- Completed-work lock, with explicit owner goal: audit
  `bb0e0479-f9e4-4301-8754-f72520c56b7f`.

The completed-work metadata also labels the files `readable: false`.
The retained assessment path reported by the campaign does not exist in this
worker:
`/opt/handrail/.handrail/validation-runs/5503c4eb-13e0-4bb5-a004-e296b8d61e71/campaigns/214a5a85-d291-4ab6-8635-efeddcdb0792/compatibility-assessment.md`.

## Resume requirement

Make the captured lock, assessment and compression configuration readable to
this worker through the documented artifact reader, or provide hash-verifiable
copies in this SDK workspace. No new dependency-assessment campaign is needed.
Then derive the SDK/asset transitive closure from those captures, add the named
cell and isolated bootstrap, and run the existing Git-install runner with exact
lock verification, real Terser precompilation, execution of the resulting
JavaScript, and valid/invalid cookie-session CSRF forwarding through its local
transport stub. Retain source/package hashes, runtime versions, resolved lock,
logs and scoped results with zero failures/errors/skips before claiming success.

No matrix pins, SDK source, sibling bootstrap changes or historical acceptance
artifacts were changed by this attempt. `ruby test/compatibility/check_matrix.rb`
passed all four existing cells and workflow consistency; this is structural
validation only. Bluecotton runtime acceptance was not run. No consumer changes,
model tests, installation, commits, pushes, deployments or queue/database writes
were performed.
