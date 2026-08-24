/**
 * The self-reference rule must be checked HERE, wholly, and by value — a source-level guard.
 *
 * WHY A SOURCE TEST. The rule itself (`refuseSelfReferences`) needs a `BaseEntity` instance and a
 * provider, so its behaviour belongs to the server tier. But the two things that went wrong were
 * STRUCTURAL, and both are checkable from the source with no database:
 *
 *   1. The guard used to be absent, and `ParentContractID -> self` was left entirely to the GENERATED
 *      validator — which is LLM-authored (`CodeGen: Check Constraint Parser`) and compares UUIDs with
 *      `===`, so it misses the case where the two ids differ only in casing (MJ#3984). Deferring a rule
 *      to code this class does not own is what turned an invalid state into a silent success.
 *   2. A later version covered ONLY the casing-differs case and returned early otherwise, still on the
 *      assumption that the generated validator had the rest. Same defect, smaller.
 *
 * So this pins the shape rather than the behaviour: the guard exists, it compares by VALUE, it is
 * called before the two guards that skip the self case, and no comparison in this file uses `===` on
 * an id. If MJ#3984 is fixed and someone deletes the guard, they have to delete this test too — which
 * is the point, because that makes it a decision rather than an oversight.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const SOURCE = readFileSync(join(__dirname, '..', 'ContractEntityServer.ts'), 'utf-8');

describe('self-reference guard — structure', () => {
    it('the guard exists', () => {
        expect(SOURCE).toContain('private refuseSelfReferences(');
    });

    it('covers BOTH self-referential axes, not just supersession', () => {
        const body = SOURCE.slice(SOURCE.indexOf('private refuseSelfReferences('));
        const end = body.indexOf('\n    }');
        const guard = body.slice(0, end);
        expect(guard).toContain("Field: 'ParentContractID'");
        expect(guard).toContain("Field: 'SupersededByContractID'");
    });

    it('compares ids by VALUE, so a casing difference cannot slip through', () => {
        const body = SOURCE.slice(SOURCE.indexOf('private refuseSelfReferences('));
        const guard = body.slice(0, body.indexOf('\n    }'));
        expect(guard).toContain('UUIDsEqual(');
    });

    it('reports unconditionally — no early return that defers the rest to another layer', () => {
        const body = SOURCE.slice(SOURCE.indexOf('private refuseSelfReferences('));
        const guard = body.slice(0, body.indexOf('\n    }'));
        // The only `continue` is the not-a-violation case; there must be no bare `return` handing the
        // rule off to somebody else.
        expect(guard).not.toMatch(/\breturn\b/);
        expect(guard).toContain('ValidationErrorType.Failure');
    });

    it('runs BEFORE the two guards that skip the self case', () => {
        const owner = SOURCE.indexOf('this.refuseSelfReferences(result)');
        const cycles = SOURCE.indexOf('await this.refuseLineageCycles(result)');
        const level = SOURCE.indexOf('await this.refuseCrossLevelSupersession(result)');
        expect(owner).toBeGreaterThan(-1);
        expect(owner).toBeLessThan(cycles);
        expect(owner).toBeLessThan(level);
    });

    it('no id comparison in CODE uses === or !==', () => {
        // Comment lines are excluded on purpose: this file QUOTES the buggy generated comparison to
        // explain MJ#3984, and a test that flags its own documentation would push someone to delete the
        // explanation rather than fix a bug.
        const offenders = SOURCE.split('\n')
            .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
            .filter((l) => /[!=]==\s*this\.ID\b/.test(l) || /this\.ID\s*[!=]==/.test(l));
        expect(offenders).toEqual([]);
    });
});
