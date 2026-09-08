/**
 * Shared vocabulary, transaction discipline, and the helpers every contracts check uses.
 *
 * ISOLATION. Mutating checks run inside {@link InRolledBackTransaction} so numbered contracts and
 * their modifications never reach disk. The committed world (`contracts-world`) is the exception:
 * it is how Explorer gets rows to open, the same split orders uses for ORD-WORLD.
 *
 * EVERY QUERY GOES THROUGH THE PROVIDER, never `ctx.Pool`. The pool is a different connection
 * (it blocks on the open transaction under READ COMMITTED) and is undefined under `mj test`.
 */
import { DatabaseProviderBase, RunView, type IMetadataProvider } from '@memberjunction/core';
import { Assert, type IntegrationCheckContext } from '@memberjunction/testing-integration/registry';
import {
    ContractEntity,
    ContractTemplateEntity,
    ContractTemplateProvisionEntity,
    TEMPLATE_DRAFT,
    TEMPLATE_PUBLISHED,
} from '@mj-biz-apps/contracts-entities';
import {
    CONTRACTS_SCHEMA,
    E_COMPANY,
    E_CONTRACT,
    E_CONTRACT_TYPE,
    E_ORGANIZATION,
    E_PROVISION,
    E_TEMPLATE,
    E_TEMPLATE_TYPE,
} from './entity-names.js';

export * from './entity-names.js';

/** Notes markers the committed world (and watchlist) look up. Stable across re-runs. */
export const WORLD_NOTE = {
    activeMsa: 'CTR-WORLD:active-msa',
    noticePassed: 'CTR-WORLD:notice-passed',
    executedFuture: 'CTR-WORLD:executed-future',
    awaitingDoc: 'CTR-WORLD:awaiting-doc',
    paymentLink: 'CTR-WORLD:payment-link',
    expired: 'CTR-WORLD:expired',
    draft: 'CTR-WORLD:draft',
    changeOrder: 'CTR-WORLD:change-order',
    terminated: 'CTR-WORLD:terminated',
    cancelWindow: 'CTR-WORLD:cancel-window',
    supersededPred: 'CTR-WORLD:superseded-pred',
    supersededSucc: 'CTR-WORLD:superseded-succ',
} as const;

export const WORLD_TEMPLATE_VERSION = 'CTR-WORLD';
export const WORLD_TEMPLATE_NAME = 'IT Master Agreement';

export interface ContractsFixture {
    CompanyID: string;
    Organizations: {
        northwind: string;
        cascadia: string;
        meridian: string;
        harbor: string;
    };
    /** TemplateRequired + RequiresExecutedDocument, unrestricted placement (Order Form as seeded). */
    OrderFormTypeID: string;
    /** RequiresExecutedDocument = 0 (Payment Link as seeded). */
    PaymentLinkTypeID: string;
    /** MustBeChild (Change Order as seeded). */
    ChangeOrderTypeID: string;
    /** MustBeRoot (Statement of Work as seeded). */
    RootTypeID: string;
    TemplateTypeID: string;
    TemplateID: string;
    /** At least two, ordered by ProvisionSortKey. */
    ProvisionIDs: string[];
}

const CUSTOMERS: ReadonlyArray<{ key: keyof ContractsFixture['Organizations']; name: string }> = [
    { key: 'northwind', name: 'Northwind Association' },
    { key: 'cascadia', name: 'Cascadia Health Society' },
    { key: 'meridian', name: 'Meridian Credit Union' },
    { key: 'harbor', name: 'Harbor Point Institute' },
];

const IT_PROVISIONS: ReadonlyArray<{ number: string; title: string; text: string }> = [
    {
        number: '1',
        title: 'Recitals',
        text: 'This agreement records the standard terms Blue Cypress offers to every customer of this edition.',
    },
    {
        number: '1.9',
        title: 'Fees',
        text: 'Customer shall pay the fees set out in the applicable Order Form within thirty (30) days of invoice.',
    },
    {
        number: '1.10',
        title: 'Taxes',
        text: 'Fees are exclusive of applicable taxes, which Customer shall pay in addition to the fees.',
    },
    {
        number: '2',
        title: 'Limitation of Liability',
        text: 'Liability is capped at the total fees paid by Customer in the twelve (12) months preceding the claim.',
    },
];

let cached: ContractsFixture | null = null;

