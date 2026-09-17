---
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-ng': minor
---

Contract Types carry renewal defaults, and a new contract starts from them (golive #217 / C-US1).

Story C-US1 says the renewal-obligation fields on a new contract are seeded from the selected
Contract Type. Nothing implemented it: `ContractType` had no default columns at all, so finance
typed `AutoRenew`, `RenewalNoticeDays`, `CancellationWindowDays` and `AnnualIncreasePercent` by hand
on every contract, including the ones whose type already determines the answer.

`ContractType` gains four nullable columns — `DefaultAutoRenew`, `DefaultRenewalNoticeDays`,
`DefaultCancellationWindowDays`, `DefaultAnnualIncreasePercent` — editable on its generated form
(reached from Configuration) in a new **Default Contract Terms** section. The three numeric ones
mirror the contract's own columns exactly, precision and `>= 0` check included, so a default that is
legal on the type can never seed a contract that will not save.

**`DefaultAutoRenew` is nullable although the column it seeds is not.** A type needs three answers —
renews, does not renew, and *no opinion* — and NULL is the third. Every existing row starts there,
so an install that never opens Configuration behaves exactly as it does today.

On an **unsaved** contract, choosing or changing the type copies those defaults onto the four fields.
Three rules govern it: a field the user has typed into is never overwritten; a field the new type
says nothing about is restored to what it held before any seeding, so a default leaves with the type
that supplied it; and saved contracts are untouched entirely, because every value on one — blanks
included — was entered by somebody reading the paper.

Nothing reads these columns at save time and nothing validates against them. They are a starting
point, unlike the type's `MustBeRoot` / `MustBeChild` / `TemplateRequired`, which are rules the
server enforces. The seeding trigger watches the record rather than a field-change event, because
`ContractTypeID` is editable both in the Agreement panel and in the generated Details section and a
hook on one of them would seed from one path and not the other.
