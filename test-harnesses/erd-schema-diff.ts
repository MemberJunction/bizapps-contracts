/**
 * DOCS TIER — does `docs/ERD.md` still describe the schema that actually exists?
 *
 * WHY THIS IS A TEST AND NOT A CHORE. An ERD is the document people reason about the model with,
 * so a stale one is worse than none: it answers questions confidently and wrongly, and nothing about
 * reading it reveals that a column moved three weeks ago. Every previous alignment pass here was a
 * throwaway script written from scratch, run once, and lost — which is exactly why the drift kept
 * coming back. This makes "the diagram matches the database" a checkable claim.
 *
 * WHAT IT COMPARES. The mermaid `erDiagram` blocks in docs/ERD.md carry an attribute line per
 * column. Those are parsed per entity and diffed against `sys.columns` for the app's schema.
 *
 * The document draws the same entities SEVERAL times (a full-detail view, per-area views), and this
 * compares the UNION of what those blocks say. So the two things it actually proves are: every real
 * column is documented SOMEWHERE, and nothing documented ANYWHERE is invented.
 *
 * What it therefore does NOT catch: a column present in one diagram and missing from another. That is
 * deliberate — the per-area diagrams exist to be readable, and forcing every block to list every
 * column would either fail honestly-partial views or pressure someone into padding them. The failure
 * this file exists to prevent is the one that actually bit us: a column that changed in the database
 * and nowhere in the document.
 *
 * WHAT IT DELIBERATELY IGNORES. CodeGen owns `__mj_CreatedAt` / `__mj_UpdatedAt` and they appear on
 * every table; listing them in every block would be noise that hides signal. Tables present in the
 * database but absent from the document are reported separately from column drift, because "a whole
 * table is undocumented" and "one column moved" are different failures with different fixes.
 *
 * Usage: npx tsx test-harnesses/erd-schema-diff.ts
 * READ-ONLY — it opens one connection and runs one SELECT.
 */
import sql from 'mssql';
import path from 'node:path';
import fs from 'node:fs';
// @ts-expect-error — load-env.mjs is plain JS with JSDoc types, shared with the .mjs harnesses on purpose.
import { loadEnvFrom } from './load-env.mjs';

const SCHEMA = '__mj_BizAppsContracts';
const ERD = path.resolve(process.cwd(), 'docs/ERD.md');

/** Columns CodeGen writes on every table. Documenting them per block would drown the real content. */
const AUDIT_COLUMNS = new Set(['__mj_CreatedAt', '__mj_UpdatedAt']);

let pass = 0;
let fail = 0;
const check = (name: string, ok: boolean, detail = ''): void => {
    if (ok) {
        pass++;
        console.log(`  ✓ ${name}`);
    } else {
        fail++;
        console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
    }
};

/**
 * Every entity block in the document, mapped to the union of columns its blocks declare.
 *
 * A block opens with `EntityName {` and closes with `}`; each attribute line inside is
 * `<type> <ColumnName> [ "note" ]`. Parsed rather than regex-scraped wholesale so that a column named
 * in prose — and there is a lot of prose — cannot be mistaken for a declared one.
 */
function parseErd(markdown: string): Map<string, Set<string>> {
    const byEntity = new Map<string, Set<string>>();
    let entity: string | null = null;

    for (const line of markdown.split('\n')) {
        const open = /^\s{0,8}(\w+)\s*\{\s*$/.exec(line);
        if (open) {
            entity = open[1];
            if (!byEntity.has(entity)) byEntity.set(entity, new Set());
            continue;
        }
        if (/^\s*\}\s*$/.test(line)) {
            entity = null;
            continue;
        }
        if (!entity) continue;

        const attr = /^\s+\w+\s+(\w+)/.exec(line);
        if (attr) byEntity.get(entity)!.add(attr[1]);
    }
    return byEntity;
}

