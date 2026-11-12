---
"@mj-biz-apps/contracts-entities": minor
"@mj-biz-apps/contracts-core-entities-server": minor
"@mj-biz-apps/contracts-ng": minor
"@mj-biz-apps/contracts-server": minor
---

Copy a contract's renewal terms to the Orders subscriptions it governs (issue #77). New `ContractOrder` table links a contract to the orders it governs, and `Contract.CarryDiscountOnRenewal` records whether a first-term discount continues at renewal. Saving a contract whose annual increase or carry-discount flag changed, or linking an order to a contract, writes `RenewalIncreasePercent` (only when the contract states an increase) and `CarryDiscountOnRenewal` to every subscription the linked orders created. A daily `Contracts.SweepRenewalTerms` scheduled job re-applies every linked contract's terms, so subscriptions created after the link receive them. The renewal terms panel gains a "Discount continues at renewal" field. A contract with linked orders can't be deleted until the links are removed. The app now requires bizapps-orders 5.28.0 or later, installed before Contracts.
