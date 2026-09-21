/**
 * @fileoverview Which migration the database ACTUALLY runs last for a layered view, and its SQL with
 * the prose taken out.
 *
 * WHY THIS IS SHARED RATHER THAN RE-TYPED. `vw<X>Generated` belongs to CodeGen, which regenerates it
 * wholesale; `vw<X>` is hand-written on top, so every schema change makes a human re-type the whole
 * view — and hand-added logic is exactly what goes missing when they start from a stale copy. The
 * guards against that kept being written per test file, and each copy went stale on its own schedule:
 *
 *   · 2026-08-23 — the flatten moved the view; the hardcoded filename was hand-repointed.
 *   · 2026-08-30 — contracts#28 item 13 moved the Terminated branch in a NEW migration; the guard
 *     carried on reading the old file and passing.
 *   · 2026-09-20 — `V202609202354` re-created the view with `DROP VIEW` + `CREATE VIEW`, which the
 *     `CREATE OR ALTER`-only pattern did not match, so the suite silently went back to describing
 *     the 1 September migration. `IsAwaitingDocument` lost its category gate for a day and nothing
 *     failed.
 *
 * Three files needed the same resolution and had three spellings of it. One implementation, tested
 * once, is the only version of this that stays correct.
 *
 * Mirrors `bizapps-orders`' helper of the same name deliberately: a developer moving between the
 * family's apps should not have to learn a second one.
 */
import { readdirSync, readFileSync } from 'node:fs';

/**
 * SQL with BOTH comment forms removed, so prose can never satisfy — or defeat — an assertion.
 *
 * `--` TO END OF LINE, NOT WHOLE LINES ONLY. The first version of this stripped `/^\s*--.*$/gm`, and
 * a trailing inline comment walked straight through it in both directions. A required predicate
 * quoted in a trailing comment SATISFIED a presence check while the executable SQL had dropped it —
 * the exact regression these guards exist for — and a banned token mentioned in a trailing comment
 * FAILED an absence check on a correct view, whose obvious repair is to weaken the assertion.
 *
 * Block comments too. The migrations happen to use `--`, but "happen to" is the whole problem: the
 * next re-type is free to explain itself in `/* … *\/` and quietly re-open the hole. The theoretical
 * cost — a `/*` inside a string literal — is not a risk these files can express, and a *wrongly*
 * stripped span can only make an assertion FAIL loudly, never pass falsely.
 *
 * Replaced with a SPACE, not with nothing, so `a--c\nb` cannot become `ab`.
 */
export function sqlCode(sql: string): string {
    return sql.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*/g, ' ');
}

/** Whitespace normalised, so a reformat of a view does not fail a predicate assertion. */
export const squash = (s: string): string => s.replace(/\s+/g, ' ').trim();

/** Any DDL naming the view: `CREATE VIEW`, `CREATE OR ALTER VIEW`, or `DROP VIEW`. */
function ddlFor(view: string): RegExp {
    return new RegExp(
        String.raw`\b(?:CREATE\s+(?:OR\s+ALTER\s+)?VIEW|DROP\s+VIEW)\s+\[[^\]]+\]\.\[${view}\]`,
        'i',
    );
}

export interface ViewDefiner {
    /** The migration the database runs last for this view. */
    file: string;
    /** That file's SQL, comments stripped. */
    code: string;
    /** The same, whitespace normalised — what predicate assertions should match against. */
    flat: string;
    /** Every migration that has ever defined the view, in apply order. */
    chain: string[];
}

/**
 * The newest migration defining `view`, by filename order — which is apply order, because
 * `migration-conventions.test.ts` proves the timestamp prefixes are zero-padded and strictly
 * increasing, so a plain sort is a real ordering rather than a hopeful one.
 *
 * @throws if no migration defines the view — a guard over it would then assert against nothing.
 * @throws if a migration AFTER the resolved one mentions the view without matching the DDL patterns
 *   above. That means a definer form exists which this helper cannot see, and the 2026-09-20
 *   incident is the argument for failing loudly instead of resolving something older.
 */
export function newestViewDefiner(migrationsDir: string, view: string): ViewDefiner {
    const dir = migrationsDir.endsWith('/') ? migrationsDir : migrationsDir + '/';
    const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
    const read = (f: string) => sqlCode(readFileSync(dir + f, 'utf8'));
    const ddl = ddlFor(view);

    const chain = files.filter((f) => ddl.test(read(f)));
    if (chain.length === 0) {
        throw new Error(`No migration defines [${view}] — a guard over it would assert against nothing.`);
    }
    const file = chain[chain.length - 1];

    const mentionsAfter = files.filter((f) => f > file && new RegExp(String.raw`\[${view}\]`).test(read(f)));
    if (mentionsAfter.length > 0) {
        throw new Error(
            `[${view}] is mentioned by migrations AFTER its newest recognised definer ${file}: ` +
            `${mentionsAfter.join(', ')}. Either they redefine it in a form newestViewDefiner does not ` +
            `match — in which case teach it that form — or the guard is now pointed at stale SQL.`,
        );
    }
    const code = read(file);
    return { file, code, flat: squash(code), chain };
}
