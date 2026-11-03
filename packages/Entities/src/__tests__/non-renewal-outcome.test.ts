/**
 * Issue #159: the renewal-risk label `NonRenewalOutcome` is a stored column, not a view expression.
 *
 * The rule lives once, in `fnContractNonRenewalOutcome`, with the day it is judged on as an argument.
 * These tests state the rule here, by hand, and check the committed migration against that statement,
 * the same way `contract-state.test.ts` checks `State`. Whether the SQL evaluates that way is proved
 * against a database by `test-harnesses/state-derivation.mjs`, whose fixtures now read the stored
 * column through the view.
 */
import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { handWritten, newestViewDefiner, sqlCode, squash } from './helpers/view-definer.js';

const MIGRATIONS_DIR = fileURLToPath(new URL('../../../../migrations/', import.meta.url));
const METADATA_DIR = fileURLToPath(new URL('../../../../metadata/', import.meta.url));

/** The migration that creates the function, its hand-written half, comments stripped and squashed. */
function definerOf(object: string): { file: string; flat: string } {
    const pattern = new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?(?:FUNCTION|PROCEDURE|TRIGGER)\s+\[[^\]]+\]\.\[${object}\]`, 'i');
    const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
    const hits = files.filter((f) => pattern.test(sqlCode(readFileSync(MIGRATIONS_DIR + f, 'utf8'))));
    expect(hits, `exactly one migration creates ${object}`).toHaveLength(1);
    const file = hits[0];
    return { file, flat: squash(sqlCode(handWritten(readFileSync(MIGRATIONS_DIR + file, 'utf8')))) };
}

describe('NonRenewalOutcome is stored and recorded by the database (#159)', () => {
    const fn = definerOf('fnContractNonRenewalOutcome');

    it('the view no longer computes the label, so nothing in it reads the clock for training', () => {
        const view = newestViewDefiner(MIGRATIONS_DIR, 'vwContracts');
        const start = view.flat.indexOf('VIEW [${flyway:defaultSchema}].[vwContracts]');
        expect(start).toBeGreaterThanOrEqual(0);
        const statement = view.flat.slice(start, view.flat.indexOf(' GO ', start));
        expect(statement).not.toMatch(/AS \[?NonRenewalOutcome\]?/);
        expect(statement).toContain('SELECT g.*');
    });

    it('adds the column with its 0/1 check inline', () => {
        expect(fn.flat).toContain(
            squash(`ALTER TABLE [\${flyway:defaultSchema}].[Contract] ADD [NonRenewalOutcome] INT NULL
                    CONSTRAINT [CK_Contract_NonRenewalOutcome] CHECK ([NonRenewalOutcome] IN (0, 1));`),
        );
    });

    // Superseded outranks terminated, the reverse of State: a renewal both terminates the old paper and
    // points it at its successor, and for training that is renewed (0). Terminated is `<=`, expired `<`,
    // the same boundaries State uses.
    const RULE = [
        'WHEN @SupersededByContractID IS NOT NULL THEN 0',
        'WHEN @TerminatedDate IS NOT NULL AND @TerminatedDate <= @AsOf THEN 1',
        'WHEN @EndDate IS NOT NULL AND @EndDate < @AsOf THEN 1',
        'ELSE NULL',
    ];

    it.each(RULE)('the rule says: %s', (branch) => {
        expect(fn.flat).toContain(squash(branch));
    });

    it('evaluates the branches in that order', () => {
        const positions = RULE.map((b) => fn.flat.indexOf(squash(b)));
        expect(positions.every((p) => p >= 0)).toBe(true);
        expect(positions).toEqual([...positions].sort((a, b) => a - b));
    });

    it('takes the day as an argument, so the rule itself never reads the clock', () => {
        const body = fn.flat.slice(fn.flat.indexOf('[fnContractNonRenewalOutcome] ('), fn.flat.indexOf('CREATE OR ALTER VIEW'));
        expect(body).toContain('@AsOf DATE');
        expect(body).not.toMatch(/GETUTCDATE|GETDATE|SYSDATETIME|fnBusinessToday/i);
    });

    it('records on every insert and update, and the hourly procedure applies the same function', () => {
        expect(definerOf('trgContract_RecordNonRenewalOutcome').file).toBe(fn.file);
        expect(definerOf('spRecordContractNonRenewalOutcomes').file).toBe(fn.file);
        expect(fn.flat).toContain('AFTER INSERT, UPDATE');
        // Both writers judge on the business day and call the one function.
        const calls = fn.flat.match(/\[fnContractNonRenewalOutcome\]\( c\.\[SupersededByContractID\], c\.\[TerminatedDate\], c\.\[EndDate\], bt\.\[Today\]\)/g) ?? [];
        expect(calls.length).toBe(3);
        expect(fn.flat).not.toMatch(/ROLLBACK/i);
    });

    it('backfills every existing contract', () => {
        expect(fn.flat).toContain(squash('EXEC [${flyway:defaultSchema}].[spRecordContractNonRenewalOutcomes];'));
    });

    it('the scheduled job runs the action that calls the procedure', () => {
        const action = JSON.parse(readFileSync(METADATA_DIR + 'actions/.contracts-renewal-outcome-actions.json', 'utf8'))[0];
        const job = JSON.parse(readFileSync(METADATA_DIR + 'scheduled-jobs/.contracts-renewal-outcome-scheduled-jobs.json', 'utf8'))[0];
        expect(action.fields.DriverClass).toBe('Contracts.RecordNonRenewalOutcomes');
        expect(JSON.parse(job.fields.Configuration).ActionID).toBe(action.primaryKey.ID);
        expect(job.fields.Status).toBe('Active');
        const order: string[] = JSON.parse(readFileSync(METADATA_DIR + '.mj-sync.json', 'utf8')).directoryOrder;
        expect(order.indexOf('action-categories')).toBeLessThan(order.indexOf('actions'));
        expect(order.indexOf('actions')).toBeLessThan(order.indexOf('scheduled-jobs'));
    });
});
