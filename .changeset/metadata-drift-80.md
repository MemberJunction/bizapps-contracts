---
"@mj-biz-apps/contracts-entities": minor
---

A host installed from migrations now matches one that also ran `mj sync push` and CodeGen. Two migrations: the Predicted Renewal Risk Band value list (Low, Medium, High, Critical) that CodeGen derives from the column's check constraint, and a Metadata_Sync carrying the metadata changed since the last one: the Contracts Special Terms query and its category, the Contracts: Watchlist view, and the Contract Type form's Default Contract Terms section and field settings. The predictive-scoring records (record process, training pipeline, models, scoring binding) are not included.
