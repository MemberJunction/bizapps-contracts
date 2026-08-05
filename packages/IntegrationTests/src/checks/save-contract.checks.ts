/**
 * contracts-save-contract — the browser's path to a whole agreement (SC1–SC9).
 *
 * WHAT THIS BUNDLE PROVES. `contracts-composition` proves the ENTITY composes a tree. This proves
 * the path a BROWSER actually takes to reach it: a `ContractDraft` payload → `Contracts.SaveContract`
 * → the same entity tree → one transaction. Both matter, and neither substitutes for the other —
 * the operation could rehydrate the payload wrongly while the entity underneath stays perfect.
 *
 * WHAT IT PROVES
 *   SC1  a draft with two terms and coverage becomes a real agreement in one call
 *   SC2  the response carries what the SERVER derived, not the client's guesses
 *   SC3  an update modifies in place rather than duplicating
 *   SC4  a named removal deletes; an OMITTED child does NOT (the lazy-client data-loss case)
 *   SC5  a term id that belongs to another contract is refused, not silently re-created
 *   SC6  a client-supplied ContractNumber is ignored on a NEW contract
 *   SC7  an invalid line fails the whole call and writes nothing
 *   SC8  a failure reports FIELD-level issues, not one joined string
 *   SC9  removing a term takes its coverage with it
 *
 * Every check runs inside a rolled-back transaction.
 *
 * CONNECTS TO:
 *   CODE: SaveContractOperation, ContractDraft (@mj-biz-apps/contracts-entities)
 */

import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration';
import { ContractDraft, type ContractDraftPayload } from '@mj-biz-apps/contracts-entities';
import { SaveContractOperation, type SaveContractOutput } from '@mj-biz-apps/contracts-core-entities-server';
import type { ContractEntityServer } from '@mj-biz-apps/contracts-core-entities-server';
import {
    CreateContractsFixture,
    E_CONTRACT,
    Fx,
    InRolledBackTransaction,
    Md,
    TeardownContractsFixture,
    TxCount,
} from '../fixture.js';

/**
 * Drive the operation exactly as MJAPI would.
 *
 * `RemoteOpServerContext` is a DIFFERENT shape from `IntegrationCheckContext` — lower-cased
 * `provider`/`user` plus a progress emitter — so it has to be built rather than passed through. The
 * first version handed the check context straight in and every save failed with "No user set",
 * which reads like a permissions problem and is really a shape mismatch.
 */
async function save(ctx: IntegrationCheckContext, draft: ContractDraft): Promise<SaveContractOutput> {
    const op = new SaveContractOperation();
    const result = await op.ExecuteServer(
        { Contract: draft.ToInput() },
        { provider: ctx.Provider, user: ctx.User, emitProgress: () => undefined } as never,
    );
    Assert(!!result.Output, `the operation itself failed: ${result.ErrorMessage ?? ''}`);
    return result.Output as SaveContractOutput;
}

/** A draft with the fixture filled in and one term carrying one line — the minimum real agreement. */
function newDraft(description: string): ContractDraft {
    const fx = Fx();
    const draft = new ContractDraft();
    draft.ContractTypeID = fx.StandardTypeID;
    draft.CompanyID = fx.CompanyID;
    draft.CustomerOrganizationID = fx.OrganizationID;
    draft.Status = 'Draft';
    draft.Description = `IT-savecontract: ${description}`;
    return draft;
}

function addTerm(draft: ContractDraft, start: string, end: string) {
    const term = draft.AddTerm();
    term.StartDate = start;
    term.EndDate = end;
    term.Status = 'Pending';
    term.BillingFrequency = 'Annual';
    return term;
}

function addLine(draft: ContractDraft, term: ReturnType<typeof addTerm>, productIndex = 0, price = 100) {
    const line = draft.AddLine(term);
    line.ProductID = Fx().ProductIDs[productIndex];
    line.LineType = 'OneTime';
    line.Quantity = 1;
    line.ContractedUnitPrice = price;
    return line;
}

