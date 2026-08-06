/**
 * contracts-amendment — changing a LIVE term, and co-terming (AM1–AM8).
 *
 * WHY CO-TERMING IS THE ONE THAT MATTERS. Master plan §5.4: adding a product mid-term creates an
 * amendment plus a line whose StartDate is the amendment date and whose EndDate is the TERM's end
 * date, so the new product lands on the SAME renewal date as everything else the customer already
 * has. Standalone subscriptions structurally cannot do this — each carries its own clock, so a
 * customer accumulates a drawer of unrelated renewal dates. It is why the contract owns the calendar.
 *
 * WHAT IT PROVES
 *   AM1  a co-term stub ends with the TERM, not a year from the amendment date
 *   AM2  the amendment and the line are written together, or not at all
 *   AM3  a preview computes the stub and writes nothing
 *   AM4  an amendment against a term that is not RUNNING is refused, with the right advice
 *   AM5  an amendment dated outside its term is refused
 *   AM6  amendment numbers are derived, and increment per term
 *   AM7  the amendment types that cannot be applied are refused with the reason, not half-done
 *   AM8  applying one writes the audit trail
 *
 * CONNECTS TO:
 *   CODE: AmendTermOperation, ContractAmendmentEntityServer
 *   DOC:  plans/bizapps-contracts-master.md §5.4 (co-terming), §3.8 (amendment vs renewal)
 */

import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration';
import {
    AmendTermOperation,
    ActivateTermOperation,
    type AmendTermInput,
    type AmendTermOutput,
    type ContractEntityServer,
    type ContractTermEntityServer,
} from '@mj-biz-apps/contracts-core-entities-server';
import {
    CreateContractsFixture,
    E_CONTRACT,
    Fx,
    InRolledBackTransaction,
    Md,
    TeardownContractsFixture,
    TxCount,
    TxOne,
} from '../fixture.js';

async function amend(ctx: IntegrationCheckContext, input: AmendTermInput): Promise<AmendTermOutput> {
    const op = new AmendTermOperation();
    const result = await op.ExecuteServer(input, {
        provider: ctx.Provider,
        user: ctx.User,
        emitProgress: () => undefined,
    } as never);
    return result.Output as AmendTermOutput;
}

/** A contract with one ACTIVE term running the whole of 2030, carrying one line. */
async function liveTerm(ctx: IntegrationCheckContext, label: string): Promise<ContractTermEntityServer> {
    const fx = Fx();
    const contract = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
    contract.NewRecord();
    contract.ContractTypeID = fx.StandardTypeID;
    contract.CompanyID = fx.CompanyID;
    contract.CustomerOrganizationID = fx.OrganizationID;
    contract.Status = 'Draft';
    contract.Description = `IT-amendment: ${label}`;
    contract.MarkTermsAuthoritative();

    const term = await contract.CreateTerm(fx.User);
    term.StartDate = new Date('2030-01-01');
    term.EndDate = new Date('2030-12-31');
    term.Status = 'Pending';
    term.CommittedAmount = 0;
    term.BillingFrequency = 'Annual';
    const line = await term.CreateLine(fx.User);
    line.ProductID = fx.ProductIDs[0];
    line.LineType = 'OneTime';
    line.Quantity = 1;
    line.ContractedUnitPrice = 1000;
    Assert(await contract.Save(), `${label} did not save: ${contract.LatestResult?.CompleteMessage ?? ''}`);

    // Through the real operation, so the term acquires its schedule the way it would in the app.
    const activate = new ActivateTermOperation();
    const activated = await activate.ExecuteServer(
        { ContractTermID: term.ID },
        { provider: ctx.Provider, user: ctx.User, emitProgress: () => undefined } as never,
    );
    Assert((activated.Output as { Success: boolean })?.Success, `${label} did not activate`);

    const live = await Md().GetEntityObject<ContractTermEntityServer>('MJ_BizApps_Contracts: Contract Terms', fx.User);
    await live.Load(term.ID);
    return live;
}

const addProduct = (termID: string, extra: Partial<AmendTermInput> = {}): AmendTermInput => ({
    ContractTermID: termID,
    AmendmentType: 'AddProduct',
    Description: 'Fifty extra seats, added mid-term',
    EffectiveDate: '2030-07-01',
    ProductID: Fx().ProductIDs[1],
    LineType: 'OneTime',
    Quantity: 50,
    ContractedUnitPrice: 25,
    ...extra,
});

