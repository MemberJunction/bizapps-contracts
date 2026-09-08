/**
 * Commit a contracts portfolio through BaseEntity so Explorer has rows to open.
 *
 * Dates are relative to UTC today so derived State / watchlist flags stay correct on every run —
 * demo-data/ cannot do that (a metadata file cannot compute). Identified by {@link WORLD_NOTE},
 * so a re-run updates rather than duplicating.
 */
import type { ContractEntity, ContractTemplateModificationEntity } from '@mj-biz-apps/contracts-entities';
import { Assert, type IntegrationCheckContext } from '@memberjunction/testing-integration/registry';
import {
    E_CONTRACT,
    E_MODIFICATION,
    FindId,
    FindRows,
    NewContract,
    ProviderOf,
    Quote,
    Reopen,
    RequireSave,
    ResolveContractsFixture,
    UtcDay,
    WORLD_NOTE,
    type ContractsFixture,
} from '../fixture.js';
import { SetWorld, type WorldContract, type WorldState } from './world.js';

export async function LoadWorld(ctx: IntegrationCheckContext): Promise<WorldState> {
    const fixture = await ResolveContractsFixture(ctx);

    const activeMsa = await upsert(
        ctx,
        fixture,
        WORLD_NOTE.activeMsa,
        'Northwind Association — active MSA with two negotiated clauses.',
        fixture.Organizations.northwind,
        (c) => {
            c.AutoRenew = true;
            c.HasModifications = true;
            c.ExecutedDate = UtcDay(-30);
            c.EffectiveDate = UtcDay(-30);
            c.EndDate = UtcDay(120);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
            c.AnnualIncreasePercent = 4;
        },
    );
    await ensureModifications(ctx, fixture, activeMsa.ID);

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.noticePassed,
        'Cascadia Health Society — renewal notice window has already passed.',
        fixture.Organizations.cascadia,
        (c) => {
            c.AutoRenew = true;
            c.ExecutedDate = UtcDay(-200);
            c.EffectiveDate = UtcDay(-200);
            c.EndDate = UtcDay(20);
            c.RenewalNoticeDays = 90;
            c.CancellationWindowDays = 45;
            c.AnnualIncreasePercent = 3;
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.executedFuture,
        'Meridian Credit Union — signed, term starts next month (R-19 Executed).',
        fixture.Organizations.meridian,
        (c) => {
            c.AutoRenew = true;
            c.ExecutedDate = UtcDay(-5);
            c.EffectiveDate = UtcDay(30);
            c.EndDate = UtcDay(395);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
            c.AnnualIncreasePercent = 3;
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.awaitingDoc,
        'Harbor Point Institute — in force, executed paper never filed.',
        fixture.Organizations.harbor,
        (c) => {
            c.ExecutedDate = UtcDay(-14);
            c.EffectiveDate = UtcDay(-10);
            c.EndDate = UtcDay(180);
            c.RenewalNoticeDays = 30;
            c.CancellationWindowDays = 30;
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.paymentLink,
        'Northwind Association — Payment Link. Nobody signs, so it is never awaiting paper.',
        fixture.Organizations.northwind,
        (c) => {
            c.ContractTypeID = fixture.PaymentLinkTypeID;
            c.EffectiveDate = UtcDay(-40);
            c.EndDate = UtcDay(325);
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.expired,
        'Cascadia Health Society — term ran out and was not renewed.',
        fixture.Organizations.cascadia,
        (c) => {
            c.ExecutedDate = UtcDay(-400);
            c.EffectiveDate = UtcDay(-400);
            c.EndDate = UtcDay(-14);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
            c.AnnualIncreasePercent = 3;
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.draft,
        'Meridian Credit Union — being prepared. Nothing signed, no dates agreed.',
        fixture.Organizations.meridian,
        (c) => {
            c.AutoRenew = true;
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.changeOrder,
        'Northwind Association — change order adding a second site mid-term.',
        fixture.Organizations.northwind,
        (c) => {
            c.ContractTypeID = fixture.ChangeOrderTypeID;
            c.ContractTemplateID = null;
            c.ParentContractID = activeMsa.ID;
            c.ExecutedDate = UtcDay(-7);
            c.EffectiveDate = UtcDay(-7);
            c.EndDate = UtcDay(120);
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.terminated,
        'Harbor Point Institute — ended early. Terminated outranks the remaining term.',
        fixture.Organizations.harbor,
        (c) => {
            c.ExecutedDate = UtcDay(-90);
            c.EffectiveDate = UtcDay(-90);
            c.EndDate = UtcDay(90);
            c.TerminatedDate = UtcDay(-1);
            c.RenewalNoticeDays = 30;
            c.CancellationWindowDays = 30;
        },
    );

    await upsert(
        ctx,
        fixture,
        WORLD_NOTE.cancelWindow,
        'Cascadia Health Society — today sits inside the customer cancellation window.',
        fixture.Organizations.cascadia,
        (c) => {
            c.AutoRenew = true;
            c.ExecutedDate = UtcDay(-200);
            c.EffectiveDate = UtcDay(-200);
            c.EndDate = UtcDay(15);
            c.RenewalNoticeDays = 90;
            c.CancellationWindowDays = 30;
        },
    );

    const successor = await upsert(
        ctx,
        fixture,
        WORLD_NOTE.supersededSucc,
        'Northwind Association — the re-papered agreement that replaced the predecessor.',
        fixture.Organizations.northwind,
        (c) => {
            c.AutoRenew = true;
            c.ExecutedDate = UtcDay(-10);
            c.EffectiveDate = UtcDay(-10);
            c.EndDate = UtcDay(355);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
        },
    );

    const predecessor = await upsert(
        ctx,
        fixture,
        WORLD_NOTE.supersededPred,
        'Northwind Association — superseded. The successor FK is the superseded state.',
        fixture.Organizations.northwind,
        (c) => {
            c.AutoRenew = false;
            c.ExecutedDate = UtcDay(-400);
            c.EffectiveDate = UtcDay(-400);
            c.EndDate = UtcDay(120);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
        },
    );

    if (!predecessor.ID || !successor.ID) {
        throw new Error('CTR-WORLD superseded pair did not save');
    }
    const pred = await Reopen(ctx, predecessor.ID);
    if ((pred.SupersededByContractID ?? '').toLowerCase() !== successor.ID.toLowerCase()) {
        pred.Supersede(await Reopen(ctx, successor.ID));
        await RequireSave(pred, 'point predecessor at successor');
    }

    const contracts: Record<string, WorldContract> = {};
    for (const [key, notes] of Object.entries(WORLD_NOTE)) {
        const row = await FindRows<{ ID: string; ContractNumber: string }>(
            ctx,
            E_CONTRACT,
            `Notes = '${Quote(notes)}'`,
            ['ID', 'ContractNumber'],
        );
        Assert(row.length === 1, `CTR-WORLD expected exactly one contract with Notes = ${notes}, found ${row.length}`);
        contracts[key] = { ID: row[0].ID, ContractNumber: row[0].ContractNumber };
    }

    const world: WorldState = { TemplateID: fixture.TemplateID, Contracts: contracts };
    SetWorld(world);
    return world;
}

async function upsert(
    ctx: IntegrationCheckContext,
    fixture: ContractsFixture,
    notes: string,
    description: string,
    organizationID: string,
    shape: (contract: ContractEntity) => void,
): Promise<WorldContract> {
    const existingID = await FindId(ctx, E_CONTRACT, `Notes = '${Quote(notes)}'`);
    const contract = existingID
        ? await (async () => {
              const loaded = await ProviderOf(ctx).GetEntityObject<ContractEntity>(E_CONTRACT, ctx.User);
              Assert(await loaded.Load(existingID), `could not load ${notes}`);
              return loaded;
          })()
        : await NewContract(ctx, fixture);

    contract.Notes = notes;
    contract.Description = description;
    contract.CustomerOrganizationID = organizationID;
    contract.CompanyID = fixture.CompanyID;
    if (!existingID) {
        contract.ContractTypeID = fixture.OrderFormTypeID;
        contract.ContractTemplateID = fixture.TemplateID;
        contract.AutoRenew = false;
        contract.HasModifications = false;
    }
    shape(contract);
    await RequireSave(contract, notes);
    Assert(!!(contract.ContractNumber ?? '').trim(), `${notes} saved without a ContractNumber`);
    return { ID: contract.ID, ContractNumber: contract.ContractNumber as string };
}

async function ensureModifications(
    ctx: IntegrationCheckContext,
    fixture: ContractsFixture,
    contractID: string,
): Promise<void> {
    const existing = await FindRows<{ ID: string }>(ctx, E_MODIFICATION, `ContractID = '${contractID}'`, ['ID']);
    if (existing.length >= 2) return;

    const contract = await Reopen(ctx, contractID);
    contract.HasModifications = true;

    const texts = [
        {
            provisionID: fixture.ProvisionIDs[fixture.ProvisionIDs.length - 1],
            text: 'Liability is capped at the total fees paid by Customer in the twenty-four (24) months preceding the claim, rather than twelve (12) months.',
            notes: 'Negotiated by legal; the customer procurement policy requires a 24-month look-back.',
        },
        {
            provisionID: fixture.ProvisionIDs[1] ?? fixture.ProvisionIDs[0],
            text: 'Prior written approval is required for any single expense exceeding $2,500 USD.',
            notes: 'Raised threshold to reduce approval churn on routine travel.',
        },
    ];

    for (const row of texts) {
        const already = await FindId(
            ctx,
            E_MODIFICATION,
            `ContractID = '${contractID}' AND ContractTemplateProvisionID = '${row.provisionID}'`,
        );
        if (already) continue;
        const mod = await contract.Modifications.Create();
        applyModification(mod, row.provisionID, row.text, row.notes);
    }
    await RequireSave(contract, 'active-msa modifications');
}

function applyModification(
    mod: ContractTemplateModificationEntity,
    provisionID: string,
    text: string,
    notes: string,
): void {
    mod.ContractTemplateProvisionID = provisionID;
    mod.ModificationText = text;
    mod.Notes = notes;
}
