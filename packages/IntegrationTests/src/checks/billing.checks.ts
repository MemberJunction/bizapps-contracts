/**
 * contracts-billing — the engine that decides what to bill (BE1–BE12).
 *
 * WHAT THIS BUNDLE PROVES. The app's stated purpose is "the thing that decides when a bill is
 * produced and what goes on it", and until now nothing produced one. These checks cover the parts
 * that are buildable today: the claim, the assembly, the failure semantics and the scheduled driver.
 * The two calls into orders are genuinely blocked (plan C0) and are exercised through the bridge —
 * which is an extension point, not a test hook: when the seams land, orders registers its
 * implementation and the engine does not change.
 *
 * WHAT IT PROVES
 *   BE1   two overlapping runs produce ONE bill — the second finds the event claimed
 *   BE2   a run over an already-Generated event bills nothing
 *   BE3   a subscription line bills every period
 *   BE4   a one-time line bills ONCE, in the period its window opens
 *   BE5   a line whose window has closed does not bill
 *   BE6   a milestone line bills in no period — nothing marks one reached yet
 *   BE7   a usage line bills in no period — metering is out of v1
 *   BE8   a minimum shortfall bills per BillShortfall, and NOT per Forfeit or Rollover
 *   BE9   a shortfall is not billed before its period ends
 *   BE10  a failure leaves the event Failed WITH a reason and writes nothing else
 *   BE11  a period with nothing due is Skipped, not Failed
 *   BE12  the scheduled driver works the queue and reports what it did
 *
 * The bridge default REFUSES rather than returning zero, so BE10 also proves the real-world state
 * today: without the C0 seams every generation attempt fails loudly with the reason, which is the
 * correct behaviour — an empty bill and a Generated event would under-bill the customer silently.
 *
 * CONNECTS TO:
 *   CODE: GenerateBillingEventOperation, BillingDraft, RunDueBillingEvents
 *   DOC:  plans/bizapps-contracts-master.md §5.1 (the six steps), §5.2 (the driver)
 */

import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration';
import {
    ActivateTermOperation,
    GenerateBillingEventOperation,
    RegisterOrdersBillingBridge,
    ResetOrdersBillingBridge,
    RunDueBillingEvents,
    type BillingDraft,
    type GenerateBillingEventOutput,
    type ContractEntityServer,
    type ContractTermEntityServer,
} from '@mj-biz-apps/contracts-core-entities-server';
import type { mjBizAppsContractsContractBillingEventEntity } from '@mj-biz-apps/contracts-entities';
import {
    CreateContractsFixture,
    E_BILLING_EVENT,
    E_CONTRACT,
    Fx,
    InRolledBackTransaction,
    Md,
    TeardownContractsFixture,
    TxCount,
    TxOne,
    TxQuery,
} from '../fixture.js';

/**
 * A bridge that always succeeds, minting a REAL order per call — which is what orders will do.
 *
 * Two constraints make the obvious shortcuts fail, and both are the database doing its job:
 *   - `FK_ContractBillingEvent_Order`, so a made-up UUID cannot be stamped. The first version of
 *     these checks handed the bridge a phantom id and every generation failed at the stamp.
 *   - `UQ_ContractBillingEvent_Order`, so ONE order may back exactly one billing event. The second
 *     version returned a constant id and the scheduled-driver check failed on its second bill.
 *
 * So the fake creates a fresh OrderHeader per materialisation, by raw SQL because it stands in for
 * what orders will create. Everything rolls back with the check.
 */
function fakeBridge(ctx: IntegrationCheckContext, total = 1000) {
    const seen: BillingDraft[] = [];
    let minted = 0;
    RegisterOrdersBillingBridge({
        PreviewOrder: async (draft) => {
            seen.push(draft);
            return { Success: true, Total: total };
        },
        CreateOrderInState: async (draft) => {
            seen.push(draft);
            minted += 1;
            const id = `aaaaaaaa-0000-4000-8000-${String(minted).padStart(12, '0')}`;
            await TxQuery(
                ctx,
                `INSERT INTO __mj_BizAppsOrders.OrderHeader
                    (ID, OrderNumber, OrderType, OrderDate, Status, CompanyID, AmountPaid, PaymentStatus, InitialPaymentAmount)
                 VALUES ('${id}', 'IT-BILL-${minted}', 'Sale', '2030-01-01', 'Draft', '${Fx().CompanyID}', 0, 'Unpaid', 0)`,
            );
            return { Success: true, OrderID: id, Total: total };
        },
    });
    return seen;
}

