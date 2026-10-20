-- =============================================================================
-- PostgreSQL counterpart of V202610121200__v0.8.x__Provision_guard_throws_without_rollback.sql
-- =============================================================================
-- Nothing to change on PostgreSQL. The T-SQL file removes ROLLBACK TRANSACTION
-- from trg_ContractTemplateProvision_Immutability, because SQL Server forbids a
-- ROLLBACK inside the INSERT-EXEC that MJ runs every save and delete through
-- (error 3915), which hid the rule's own message.
--
-- The PostgreSQL trigger function in the baseline (B202609211300) never had a
-- ROLLBACK: it refuses with RAISE EXCEPTION alone, which aborts the statement and
-- the caller's transaction. Its conditions, messages and check order already
-- match the corrected T-SQL trigger, so this file only keeps the two migration
-- sets in step. `mj migrate convert --split` flags the T-SQL trigger for
-- hand-authoring; the hand-authored result is "no change".
-- =============================================================================

SET search_path TO __mj_bizappscontracts, public;
