/**
 * contracts-graph-save — header + modifications as one save, plus the rules that save enforces.
 *
 * D-15's acceptance test: a contract and its modifications land together or not at all, and
 * HasModifications is monotonic. Each check rolls its transaction back.
 */
import { randomUUID } from 'node:crypto';
import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration/registry';
import {
    ContractEntity,
    ContractTemplateEntity,
    ContractTemplateModificationEntity,
    ContractTemplateProvisionEntity,
    TEMPLATE_DRAFT,
    TEMPLATE_PUBLISHED,
} from '@mj-biz-apps/contracts-entities';
import {
    E_CONTRACT,
    E_MODIFICATION,
    E_PROVISION,
    E_TEMPLATE,
    FindId,
    InRolledBackTransaction,
    NewContract,
    ProviderOf,
    Quote,
    RefuseSave,
    Reopen,
    RequireSave,
    ResolveContractsFixture,
    type ContractsFixture,
} from '../fixture.js';

type Ctx = IntegrationCheckContext;

async function addMod(
    contract: ContractEntity,
    provisionID: string,
    text: string,
): Promise<ContractTemplateModificationEntity> {
    const mod = await contract.Modifications.Create();
    mod.ContractTemplateProvisionID = provisionID;
    mod.ModificationText = text;
    return mod;
}

export const GraphSaveChecks: NamedCheck[] = [
    {
        Id: 'contracts-graph-save.GS1',
        Name: 'GS1 — header + two modifications persist in one Save',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.Notes = `IT-GS1-${randomUUID()}`;
                    c.HasModifications = true;
                });
                await addMod(contract, f.ProvisionIDs[0], 'Negotiated wording for clause A.');
                await addMod(contract, f.ProvisionIDs[1], 'Negotiated wording for clause B.');
                await RequireSave(contract, 'GS1 graph save');

                Assert(!!(contract.ContractNumber ?? '').trim(), 'GS1 saved with no ContractNumber');
                const reopened = await Reopen(ctx, contract.ID);
                AssertEqual(reopened.Modifications.Count, 2, 'GS1 expected two modifications after reopen');
                Assert(reopened.HasModifications === true, 'GS1 HasModifications should stay true');
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS2',
        Name: 'GS2 — a blank modification refuses the whole graph; no header is written',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const notes = `IT-GS2-${randomUUID()}`;
                const contract = await NewContract(ctx, f, (c) => {
                    c.Notes = notes;
                    c.HasModifications = true;
                });
                await addMod(contract, f.ProvisionIDs[0], '');
                await RefuseSave(contract, 'GS2 blank modification', /instead of the standard clause|cannot be null|Modification Text/i);

                const leftover = await FindId(ctx, E_CONTRACT, `Notes = '${Quote(notes)}'`);
                Assert(!leftover, `GS2 wrote a header (${leftover}) for a graph that was refused — D-15 is broken`);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS3',
        Name: 'GS3 — HasModifications false is refused when modification rows are staged',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.HasModifications = false;
                });
                await addMod(contract, f.ProvisionIDs[0], 'A staged deviation.');
                await RefuseSave(contract, 'GS3 flag false with rows', /cannot be marked as unmodified|has modifications/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS4',
        Name: 'GS4 — the flag is monotonic: clearing it after rows exist is refused',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.HasModifications = true;
                });
                await addMod(contract, f.ProvisionIDs[0], 'Recorded deviation.');
                await RequireSave(contract, 'GS4 initial save');

                const reopened = await Reopen(ctx, contract.ID);
                reopened.HasModifications = false;
                await RefuseSave(reopened, 'GS4 clearing the flag', /cannot be marked as unmodified|has modifications/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS5',
        Name: 'GS5 — a standalone modification save forces the parent flag true',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.HasModifications = false;
                });
                await RequireSave(contract, 'GS5 header');
                Assert(contract.HasModifications === false, 'GS5 header should start unmodified');

                const mod = await ProviderOf(ctx).GetEntityObject<ContractTemplateModificationEntity>(
                    E_MODIFICATION,
                    ctx.User,
                );
                mod.NewRecord();
                mod.ContractID = contract.ID;
                mod.ContractTemplateProvisionID = f.ProvisionIDs[0];
                mod.ModificationText = 'Added from the standalone form, not the graph.';
                await RequireSave(mod, 'GS5 standalone modification');

                const reopened = await Reopen(ctx, contract.ID);
                Assert(
                    reopened.HasModifications === true,
                    'GS5 parent HasModifications stayed false after a standalone modification save',
                );
                AssertEqual(reopened.Modifications.Count, 1, 'GS5 expected the standalone row on reopen');
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS6',
        Name: 'GS6 — two staged modifications of the same provision are refused',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.HasModifications = true;
                });
                await addMod(contract, f.ProvisionIDs[0], 'First wording.');
                await addMod(contract, f.ProvisionIDs[0], 'Second wording of the same clause.');
                await RefuseSave(contract, 'GS6 duplicate provision', /modified more than once|ONE negotiated wording/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS7',
        Name: 'GS7 — MustBeChild without a parent is refused',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.ContractTypeID = f.ChangeOrderTypeID;
                    c.ContractTemplateID = null;
                    c.ParentContractID = null;
                });
                await RefuseSave(contract, 'GS7 parentless change order', /must name the contract it changes|ParentContractID/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS8',
        Name: 'GS8 — MustBeRoot with a parent is refused',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const parent = await NewContract(ctx, f);
                await RequireSave(parent, 'GS8 parent');

                const child = await NewContract(ctx, f, (c) => {
                    c.ContractTypeID = f.RootTypeID;
                    c.ParentContractID = parent.ID;
                });
                await RefuseSave(child, 'GS8 rooted type with a parent', /stands on its own|cannot sit under/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS9',
        Name: 'GS9 — a new contract may not incorporate a Draft template',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const draftID = await createDraftTemplate(ctx, f, `IT draft ${randomUUID()}`);
                const contract = await NewContract(ctx, f, (c) => {
                    c.ContractTemplateID = draftID;
                });
                await RefuseSave(contract, 'GS9 draft template', /still a draft|not settled|Publish that version/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS10',
        Name: 'GS10 — a hand-typed CTR- number is refused on create',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.ContractNumber = 'CTR-000001';
                });
                await RefuseSave(contract, 'GS10 reserved number', /CTR-#### pattern is reserved|cannot be entered by hand/i);
            });
        },
    },
    {
        Id: 'contracts-graph-save.GS11',
        Name: 'GS11 — a modification may not cite a provision outside the contract tree',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const otherProvisionID = await createForeignProvision(ctx, f);
                const contract = await NewContract(ctx, f, (c) => {
                    c.HasModifications = true;
                });
                await addMod(contract, otherProvisionID, 'Wording against the wrong edition.');
                await RefuseSave(contract, 'GS11 out-of-tree provision', /belongs to|sits under|agreement version/i);
            });
        },
    },
];

