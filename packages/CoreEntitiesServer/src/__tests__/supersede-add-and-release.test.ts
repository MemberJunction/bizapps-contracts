/**
 * `Contracts.Supersede` — linking ADDS, and releasing targets ONE contract.
 *
 * WHY THIS EXISTS. contracts#28 reported two defects in the same operation, and they are opposite
 * halves of one wrong idea:
 *
 *   item 9  — "Unlink CTR-0001" also unlinked CTR-0002. The panel passed the clicked ID to a handler
 *             that discarded it and asked the server to release EVERY predecessor.
 *   item 10 — linking CTR-0002 silently released CTR-0001, with the only trace a "Released …" suffix
 *             on a success message that reads like reassurance.
 *
 * Both came from a deliberate, documented decision — the module argued REPLACE, NOT ADD from the fact
 * that the picker is a single-select. Reversing a decision is exactly the change that a comment
 * survives and the code forgets, so these assertions are written against the BEHAVIOUR Andrew
 * specified ("a contract may supersede many earlier contracts; Link adds"), not against the new code.
 *
 * WHY A FAKE PROVIDER RATHER THAN THE DATABASE. What changed is which records get written, and that is
 * observable without SQL: the fake records every save. The DB tier cannot run here anyway — the local
 * instance sits four migrations behind the repo — and a rule this cheap to test should not wait on it.
 * The fake deliberately allows what the database would allow, so it cannot make a broken operation
 * look correct by refusing writes the server would accept.
 */
import { describe, expect, it } from 'vitest';
import { SupersedeOperation, type SupersedeInput, type SupersedeOutput } from '../SupersedeOperation.js';

type Row = { ID: string; ContractNumber: string; SupersededByContractID: string | null };

/** An in-memory contract table that behaves the way the real one does for these paths. */
function makeWorld(rows: Row[]) {
    const table = new Map(rows.map((r) => [r.ID.toLowerCase(), { ...r }]));
    const saves: Array<{ ID: string; SupersededByContractID: string | null }> = [];

    const entity = () => {
        let me: Row | null = null;
        const api = {
            get ID() { return me?.ID ?? null; },
            get ContractNumber() { return me?.ContractNumber ?? null; },
            get SupersededByContractID() { return me?.SupersededByContractID ?? null; },
            set SupersededByContractID(v: string | null) { if (me) me.SupersededByContractID = v; },
            LatestResult: { Message: '' },
            async Load(id: string) {
                me = table.get(String(id).toLowerCase()) ?? null;
                return !!me;
            },
            /** Mirrors ContractEntity.Supersede: two guards, then the field write. */
            Supersede(successor: { ID: string | null }) {
                if (!successor?.ID) throw new Error('the replacement contract must be saved first');
                if (successor.ID === me?.ID) throw new Error('cannot supersede itself');
                if (me) me.SupersededByContractID = successor.ID;
            },
            async Save() {
                if (!me) return false;
                saves.push({ ID: me.ID, SupersededByContractID: me.SupersededByContractID });
                return true;
            },
        };
        return api;
    };

    const provider = {
        async GetEntityObject() { return entity(); },
        // What RunView.FromMetadataProvider(provider) ends up calling. The operation only ever asks
        // "which contracts name this successor", so that is the only filter honoured here.
        async RunView(params: { ExtraFilter?: string }) {
            const m = /SupersededByContractID = '([^']+)'/.exec(params?.ExtraFilter ?? '');
            const successorID = m?.[1] ?? '';
            const Results = [...table.values()]
                .filter((r) => (r.SupersededByContractID ?? '').toLowerCase() === successorID.toLowerCase())
                .map((r) => ({ ID: r.ID, ContractNumber: r.ContractNumber }))
                .sort((a, b) => a.ContractNumber.localeCompare(b.ContractNumber));
            return { Success: true, Results };
        },
    };

    return { table, saves, provider };
}

const SUCCESSOR = 'S-100';
/** Two predecessors already superseded by the successor — the consolidation case both bugs needed. */
const TWO_PREDECESSORS: Row[] = [
    { ID: SUCCESSOR, ContractNumber: 'CTR-0100', SupersededByContractID: null },
    { ID: 'P-1', ContractNumber: 'CTR-0001', SupersededByContractID: SUCCESSOR },
    { ID: 'P-2', ContractNumber: 'CTR-0002', SupersededByContractID: SUCCESSOR },
    { ID: 'P-3', ContractNumber: 'CTR-0003', SupersededByContractID: null },
];