async function main(): Promise<void> {
    // Use the SHARED resolver, which walks up and asks the filesystem. This file used to count
    // three directories up, which was right for the pre-6.x nested layout (mj/packages/dev-apps/<app>)
    // and resolves to ~/MJDev under the parent-workspace topology. dotenv does not error on a missing
    // path, so DB_PORT simply stayed undefined and this died with "Failed to connect to
    // localhost:1433" — which reads like Docker being down, not like a path bug. The .mjs harnesses
    // were moved onto load-env.mjs when that bit us there; this one was missed, which is why the ERD
    // drift below went unnoticed for as long as it did.
    loadEnvFrom(import.meta.url);

    if (!fs.existsSync(ERD)) {
        console.error(`docs/ERD.md not found at ${ERD} — run this from the app root.`);
        process.exit(2);
    }

    const pool = await new sql.ConnectionPool({
        server: process.env.DB_HOST ?? 'localhost',
        port: Number(process.env.DB_PORT ?? 1433),
        user: process.env.DB_USERNAME,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_DATABASE,
        options: { encrypt: false, trustServerCertificate: true, enableQuotedIdentifier: true },
        requestTimeout: 60000,
    }).connect();

    const rows = (
        await pool.request().query(
            `SELECT t.name AS TableName, c.name AS ColumnName
               FROM sys.columns c
               JOIN sys.tables t  ON t.object_id = c.object_id
               JOIN sys.schemas s ON s.schema_id = t.schema_id
              WHERE s.name = '${SCHEMA}'
                AND t.name <> 'flyway_schema_history'
              ORDER BY t.name, c.column_id`,
        )
    ).recordset as { TableName: string; ColumnName: string }[];

    const db = new Map<string, Set<string>>();
    for (const r of rows) {
        if (AUDIT_COLUMNS.has(r.ColumnName)) continue;
        if (!db.has(r.TableName)) db.set(r.TableName, new Set());
        db.get(r.TableName)!.add(r.ColumnName);
    }

    const erd = parseErd(fs.readFileSync(ERD, 'utf8'));

    console.log(`\nERD vs ${SCHEMA} — ${db.size} tables, ${rows.length} columns\n`);

    console.log('A. Every table in the database appears in the document');
    for (const table of [...db.keys()].sort()) {
        check(`A.${table} is documented`, erd.has(table));
    }

    console.log('\nB. Every documented column exists, and every real column is documented');
    for (const table of [...db.keys()].sort()) {
        const documented = erd.get(table);
        if (!documented) continue; // already reported in A; not a second failure

        const real = db.get(table)!;
        const missing = [...real].filter((c) => !documented.has(c));
        const phantom = [...documented].filter((c) => !real.has(c));

        check(`B.${table} documents every column`, missing.length === 0, `missing: ${missing.join(', ')}`);
        check(`B.${table} documents no column that does not exist`, phantom.length === 0, `not in DB: ${phantom.join(', ')}`);
    }

    console.log('\nC. The document describes no table this schema does not have');
    // Scoped to names the DB also knows OR that look like this app's entities: the document
    // legitimately draws cross-app tables (Product, Organization) it does not own.
    const ownEntities = [...erd.keys()].filter((e) => /^Contract/.test(e));
    for (const e of ownEntities.sort()) {
        check(`C.${e} is a real table`, db.has(e), 'documented but absent from the schema');
    }

    console.log('\nD. The header\'s counts are still true');
    // The header states five numbers about the schema. They are the most quotable thing in the
    // document and the easiest to leave behind, because nothing about reading them suggests they
    // were true only on the day someone typed them.
    const counts = (
        await pool.request().query(
            `DECLARE @s INT = (SELECT schema_id FROM sys.schemas WHERE name = '${SCHEMA}');
             SELECT
               (SELECT COUNT(*) FROM sys.tables
                 WHERE schema_id = @s AND name <> 'flyway_schema_history') AS Tables_,
               (SELECT COUNT(*) FROM sys.foreign_keys fk
                  JOIN sys.tables t ON t.object_id = fk.parent_object_id
                 WHERE t.schema_id = @s
                   AND fk.referenced_object_id IN (SELECT object_id FROM sys.tables WHERE schema_id = @s)) AS InternalFKs,
               (SELECT COUNT(*) FROM sys.foreign_keys fk
                  JOIN sys.tables t ON t.object_id = fk.parent_object_id
                 WHERE t.schema_id = @s
                   AND fk.referenced_object_id NOT IN (SELECT object_id FROM sys.tables WHERE schema_id = @s)) AS CrossAppFKs,
               (SELECT COUNT(*) FROM sys.check_constraints cc
                  JOIN sys.tables t ON t.object_id = cc.parent_object_id
                 WHERE t.schema_id = @s) AS Checks_,
               (SELECT COUNT(*) FROM sys.indexes i
                  JOIN sys.tables t ON t.object_id = i.object_id
                 WHERE t.schema_id = @s AND i.is_unique = 1 AND i.is_primary_key = 0) AS UniqueIx`,
        )
    ).recordset[0] as Record<string, number>;

    const header = fs.readFileSync(ERD, 'utf8').slice(0, 4000);
    const stated = (pattern: RegExp): number | null => {
        const m = pattern.exec(header);
        return m ? Number(m[1]) : null;
    };
    const claims: [string, number | null, number][] = [
        ['tables', stated(/\*\*(\d+) tables/), counts.Tables_],
        ['internal relationships', stated(/(\d+) internal\s*\n?>?\s*relationships/), counts.InternalFKs],
        ['cross-app foreign keys', stated(/(\d+) cross-app foreign keys/), counts.CrossAppFKs],
        ['CHECK constraints', stated(/(\d+) CHECK constraints/), counts.Checks_],
        ['unique indexes', stated(/(\d+) unique indexes/), counts.UniqueIx],
    ];
    for (const [label, said, real] of claims) {
        check(`D.the header's ${label} count is right`, said === real, `document says ${said}, database has ${real}`);
    }

    await pool.close();

    console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${pass} passed, ${fail} failed`);
    process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
    console.error(e);
    process.exit(2);
});