async function createDraftTemplate(ctx: Ctx, f: ContractsFixture, name: string): Promise<string> {
    const template = await ProviderOf(ctx).GetEntityObject<ContractTemplateEntity>(E_TEMPLATE, ctx.User);
    template.NewRecord();
    template.Name = name;
    template.ContractTemplateTypeID = f.TemplateTypeID;
    template.VersionLabel = `draft-${randomUUID().slice(0, 8)}`;
    template.SourceURL = 'https://example.test/draft';
    template.Status = TEMPLATE_DRAFT;
    await RequireSave(template, name);
    return template.ID;
}

async function createForeignProvision(ctx: Ctx, f: ContractsFixture): Promise<string> {
    const template = await ProviderOf(ctx).GetEntityObject<ContractTemplateEntity>(E_TEMPLATE, ctx.User);
    template.NewRecord();
    template.Name = `IT other ${randomUUID().slice(0, 8)}`;
    template.ContractTemplateTypeID = f.TemplateTypeID;
    template.VersionLabel = `other-${randomUUID().slice(0, 8)}`;
    template.SourceURL = 'https://example.test/other';
    template.Status = TEMPLATE_DRAFT;
    await RequireSave(template, 'foreign template draft');

    const provision = await ProviderOf(ctx).GetEntityObject<ContractTemplateProvisionEntity>(E_PROVISION, ctx.User);
    provision.NewRecord();
    provision.ContractTemplateID = template.ID;
    provision.ProvisionNumber = '99';
    provision.Title = 'Foreign clause';
    provision.ProvisionText = 'This clause belongs to a different agreement version.';
    await RequireSave(provision, 'foreign provision');

    template.Status = TEMPLATE_PUBLISHED;
    await RequireSave(template, 'publish foreign template');
    return provision.ID;
}

for (const check of GraphSaveChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-graph-save', {
    Setup: async (ctx) => {
        await ResolveContractsFixture(ctx);
    },
    Teardown: async () => undefined,
});
