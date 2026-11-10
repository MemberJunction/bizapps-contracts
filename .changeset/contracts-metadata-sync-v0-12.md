---
"@mj-biz-apps/contracts-entities": minor
---

Release seed for the stored renewal outcome: `V…__v0.12.x__Metadata_Sync` creates the Contracts action category, the Record Contract Renewal Outcomes action, and the hourly "Contracts — Record Renewal Outcomes" scheduled job that runs it. Every record is create-only, guarded on its ID or natural key, so a host that pauses the job keeps it paused.
