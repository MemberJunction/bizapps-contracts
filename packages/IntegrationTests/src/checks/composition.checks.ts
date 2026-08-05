/**
 * contracts-composition — the contract as ONE entity, ONE transaction, ONE tree (CC1–CC14).
 *
 * WHAT THIS BUNDLE EXISTS TO PROVE. `ContractEntityServer` could not create a contract: it had no
 * child collection, so the UI wrote the agreement as separate round trips — contract, then term,
 * then each line — and a failure partway left a NUMBERED contract with nothing under it. A record
 * that looks real, cannot be activated, and nothing cleans up.
 *
 * The entity now composes the whole agreement and writes it atomically:
 *
 *     Contract.Terms  ->  Term.{ Lines, Schedules, Commitments }
 *
 * WHAT IT PROVES
 *   CC1   one Save() writes contract + 2 terms + 3 lines + a schedule + a commitment
 *   CC2   term numbers are DERIVED (1, 2) rather than colliding, and coverage is sequenced
 *   CC3   a bad line at the DEEPEST level rolls back the header, the term and the good line
 *   CC4   and returns the contract number to the sequence rather than stranding it
 *   CC5   Load() is shallow — the roster case; LoadFull() hydrates the tree
 *   CC6   LoadFull() gives each term ITS OWN children, with exact values intact
 *   CC7   a lazily loaded ACTIVE contract stays editable (un-hydrated is not empty)
 *   CC8   but an Active contract with genuinely no term is refused
 *   CC9   coverage must sit inside its term's dates, both ends
 *   CC10  a Subscription line without a subscription type is refused, in a SENTENCE
 *   CC11  a Completed term gains no new coverage
 *   CC12  an Active term must entitle the customer to something
 *   CC13  an amendment targets a RUNNING term only
 *   CC14  a contract type's default escalation must fit under its own default ceiling
 *
 * Deterministic, and every check runs inside a rolled-back transaction — nothing this bundle
 * writes ever reaches disk, which is the difference between this and the `tsx` harness it replaces
 * (whose FK-ordered teardown walk never ran when a check threw partway).
 *
 * CONNECTS TO:
 *   CODE: ContractEntityServer, ContractTermEntityServer, ChildCollection, and the five entity
 *         subclasses added 2026-08-05 (Line, BillingSchedule, Commitment, Amendment, Type)
 *   DOC:  plans/bizapps-contracts-master.md §12 (the pricing lock), §6 (invariants)
 */

import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration';
import type {
    ContractEntityServer,
    ContractTermEntityServer,
    ContractTypeEntityServer,
    ContractAmendmentEntityServer,
} from '@mj-biz-apps/contracts-core-entities-server';
import {
    CreateContractsFixture,
    E_AMENDMENT,
    E_CONTRACT,
    E_TERM,
    E_TYPE,
    Fx,
    InRolledBackTransaction,
    Md,
    TeardownContractsFixture,
    TxCount,
    TxOne,
} from '../fixture.js';

/** A contract header with the fixture filled in. Terms marked authoritative — it is a new record. */
async function newContract(description: string): Promise<ContractEntityServer> {
    const fx = Fx();
    const c = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
    c.NewRecord();
    c.ContractTypeID = fx.StandardTypeID;
    c.CompanyID = fx.CompanyID;
    c.CustomerOrganizationID = fx.OrganizationID;
    c.Status = 'Draft';
    c.Description = `IT-contracts: ${description}`;
    c.MarkTermsAuthoritative();
    return c;
}

/** A term on `contract`, with the required columns set. */
async function addTerm(
    contract: ContractEntityServer,
    start: string,
    end: string,
    frequency: 'Monthly' | 'Quarterly' | 'Annual' = 'Annual',
): Promise<ContractTermEntityServer> {
    const term = await contract.CreateTerm(Fx().User);
    term.StartDate = new Date(start);
    term.EndDate = new Date(end);
    term.Status = 'Pending';
    term.BillingFrequency = frequency;
    return term;
}