export const SaveContractChecks: NamedCheck[] = [
    {
        Id: 'contracts-save-contract.SC1',
        Name: 'a draft with two terms and coverage becomes a real agreement in one call',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('two terms');
                const t1 = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, t1, 0, 5000);
                addLine(draft, t1, 1, 250);
                const t2 = addTerm(draft, '2031-01-01', '2031-12-31');
                addLine(draft, t2, 0, 6000);

                Assert(draft.Validate().IsValid, `the draft refused itself: ${JSON.stringify(draft.Validate().Issues)}`);

                const out = await save(ctx, draft);
                Assert(out.Success, out.Message ?? 'save reported failure');

                const id = out.Contract?.ID ?? '';
                AssertEqual(await TxCount(ctx, 'ContractTerm', `ContractID='${id}'`), 2, 'term rows written');
                AssertEqual(out.Contract?.Terms.length, 2, 'terms returned');
                AssertEqual(out.Contract?.Terms[0].Lines.length, 2, "term 1's coverage");
                AssertEqual(out.Contract?.Terms[1].Lines.length, 1, "term 2's coverage");
            }),
    },

    {
        Id: 'contracts-save-contract.SC2',
        Name: 'the response carries what the SERVER derived, not the client\'s guesses',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('derived values');
                const t1 = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, t1);
                const t2 = addTerm(draft, '2031-01-01', '2031-12-31');
                addLine(draft, t2);

                // The client supplies NONE of these. Every one is the server's to decide.
                Assert(draft.ContractNumber === null, 'precondition: the client names no number');
                Assert(draft.PricedAt === null, 'precondition: the client names no pricing date');

                const out = await save(ctx, draft);
                Assert(out.Success, out.Message ?? 'save failed');

                Assert(/^CTR-\d{6}$/.test(out.Contract?.ContractNumber ?? ''), `number came back as "${out.Contract?.ContractNumber}"`);
                Assert(!!out.Contract?.PricedAt, 'PricedAt was not defaulted, so the agreement has no pricing moment');

                // Round-tripping through FromPayload is what the UI does after a save, so the values
                // it will actually display are the ones asserted here.
                const rebuilt = ContractDraft.FromPayload(out.Contract as ContractDraftPayload);
                AssertEqual(rebuilt.Terms.length, 2, 'rebuilt term count');
                Assert(!!rebuilt.ID, 'the rebuilt draft has no id, so a second save would create a duplicate');
                Assert(rebuilt.IsSaved, 'the rebuilt draft does not know it is saved');
            }),
    },

    {
        Id: 'contracts-save-contract.SC3',
        Name: 'an update modifies in place rather than duplicating',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('update in place');
                const term = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, term, 0, 100);

                const first = await save(ctx, draft);
                Assert(first.Success, first.Message ?? 'first save failed');
                const id = first.Contract?.ID ?? '';

                const round2 = ContractDraft.FromPayload(first.Contract as ContractDraftPayload);
                round2.Description = 'IT-savecontract: update in place (edited)';
                round2.Terms[0].Lines[0].ContractedUnitPrice = 175;

                const second = await save(ctx, round2);
                Assert(second.Success, second.Message ?? 'second save failed');

                AssertEqual(second.Contract?.ID, id, 'the id changed, so a second contract was created');
                AssertEqual(await TxCount(ctx, 'ContractTerm', `ContractID='${id}'`), 1, 'term rows after the update');
                AssertEqual(
                    await TxCount(ctx, 'ContractLine', `ContractTermID='${second.Contract?.Terms[0].ID}'`),
                    1,
                    'coverage rows after the update',
                );
                AssertEqual(Number(second.Contract?.Terms[0].Lines[0].ContractedUnitPrice), 175, 'the edited price');
            }),
    },

    {
        Id: 'contracts-save-contract.SC4',
        Name: 'a NAMED removal deletes; an omitted child does not — the lazy-client data-loss case',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('omission is not deletion');
                const term = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, term, 0, 100);
                addLine(draft, term, 1, 200);

                const first = await save(ctx, draft);
                Assert(first.Success, first.Message ?? 'first save failed');
                const termID = first.Contract?.Terms[0].ID ?? '';
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${termID}'`), 2, 'coverage before');

                // A client that loaded lazily holds ONE line and sends only that. If the server
                // inferred deletion from absence, the other line would silently vanish — a data-loss
                // bug that every test written against a fully-loaded fixture passes straight through.
                const partial = ContractDraft.FromPayload(first.Contract as ContractDraftPayload);
                partial.Terms[0].Lines.splice(1, 1); // drop it WITHOUT recording a removal
                const second = await save(ctx, partial);
                Assert(second.Success, second.Message ?? 'partial save failed');
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${termID}'`), 2, 'coverage after an OMISSION');

                // Now remove it properly, through the model, which records the id.
                const full = ContractDraft.FromPayload(second.Contract as ContractDraftPayload);
                full.RemoveLine(full.Terms[0], full.Terms[0].Lines[1]);
                AssertEqual(full.RemovedLineIDs.length, 1, 'the removal was recorded');
                const third = await save(ctx, full);
                Assert(third.Success, third.Message ?? 'removal save failed');
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${termID}'`), 1, 'coverage after a NAMED removal');
            }),
    },

    {
        Id: 'contracts-save-contract.SC5',
        Name: "a term id belonging to another contract is refused, not silently re-created",
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const a = newDraft('owner A');
                const aTerm = addTerm(a, '2030-01-01', '2030-12-31');
                addLine(a, aTerm);
                const savedA = await save(ctx, a);
                Assert(savedA.Success, savedA.Message ?? 'A failed');

                const b = newDraft('owner B');
                const bTerm = addTerm(b, '2030-01-01', '2030-12-31');
                addLine(b, bTerm);
                const savedB = await save(ctx, b);
                Assert(savedB.Success, savedB.Message ?? 'B failed');

                // Point B's payload at A's term. Creating a fresh term instead would hide whatever
                // went wrong upstream and quietly give B a term it should not have.
                const tampered = ContractDraft.FromPayload(savedB.Contract as ContractDraftPayload);
                tampered.Terms[0].ID = savedA.Contract?.Terms[0].ID ?? null;
                const out = await save(ctx, tampered);
                Assert(!out.Success, 'a foreign term id was accepted');
                Assert(
                    (out.Message ?? '').includes('does not belong to this contract'),
                    `wrong refusal: ${out.Message}`,
                );
            }),
    },

    {
        Id: 'contracts-save-contract.SC6',
        Name: 'a client-supplied ContractNumber is ignored on a NEW contract',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('number is the server\'s');
                const term = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, term);
                draft.ContractNumber = 'CTR-999999'; // a client trying to name its own

                const out = await save(ctx, draft);
                Assert(out.Success, out.Message ?? 'save failed');

                // Honouring it would let two browsers claim the same human-facing number, and
                // ContractNumber is uniquely indexed — so the second one fails at the database with
                // a constraint name.
                Assert(
                    out.Contract?.ContractNumber !== 'CTR-999999',
                    'the client named the contract number and the server took it',
                );
                Assert(/^CTR-\d{6}$/.test(out.Contract?.ContractNumber ?? ''), `got "${out.Contract?.ContractNumber}"`);
            }),
    },

    {
        Id: 'contracts-save-contract.SC7',
        Name: 'an invalid line fails the whole call and writes nothing',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('atomic failure');
                const term = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, term, 0, 100);
                const bad = draft.AddLine(term);
                bad.ProductID = Fx().ProductIDs[1];
                bad.LineType = 'Subscription'; // no SubscriptionTypeID
                bad.Quantity = 1;

                const out = await save(ctx, draft);
                Assert(!out.Success, 'a subscription line with no type was accepted');
                AssertEqual(
                    await TxCount(ctx, 'Contract', `Description='IT-savecontract: atomic failure'`),
                    0,
                    'a contract survived a failed save',
                );
            }),
    },

    {
        Id: 'contracts-save-contract.SC8',
        Name: 'the client-side validator reports FIELD-level issues by section',
        Fn: () =>
            Promise.resolve().then(() => {
                // Framework-free, so this needs no database at all — the point of the draft living
                // in the Entities package rather than in an Angular service.
                const draft = new ContractDraft();
                draft.Status = 'Active';
                const term = draft.AddTerm();
                term.Status = 'Active';
                term.StartDate = '2030-12-31';
                term.EndDate = '2030-01-01'; // backwards
                const line = draft.AddLine(term);
                line.LineType = 'Subscription'; // no type, no product

                const result = draft.Validate();
                Assert(!result.IsValid, 'a draft missing everything reported itself valid');

                const sections = draft.SectionsWithErrors;
                Assert(sections.includes('contract'), 'the missing type/company/customer did not reach the contract pane');
                Assert(sections.includes('terms'), 'the backwards dates did not reach the terms pane');
                Assert(sections.includes('coverage'), 'the bad line did not reach the coverage pane');

                // FIELD level, which is what puts a marker on the input rather than a paragraph
                // above the form.
                const fields = result.Issues.map((i) => i.Field);
                Assert(fields.includes('ContractTypeID'), 'no issue named ContractTypeID');
                Assert(fields.includes('EndDate'), 'no issue named EndDate');
                Assert(fields.includes('SubscriptionTypeID'), 'no issue named SubscriptionTypeID');

                // And positioned, so the UI can point at the right row rather than the right tab.
                const lineIssue = result.Issues.find((i) => i.Field === 'SubscriptionTypeID');
                AssertEqual(lineIssue?.TermIndex, 0, "the line issue's term position");
                AssertEqual(lineIssue?.LineIndex, 0, "the line issue's line position");
            }),
    },

    {
        Id: 'contracts-save-contract.SC9',
        Name: 'removing a term takes its coverage with it',
        Fn: (ctx) =>
            InRolledBackTransaction(ctx, async () => {
                const draft = newDraft('cascade');
                const keep = addTerm(draft, '2030-01-01', '2030-12-31');
                addLine(draft, keep, 0, 100);
                const drop = addTerm(draft, '2031-01-01', '2031-12-31');
                addLine(draft, drop, 0, 200);
                addLine(draft, drop, 1, 300);

                const first = await save(ctx, draft);
                Assert(first.Success, first.Message ?? 'first save failed');
                const doomedTermID = first.Contract?.Terms[1].ID ?? '';
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${doomedTermID}'`), 2, 'coverage before');

                const round2 = ContractDraft.FromPayload(first.Contract as ContractDraftPayload);
                round2.RemoveTerm(round2.Terms[1]);
                AssertEqual(round2.RemovedTermIDs.length, 1, 'the term removal was recorded');
                AssertEqual(round2.RemovedLineIDs.length, 2, "its coverage ids were recorded too — the FK needs them gone first");

                const second = await save(ctx, round2);
                Assert(second.Success, second.Message ?? 'removal save failed');
                AssertEqual(await TxCount(ctx, 'ContractTerm', `ID='${doomedTermID}'`), 0, 'the term survived');
                AssertEqual(await TxCount(ctx, 'ContractLine', `ContractTermID='${doomedTermID}'`), 0, 'its coverage survived');

                const remaining = await Md().GetEntityObject<ContractEntityServer>(E_CONTRACT, Fx().User);
                await remaining.Load(second.Contract?.ID ?? '');
                await remaining.LoadFull(Fx().User);
                AssertEqual(remaining.Terms.length, 1, 'the surviving term count');
            }),
    },
];

for (const check of SaveContractChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-save-contract', {
    Setup: async (ctx) => {
        await CreateContractsFixture(ctx);
    },
    Teardown: async (ctx) => {
        await TeardownContractsFixture(ctx);
    },
});