export function Quote(value: string): string {
    return value.replace(/'/g, "''");
}

export function ProviderOf(ctx: IntegrationCheckContext): IMetadataProvider {
    return ctx.Provider;
}

export function View(ctx: IntegrationCheckContext): RunView {
    return RunView.FromMetadataProvider(ctx.Provider as IMetadataProvider);
}

export function UtcToday(): Date {
    const now = new Date();
    return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

export function UtcDay(offsetDays: number): Date {
    const day = UtcToday();
    day.setUTCDate(day.getUTCDate() + offsetDays);
    return day;
}

export async function FindRows<T extends object>(
    ctx: IntegrationCheckContext,
    entityName: string,
    extraFilter: string,
    fields: string[],
    orderBy?: string,
): Promise<T[]> {
    const result = await View(ctx).RunView<T>(
        {
            EntityName: entityName,
            ExtraFilter: extraFilter || undefined,
            Fields: fields,
            OrderBy: orderBy,
            ResultType: 'simple',
        },
        ctx.User,
    );
    Assert(result.Success, `RunView ${entityName} failed — ${result.ErrorMessage ?? 'unknown error'}`);
    return result.Results ?? [];
}

export async function FindId(
    ctx: IntegrationCheckContext,
    entityName: string,
    extraFilter: string,
    orderBy?: string,
): Promise<string | null> {
    const rows = await FindRows<{ ID: string }>(ctx, entityName, extraFilter, ['ID'], orderBy);
    return rows[0]?.ID ?? null;
}

export async function RequireSave(
    entity: { Save: () => Promise<boolean>; LatestResult?: { CompleteMessage?: string; Message?: string } },
    what: string,
): Promise<void> {
    const ok = await entity.Save();
    Assert(
        ok,
        `${what} failed: ${entity.LatestResult?.CompleteMessage ?? entity.LatestResult?.Message ?? 'unknown error'}`,
    );
}

export async function RefuseSave(
    entity: { Save: () => Promise<boolean>; LatestResult?: { CompleteMessage?: string; Message?: string } },
    what: string,
    matching?: RegExp,
): Promise<string> {
    const ok = await entity.Save();
    const message = entity.LatestResult?.CompleteMessage ?? entity.LatestResult?.Message ?? '';
    Assert(!ok, `${what} was accepted; it should have been refused. LatestResult: ${message || 'empty'}`);
    if (matching) {
        Assert(matching.test(message), `${what} was refused, but the message did not match ${matching}: ${message}`);
    }
    return message;
}

/**
 * A minimal valid Order Form, not yet saved. `shape` mutates it for whatever the check is about.
 *
 * Built through the PROVIDER so the entity rides the same connection as the open transaction.
 */
export async function NewContract(
    ctx: IntegrationCheckContext,
    fixture: ContractsFixture,
    shape?: (contract: ContractEntity) => void,
): Promise<ContractEntity> {
    const contract = await ProviderOf(ctx).GetEntityObject<ContractEntity>(E_CONTRACT, ctx.User);
    contract.NewRecord();
    contract.ContractTypeID = fixture.OrderFormTypeID;
    contract.CompanyID = fixture.CompanyID;
    contract.CustomerOrganizationID = fixture.Organizations.northwind;
    contract.ContractTemplateID = fixture.TemplateID;
    contract.AutoRenew = false;
    contract.HasModifications = false;
    shape?.(contract);
    return contract;
}

export async function Reopen(ctx: IntegrationCheckContext, contractID: string): Promise<ContractEntity> {
    const contract = await ProviderOf(ctx).GetEntityObject<ContractEntity>(E_CONTRACT, ctx.User);
    Assert(await contract.Load(contractID), `contract ${contractID} could not be re-read`);
    await contract.LoadRelatedRecords('Modifications');
    Assert(contract.Modifications.IsLoaded, 'the Modifications collection did not load');
    return contract;
}

export async function InRolledBackTransaction<T>(
    ctx: IntegrationCheckContext,
    body: () => Promise<T>,
): Promise<T> {
    const db = ctx.Provider as unknown as DatabaseProviderBase;
    await db.BeginTransaction();
    try {
        return await body();
    } finally {
        try {
            await db.RollbackTransaction();
        } catch {
            // A body that already rolled back can leave nothing to roll back. Swallow so a cleanup
            // error does not replace the check's real failure.
        }
    }
}

export async function TxOne<T extends Record<string, unknown>>(
    ctx: IntegrationCheckContext,
    sql: string,
): Promise<T> {
    const provider = ctx.Provider as unknown as {
        ExecuteSQL: (
            sql: string,
            params: Record<string, unknown> | undefined,
            options: { isMutation: boolean; description: string },
            user: unknown,
        ) => Promise<Record<string, unknown>[]>;
    };
    const rows = await provider.ExecuteSQL(sql, undefined, { isMutation: false, description: 'contracts check read' }, ctx.User);
    Assert(!!rows?.length, `TxOne returned no rows for: ${sql}`);
    return rows[0] as T;
}

export async function TxQuery<T extends Record<string, unknown>>(
    ctx: IntegrationCheckContext,
    sql: string,
): Promise<T[]> {
    const provider = ctx.Provider as unknown as {
        ExecuteSQL: (
            sql: string,
            params: Record<string, unknown> | undefined,
            options: { isMutation: boolean; description: string },
            user: unknown,
        ) => Promise<Record<string, unknown>[]>;
    };
    const rows = await provider.ExecuteSQL(sql, undefined, { isMutation: false, description: 'contracts check read' }, ctx.User);
    return (rows ?? []) as T[];
}

/**
 * Resolve (and cache) the vocabulary the suite needs. Types come from metadata; the published
 * template and demo customers are created if missing so a host without `demo-data/` still runs.
 *
 * Called OUTSIDE the rolled-back transaction — creating the template inside one would disappear
 * before the next check.
 */
export async function ResolveContractsFixture(ctx: IntegrationCheckContext): Promise<ContractsFixture> {
    if (cached) {
        return cached;
    }

    const types = await FindRows<{
        ID: string;
        Name: string;
        MustBeRoot: boolean;
        MustBeChild: boolean;
        TemplateRequired: boolean;
        RequiresExecutedDocument: boolean;
        Status: string;
    }>(
        ctx,
        E_CONTRACT_TYPE,
        `Status = 'Active'`,
        ['ID', 'Name', 'MustBeRoot', 'MustBeChild', 'TemplateRequired', 'RequiresExecutedDocument', 'Status'],
    );
    Assert(
        types.length > 0,
        'fixture: no active contract types. Push metadata/contract-types (mj sync push --dir metadata) first.',
    );

    const orderForm = types.find((t) => t.TemplateRequired && t.RequiresExecutedDocument && !t.MustBeChild && !t.MustBeRoot);
    const paymentLink = types.find((t) => !t.RequiresExecutedDocument);
    const changeOrder = types.find((t) => t.MustBeChild);
    const root = types.find((t) => t.MustBeRoot);
    Assert(!!orderForm, 'fixture: no unrestricted type that requires a template and executed paper (seeded as Order Form).');
    Assert(!!paymentLink, 'fixture: no type with RequiresExecutedDocument = 0 (seeded as Payment Link).');
    Assert(!!changeOrder, 'fixture: no type with MustBeChild = 1 (seeded as Change Order).');
    Assert(!!root, 'fixture: no type with MustBeRoot = 1 (seeded as Statement of Work).');

    const templateTypeID = await FindId(ctx, E_TEMPLATE_TYPE, `Status = 'Active'`, 'Name ASC');
    Assert(
        !!templateTypeID,
        'fixture: no active contract template type. Push metadata/contract-template-types first.',
    );

    const companyID = await resolveCompany(ctx);
    const organizations = await resolveOrganizations(ctx);
    const templateID = await ensurePublishedTemplate(ctx, templateTypeID!);
    const provisions = await FindRows<{ ID: string }>(
        ctx,
        E_PROVISION,
        `ContractTemplateID = '${templateID}'`,
        ['ID'],
        'ProvisionSortKey ASC, ProvisionNumber ASC',
    );
    Assert(
        provisions.length >= 2,
        `fixture: published template ${templateID} needs at least two provisions; found ${provisions.length}.`,
    );

    cached = {
        CompanyID: companyID,
        Organizations: organizations,
        OrderFormTypeID: orderForm!.ID,
        PaymentLinkTypeID: paymentLink!.ID,
        ChangeOrderTypeID: changeOrder!.ID,
        RootTypeID: root!.ID,
        TemplateTypeID: templateTypeID!,
        TemplateID: templateID,
        ProvisionIDs: provisions.map((p) => p.ID),
    };
    return cached;
}

async function resolveCompany(ctx: IntegrationCheckContext): Promise<string> {
    const named = await FindId(ctx, E_COMPANY, `Name LIKE '%Blue Cypress%'`);
    if (named) return named;
    const any = await FindId(ctx, E_COMPANY, '', 'Name ASC');
    Assert(
        !!any,
        'fixture: no MJ: Companies row. Run the orders catalog-world bundle, or create a company in Explorer.',
    );
    return any!;
}

async function resolveOrganizations(ctx: IntegrationCheckContext): Promise<ContractsFixture['Organizations']> {
    const ids: Partial<ContractsFixture['Organizations']> = {};
    for (const customer of CUSTOMERS) {
        const existing = await FindId(ctx, E_ORGANIZATION, `Name = '${Quote(customer.name)}'`);
        if (existing) {
            ids[customer.key] = existing;
            continue;
        }
        const created = await createOrganization(ctx, customer.name);
        if (created) {
            ids[customer.key] = created;
            continue;
        }
        const fallback = await FindId(ctx, E_ORGANIZATION, '', 'Name ASC');
        Assert(
            !!fallback,
            `fixture: could not create organization "${customer.name}" and no existing organization was found. ` +
                'Run the orders catalog-world bundle (it seeds customer orgs) or push demo-data/.',
        );
        ids[customer.key] = fallback!;
    }
    return ids as ContractsFixture['Organizations'];
}

async function createOrganization(ctx: IntegrationCheckContext, name: string): Promise<string | null> {
    try {
        const org = await ProviderOf(ctx).GetEntityObject(E_ORGANIZATION, ctx.User);
        org.NewRecord();
        org.Set('Name', name);
        org.Set('Status', 'Active');
        if (!(await org.Save())) {
            return null;
        }
        const id = String(org.Get('ID') ?? '');
        return id || null;
    } catch {
        return null;
    }
}

/**
 * A published, usable template with enough provisions to hang modifications on.
 *
 * Prefers the committed IT template so re-runs are no-ops. Will not try to edit a Published
 * version (the freeze trigger refuses provision writes); a missing provision list means we
 * create a new Draft version instead of fighting the freeze.
 */
async function ensurePublishedTemplate(ctx: IntegrationCheckContext, templateTypeID: string): Promise<string> {
    const existing = await FindId(
        ctx,
        E_TEMPLATE,
        `VersionLabel = '${WORLD_TEMPLATE_VERSION}' AND Status = '${TEMPLATE_PUBLISHED}'`,
    );
    if (existing) {
        const count = await FindRows<{ ID: string }>(ctx, E_PROVISION, `ContractTemplateID = '${existing}'`, ['ID']);
        if (count.length >= 2) return existing;
    }

    const template = await ProviderOf(ctx).GetEntityObject<ContractTemplateEntity>(E_TEMPLATE, ctx.User);

    const draftID = await FindId(ctx, E_TEMPLATE, `VersionLabel = '${WORLD_TEMPLATE_VERSION}'`);
    if (draftID) {
        Assert(await template.Load(draftID), `could not load template ${draftID}`);
    } else {
        template.NewRecord();
        template.Name = WORLD_TEMPLATE_NAME;
        template.ContractTemplateTypeID = templateTypeID;
        template.VersionLabel = WORLD_TEMPLATE_VERSION;
        template.SourceURL = 'https://example.test/it-master-agreement';
        template.Description = 'Integration-test master agreement. Four clauses, including 1.9 / 1.10 for natural order.';
        template.Status = TEMPLATE_DRAFT;
        template.IntroducedDate = UtcToday();
        await RequireSave(template, 'create IT master agreement');
    }

    if (template.Status !== TEMPLATE_PUBLISHED) {
        await seedProvisions(ctx, template.ID);
        template.SourceURL = template.SourceURL || 'https://example.test/it-master-agreement';
        template.Status = TEMPLATE_PUBLISHED;
        await RequireSave(template, 'publish IT master agreement');
    }

    return template.ID;
}

async function seedProvisions(ctx: IntegrationCheckContext, templateID: string): Promise<void> {
    for (const clause of IT_PROVISIONS) {
        const already = await FindId(
            ctx,
            E_PROVISION,
            `ContractTemplateID = '${templateID}' AND ProvisionNumber = '${Quote(clause.number)}'`,
        );
        if (already) continue;
        const provision = await ProviderOf(ctx).GetEntityObject<ContractTemplateProvisionEntity>(E_PROVISION, ctx.User);
        provision.NewRecord();
        provision.ContractTemplateID = templateID;
        provision.ProvisionNumber = clause.number;
        provision.Title = clause.title;
        provision.ProvisionText = clause.text;
        await RequireSave(provision, `provision ${clause.number}`);
    }
}

/** Escape hatch for checks that need to see the schema name in SQL. */
export function ContractTable(): string {
    return `${CONTRACTS_SCHEMA}.[Contract]`;
}
