---
'@mj-biz-apps/contracts-ng': patch
---

The contract header showed **Company twice**. `next` already carried the Company stat and the rebase re-applied this branch's version next to it; the two insertions were adjacent rather than overlapping, so nothing conflicted and a build-only CI had nothing to fail on. One block now, and a test asserts no stat label is rendered twice — generalised, because a duplicated stat is exactly what a rebase against a branch solving the same issue produces.

The **Re-papering read-only chips** now read "Finish editing to change" / "Save this contract first", as #203 item 19 specified. They were missed because the commit carrying that copy also carried supersede work `next` had solved its own way, so the whole commit was dropped in the rebase.
