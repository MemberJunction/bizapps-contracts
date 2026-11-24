/**
 * Check that every `spUpdate*` procedure in `__mj_BizAppsContracts` takes a parameter for each
 * field MJ passes to it.
 *
 * MJ's save passes every updatable field of a loaded record to the entity's update procedure, not
 * only the changed ones. A procedure that lacks one of those parameters makes SQL Server refuse
 * every update of that entity ("@X is not a parameter for procedure spUpdateY"). That happened
 * when V202611201235 recreated spUpdateContract from text captured before
 * Contract.CarryDiscountOnRenewal existed; V202611242335 restores it.
 *
 * A field counts when it is a column of the entity's base table that is not computed, not an
 * identity, not a primary key and not an `__mj_` timestamp, and its `__mj.EntityField` row has
 * AllowUpdateAPI = 1.
 *
 * Usage:  node test-harnesses/spupdate-parameter-audit.mjs
 * Exit:   0 every procedure covers its fields · 1 a parameter is missing · 2 bootstrap failure
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

let exitCode = 0;
try {
    const res = await pool.request()
        .input('schema', contractsSchema)
        .query(`
            SELECT
                e.Name AS EntityName,
                COALESCE(NULLIF(e.spUpdate, ''), 'spUpdate' + e.BaseTable) AS ProcName,
                c.name AS FieldName,
                CASE WHEN p.name IS NULL THEN 0 ELSE 1 END AS HasParam,
                CASE WHEN OBJECT_ID(QUOTENAME(@schema) + '.' + QUOTENAME(COALESCE(NULLIF(e.spUpdate, ''), 'spUpdate' + e.BaseTable)), 'P') IS NULL THEN 0 ELSE 1 END AS HasProc
            FROM [${mjSchema}].[Entity] e
            INNER JOIN sys.tables t ON t.name = e.BaseTable AND SCHEMA_NAME(t.schema_id) = @schema
            INNER JOIN sys.columns c ON c.object_id = t.object_id
            INNER JOIN [${mjSchema}].[EntityField] ef ON ef.EntityID = e.ID AND ef.Name = c.name
            LEFT JOIN sys.parameters p
                ON p.object_id = OBJECT_ID(QUOTENAME(@schema) + '.' + QUOTENAME(COALESCE(NULLIF(e.spUpdate, ''), 'spUpdate' + e.BaseTable)), 'P')
               AND p.name = '@' + c.name
            WHERE e.SchemaName = @schema
              AND e.AllowUpdateAPI = 1
              AND ef.AllowUpdateAPI = 1
              AND ef.IsPrimaryKey = 0
              AND c.is_computed = 0
              AND c.is_identity = 0
              AND c.name NOT LIKE '[_][_]mj[_]%'
            ORDER BY e.Name, c.column_id;
        `);
    const rows = res.recordset ?? [];
    const entities = new Set(rows.map((r) => r.EntityName));
    console.log(`Checked ${rows.length} fields on ${entities.size} entities in [${contractsSchema}].`);
    if (entities.size === 0) {
        console.log('  ✖ No updatable entities found; the query matched nothing');
        exitCode = 1;
    }
    for (const r of rows) {
        if (!r.HasProc) {
            console.log(`  ✖ ${r.EntityName}: procedure ${r.ProcName} does not exist`);
            exitCode = 1;
        } else if (!r.HasParam) {
            console.log(`  ✖ ${r.EntityName}: ${r.ProcName} has no @${r.FieldName} parameter`);
            exitCode = 1;
        }
    }
    if (exitCode === 0) console.log('  ✔ Every spUpdate* takes every updatable field');
} catch (e) {
    console.error(`BOOTSTRAP: query failed (${e.message})`);
    exitCode = 2;
} finally {
    await pool.close();
}
process.exit(exitCode);
