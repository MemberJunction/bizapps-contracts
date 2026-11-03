/**
 * Audit `__mj.EntityField` rows for `__mj_BizAppsContracts` after a from-zero migration replay (#113).
 *
 * Four early migrations (`V202608270100`, `V202608300100`, `V202609020200`, `V202609192100`)
 * called `spDeleteUnneededEntityFields` before `.github/scripts/check-migration-no-prune.mjs`
 * banned that proc from hand-written migrations. This harness verifies on a replayed database that:
 *
 *   1. All 6 `__mj_BizAppsContracts` entities are registered in `__mj.Entity`.
 *   2. Every column exposed by each entity's `BaseView` (`vwContract*`) has a corresponding row in
 *      `__mj.EntityField` immediately after migration replay (zero pruned fields).
 *   3. No `EntityField` row references a non-existent column on its `BaseView`.
 *   4. Running `EXEC [__mj].[spUpdateExistingEntityFieldsFromSchema]` for `__mj_BizAppsContracts`
 *      leaves the `EntityField` set unchanged.
 *
 * Usage:  node test-harnesses/entity-field-replay-audit.mjs
 * Exit:   0 all checks pass · 1 drift or missing fields · 2 bootstrap failure
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';

loadEnvFrom(import.meta.url);

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD, MJ_CONTRACTS_SCHEMA, MJ_CORE_SCHEMA } = process.env;
const contractsSchema = MJ_CONTRACTS_SCHEMA || '__mj_BizAppsContracts';
const mjSchema = MJ_CORE_SCHEMA || '__mj';

if (!DB_DATABASE) {
    console.error('BOOTSTRAP: no DB_DATABASE — set DB_DATABASE or provide an instance .env');
    process.exit(2);
}

const pool = await new sql.ConnectionPool({
    server: DB_HOST ?? 'localhost',
    port: Number(DB_PORT ?? 1433),
    database: DB_DATABASE,
    user: DB_USERNAME,
    password: DB_PASSWORD,
    options: { trustServerCertificate: true, encrypt: false },
}).connect().catch((e) => {
    console.error(`BOOTSTRAP: cannot connect (${e.message})`);
    process.exit(2);
});

let failures = 0;

try {
    const entitiesRes = await pool.request()
        .input('schema', contractsSchema)
        .query(`
            SELECT ID, Name, BaseTable, BaseView
            FROM [${mjSchema}].[Entity]
            WHERE SchemaName = @schema
            ORDER BY BaseTable ASC;
        `);
    const entities = entitiesRes.recordset ?? [];
    console.log(`Auditing ${entities.length} entities in schema [${contractsSchema}]...`);

    if (entities.length !== 6) {
        failures++;
        console.log(`  ✖ Expected 6 entities in [${contractsSchema}], found ${entities.length}`);
    }

    const beforeRes = await pool.request()
        .input('schema', contractsSchema)
        .query(`
            SELECT e.BaseTable, e.BaseView, ef.Name AS FieldName, ef.Sequence, ef.IsVirtual
            FROM [${mjSchema}].[EntityField] ef
            INNER JOIN [${mjSchema}].[Entity] e ON e.ID = ef.EntityID
            WHERE e.SchemaName = @schema
            ORDER BY e.BaseTable ASC, ef.Sequence ASC, ef.Name ASC;
        `);
    const beforeRows = beforeRes.recordset ?? [];

    const viewColsRes = await pool.request()
        .input('schema', contractsSchema)
        .query(`
            SELECT v.name AS ViewName, c.name AS ColumnName, c.column_id AS ColumnOrder
            FROM sys.views v
            INNER JOIN sys.schemas s ON s.schema_id = v.schema_id
            INNER JOIN sys.columns c ON c.object_id = v.object_id
            WHERE s.name = @schema
            ORDER BY v.name ASC, c.column_id ASC;
        `);
    const viewCols = viewColsRes.recordset ?? [];

    for (const entity of entities) {
        const entityFields = new Set(
            beforeRows.filter((r) => r.BaseTable === entity.BaseTable).map((r) => r.FieldName),
        );
        const cols = viewCols.filter((c) => c.ViewName === entity.BaseView).map((c) => c.ColumnName);

        const missingFromEntityField = cols.filter((col) => !entityFields.has(col));
        const orphanedInEntityField = [...entityFields].filter((f) => !cols.includes(f));

        if (missingFromEntityField.length === 0 && orphanedInEntityField.length === 0) {
            console.log(`  ✔ ${entity.BaseTable} (${entity.BaseView}): ${cols.length} view columns match ${entityFields.size} EntityField rows`);
        } else {
            if (missingFromEntityField.length > 0) {
                failures++;
                console.log(`  ✖ ${entity.BaseTable}: columns on ${entity.BaseView} missing from __mj.EntityField: ${missingFromEntityField.join(', ')}`);
            }
            if (orphanedInEntityField.length > 0) {
                failures++;
                console.log(`  ✖ ${entity.BaseTable}: __mj.EntityField rows not present on ${entity.BaseView}: ${orphanedInEntityField.join(', ')}`);
            }
        }
    }

    await pool.request()
        .input('excluded', `sys,staging,dbo,${mjSchema}`)
        .input('included', contractsSchema)
        .query(`
            EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema]
                @ExcludedSchemaNames = @excluded,
                @IncludedSchemaNames = @included;
        `);

    const afterRes = await pool.request()
        .input('schema', contractsSchema)
        .query(`
            SELECT e.BaseTable, ef.Name AS FieldName
            FROM [${mjSchema}].[EntityField] ef
            INNER JOIN [${mjSchema}].[Entity] e ON e.ID = ef.EntityID
            WHERE e.SchemaName = @schema
            ORDER BY e.BaseTable ASC, ef.Name ASC;
        `);
    const beforeKeys = new Set(beforeRows.map((r) => `${r.BaseTable}.${r.FieldName}`));
    const afterKeys = new Set((afterRes.recordset ?? []).map((r) => `${r.BaseTable}.${r.FieldName}`));

    const addedByReconcile = [...afterKeys].filter((k) => !beforeKeys.has(k));
    const removedByReconcile = [...beforeKeys].filter((k) => !afterKeys.has(k));

    if (addedByReconcile.length === 0 && removedByReconcile.length === 0) {
        console.log(`  ✔ spUpdateExistingEntityFieldsFromSchema reconciliation produced 0 diff across ${beforeKeys.size} fields`);
    } else {
        failures++;
        console.log(`  ✖ spUpdateExistingEntityFieldsFromSchema diff: added=[${addedByReconcile.join(', ')}], removed=[${removedByReconcile.join(', ')}]`);
    }
} finally {
    void pool.close().catch(() => undefined);
}

console.log(
    failures === 0
        ? '\nPASS — All __mj_BizAppsContracts EntityField rows match BaseView columns after migration replay.'
        : `\nFAIL — ${failures} EntityField replay check(s) failed.`,
);
process.exit(failures === 0 ? 0 : 1);