async function run(rows: Row[], input: SupersedeInput) {
    const world = makeWorld(rows);
    const op = new SupersedeOperation() as unknown as {
        InternalExecute(i: SupersedeInput, p: unknown, u: unknown, c: unknown): Promise<SupersedeOutput>;
    };
    const out = await op.InternalExecute(input, world.provider, {} as never, {} as never);
    return { out, world };
}

describe('item 9 — releasing targets exactly the contract named', () => {
    it('releases the one asked for and leaves the other superseded', async () => {
        const { out, world } = await run(TWO_PREDECESSORS, {
            SuccessorID: SUCCESSOR,
            ReleasePredecessorID: 'P-1',
        });
        expect(out.Released).toEqual(['CTR-0001']);
        expect(world.table.get('p-1')!.SupersededByContractID).toBeNull();
        expect(
            world.table.get('p-2')!.SupersededByContractID,
            'CTR-0002 was not named, so it must still be superseded — this is the bug',
        ).toBe(SUCCESSOR);
        expect(out.Supersedes.map((r) => r.ContractNumber)).toEqual(['CTR-0002']);
    });

    it('writes to exactly one record', async () => {
        // Stronger than checking the end state: it pins that the other row was never touched, so a
        // clear-then-rewrite that happens to land on the same values could not pass.
        const { world } = await run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, ReleasePredecessorID: 'P-2' });
        expect(world.saves.map((s) => s.ID)).toEqual(['P-2']);
    });

    it('refuses when the named contract is not actually a predecessor', async () => {
        const { out, world } = await run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, ReleasePredecessorID: 'P-3' });
        expect(out.Refused).toMatch(/not superseded by this agreement/i);
        expect(world.saves, 'nothing should be written').toEqual([]);
    });
});

describe('item 10 — linking adds, and never releases', () => {
    it('adds a third predecessor while both existing ones stay linked', async () => {
        const { out, world } = await run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, PredecessorID: 'P-3' });
        expect(out.Released, 'linking must release nothing at all').toEqual([]);
        expect(out.Supersedes.map((r) => r.ContractNumber)).toEqual(['CTR-0001', 'CTR-0002', 'CTR-0003']);
        expect(world.table.get('p-1')!.SupersededByContractID).toBe(SUCCESSOR);
        expect(world.table.get('p-2')!.SupersededByContractID).toBe(SUCCESSOR);
    });

    it('writes only the newly linked record', async () => {
        const { world } = await run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, PredecessorID: 'P-3' });
        expect(world.saves.map((s) => s.ID)).toEqual(['P-3']);
    });

    it('re-linking a contract that is already a predecessor changes nothing observable', async () => {
        const { out } = await run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, PredecessorID: 'P-1' });
        expect(out.Released).toEqual([]);
        expect(out.Supersedes.map((r) => r.ContractNumber)).toEqual(['CTR-0001', 'CTR-0002']);
    });
});

describe('the shapes that must not be read as "release everything"', () => {
    it('refuses a call carrying neither ID', async () => {
        // The old wire shape. A caller still sending `{ SuccessorID, PredecessorID: null }` meant
        // "clear every predecessor"; silently doing nothing would be the worst available outcome.
        await expect(run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, PredecessorID: null })).rejects.toThrow(
            /release every predecessor/i,
        );
    });

    it('leaves every predecessor intact when it refuses', async () => {
        const world = makeWorld(TWO_PREDECESSORS);
        const op = new SupersedeOperation() as unknown as {
            InternalExecute(i: SupersedeInput, p: unknown, u: unknown, c: unknown): Promise<SupersedeOutput>;
        };
        await expect(
            op.InternalExecute({ SuccessorID: SUCCESSOR }, world.provider, {} as never, {} as never),
        ).rejects.toThrow();
        expect(world.saves).toEqual([]);
        expect(world.table.get('p-1')!.SupersededByContractID).toBe(SUCCESSOR);
        expect(world.table.get('p-2')!.SupersededByContractID).toBe(SUCCESSOR);
    });

    it('refuses a contract superseding itself instead of quietly reporting success', async () => {
        const { out, world } = await run(TWO_PREDECESSORS, { SuccessorID: SUCCESSOR, PredecessorID: SUCCESSOR });
        expect(out.Refused).toMatch(/cannot supersede itself/i);
        expect(world.saves).toEqual([]);
    });
});