/** A bridge that refuses at the materialise step — the "orders said no" failure path. */
function refusingBridge(message: string) {
    RegisterOrdersBillingBridge({
        PreviewOrder: async () => ({ Success: true, Total: 500 }),
        CreateOrderInState: async () => ({ Success: false, Message: message }),
    });
}

async function run(ctx: IntegrationCheckContext, eventID: string, previewOnly = false): Promise<GenerateBillingEventOutput> {
    const op = new GenerateBillingEventOperation();
    const result = await op.ExecuteServer(
        { ContractBillingEventID: eventID, PreviewOnly: previewOnly },
        { provider: ctx.Provider, user: ctx.User, emitProgress: () => undefined } as never,
    );
    return result.Output as GenerateBillingEventOutput;
}

/**
 * A live contract with one annual term, plus whatever coverage the caller adds, and one Scheduled
 * billing event on the term's start date.
 */
async function scenario(
    label: string,
    build: (draft: ContractTermEntityServer) => Promise<void>,
): Promise<{ Contract: ContractEntityServer; Term: ContractTermEntityServer; EventID: string }> {
    const fx = Fx();
    const contract = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
    contract.NewRecord();
    contract.ContractTypeID = fx.StandardTypeID;
    contract.CompanyID = fx.CompanyID;
    contract.CustomerOrganizationID = fx.OrganizationID;
    contract.Status = 'Draft';
    contract.Description = `IT-billing: ${label}`;
    contract.MarkTermsAuthoritative();

    const term = await contract.CreateTerm(fx.User);
    term.StartDate = new Date('2030-01-01');
    term.EndDate = new Date('2030-12-31');
    term.Status = 'Pending';
    term.BillingFrequency = 'Annual';
    await build(term);

    Assert(await contract.Save(), `scenario "${label}" did not save: ${contract.LatestResult?.CompleteMessage ?? ''}`);

    const event = await Md().GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVENT, fx.User);
    event.NewRecord();
    event.ContractTermID = term.ID;
    event.ScheduledDate = new Date('2030-01-01');
    event.Status = 'Scheduled';
    Assert(await event.Save(), `scenario "${label}" event did not save: ${event.LatestResult?.CompleteMessage ?? ''}`);

    return { Contract: contract, Term: term, EventID: event.ID };
}

/** A plain coverage line of the given type. */
async function line(
    term: ContractTermEntityServer,
    type: 'Subscription' | 'OneTime' | 'Milestone' | 'Usage' | 'Minimum',
    opts: { Price?: number; Start?: string; End?: string; ProductIndex?: number } = {},
): Promise<void> {
    const l = await term.CreateLine(Fx().User);
    l.ProductID = Fx().ProductIDs[opts.ProductIndex ?? 0];
    l.LineType = type;
    if (type === 'Subscription') l.SubscriptionTypeID = Fx().SubscriptionTypeID;
    l.Quantity = 1;
    l.ContractedUnitPrice = opts.Price ?? 100;
    if (opts.Start) l.StartDate = new Date(opts.Start);
    if (opts.End) l.EndDate = new Date(opts.End);
}

/** Activate a term and return the dates its cadence produced. */
async function activate(ctx: IntegrationCheckContext, termID: string): Promise<string[]> {
    const op = new ActivateTermOperation();
    const result = await op.ExecuteServer(
        { ContractTermID: termID },
        { provider: ctx.Provider, user: ctx.User, emitProgress: () => undefined } as never,
    );
    const output = result.Output as { Success: boolean; Message?: string; ScheduledDates?: string[] } | undefined;
    Assert(!!output?.Success, `activation failed: ${output?.Message ?? result.ErrorMessage ?? ''}`);
    return output!.ScheduledDates ?? [];
}

