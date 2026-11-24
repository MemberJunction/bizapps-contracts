-- =============================================================================
-- PostgreSQL counterpart of V202611242335__v1.0.x__Restore_CarryDiscountOnRenewal_in_spUpdateContract.sql
-- =============================================================================
-- Nothing to change on PostgreSQL. This file only keeps the two migration sets
-- in step.
--
-- The T-SQL file recreates spUpdateContract because the T-SQL single-write
-- migration (V202611201235) replaced it with a version that has no
-- @CarryDiscountOnRenewal parameter. The PostgreSQL counterpart of
-- V202611201235 changes nothing, so spUpdateContract here still takes
-- p_carrydiscountonrenewal from V202611121200, and the BEFORE UPDATE trigger
-- already stamps __mj_UpdatedAt in one write.
--
-- Runs once, in order, after V202611201235.
-- =============================================================================

SET search_path TO __mj_bizappscontracts, public;
