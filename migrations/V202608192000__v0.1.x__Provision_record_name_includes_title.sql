-- =============================================================================
-- V202608192000 — a provision's record name is its number AND its heading.
-- =============================================================================
-- WHAT MARCELO SAW (2026-08-19): record tabs for provisions were titled just "9.1"
-- — or worse, "1". A tab strip of bare clause numbers is unreadable, and there is
-- no way to tell which agreement's 9.1 you are looking at.
--
-- WHY IT IS METADATA AND NOT A SCHEMA CHANGE. MJ supports MULTI-FIELD record names
-- natively: `DatabaseProviderBase.BuildEntityRecordNameSQL` collects EVERY field
-- flagged `IsNameField`, in `Sequence` order, and `InternalGetEntityRecordName`
-- joins the non-empty values with a space (its own example is FirstName + LastName
-- → "Elizabeth Rodriguez"). So naming the heading as a second name field is all
-- this needs — no computed column, no view change, no CodeGen run.
--
-- `ProvisionNumber` has the lower Sequence, so the name reads "9.1 Liability and
-- indemnity" — number first, which is how a legal document is cited. Both columns
-- are NOT NULL, so neither half can drop out and leave a dangling separator.
--
-- WHAT THIS DOES NOT CHANGE, deliberately: the `ContractTemplateProvision` virtual
-- name column in the modification base view still shows the number alone. That
-- column is CodeGen output baked into the view, so metadata does not touch it —
-- and the compact form is the right one for a grid cell anyway. The longer name is
-- for places that identify a record to a human: tabs, FK search dropdowns, links.
--
-- Idempotent.
-- =============================================================================

UPDATE f
SET f.IsNameField = 1
FROM [__mj].[EntityField] f
INNER JOIN [__mj].[Entity] e ON e.[ID] = f.[EntityID]
WHERE e.[SchemaName] = '__mj_BizAppsContracts'
  AND e.[BaseTable] = 'ContractTemplateProvision'
  AND f.[Name] = 'Title'
  AND f.[IsNameField] = 0;