export const AmendmentChecks: NamedCheck[] = [
    {
        Id: 'contracts-amendment.AM1',
        Name: 'a co-term stub ends with the TERM, not a year from the amendment date',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'co-term stub');
                const out = await amend(ctx, addProduct(term.ID));
                Assert(out.Success, out.Message ?? 'the amendment failed');

                // THE WHOLE POINT: the new product lands on the same renewal date as everything else.
                // A standalone subscription would run to 2031-06-30 and give the customer a second
                // renewal date to remember.
                AssertEqual(out.StubStart, '2030-07-01', 'the stub starts at the amendment date');
                AssertEqual(out.StubEnd, '2030-12-31', "the stub ends with the TERM");
                AssertEqual(out.StubDays, 184, 'the days the stub covers — what the proration is of');

                const row = await TxOne<{ StartDate: string; EndDate: string }>(
                    ctx,
                    `SELECT CONVERT(varchar(10), StartDate, 23) AS StartDate, CONVERT(varchar(10), EndDate, 23) AS EndDate
                       FROM __mj_BizAppsContracts.ContractLine WHERE ID='${out.LineID}'`,
                );
                AssertEqual(row.StartDate, '2030-07-01', "the written line's start");
                AssertEqual(row.EndDate, '2030-12-31', "the written line's end");
            }),
    },

    {
        Id: 'contracts-amendment.AM2',
        Name: 'the amendment and the line are written together, or not at all',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'atomic');
                const before = await TxCount(ctx, 'ContractLine', `ContractTermID='${term.ID}'`);

                const out = await amend(ctx, addProduct(term.ID));
                Assert(out.Success, out.Message ?? 'the amendment failed');
                AssertEqual(await TxCount(ctx, 'ContractAmendment', `ContractTermID='${term.ID}'`), 1, 'amendment rows');
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${term.ID}'`), before + 1, 'coverage rows');

                // A line that fails leaves NO amendment either — an amendment with no line is a
                // change nobody can point at, and coverage with no amendment is coverage nobody
                // authorised.
                const bad = await amend(ctx, addProduct(term.ID, {
                    LineType: 'Subscription', // a subscription with no SubscriptionTypeID is refused
                    SubscriptionTypeID: null,
                    Description: 'This one cannot save',
                }));
                Assert(!bad.Success, 'an invalid line was accepted');
                AssertEqual(
                    await TxCount(ctx, 'ContractAmendment', `ContractTermID='${term.ID}'`),
                    1,
                    'the failed amendment left a row behind',
                );
            }),
    },

    {
        Id: 'contracts-amendment.AM3',
        Name: 'a preview computes the stub and writes nothing',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'preview');
                const lines = await TxCount(ctx, 'ContractLine', `ContractTermID='${term.ID}'`);

                const out = await amend(ctx, addProduct(term.ID, { PreviewOnly: true }));
                Assert(out.Success, out.Message ?? 'the preview failed');
                Assert(out.Preview, 'the result does not report itself as a preview');
                AssertEqual(out.StubEnd, '2030-12-31', 'the previewed stub end');
                Assert(!out.AmendmentID, 'a preview created an amendment');

                AssertEqual(await TxCount(ctx, 'ContractAmendment', `ContractTermID='${term.ID}'`), 0, 'amendments after a preview');
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${term.ID}'`), lines, 'coverage after a preview');
            }),
    },

    {
        Id: 'contracts-amendment.AM4',
        Name: 'an amendment against a term that is not RUNNING is refused, with the right advice',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                // A PENDING term: the change belongs in the term itself, which has not started.
                const fx = Fx();
                const contract = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
                contract.NewRecord();
                contract.ContractTypeID = fx.StandardTypeID;
                contract.CompanyID = fx.CompanyID;
                contract.CustomerOrganizationID = fx.OrganizationID;
                contract.Status = 'Draft';
                contract.Description = 'IT-amendment: pending term';
                contract.MarkTermsAuthoritative();
                const term = await contract.CreateTerm(fx.User);
                term.StartDate = new Date('2030-01-01');
                term.EndDate = new Date('2030-12-31');
                term.Status = 'Pending';
                term.CommittedAmount = 0;
                term.BillingFrequency = 'Annual';
                const line = await term.CreateLine(fx.User);
                line.ProductID = fx.ProductIDs[0];
                line.LineType = 'OneTime';
                line.Quantity = 1;
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? '');

                const out = await amend(ctx, addProduct(term.ID));
                Assert(!out.Success, 'an amendment against a Pending term was applied');
                Assert(
                    (out.Message ?? '').includes('has not started'),
                    `the refusal should say to change the term itself: ${out.Message}`,
                );
            }),
    },

    {
        Id: 'contracts-amendment.AM5',
        Name: 'an amendment dated outside its term is refused',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'date outside');

                const after = await amend(ctx, addProduct(term.ID, { EffectiveDate: '2031-03-01' }));
                Assert(!after.Success, 'an amendment dated after the term was applied');
                Assert((after.Message ?? '').includes('outside term'), `wrong refusal: ${after.Message}`);

                const before = await amend(ctx, addProduct(term.ID, { EffectiveDate: '2029-11-01' }));
                Assert(!before.Success, 'an amendment dated before the term was applied');
            }),
    },

    {
        Id: 'contracts-amendment.AM6',
        Name: 'amendment numbers are derived, and increment per term',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'numbering');

                const first = await amend(ctx, addProduct(term.ID, { Description: 'First change' }));
                Assert(first.Success, first.Message ?? '');
                AssertEqual(first.AmendmentNumber, 1, 'the first amendment number');

                const second = await amend(ctx, addProduct(term.ID, { Description: 'Second change', EffectiveDate: '2030-09-01' }));
                Assert(second.Success, second.Message ?? '');
                // Derived, not typed: UQ_ContractAmendment_Term_Number would reject a duplicate at
                // the worst possible moment.
                AssertEqual(second.AmendmentNumber, 2, 'the second amendment number');
                AssertEqual(second.StubDays, 122, "the second stub's days — 1 Sept to 31 Dec inclusive");
            }),
    },

    {
        Id: 'contracts-amendment.AM7',
        Name: 'the amendment types that cannot be applied are refused with the reason, not half-done',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'unsupported types');

                // ContractAmendment records THAT a term changed and of what kind, not WHICH line
                // changed or to what value. Applying these would mean guessing, and a wrong guess
                // produces an amendment marked Applied against a term nothing changed on.
                for (const type of ['ChangeQuantity', 'ChangePrice', 'PartialTerminate'] as const) {
                    const out = await amend(ctx, addProduct(term.ID, { AmendmentType: type }));
                    Assert(!out.Success, `${type} was applied`);
                    Assert(
                        (out.Message ?? '').includes('carries no columns'),
                        `${type}'s refusal should explain WHY: ${out.Message}`,
                    );
                }
                AssertEqual(await TxCount(ctx, 'ContractAmendment', `ContractTermID='${term.ID}'`), 0, 'nothing was written');
            }),
    },

    {
        Id: 'contracts-amendment.AM8',
        Name: 'applying an amendment writes the audit trail',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const term = await liveTerm(ctx, 'audit');
                const out = await amend(ctx, addProduct(term.ID));
                Assert(out.Success, out.Message ?? '');

                const row = await TxOne<{ N: number; Payload: string }>(
                    ctx,
                    `SELECT COUNT(*) AS N, MAX(ISNULL(Payload,'')) AS Payload
                       FROM __mj_BizAppsContracts.ContractEvent
                      WHERE ContractTermID='${term.ID}' AND EventType='AmendmentApplied'`,
                );
                AssertEqual(Number(row.N), 1, 'AmendmentApplied events');
                // The payload has to carry enough to answer "what changed and over what window"
                // without re-deriving it from the line.
                Assert(row.Payload.includes('2030-12-31'), `the payload should carry the stub window: ${row.Payload.slice(0, 200)}`);
                Assert(row.Payload.includes('AddProduct'), `the payload should carry the kind: ${row.Payload.slice(0, 200)}`);
            }),
    },
];

for (const check of AmendmentChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-amendment', {
    Setup: async (ctx) => {
        await CreateContractsFixture(ctx);
    },
    Teardown: async (ctx) => {
        await TeardownContractsFixture(ctx);
    },
});
