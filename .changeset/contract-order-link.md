---
"@mj-biz-apps/contracts-entities": minor
---

Add `ContractOrder`, linking a contract to the orders it governs, and `Contract.CarryDiscountOnRenewal`. The app now depends on bizapps-orders 5.28.0 or later. Part of issue #77: the contract's renewal terms are copied to those orders' subscriptions in a follow-up change.
