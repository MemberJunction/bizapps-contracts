---
"@mj-biz-apps/contracts-entities": patch
"@mj-biz-apps/contracts-core-entities-server": patch
"@mj-biz-apps/contracts-ng": patch
---

Contract fixes:

- A new contract no longer defaults to a template whose template type is retired, and two quick contract-type changes can no longer apply the earlier type's template decision. The panel and the server read the default through one shared `ReadCurrentTemplateID`.
- Renewal-risk scoring writes back the probability and timestamp, and the contract's server save sets `PredictedRenewalRiskBand` from the probability (Low < 0.2, Medium < 0.5, High < 0.8, Critical ≥ 0.8).
- The source deal picker shows the saved deal and is locked again after Cancel.
- The Executed agreement section offers to mark a newly attached file as the signed agreement, so a contract stops showing "Awaiting document" without a separate trip to the file's category.
- Foreign-key links in the Organization form's Agreements grid open the record.
- `mj-app.json` requires bizapps-common 5.43.0 or later, the first release with the business time zone a contracts migration reads.
