---
'@mj-biz-apps/contracts-ng': patch
---

The contract header names the record that created it, and labels its two parties the way the rest of the app does (#28 items 1 and 8).

The "Created by" stat promised a person and rendered an entity name: a contract raised from a Close-Won deal read "Deals", one entered by hand read "—" over the words "entered directly", and neither told the reader which deal. It is now a **Source Deal** stat whose value is the deal's own name, clickable through to the record, and it is absent entirely when `CreatingEntityID` is null rather than spending the most-read row on the absence of a fact. `CreatingEntityID`/`CreatingRecordID` is a polymorphic pair, so nothing is hardcoded to Deals — the entity is resolved from the id, the label takes that entity's singular name, and a contract created by an Order would read "Source Order" with no code change.

The header's meta row now reads `<number> · Company: … · Customer: …`. It previously put the customer first and labelled the selling company "Selling", a word that appeared on no other surface and matched no field a user could go looking for. No metadata change accompanies it: the issue asked for `EntityField.DisplayName` on `CompanyID` to be set to "Company", but CodeGen strips the trailing `ID` from a foreign-key field and already produces exactly that — the same rule that makes `CustomerOrganizationID` read "Customer Organization". The generated Stakeholders section and the grids already agree with the header.