/** A plain one-time coverage line — the simplest thing that satisfies "this term grants something". */
async function addOneTimeLine(term: ContractTermEntityServer, productIndex = 0, price = 100): Promise<void> {
    const line = await term.CreateLine(Fx().User);
    line.ProductID = Fx().ProductIDs[productIndex];
    line.LineType = 'OneTime';
    line.Quantity = 1;
    line.ContractedUnitPrice = price;
}

/** The sequence counter, read on the check's own connection so it sees uncommitted state. */
async function sequenceValue(ctx: IntegrationCheckContext): Promise<number> {
    const row = await TxOne<{ N: number }>(ctx, 'SELECT NextSequenceNumber AS N FROM __mj_BizAppsContracts.ContractSequence');
    return Number(row.N);
}

export const CompositionChecks: NamedCheck[] = [
    {
        Id: 'contracts-composition.CC1',
        Name: 'one Save() writes the whole agreement — verified by raw SQL, not by the entity',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const fx = Fx();
                const contract = await newContract('whole tree');

                const term1 = await addTerm(contract, '2030-01-01', '2030-12-31', 'Quarterly');
                term1.CommittedAmount = 120000;

                const sub = await term1.CreateLine(fx.User);
                sub.ProductID = fx.ProductIDs[0];
                sub.LineType = 'Subscription';
                sub.SubscriptionTypeID = fx.SubscriptionTypeID;
                sub.Quantity = 10;
                sub.ContractedUnitPrice = 1000;

                await addOneTimeLine(term1, 1, 5000);

                const schedule = await term1.CreateSchedule(fx.User);
                schedule.ScheduleType = 'Cadence';
                schedule.Frequency = 'Quarterly';
                schedule.AnchorDate = new Date('2030-01-01');

                const commitment = await term1.CreateCommitment(fx.User);
                commitment.CommitmentType = 'Minimum';
                commitment.CommittedAmount = 120000;
                commitment.ConsumedAmount = 0;
                commitment.TrueUpPolicy = 'BillShortfall';
                commitment.Status = 'Open';

                const term2 = await addTerm(contract, '2031-01-01', '2031-12-31');
                await addOneTimeLine(term2, 0, 1100);

                Assert(await contract.Save(), `the tree did not save: ${contract.LatestResult?.CompleteMessage ?? ''}`);

                // RAW SQL, underneath the entity layer. Asserting `contract.Terms.length` would pass
                // on an entity reporting its own in-memory collections back, proving nothing.
                AssertEqual(await TxCount(ctx, 'ContractTerm', `ContractID='${contract.ID}'`), 2, 'term rows');
                AssertEqual(
                    await TxCount(ctx, 'ContractLine', `ContractTermID IN ('${term1.ID}','${term2.ID}')`),
                    3,
                    'coverage rows',
                );
                AssertEqual(await TxCount(ctx, 'ContractBillingSchedule', `ContractTermID='${term1.ID}'`), 1, 'schedule rows');
                AssertEqual(await TxCount(ctx, 'ContractCommitment', `ContractTermID='${term1.ID}'`), 1, 'commitment rows');
                Assert(/^CTR-\d{6}$/.test(contract.ContractNumber ?? ''), `number was "${contract.ContractNumber}"`);
                Assert(!!contract.PricedAt, 'PricedAt was not defaulted — the pricing moment is undefined');
            }),
    },

    {
        Id: 'contracts-composition.CC2',
        Name: 'term numbers are derived rather than collided, and coverage is sequenced within its term',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('derived numbering');
                const t1 = await addTerm(contract, '2030-01-01', '2030-12-31');
                await addOneTimeLine(t1, 0);
                await addOneTimeLine(t1, 1);
                const t2 = await addTerm(contract, '2031-01-01', '2031-12-31');
                await addOneTimeLine(t2, 0);
                const t3 = await addTerm(contract, '2032-01-01', '2032-12-31');
                await addOneTimeLine(t3, 0);

                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                // THREE terms created together. Each derives its number by reading the contract's
                // existing terms — a read that must see the SIBLINGS inserted moments earlier by the
                // same transaction. If it did not, all three would take 1 and collide on
                // UQ (ContractID, TermNumber).
                AssertEqual(t1.TermNumber, 1, 'first term number');
                AssertEqual(t2.TermNumber, 2, 'second term number');
                AssertEqual(t3.TermNumber, 3, 'third term number');

                AssertEqual(t1.Lines[0].DisplayOrder, 1, 'first line position');
                AssertEqual(t1.Lines[1].DisplayOrder, 2, 'second line position');
            }),
    },

    {
        Id: 'contracts-composition.CC3',
        Name: 'a bad line at the deepest level rolls back the header, the term and the good line',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const fx = Fx();
                const contract = await newContract('rollback proof');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');

                const good = await term.CreateLine(fx.User);
                good.ProductID = fx.ProductIDs[0];
                good.LineType = 'OneTime';
                good.Quantity = 1;
                good.ContractedUnitPrice = 100;

                // A Subscription line with no SubscriptionTypeID — refused by the line's own
                // Validate. Chosen deliberately: it fails at the DEEPEST point of the tree, after
                // the header, the term and one good line have already been written.
                const bad = await term.CreateLine(fx.User);
                bad.ProductID = fx.ProductIDs[1];
                bad.LineType = 'Subscription';
                bad.Quantity = 1;

                let threw = false;
                let saved = false;
                try {
                    saved = await contract.Save();
                } catch {
                    threw = true;
                }

                Assert(!saved, 'the save reported success despite an invalid line');
                Assert(threw, 'the failure was swallowed as a silent false rather than raised');
                AssertEqual(await TxCount(ctx, 'Contract', `Description='IT-contracts: rollback proof'`), 0, 'surviving contracts');
                AssertEqual(await TxCount(ctx, 'ContractTerm', `ID='${term.ID}'`), 0, 'surviving terms');
                AssertEqual(await TxCount(ctx, 'ContractLine', `ID='${good.ID}'`), 0, 'surviving lines from the good line');
            }),
    },

    {
        Id: 'contracts-composition.CC4',
        Name: 'a rolled-back contract returns its number to the sequence rather than stranding it',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const before = await sequenceValue(ctx);

                const contract = await newContract('sequence proof');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                const bad = await term.CreateLine(Fx().User);
                bad.ProductID = Fx().ProductIDs[0];
                bad.LineType = 'Subscription'; // no SubscriptionTypeID — refused
                bad.Quantity = 1;

                await contract.Save().catch(() => false);

                // Allocation happens INSIDE the tree transaction precisely so this holds. Allocated
                // outside it, a failed save strands the number; allocated in a transaction of its
                // own, a later failure commits an allocation for a contract that does not exist.
                AssertEqual(await sequenceValue(ctx), before, 'sequence counter after a failed save');
            }),
    },

    {
        Id: 'contracts-composition.CC5',
        Name: 'Load() stays shallow and LoadFull() hydrates — the roster case versus the workspace case',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('lazy loading');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                await addOneTimeLine(term, 0);
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                const shallow = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, Fx().User);
                Assert(await shallow.Load(contract.ID), 'shallow load failed');
                AssertEqual(shallow.Terms.length, 0, 'a plain Load must not drag the tree into memory');
                Assert(!shallow.TermsAreLoaded, 'a plain Load must not claim the collection is authoritative');

                const deep = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, Fx().User);
                Assert(await deep.Load(contract.ID), 'deep load failed');
                await deep.LoadFull(Fx().User);
                AssertEqual(deep.Terms.length, 1, 'LoadFull term count');
                Assert(deep.TermsAreLoaded, 'LoadFull must mark the collection authoritative');
            }),
    },

    {
        Id: 'contracts-composition.CC6',
        Name: 'LoadFull() gives each term its own children, with exact values intact',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const fx = Fx();
                const contract = await newContract('bulk hydration');

                const t1 = await addTerm(contract, '2030-01-01', '2030-12-31', 'Quarterly');
                await addOneTimeLine(t1, 0, 5000);
                await addOneTimeLine(t1, 1, 250);
                const schedule = await t1.CreateSchedule(fx.User);
                schedule.ScheduleType = 'Cadence';
                schedule.Frequency = 'Quarterly';
                const commitment = await t1.CreateCommitment(fx.User);
                commitment.CommitmentType = 'Minimum';
                commitment.CommittedAmount = 40000;
                commitment.ConsumedAmount = 0;
                commitment.TrueUpPolicy = 'BillShortfall';
                commitment.Status = 'Open';

                const t2 = await addTerm(contract, '2031-01-01', '2031-12-31');
                await addOneTimeLine(t2, 0, 6000);

                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                const deep = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, fx.User);
                await deep.Load(contract.ID);
                await deep.LoadFull(fx.User);

                const first = deep.Terms.find((t) => t.TermNumber === 1);
                const second = deep.Terms.find((t) => t.TermNumber === 2);
                Assert(!!first && !!second, 'both terms should hydrate');

                // The distribution is the thing that can silently go wrong: one bulk read per child
                // type, then grouped by ContractTermID in memory. A mis-grouping shows one term
                // holding another term's coverage, which reads as plausible in the UI.
                AssertEqual(first!.Lines.length, 2, "term 1's coverage count");
                AssertEqual(second!.Lines.length, 1, "term 2's coverage count");
                AssertEqual(first!.Schedules.length, 1, "term 1's schedules");
                AssertEqual(second!.Schedules.length, 0, 'term 2 should have no schedule');
                AssertEqual(first!.Commitments.length, 1, "term 1's commitments");
                AssertEqual(second!.Commitments.length, 0, 'term 2 should have no commitment');

                // Exact values, not "an array came back".
                AssertEqual(Number(first!.Lines[0].ContractedUnitPrice), 5000, "term 1 line 1's price");
                AssertEqual(Number(first!.Lines[1].ContractedUnitPrice), 250, "term 1 line 2's price");
                AssertEqual(Number(second!.Lines[0].ContractedUnitPrice), 6000, "term 2's price");
                AssertEqual(Number(first!.Commitments[0].CommittedAmount), 40000, 'the commitment amount');
            }),
    },

    {
        Id: 'contracts-composition.CC7',
        Name: 'a lazily loaded Active contract stays editable — un-hydrated is not empty',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('lazy active edit');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                await addOneTimeLine(term, 0);
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');
                contract.Status = 'Active';
                Assert(await contract.Save(), `activation failed: ${contract.LatestResult?.CompleteMessage ?? ''}`);

                // THE SUBTLE ONE. This contract is Active and genuinely has a term, but a lazy load
                // leaves Terms empty. A validator that read "no terms in memory" as "no terms" would
                // refuse this edit — and would therefore refuse EVERY edit to EVERY live contract in
                // the system, with a message that reads like a business rule and is really a bug.
                const lazy = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, Fx().User);
                Assert(await lazy.Load(contract.ID), 'lazy load failed');
                AssertEqual(lazy.Terms.length, 0, 'precondition: the lazy load really is un-hydrated');
                lazy.Description = 'IT-contracts: lazy active edit (edited)';
                Assert(await lazy.Save(), `a lazily loaded Active contract was refused: ${lazy.LatestResult?.CompleteMessage ?? ''}`);
            }),
    },

    {
        Id: 'contracts-composition.CC8',
        Name: 'an Active contract with genuinely no term is refused',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const bare = await newContract('active with no term');
                bare.Status = 'Active';
                const saved = await bare.Save().catch(() => false);
                Assert(!saved, 'an Active contract with no term at all saved');
                Assert(
                    (bare.LatestResult?.CompleteMessage ?? '').includes('at least one term'),
                    `the refusal did not explain itself: ${bare.LatestResult?.CompleteMessage ?? ''}`,
                );
            }),
    },

    {
        Id: 'contracts-composition.CC9',
        Name: "coverage must sit inside its term's dates, at both ends",
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('coverage window');
                const term = await addTerm(contract, '2030-06-01', '2030-12-31');
                await addOneTimeLine(term, 0);
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                const overrun = await term.CreateLine(Fx().User);
                overrun.ProductID = Fx().ProductIDs[1];
                overrun.LineType = 'OneTime';
                overrun.Quantity = 1;
                overrun.StartDate = new Date('2030-06-01');
                overrun.EndDate = new Date('2031-06-01');
                Assert(!(await overrun.Save()), 'coverage running past the term end saved');
                Assert(
                    (overrun.LatestResult?.CompleteMessage ?? '').includes('past the end of term'),
                    `the refusal names the wrong thing — it must be the date rule, not a null FK: ` +
                        `${overrun.LatestResult?.CompleteMessage ?? ''}`,
                );
                term.RemoveLine(overrun);

                const early = await term.CreateLine(Fx().User);
                early.ProductID = Fx().ProductIDs[1];
                early.LineType = 'OneTime';
                early.Quantity = 1;
                early.StartDate = new Date('2030-01-01');
                Assert(!(await early.Save()), 'coverage starting before the term began saved');
                Assert(
                    (early.LatestResult?.CompleteMessage ?? '').includes('before term'),
                    `wrong refusal: ${early.LatestResult?.CompleteMessage ?? ''}`,
                );
            }),
    },

    {
        Id: 'contracts-composition.CC10',
        Name: 'a Subscription line without a subscription type is refused in a sentence, not a constraint name',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('subscription shape');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                await addOneTimeLine(term, 0);
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                const typeless = await term.CreateLine(Fx().User);
                typeless.ProductID = Fx().ProductIDs[1];
                typeless.LineType = 'Subscription';
                typeless.Quantity = 1;
                Assert(!(await typeless.Save()), 'a Subscription line with no type saved');

                // The CHECK constraint already prevents the row. What it CANNOT do is explain
                // itself: it reports as CK_ContractLine_SubscriptionNeedsType, a symbol, to a UI
                // that can only render it verbatim.
                const message = typeless.LatestResult?.CompleteMessage ?? '';
                Assert(message.includes('WHICH KIND of subscription'), `not the readable message: ${message}`);
                Assert(!message.includes('CK_ContractLine'), `leaked the constraint symbol: ${message}`);
            }),
    },

    {
        Id: 'contracts-composition.CC11',
        Name: 'a Completed term gains no new coverage',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('closed term');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                await addOneTimeLine(term, 0);
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                const live = await Md().GetEntityObject<ContractTermEntityServer>(E_TERM, Fx().User);
                await live.Load(term.ID);
                await live.LoadChildren(Fx().User);
                live.Status = 'Active';
                Assert(await live.Save(), `activation failed: ${live.LatestResult?.CompleteMessage ?? ''}`);
                live.Status = 'Completed';
                Assert(await live.Save(), `completion failed: ${live.LatestResult?.CompleteMessage ?? ''}`);

                const late = await live.CreateLine(Fx().User);
                late.ProductID = Fx().ProductIDs[1];
                late.LineType = 'OneTime';
                late.Quantity = 1;
                Assert(!(await late.Save()), 'coverage was added to a Completed term');
                Assert(
                    (late.LatestResult?.CompleteMessage ?? '').includes('settled and cannot change'),
                    `wrong refusal: ${late.LatestResult?.CompleteMessage ?? ''}`,
                );
            }),
    },

    {
        Id: 'contracts-composition.CC12',
        Name: 'an Active term must entitle the customer to something',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('bare active term');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                term.Status = 'Active'; // no coverage at all
                const saved = await contract.Save().catch(() => false);
                Assert(!saved, 'an Active term with no coverage saved');
            }),
    },

    {
        Id: 'contracts-composition.CC13',
        Name: 'an amendment targets a running term only — amendments change, renewals start over',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const contract = await newContract('amendment target');
                const term = await addTerm(contract, '2030-01-01', '2030-12-31');
                await addOneTimeLine(term, 0);
                Assert(await contract.Save(), contract.LatestResult?.CompleteMessage ?? 'save failed');

                // Against a PENDING term first — that change belongs in the term itself.
                const early = await Md().GetEntityObject<ContractAmendmentEntityServer>(E_AMENDMENT, Fx().User);
                early.NewRecord();
                early.ContractTermID = term.ID;
                early.EffectiveDate = new Date('2030-03-01');
                early.AmendmentType = 'ChangeQuantity';
                early.Status = 'Draft';
                Assert(!(await early.Save()), 'an amendment against a Pending term saved');
                Assert(
                    (early.LatestResult?.CompleteMessage ?? '').includes('has not started yet'),
                    `wrong refusal: ${early.LatestResult?.CompleteMessage ?? ''}`,
                );

                // Now activate the term and confirm the amendment is accepted, so the check proves a
                // RULE rather than merely that amendments never save.
                const live = await Md().GetEntityObject<ContractTermEntityServer>(E_TERM, Fx().User);
                await live.Load(term.ID);
                await live.LoadChildren(Fx().User);
                live.Status = 'Active';
                Assert(await live.Save(), `activation failed: ${live.LatestResult?.CompleteMessage ?? ''}`);

                const ok = await Md().GetEntityObject<ContractAmendmentEntityServer>(E_AMENDMENT, Fx().User);
                ok.NewRecord();
                ok.ContractTermID = term.ID;
                ok.EffectiveDate = new Date('2030-03-01');
                ok.AmendmentType = 'ChangeQuantity';
                ok.Status = 'Draft';
                Assert(await ok.Save(), `an amendment against an Active term was refused: ${ok.LatestResult?.CompleteMessage ?? ''}`);
                AssertEqual(ok.AmendmentNumber, 1, 'the amendment number is derived, not typed');
            }),
    },

    {
        Id: 'contracts-composition.CC14',
        Name: "a contract type's default escalation must fit under its own default ceiling",
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const bad = await Md().GetEntityObject<ContractTypeEntityServer>(E_TYPE, Fx().User);
                bad.NewRecord();
                bad.Code = `IT-contracts-badtype-${Date.now().toString().slice(-8)}`;
                bad.Name = 'IT-contracts bad type';
                bad.RenewalMode = 'Deal';
                bad.DefaultEscalationPercent = 0.06;
                bad.DefaultMaxEscalationPercent = 0.05;

                Assert(!(await bad.Save()), 'a type prescribing 6% under a 5% ceiling saved');

                // This rule cannot be a CHECK: a two-column constraint makes CodeGen emit a call to
                // a validation method it never defines. So it lives in Validate(), and the message
                // has to explain why it is reported HERE rather than against the terms that would
                // inherit the contradiction.
                Assert(
                    (bad.LatestResult?.CompleteMessage ?? '').includes('not where it can be fixed'),
                    `wrong refusal: ${bad.LatestResult?.CompleteMessage ?? ''}`,
                );
            }),
    },
];

for (const check of CompositionChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-composition', {
    Setup: async (ctx) => {
        await CreateContractsFixture(ctx);
    },
    Teardown: async (ctx) => {
        await TeardownContractsFixture(ctx);
    },
});
