---
"@mj-biz-apps/contracts-entities": minor
---

Add predictive contract renewal outcome columns, engineered training features, and layered base views.

- Materializes `PredictedNonRenewalRisk`, `PredictedRenewalRiskBand`, and `PredictedRenewalScoredAt` on `Contract`.
- Updates layered base view `vwContracts` to compute engineered renewal features (`NonRenewalOutcome`, `TermLengthDays`, `DaysUntilNoticeDeadline`, `HasModificationsFlag`, `AutoRenewFlag`, `HasParentContract`, `HasCancellationWindow`, `HasAnnualIncrease`).
- Configures scheduled scoring write-back binding targeting `PredictedNonRenewalRisk`.
- Removes non-app core remote operations from generated remote_operations.ts.
