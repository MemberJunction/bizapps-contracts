-- =============================================================================
-- V202608200700 — Drop the pinned grid layouts that still name the removed Sequence column.
-- =============================================================================
-- V202608200400 removed `ContractTemplateProvision.Sequence`. It did not account for the fact that
-- MJ's grid PERSISTS a per-user layout -- chosen columns, widths, order and sort -- as a
-- `__mj.UserSetting` row keyed `default-view-setting/<Entity Name>`, and that layout PINS those
-- columns regardless of what entity metadata now says.
--
-- So for any user who had ever opened that grid, the stored layout still said:
--
--     {"columnSettings":[… {"Name":"Sequence" …}], "sortSettings":[{"field":"Sequence","dir":"asc"}]}
--
-- and the grid dutifully emitted `ORDER BY ContractTemplate ASC, Sequence ASC` against a view that no
-- longer has the column. Result: **the all-provisions page failed to load entirely** --
-- `Invalid column name 'Sequence'` -- while a user with no saved layout was fine. Reported by Marcelo
-- 2026-08-20 on the running instance; the page, not just the sort, was dead.
--
-- THIS IS NOT A DEV-INSTANCE ARTEFACT, which is why it is a migration rather than a one-off DELETE.
-- Every deployment has the same rows, so dropping a column that a saved layout references breaks that
-- grid for exactly the users who used it most. Any migration that drops a column has this obligation.
--
-- WHY DELETE THE ROW RATHER THAN EDIT THE JSON. Surgically removing one entry from `columnSettings`
-- and `sortSettings` in T-SQL is fragile (nested arrays, two places, no JSON array-remove primitive
-- before recent versions), and the prize is preserving the widths of two other columns. The row is a
-- UI PREFERENCE that MJ regenerates from `DefaultInView` metadata on the next visit, so deleting it
-- costs a user their column widths once and costs nothing else. Proportionate; JSON surgery is not.
--
-- SCOPED THREE WAYS so it cannot touch a layout it has no business touching: the settings key for this
-- ONE entity, and only rows whose value actually mentions the removed column.
--
-- ⚠ The general fix belongs in MJ, not here: a grid should intersect its persisted column set with
-- current entity metadata and drop what no longer exists, rather than emitting SQL that names a
-- dropped field. Logged in MJ-UPSTREAM.md. Until then, every app dropping a column owes its users a
-- migration like this one.
-- =============================================================================

DELETE FROM [${mjSchema}].[UserSetting]
 WHERE [Setting] = 'default-view-setting/MJ_BizApps_Contracts: Contract Template Provisions'
   AND [Value] LIKE '%"Sequence"%';
GO
