---
"@mj-biz-apps/contracts-entities": minor
"@mj-biz-apps/contracts-actions": minor
---

The renewal-risk label `NonRenewalOutcome` is now a stored column on Contract instead of a `vwContracts` expression that read the clock (#159). The database records it on every save (trigger `trgContract_RecordNonRenewalOutcome`) and for contracts whose end date has passed (`spRecordContractNonRenewalOutcomes`, run hourly by the new "Contracts — Record Renewal Outcomes" scheduled job through the `Contracts.RecordNonRenewalOutcomes` action). The rule is unchanged and lives once, in `fnContractNonRenewalOutcome`, which takes the day as an argument. Training runs over the same rows now see the same labels. Ships migration `V202611031700` and new `metadata/` folders (action-categories, actions, scheduled-jobs).
