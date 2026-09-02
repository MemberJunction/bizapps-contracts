/**
 * Re-papering writes ONE record per verb — a source-level guard for issue #28 items 9 and 10.
 *
 * WHY A SOURCE TEST. `InternalExecute` needs a metadata provider, a `UserInfo` and `RunView`, so its
 * behaviour belongs to an integration tier this package does not have. But both defects were
 * STRUCTURAL, and both are checkable from the source with no database:
 *
 *   1. ITEM 9 — `UnlinkSupersedes(_predecessorID)` in the panel took the clicked contract's ID and
 *      THREW IT AWAY, calling the operation with `PredecessorID: null`, which the server read as
 *      "release every predecessor". Unlinking one of three unlinked all three. An ignored argument is
 *      invisible at a glance and produced no error, which is why it survived review.
 *   2. ITEM 10 — the operation released every OTHER predecessor before linking, on the reasoning that
 *      a single-select picker means a single predecessor. The schema allows many (a consolidated
 *      agreement replacing several), so linking a second contract silently unlinked the first.
 *
 * So this pins the SHAPE the fix depends on: two separately-named inputs, each naming exactly one
 * record; no sentinel that means "all"; no loop that clears predecessors wholesale; and a panel that
 * forwards the ID it was given. Someone reintroducing the release-all behaviour has to delete these
 * tests to do it, which makes it a decision rather than an oversight.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const OP = readFileSync(join(__dirname, '..', 'SupersedeOperation.ts'), 'utf-8');
const PANEL = readFileSync(
    join(__dirname, '..', '..', '..', 'Angular', 'src', 'lib', 'form-panels', 'supersede.panel.ts'),
    'utf-8',
);

/** The body of `InternalExecute`, which is where both defects lived. */
const executeBody = (): string => {
    const start = OP.indexOf('protected override async InternalExecute(');
    expect(start).toBeGreaterThan(-1);
    const end = OP.indexOf('\n    /** Live read of what a contract supersedes', start);
    expect(end).toBeGreaterThan(start);
    return OP.slice(start, end);
};

describe('SupersedeInput — one named target per verb', () => {
    it('declares the two verbs separately', () => {
        expect(OP).toContain('PredecessorID?: string | null;');
        expect(OP).toContain('ReleasePredecessorID?: string | null;');
    });

    it('no longer carries a required nullable PredecessorID whose null meant "release everything"', () => {
        expect(OP).not.toContain('PredecessorID: string | null;');
    });
});

describe('item 9 — release names exactly one record', () => {
    it('the release branch is keyed on ReleasePredecessorID', () => {
        expect(executeBody()).toContain('if (input.ReleasePredecessorID)');
    });

    it('refuses a target this agreement does not actually supersede', () => {
        const body = executeBody();
        // Membership is checked against the live list before anything is written, so a stale panel
        // cannot clear the column on an unrelated contract.
        expect(body).toContain('current.find((c) => same(c.ID, input.ReleasePredecessorID))');
        // The not-found branch returns a Refused result and writes nothing.
        const notFound = body.slice(body.indexOf('if (!target)'), body.indexOf('const previous ='));
        expect(notFound).toContain('Refused:');
        expect(notFound).not.toContain('.Save()');
    });

    it('clears the column exactly once, and only inside the release branch', () => {
        const body = executeBody();
        const clears = body.match(/SupersededByContractID = null/g) ?? [];
        expect(clears).toHaveLength(1);

        const releaseStart = body.indexOf('if (input.ReleasePredecessorID)');
        const linkStart = body.indexOf('if (\n            input.PredecessorID');
        const clearAt = body.indexOf('SupersededByContractID = null');
        expect(clearAt).toBeGreaterThan(releaseStart);
        expect(clearAt).toBeLessThan(linkStart);
    });
});

describe('one verb per call', () => {
    it('refuses both inputs in the same request', () => {
        const body = executeBody();
        expect(body).toContain('if (input.PredecessorID && input.ReleasePredecessorID)');
        expect(body).toMatch(/PredecessorID && input\.ReleasePredecessorID\)[\s\S]{0,400}throw new Error/);
    });

    it('refuses BEFORE reading anything, so a rejected call writes nothing', () => {
        const body = executeBody();
        const guard = body.indexOf('input.PredecessorID && input.ReleasePredecessorID');
        const read = body.indexOf('const current = await this.readSupersedes');
        expect(guard).toBeGreaterThan(-1);
        expect(guard).toBeLessThan(read);
    });

    it('the input contract says they are mutually exclusive', () => {
        expect(OP).toContain('Mutually exclusive with `ReleasePredecessorID`');
    });
});

describe('item 10 — link adds, and leaves existing predecessors alone', () => {
    it('the release-every-other-predecessor loop is gone', () => {
        const body = executeBody();
        // The defect was a loop over the current predecessors that cleared each one before linking.
        expect(body).not.toMatch(/for \(const \w+ of await this\.readSupersedes\(/);
    });

    it('linking an already-linked contract is a no-op rather than a clear-and-reset', () => {
        expect(executeBody()).toContain('!current.some((c) => same(c.ID, input.PredecessorID))');
    });

    it('the panel no longer reports contracts it released while linking', () => {
        expect(PANEL).toContain('this.LinkOk = okMessage;');
        expect(PANEL).not.toContain('Released ${');
    });
});

describe('the panel forwards the ID it was given', () => {
    it('Unlink passes the clicked contract as ReleasePredecessorID', () => {
        expect(PANEL).toContain('public async UnlinkSupersedes(predecessorID: string)');
        expect(PANEL).toContain('{ ReleasePredecessorID: predecessorID }');
    });

    it('the argument is used, not discarded behind an underscore', () => {
        expect(PANEL).not.toContain('UnlinkSupersedes(_predecessorID');
    });

    it('Link passes only the picked contract, and no null sentinel', () => {
        expect(PANEL).toContain('{ PredecessorID: this.PickedPredecessorID }');
        expect(PANEL).not.toContain('this.invoke(null');
    });
});
