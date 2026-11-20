---
"@mj-biz-apps/contracts-entities": minor
"@mj-biz-apps/contracts-ng": minor
---

Add the `Termination Agreement` file category, which marks the signed early-termination agreement among a contract's attached files. The row ships as metadata (`metadata/file-categories/`), and its name is exported as `TERMINATION_AGREEMENT_FILE_CATEGORY` from `@mj-biz-apps/contracts-entities` so another app can file a document under it. The contract form's Executed agreement panel shows files in that category and, on a contract with a Terminated Date, lets a linked file be marked or unmarked as the termination agreement.