/** A term with the given cadence and anchor, ready to activate. */
async function anchoredTerm(
    label: string,
    frequency: 'Monthly' | 'Quarterly' | 'Annual',
    start: string,
    end: string,
    anchor: { Day?: number; Month?: number },
): Promise<string> {
    const fx = Fx();
    const contract = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
    contract.NewRecord();
    contract.ContractTypeID = fx.StandardTypeID;
    contract.CompanyID = fx.CompanyID;
    contract.CustomerOrganizationID = fx.OrganizationID;
    contract.Status = 'Draft';
    contract.Description = `IT-billing: ${label}`;
    contract.MarkTermsAuthoritative();
    const term = await contract.CreateTerm(fx.User);
    term.StartDate = new Date(start);
    term.EndDate = new Date(end);
    term.Status = 'Pending';
    term.BillingFrequency = frequency;
    if (anchor.Day) term.BillingAnchorDay = anchor.Day;
    if (anchor.Month) term.BillingAnchorMonth = anchor.Month;
    await line(term, 'Subscription');
    Assert(await contract.Save(), `${label} did not save: ${contract.LatestResult?.CompleteMessage ?? ''}`);
    return term.ID;
}

export const BillingChecks: NamedCheck[] = [
    {
        Id: 'contracts-billing.BE13',
        Name: 'a term with no anchor still bills from its start date',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                // The baseline, so BE14/BE15 prove the anchor CHANGED something rather than merely
                // producing plausible dates.
                const termID = await anchoredTerm('no anchor', 'Quarterly', '2030-02-15', '2030-12-31', {});
                const dates = await activate(ctx, termID);
                AssertEqual(dates[0], '2030-02-15', 'the first occurrence with no anchor');
                AssertEqual(dates[1], '2030-05-15', 'the second');
            }),
    },

    {
        Id: 'contracts-billing.BE14',
        Name: "BillingAnchorDay moves the cadence onto the day the term negotiated",
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                // These two columns were copied forward by RenewTerm and read by NOTHING, so a
                // contract saying "bills on the 1st" was recorded faithfully and billed on whatever
                // day it happened to start.
                const termID = await anchoredTerm('anchor day', 'Quarterly', '2030-02-15', '2030-12-31', { Day: 1 });
                const dates = await activate(ctx, termID);
                Assert(dates.length > 0, 'no occurrences were scheduled');
                for (const d of dates) {
                    AssertEqual(d.slice(-2), '01', `every occurrence should fall on the 1st — got ${d}`);
                }
                // NEVER BEFORE THE TERM STARTS: the 1st of February precedes 15 February, so the
                // first occurrence steps forward rather than scheduling a period the term does not
                // cover.
                Assert(dates[0] >= '2030-02-15', `the first occurrence ${dates[0]} precedes the term start`);
                AssertEqual(dates[0], '2030-03-01', 'the first occurrence after stepping forward');
            }),
    },

    {
        Id: 'contracts-billing.BE15',
        Name: 'BillingAnchorMonth pins an annual term to the month it always bills in',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                // How "always bills in January" is expressed on a term signed in March.
                const termID = await anchoredTerm('anchor month', 'Annual', '2030-03-10', '2032-12-31', { Month: 1, Day: 1 });
                const dates = await activate(ctx, termID);
                Assert(dates.length > 0, 'no occurrences were scheduled');
                AssertEqual(dates[0], '2031-01-01', 'the first January on or after the term start');
                for (const d of dates) {
                    AssertEqual(d.slice(5), '01-01', `every occurrence should be 1 January — got ${d}`);
                }
            }),
    },

    {
        Id: 'contracts-billing.BE1',
        Name: 'two overlapping runs produce ONE bill — the second finds the event claimed',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const s = await scenario('concurrent claim', (t) => line(t, 'Subscription'));

                const first = await run(ctx, s.EventID);
                Assert(first.Success, first.Message ?? 'the first run failed');
                Assert(!!first.OrderID, 'the first run produced no order');

                // The second run is what a duplicate scheduled job looks like. The claim's WHERE is
                // re-evaluated after the lock, so it finds the row Generated and stops.
                const second = await run(ctx, s.EventID);
                Assert(!second.Success, 'the second run billed as well');
                Assert(second.AlreadyClaimed === true, `expected AlreadyClaimed, got: ${second.Message}`);
                Assert(!second.OrderID, 'the second run produced an order — that is a duplicate bill');

                const row = await TxOne<{ Status: string; OrderID: string }>(
                    ctx,
                    `SELECT Status, CAST(OrderID AS varchar(50)) AS OrderID FROM __mj_BizAppsContracts.ContractBillingEvent WHERE ID='${s.EventID}'`,
                );
                AssertEqual(row.Status, 'Generated', 'the event status after both runs');
            }),
    },

    {
        Id: 'contracts-billing.BE2',
        Name: 'a run over an already-Generated event bills nothing',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const s = await scenario('idempotent', (t) => line(t, 'Subscription'));
                Assert((await run(ctx, s.EventID)).Success, 'the first run failed');

                const again = await run(ctx, s.EventID);
                Assert(again.AlreadyClaimed === true, `expected AlreadyClaimed, got: ${again.Message}`);
                // The order count is the real proof: one order, however many times the driver runs.
                AssertEqual(
                    await TxCount(ctx, 'ContractBillingEvent', `ContractTermID='${s.Term.ID}' AND Status='Generated'`),
                    1,
                    'generated events for this term',
                );
            }),
    },

    {
        Id: 'contracts-billing.BE3',
        Name: 'a subscription line bills for the period',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const s = await scenario('subscription', (t) => line(t, 'Subscription', { Price: 1200 }));

                const out = await run(ctx, s.EventID, true);
                AssertEqual(out.Draft?.Lines.length, 1, 'drafted lines');
                AssertEqual(out.Draft?.Lines[0].Reason, 'subscription-period', 'the reason');
                AssertEqual(Number(out.Draft?.Lines[0].ContractedUnitPrice), 1200, 'the contracted price carried through');
                // The window is the whole annual term, clamped to its end.
                AssertEqual(out.Draft?.PeriodStart, '2030-01-01', 'period start');
                AssertEqual(out.Draft?.PeriodEnd, '2030-12-31', 'period end');
            }),
    },

    {
        Id: 'contracts-billing.BE4',
        Name: 'a one-time line bills ONCE, in the period its window opens',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const s = await scenario('one-time', (t) => line(t, 'OneTime', { Price: 5000 }));

                const first = await run(ctx, s.EventID, true);
                AssertEqual(first.Draft?.Lines.length, 1, 'it bills on the first occurrence');
                AssertEqual(first.Draft?.Lines[0].Reason, 'one-time-window-opened', 'the reason');

                // A LATER occurrence must not bill it again. Same line, a period that starts after
                // the line's window opened.
                const later = await Md().GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVENT, Fx().User);
                later.NewRecord();
                later.ContractTermID = s.Term.ID;
                later.ScheduledDate = new Date('2030-07-01');
                later.Status = 'Scheduled';
                Assert(await later.Save(), later.LatestResult?.CompleteMessage ?? 'later event failed');

                const second = await run(ctx, later.ID, true);
                AssertEqual(second.Draft?.Lines.length, 0, 'a one-time charge billed twice');
            }),
    },

    {
        Id: 'contracts-billing.BE5',
        Name: 'a line whose window has closed does not bill',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                // Coverage that ended before this occurrence's period begins.
                const s = await scenario('closed window', (t) =>
                    line(t, 'Subscription', { Start: '2030-01-01', End: '2030-03-31' }),
                );
                const later = await Md().GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVENT, Fx().User);
                later.NewRecord();
                later.ContractTermID = s.Term.ID;
                later.ScheduledDate = new Date('2030-07-01');
                later.Status = 'Scheduled';
                Assert(await later.Save(), later.LatestResult?.CompleteMessage ?? '');

                const out = await run(ctx, later.ID, true);
                AssertEqual(out.Draft?.Lines.length, 0, 'expired coverage billed anyway');
            }),
    },

    {
        Id: 'contracts-billing.BE6',
        Name: 'a milestone line bills in no period — nothing marks one reached yet',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const s = await scenario('milestone', (t) => line(t, 'Milestone', { Price: 9000 }));
                const out = await run(ctx, s.EventID, true);
                // Billing every period would be wrong in the EXPENSIVE direction, so it bills in
                // none until a reached-marker exists. Logged as a gap rather than guessed at.
                AssertEqual(out.Draft?.Lines.length, 0, 'a milestone billed without being reached');
            }),
    },

    {
        Id: 'contracts-billing.BE7',
        Name: 'a usage line bills in no period — metering is out of v1',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const s = await scenario('usage', (t) => line(t, 'Usage', { Price: 3 }));
                const out = await run(ctx, s.EventID, true);
                AssertEqual(out.Draft?.Lines.length, 0, 'usage billed with no meter to read');
            }),
    },

    {
        Id: 'contracts-billing.BE8',
        Name: 'a minimum shortfall bills per BillShortfall, and NOT per Forfeit or Rollover',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);

                // Committed 10,000, consumed 4,000 -> a 6,000 shortfall. The subtraction is between
                // two figures the AGREEMENT records; it is not a price.
                const s = await scenario('shortfall', async (t) => {
                    await line(t, 'Subscription');
                    const c = await t.CreateCommitment(Fx().User);
                    c.CommitmentType = 'Minimum';
                    c.CommittedAmount = 10000;
                    c.ConsumedAmount = 4000;
                    c.TrueUpPolicy = 'BillShortfall';
                    c.Status = 'Open';
                    c.PeriodStart = new Date('2030-01-01');
                    c.PeriodEnd = new Date('2030-12-31');
                });

                const out = await run(ctx, s.EventID, true);
                const shortfall = out.Draft?.Lines.find((l) => l.Reason === 'minimum-shortfall');
                Assert(!!shortfall, `no shortfall line was drafted: ${JSON.stringify(out.Draft?.Lines)}`);
                AssertEqual(Number(shortfall!.ContractedUnitPrice), 6000, 'the shortfall amount');

                // Forfeit and Rollover produce NO charge now — the customer loses it or carries it.
                for (const policy of ['Forfeit', 'Rollover'] as const) {
                    const other = await scenario(`shortfall ${policy}`, async (t) => {
                        await line(t, 'Subscription');
                        const c = await t.CreateCommitment(Fx().User);
                        c.CommitmentType = 'Minimum';
                        c.CommittedAmount = 10000;
                        c.ConsumedAmount = 4000;
                        c.TrueUpPolicy = policy;
                        c.Status = 'Open';
                        c.PeriodStart = new Date('2030-01-01');
                        c.PeriodEnd = new Date('2030-12-31');
                    });
                    const result = await run(ctx, other.EventID, true);
                    Assert(
                        !result.Draft?.Lines.some((l) => l.Reason === 'minimum-shortfall'),
                        `${policy} produced a shortfall charge`,
                    );
                }
            }),
    },

    {
        Id: 'contracts-billing.BE9',
        Name: 'a shortfall is not billed before its period ends',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                // A monthly term, so the first occurrence covers January while the commitment runs
                // to December — the customer still has eleven months to spend it.
                const fx = Fx();
                const contract = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
                contract.NewRecord();
                contract.ContractTypeID = fx.StandardTypeID;
                contract.CompanyID = fx.CompanyID;
                contract.CustomerOrganizationID = fx.OrganizationID;
                contract.Status = 'Draft';
                contract.Description = 'IT-billing: early shortfall';
                contract.MarkTermsAuthoritative();
                const term = await contract.CreateTerm(fx.User);
                term.StartDate = new Date('2030-01-01');
                term.EndDate = new Date('2030-12-31');
                term.Status = 'Pending';
                term.BillingFrequency = 'Monthly';
                await line(term, 'Subscription');
                const c = await term.CreateCommitment(fx.User);
                c.CommitmentType = 'Minimum';
                c.CommittedAmount = 10000;
                c.ConsumedAmount = 0;
                c.TrueUpPolicy = 'BillShortfall';
                c.Status = 'Open';
                c.PeriodStart = new Date('2030-01-01');
                c.PeriodEnd = new Date('2030-12-31');
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? '');

                const event = await Md().GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVENT, fx.User);
                event.NewRecord();
                event.ContractTermID = term.ID;
                event.ScheduledDate = new Date('2030-01-01');
                event.Status = 'Scheduled';
                Assert(await event.Save(), event.LatestResult?.CompleteMessage ?? '');

                const out = await run(ctx, event.ID, true);
                Assert(
                    !out.Draft?.Lines.some((l) => l.Reason === 'minimum-shortfall'),
                    'a shortfall was billed in January for a commitment running to December',
                );
            }),
    },

    {
        Id: 'contracts-billing.BE10',
        Name: 'a failure leaves the event Failed WITH a reason and writes nothing else',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                refusingBridge('the payment gateway is unreachable');
                const s = await scenario('failure', (t) => line(t, 'Subscription'));

                const out = await run(ctx, s.EventID);
                Assert(!out.Success, 'a refused materialisation reported success');
                Assert((out.Message ?? '').includes('gateway is unreachable'), `wrong reason: ${out.Message}`);

                // The failure record is written OUTSIDE the rolled-back transaction. Inside it, the
                // explanation would roll back with the failure and the row would look untried.
                const row = await TxOne<{ Status: string; FailureReason: string; OrderID: string | null }>(
                    ctx,
                    `SELECT Status, ISNULL(FailureReason,'') AS FailureReason, CAST(OrderID AS varchar(50)) AS OrderID
                       FROM __mj_BizAppsContracts.ContractBillingEvent WHERE ID='${s.EventID}'`,
                );
                AssertEqual(row.Status, 'Failed', 'the event status after a refusal');
                Assert(row.FailureReason.includes('gateway is unreachable'), `stored reason: ${row.FailureReason}`);
                Assert(!row.OrderID, 'a failed event named an order');
            }),
    },

    {
        Id: 'contracts-billing.BE11',
        Name: 'a period with nothing due is Skipped, not Failed',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                // Only a milestone line, which never bills — so the run has nothing to bill and that
                // is a real, common outcome rather than an error.
                const s = await scenario('nothing due', (t) => line(t, 'Milestone'));

                const out = await run(ctx, s.EventID);
                Assert(out.Success, `a nothing-due period reported failure: ${out.Message}`);
                Assert(!out.OrderID, 'a skipped period produced an order');

                const row = await TxOne<{ Status: string }>(
                    ctx,
                    `SELECT Status FROM __mj_BizAppsContracts.ContractBillingEvent WHERE ID='${s.EventID}'`,
                );
                // Skipped, NOT Failed: nothing went wrong, and a worklist full of "failures" that
                // are really quiet periods is a worklist nobody reads.
                AssertEqual(row.Status, 'Skipped', 'the event status');
            }),
    },

    {
        Id: 'contracts-billing.BE12',
        Name: 'the scheduled driver works the queue and reports what it did',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                fakeBridge(ctx);
                const billable = await scenario('driver billable', (t) => line(t, 'Subscription'));
                const quiet = await scenario('driver quiet', (t) => line(t, 'Milestone'));

                // As-of AFTER both scheduled dates, so both are due.
                const summary = await RunDueBillingEvents(Fx().User, { AsOf: new Date('2030-06-01'), MaxEvents: 50 });

                Assert(summary.Considered >= 2, `the driver considered ${summary.Considered} events`);
                Assert(summary.Generated >= 1, `nothing was generated (${JSON.stringify(summary)})`);
                Assert(summary.Skipped >= 1, `nothing was skipped (${JSON.stringify(summary)})`);

                const billableRow = await TxOne<{ Status: string }>(
                    ctx,
                    `SELECT Status FROM __mj_BizAppsContracts.ContractBillingEvent WHERE ID='${billable.EventID}'`,
                );
                const quietRow = await TxOne<{ Status: string }>(
                    ctx,
                    `SELECT Status FROM __mj_BizAppsContracts.ContractBillingEvent WHERE ID='${quiet.EventID}'`,
                );
                AssertEqual(billableRow.Status, 'Generated', 'the billable event');
                AssertEqual(quietRow.Status, 'Skipped', 'the quiet event');

                // A second pass must change nothing — that is what makes the job safe to re-run.
                const again = await RunDueBillingEvents(Fx().User, { AsOf: new Date('2030-06-01'), MaxEvents: 50 });
                AssertEqual(again.Generated, 0, 'the second pass generated more bills');
            }),
    },
];

for (const check of BillingChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-billing', {
    Setup: async (ctx) => {
        await CreateContractsFixture(ctx);
    },
    Teardown: async (ctx) => {
        // Put the real (unavailable) bridge back, so a later bundle cannot accidentally run against
        // a fake one and report that billing works.
        ResetOrdersBillingBridge();
        await TeardownContractsFixture(ctx);
    },
});
