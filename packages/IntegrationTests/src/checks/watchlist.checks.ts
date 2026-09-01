/**
 * contracts-watchlist — derived column VALUES, not just presence.
 *
 * `State` / `IsAwaitingDocument` / `DaysToEnd` / `RenewalNoticeDeadline` / `IsInCancellationWindow`
 * are projections on vwContracts. IsChangeOrder was removed (it restated ParentContractID); W8
 * asserts the FK instead.
 *
 * Reads the committed CTR-WORLD rows. Run contracts-world first.
 */
import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration/registry';
import { E_CONTRACT, FindRows, Quote, ResolveContractsFixture, WORLD_NOTE } from '../fixture.js';

type Ctx = IntegrationCheckContext;

interface WatchRow {
    ID: string;
    Notes: string;
    State: string;
    IsAwaitingDocument: boolean | number;
    DaysToEnd: number | null;
    RenewalNoticeDeadline: Date | string | null;
    IsInCancellationWindow: boolean | number;
    ParentContractID: string | null;
    EndDate: Date | string | null;
    RenewalNoticeDays: number | null;
    CancellationWindowDays: number | null;
}

function flag(value: boolean | number | null | undefined): boolean {
    return value === true || value === 1;
}

export const WatchlistChecks: NamedCheck[] = [
    {
        Id: 'contracts-watchlist.W1',
        Name: 'W1 — an Order Form with no linked file is awaiting a document',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const row = await load(ctx, WORLD_NOTE.awaitingDoc);
            Assert(flag(row.IsAwaitingDocument), `${WORLD_NOTE.awaitingDoc} should be awaiting a document`);
        },
    },
    {
        Id: 'contracts-watchlist.W2',
        Name: 'W2 — a Payment Link is never awaiting a document',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const row = await load(ctx, WORLD_NOTE.paymentLink);
            Assert(!flag(row.IsAwaitingDocument), `${WORLD_NOTE.paymentLink} must not sit on the awaiting-document list`);
        },
    },
    {
        Id: 'contracts-watchlist.W3',
        Name: 'W3 — DaysToEnd equals DATEDIFF(day, UTC today, EndDate)',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const row = await load(ctx, WORLD_NOTE.activeMsa);
            Assert(row.EndDate != null, 'active-msa has no EndDate');
            Assert(row.DaysToEnd != null, 'active-msa has no DaysToEnd');
            const expected = diffDays(ymd(new Date())!, ymd(row.EndDate)!);
            AssertEqual(
                Number(row.DaysToEnd),
                expected,
                `active-msa DaysToEnd ${row.DaysToEnd} !== DATEDIFF to EndDate ${expected}`,
            );
        },
    },
    {
        Id: 'contracts-watchlist.W4',
        Name: 'W4 — RenewalNoticeDeadline is EndDate minus RenewalNoticeDays',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const row = await load(ctx, WORLD_NOTE.activeMsa);
            Assert(row.RenewalNoticeDeadline != null, 'active-msa has no RenewalNoticeDeadline');
            AssertEqual(Number(row.RenewalNoticeDays), 60, 'active-msa RenewalNoticeDays should be 60');
            // End +120, notice 60 → deadline in 60 days. Compare as UTC yyyy-mm-dd.
            const deadline = ymd(row.RenewalNoticeDeadline);
            const end = ymd(row.EndDate);
            Assert(!!deadline && !!end, 'active-msa deadline/end did not convert to a date');
            const expected = shiftYmd(end!, -60);
            AssertEqual(deadline, expected, `RenewalNoticeDeadline ${deadline} !== EndDate-60 ${expected}`);
        },
    },
    {
        Id: 'contracts-watchlist.W5',
        Name: 'W5 — today inside the cancellation window sets IsInCancellationWindow',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const row = await load(ctx, WORLD_NOTE.cancelWindow);
            Assert(flag(row.IsInCancellationWindow), `${WORLD_NOTE.cancelWindow} should be in the cancellation window`);
            const control = await load(ctx, WORLD_NOTE.activeMsa);
            Assert(
                !flag(control.IsInCancellationWindow),
                'active-msa (end in 120 days, window 30) should not be in the cancellation window',
            );
        },
    },
    {
        Id: 'contracts-watchlist.W6',
        Name: 'W6 — State covers Active, Executed, Draft, Expired, Terminated, Superseded',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const expected: Array<[string, string]> = [
                [WORLD_NOTE.activeMsa, 'Active'],
                [WORLD_NOTE.executedFuture, 'Executed'],
                [WORLD_NOTE.draft, 'Draft'],
                [WORLD_NOTE.expired, 'Expired'],
                [WORLD_NOTE.terminated, 'Terminated'],
                [WORLD_NOTE.supersededPred, 'Superseded'],
            ];
            for (const [notes, state] of expected) {
                const row = await load(ctx, notes);
                AssertEqual(row.State, state, `${notes} State = ${row.State}, expected ${state}`);
            }
        },
    },
    {
        Id: 'contracts-watchlist.W7',
        Name: 'W7 — notice window passed: deadline is in the past, contract still Active',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const row = await load(ctx, WORLD_NOTE.noticePassed);
            AssertEqual(row.State, 'Active', 'notice-passed should still be Active');
            Assert(row.RenewalNoticeDeadline != null, 'notice-passed has no deadline');
            Assert(ymd(row.RenewalNoticeDeadline)! < ymd(new Date())!, 'notice-passed deadline should already have elapsed');
            Assert(Number(row.DaysToEnd) > 0, 'notice-passed should still have days left on the term');
        },
    },
    {
        Id: 'contracts-watchlist.W8',
        Name: 'W8 — a change order names its parent (the structural fact IsChangeOrder used to restate)',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const child = await load(ctx, WORLD_NOTE.changeOrder);
            const parent = await load(ctx, WORLD_NOTE.activeMsa);
            Assert(!!child.ParentContractID, 'change-order has no ParentContractID');
            Assert(
                child.ParentContractID!.toLowerCase() === parent.ID.toLowerCase(),
                `change-order parent ${child.ParentContractID} !== active-msa ${parent.ID}`,
            );
        },
    },
];

