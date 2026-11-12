---
"@mj-biz-apps/contracts-core-entities-server": patch
---

Clearing a contract's template is now refused when a modification on a child contract still cites that template and no other contract above the child references it. The refusal names the child-contract count separately.
