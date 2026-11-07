/**
 * The template default's reads and its end-to-end decision.
 *
 *   · #138 — a template whose TYPE is retired is never defaulted: the server refuses a newly selected
 *     template of a retired type, so defaulting one refuses a save the caller never chose.
 *   · #153 — two type changes in quick succession: a call that a later one has superseded decides
 *     nothing, whichever read finishes last.
 */
import { describe, expect, it, vi } from 'vitest';
import type { RunViewParams } from '@memberjunction/core';
import {
    CurrentTemplateFilter,
    CurrentTemplateFilterExcluding,
    CurrentTemplateOrderBy,
    DecideTemplateDefault,
    ReadCurrentTemplateID,
    RetiredTemplateTypeFilter,
    type TemplateViewRunner,
} from '../default-template';

const RETIRED_A = 'AAAAAAAA-0000-4000-8000-0000000000A1';
const RETIRED_B = 'AAAAAAAA-0000-4000-8000-0000000000A2';
const CURRENT = 'CCCCCCCC-0000-4000-8000-00000000000C';
const OURS = 'DDDDDDDD-0000-4000-8000-00000000000D';
const THEIRS = 'EEEEEEEE-0000-4000-8000-00000000000E';

describe('CurrentTemplateFilterExcluding — #138', () => {
    it('is the plain filter when no type is retired', () => {
        expect(CurrentTemplateFilterExcluding([])).toBe(CurrentTemplateFilter);
        expect(CurrentTemplateFilterExcluding([null, undefined, '  '])).toBe(CurrentTemplateFilter);
    });
    it('excludes every retired template type, keeping the Published / usable rule', () => {
        expect(CurrentTemplateFilterExcluding([RETIRED_A, RETIRED_B])).toBe(
            `${CurrentTemplateFilter} AND ContractTemplateTypeID NOT IN ('${RETIRED_A}', '${RETIRED_B}')`,
        );
    });
    it('escapes quotes, so an ID cannot close the literal', () => {
        expect(CurrentTemplateFilterExcluding(["x' OR 1=1 --"])).toContain(`'x'' OR 1=1 --'`);
    });
    it('reads retired types by the value the server refuses on', () => {
        expect(RetiredTemplateTypeFilter).toBe(`Status = 'Inactive'`);
    });
});

/** A runner that answers by entity name and records what it was asked. */
function runner(answers: {
    types?: { Success: boolean; Results?: { ID: string }[]; ErrorMessage?: string };
    templates?: { Success: boolean; Results?: { ID: string }[]; ErrorMessage?: string };
}) {
    const calls: RunViewParams[] = [];
    const run: TemplateViewRunner = {
        RunView: vi.fn(async (params: RunViewParams) => {
            calls.push(params);
            const a = params.EntityName === 'MJ_BizApps_Contracts: Contract Template Types' ? answers.types : answers.templates;
            return (a ?? { Success: true, Results: [] }) as never;
        }),
    };
    return { run, calls };
}

describe('ReadCurrentTemplateID — #138', () => {
    it('skips templates of a retired type', async () => {
        const { run, calls } = runner({
            types: { Success: true, Results: [{ ID: RETIRED_A }] },
            templates: { Success: true, Results: [{ ID: CURRENT }] },
        });
        const read = await ReadCurrentTemplateID(run);
        expect(read).toEqual({ Success: true, TemplateID: CURRENT });
        expect(calls[0].ExtraFilter).toBe(RetiredTemplateTypeFilter);
        expect(calls[1].ExtraFilter).toBe(CurrentTemplateFilterExcluding([RETIRED_A]));
        expect(calls[1].OrderBy).toBe(CurrentTemplateOrderBy);
        expect(calls[1].MaxRows).toBe(1);
    });
    it('returns no template when only retired-type templates exist', async () => {
        const { run } = runner({ types: { Success: true, Results: [{ ID: RETIRED_A }] }, templates: { Success: true, Results: [] } });
        expect(await ReadCurrentTemplateID(run)).toEqual({ Success: true, TemplateID: null });
    });
    it('defaults nothing when the retired types cannot be read, and does not query templates', async () => {
        const { run, calls } = runner({ types: { Success: false, ErrorMessage: 'boom' } });
        expect(await ReadCurrentTemplateID(run)).toEqual({ Success: false, TemplateID: null, ErrorMessage: 'boom' });
        expect(calls).toHaveLength(1);
    });
    it('reports a failed template read', async () => {
        const { run } = runner({ templates: { Success: false, ErrorMessage: 'nope' } });
        expect(await ReadCurrentTemplateID(run)).toEqual({ Success: false, TemplateID: null, ErrorMessage: 'nope' });
    });
    it('reports a thrown read instead of throwing', async () => {
        const run: TemplateViewRunner = { RunView: vi.fn(async () => { throw new Error('down'); }) };
        expect(await ReadCurrentTemplateID(run)).toEqual({ Success: false, TemplateID: null, ErrorMessage: 'down' });
    });
});

