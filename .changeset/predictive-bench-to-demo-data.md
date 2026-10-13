---
"@mj-biz-apps/contracts-entities": minor
---

Move the predictive-scoring bench (training pipeline, model versions, scoring record process and binding) from `metadata/` to `demo-data/`, so the install seed no longer carries models fitted on one dataset. The record process is now pushed `Disabled` with its schedule off.
