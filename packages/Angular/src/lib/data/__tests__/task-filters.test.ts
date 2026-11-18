/**
 * The open-task and overdue-task filter fragments, run through the screen MJ 6.2's GraphQL boundary
 * applies to every client `ExtraFilter`.
 *
 * MJ 6.2 parses a client filter and accepts a FROM item only when it names an entity base view
 * (`ClientClauseScreen.AssertClauseUsesEntityBaseViews`, called from
 * `ResolverBase.assertClientClauseUsesEntityBaseViews`). `HasOverdueTask` used to read the business
 * day with a subquery on `[__mj_BizAppsCommon].[fnBusinessToday]()` inside its EXISTS, so the whole
 * filter was refused and the dashboard tile and the grid pill raised an error. It now calls the
 * scalar `[__mj_BizAppsCommon].[fnBusinessDayOf](SYSDATETIMEOFFSET())`, which the screen accepts.
 *
 * The screen is called here without a user, which skips its permission checks (read access to Task
 * Links and Tasks, no row filter, no denied fields) and keeps the shape checks: one read-only
 * fragment whose FROM items are all base views of the entities passed in.
 */
import { describe, expect, it, vi } from 'vitest';
import type { EntityInfo, IMetadataProvider } from '@memberjunction/core';
import { ClientClauseScreen } from '@memberjunction/generic-database-provider';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../entity-names';

const TYPE_ID = '22222222-0000-4000-8000-000000000002';

vi.mock('../provider', () => ({
    ScopedRunView: () => ({
        RunView: async () => ({ Success: true, Results: [{ ID: TYPE_ID }] }),
    }),
}));

const { BuildOpenTaskFilters } = await import('../task-filters');

/** The three entities the builder reads, with the base views a host carries. */
const ENTITIES = [
    {
        ID: '5DEB0B11-ED6C-48B3-9200-F4441396C5E2',
        Name: MJC_ENTITIES.Contract,
        SchemaName: '__mj_BizAppsContracts',
        BaseView: 'vwContracts',
    },
    {
        ID: '33333333-0000-4000-8000-000000000003',
        Name: MJC_FOREIGN_ENTITIES.TaskLink,
        SchemaName: '__mj_BizAppsTasks',
        BaseView: 'vwTaskLinks',
    },
    {
        ID: '44444444-0000-4000-8000-000000000004',
        Name: MJC_FOREIGN_ENTITIES.Task,
        SchemaName: '__mj_BizAppsTasks',
        BaseView: 'vwTasks',
    },
] as unknown as EntityInfo[];

const provider = { Entities: ENTITIES } as unknown as IMetadataProvider;

/** The boundary screen, as the GraphQL resolver applies it to an `ExtraFilter`. */
const screen = (filter: string) =>
    ClientClauseScreen.AssertClauseUsesEntityBaseViews(
        filter,
        'ExtraFilter',
        ENTITIES,
        ClientClauseScreen.DialectFor(null),
    );

describe('BuildOpenTaskFilters', () => {
    it('compares DueAt with the business day, resolved in SQL', async () => {
        const filters = await BuildOpenTaskFilters(provider);
        expect(filters?.HasOverdueTask).toContain('t.DueAt < [__mj_BizAppsCommon].[fnBusinessDayOf](SYSDATETIMEOFFSET())');
    });

    it('reads no table function and no UTC clock', async () => {
        const filters = await BuildOpenTaskFilters(provider);
        expect(filters?.HasOverdueTask).not.toMatch(/fnBusinessToday|GETUTCDATE|GETDATE/i);
    });

    it('narrows the open-task filter and nothing else', async () => {
        const filters = await BuildOpenTaskFilters(provider);
        const open = filters!.HasOpenTask;
        expect(filters!.HasOverdueTask).toBe(
            open.slice(0, -1) + ' AND t.DueAt < [__mj_BizAppsCommon].[fnBusinessDayOf](SYSDATETIMEOFFSET()))',
        );
    });

    it.each(['HasOpenTask', 'HasOverdueTask'] as const)('%s passes MJ 6.2’s client-filter screen', async (key) => {
        const filters = await BuildOpenTaskFilters(provider);
        expect(() => screen(filters![key])).not.toThrow();
    });

    it('the inline function call it replaced is refused by the same screen', async () => {
        // The regression, kept as evidence the screen above is the one that matters: the previous
        // fragment differs only in where "today" comes from.
        const filters = await BuildOpenTaskFilters(provider);
        const previous = filters!.HasOverdueTask.replace(
            '[__mj_BizAppsCommon].[fnBusinessDayOf](SYSDATETIMEOFFSET())',
            '(SELECT b.[Today] FROM [__mj_BizAppsCommon].[fnBusinessToday]() b)',
        );
        expect(() => screen(previous)).toThrow(/fnBusinessToday/);
    });

    it('returns null when the Tasks app is not installed', async () => {
        const contractsOnly = { Entities: ENTITIES.slice(0, 1) } as unknown as IMetadataProvider;
        expect(await BuildOpenTaskFilters(contractsOnly)).toBeNull();
    });
});
