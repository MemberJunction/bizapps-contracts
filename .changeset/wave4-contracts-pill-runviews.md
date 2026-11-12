---
"@mj-biz-apps/contracts-ng": patch
---

Batch contract filter-pill, section-badge, and dashboard-tile count queries into single `RunViews` calls with `ResultType: 'count_only'`, and avoid recounting existing pills when the async open-task pill attaches.
