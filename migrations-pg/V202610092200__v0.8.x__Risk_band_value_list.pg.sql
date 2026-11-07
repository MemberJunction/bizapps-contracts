-- =============================================================================
-- PostgreSQL counterpart of V202610092200__v0.8.x__Risk_band_value_list.sql
-- Contract.PredictedRenewalRiskBand: the value list CodeGen derives from its CHECK
-- =============================================================================
-- Same rows as the T-SQL file; see its header for why they ship. The PostgreSQL
-- baseline (B202609211300) carries CK_Contract_PredictedRenewalRiskBand but, like
-- the T-SQL train, no EntityFieldValue rows for the field and ValueListType 'None'.
--
-- HOW IT WAS MADE: `mj sql-convert --from tsql --to postgres` (MJ CLI 6.1.6) on
-- the T-SQL file, with `${mjSchema}` written as `__mj` as in this app's
-- PostgreSQL baseline. `mj migrate convert --bake-codegen` emits nothing for this
-- file, because it drops CodeGen-captured metadata (MemberJunction/MJ#5550).
-- =============================================================================

INSERT INTO __mj."EntityFieldValue"
    ("ID", "EntityFieldID", "Sequence", "Value", "Code", "__mj_CreatedAt", "__mj_UpdatedAt")
VALUES
    ('f9404ebe-5434-4725-bedd-397ca8acf877', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 1, 'Critical', 'Critical', NOW(), NOW());

INSERT INTO __mj."EntityFieldValue"
    ("ID", "EntityFieldID", "Sequence", "Value", "Code", "__mj_CreatedAt", "__mj_UpdatedAt")
VALUES
    ('1158e600-d245-47b2-96a6-2a11261d0645', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 2, 'High', 'High', NOW(), NOW());

INSERT INTO __mj."EntityFieldValue"
    ("ID", "EntityFieldID", "Sequence", "Value", "Code", "__mj_CreatedAt", "__mj_UpdatedAt")
VALUES
    ('6ef178b2-0cbf-4472-bb56-35ae9278d500', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 3, 'Low', 'Low', NOW(), NOW());

INSERT INTO __mj."EntityFieldValue"
    ("ID", "EntityFieldID", "Sequence", "Value", "Code", "__mj_CreatedAt", "__mj_UpdatedAt")
VALUES
    ('d3f12a28-83c7-4464-989e-6dfb25532fb4', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 4, 'Medium', 'Medium', NOW(), NOW());

UPDATE __mj."EntityField" SET "ValueListType" = 'List' WHERE "ID" = 'E25C8E07-F5DC-4D15-9EF4-56F51111575E';
