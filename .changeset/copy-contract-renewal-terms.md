---
"@mj-biz-apps/contracts-core-entities-server": minor
"@mj-biz-apps/contracts-ng": minor
---

Copy a contract's renewal terms to the Orders subscriptions it governs (issue #77). Saving a contract whose annual increase or carry-discount flag changed, or linking an order to a contract, writes `RenewalIncreasePercent` (only when the contract states an increase) and `CarryDiscountOnRenewal` to every subscription the linked orders created. The renewal terms panel gains a "Discount continues at renewal" field. A contract with linked orders can't be deleted until the links are removed.
