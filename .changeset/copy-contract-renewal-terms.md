---
"@mj-biz-apps/contracts-core-entities-server": minor
"@mj-biz-apps/contracts-ng": minor
"@mj-biz-apps/contracts-server": minor
---

Copy a contract's renewal terms to the Orders subscriptions it governs (issue #77). Saving a contract whose annual increase or carry-discount flag changed, or linking an order to a contract, writes `RenewalIncreasePercent` (only when the contract states an increase) and `CarryDiscountOnRenewal` to every subscription the linked orders created. The renewal terms panel gains a "Discount continues at renewal" field. A contract with linked orders can't be deleted until the links are removed. A daily `Contracts.SweepRenewalTerms` scheduled job re-applies every linked contract's terms, so subscriptions Orders creates after the link (when the order is booked) receive them.