async function load(ctx: Ctx, notes: string): Promise<WatchRow> {
    const rows = await FindRows<WatchRow>(
        ctx,
        E_CONTRACT,
        `Notes = '${Quote(notes)}'`,
        [
            'ID',
            'Notes',
            'State',
            'IsAwaitingDocument',
            'DaysToEnd',
            'RenewalNoticeDeadline',
            'IsInCancellationWindow',
            'ParentContractID',
            'EndDate',
            'RenewalNoticeDays',
            'CancellationWindowDays',
        ],
    );
    Assert(rows.length === 1, `watchlist: expected one row for ${notes}, found ${rows.length}. Run contracts-world first.`);
    return rows[0];
}

function ymd(value: Date | string | null | undefined): string | null {
    if (value == null) return null;
    if (typeof value === 'string') return value.slice(0, 10);
    return value.toISOString().slice(0, 10);
}

function shiftYmd(iso: string, days: number): string {
    const [y, m, d] = iso.split('-').map((n) => Number(n));
    const dt = new Date(Date.UTC(y, m - 1, d + days));
    return dt.toISOString().slice(0, 10);
}

/** Same as SQL DATEDIFF(day, from, to) on date-only values. */
function diffDays(fromYmd: string, toYmd: string): number {
    const from = Date.parse(`${fromYmd}T00:00:00Z`);
    const to = Date.parse(`${toYmd}T00:00:00Z`);
    return Math.round((to - from) / 86_400_000);
}

for (const check of WatchlistChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-watchlist', {
    Setup: async (ctx) => {
        await ResolveContractsFixture(ctx);
        const sample = await FindRows<{ ID: string }>(ctx, E_CONTRACT, `Notes = '${Quote(WORLD_NOTE.activeMsa)}'`, ['ID']);
        Assert(
            sample.length === 1,
            'contracts-watchlist needs CTR-WORLD. Run `node test-harnesses/integration.mjs contracts-world` first.',
        );
    },
    Teardown: async () => undefined,
});