describe('DecideTemplateDefault', () => {
    const NEW_EMPTY = { isSaved: false, currentTemplateID: null, lastDefaultedID: null };

    it('defaults the current template on a new contract whose type requires one', async () => {
        const current = vi.fn(async () => CURRENT);
        expect(await DecideTemplateDefault(NEW_EMPTY, async () => true, current)).toEqual({ Action: 'default', TemplateID: CURRENT });
        expect(current).toHaveBeenCalledOnce();
    });
    it('withdraws our own default when the type stops requiring one, without reading templates', async () => {
        const current = vi.fn(async () => CURRENT);
        const state = { isSaved: false, currentTemplateID: OURS, lastDefaultedID: OURS };
        expect(await DecideTemplateDefault(state, async () => false, current)).toEqual({ Action: 'withdraw' });
        expect(current).not.toHaveBeenCalled();
    });
    it('does nothing when the type could not be read', async () => {
        expect(await DecideTemplateDefault(NEW_EMPTY, async () => null, async () => CURRENT)).toEqual({ Action: 'none' });
    });
    it('reads nothing for a saved contract or a hand-picked template', async () => {
        const required = vi.fn(async () => true);
        await DecideTemplateDefault({ ...NEW_EMPTY, isSaved: true }, required, async () => CURRENT);
        await DecideTemplateDefault({ ...NEW_EMPTY, currentTemplateID: THEIRS }, required, async () => CURRENT);
        expect(required).not.toHaveBeenCalled();
    });

    describe('#153 — a superseded call decides nothing', () => {
        it('when superseded during the type read: no default, and the template is not read', async () => {
            let current = true;
            const templates = vi.fn(async () => CURRENT);
            const decision = await DecideTemplateDefault(
                NEW_EMPTY,
                async () => {
                    current = false; // a later type change started while this read was in flight
                    return true;
                },
                templates,
                () => current,
            );
            expect(decision).toEqual({ Action: 'none' });
            expect(templates).not.toHaveBeenCalled();
        });
        it('when superseded during the type read of a withdrawal: the default stays', async () => {
            let current = true;
            const state = { isSaved: false, currentTemplateID: OURS, lastDefaultedID: OURS };
            const decision = await DecideTemplateDefault(
                state,
                async () => {
                    current = false;
                    return false;
                },
                async () => CURRENT,
                () => current,
            );
            expect(decision).toEqual({ Action: 'none' });
        });
        it('when superseded during the template read: no default', async () => {
            let current = true;
            const decision = await DecideTemplateDefault(
                NEW_EMPTY,
                async () => true,
                async () => {
                    current = false;
                    return CURRENT;
                },
                () => current,
            );
            expect(decision).toEqual({ Action: 'none' });
        });
        it('the older read finishing last loses to the newer call', async () => {
            // Panel-shaped: a sequence counter, two calls, the first one's read resolved last.
            let seq = 0;
            const start = () => {
                const mine = ++seq;
                return () => mine === seq;
            };
            let releaseOlder!: (v: boolean) => void;
            const olderRead = new Promise<boolean>((r) => (releaseOlder = r));

            const older = DecideTemplateDefault(NEW_EMPTY, () => olderRead, async () => CURRENT, start());
            const newer = DecideTemplateDefault(
                { isSaved: false, currentTemplateID: null, lastDefaultedID: null },
                async () => false, // the newer type needs no template
                async () => CURRENT,
                start(),
            );
            expect(await newer).toEqual({ Action: 'none' });
            releaseOlder(true);
            expect(await older).toEqual({ Action: 'none' });
        });
    });
});
