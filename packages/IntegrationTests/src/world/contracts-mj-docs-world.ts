/**
 * Multi-domain MJ Docs (`MJ: Artifacts`) world loader for BizApps Contracts integration tests.
 *
 * Commits a realistic >= 20-record portfolio across 4 industry verticals (Enterprise IT & Legal,
 * Healthcare Compliance, Financial Services, Research & Education), spanning:
 *   - Organizations (`MJ_BizApps_Common: Organizations`)
 *   - People (`MJ_BizApps_Common: People`)
 *   - Roles verification (`MJ: Roles`)
 *   - Published Contract Templates & Relational Clauses (`ContractTemplate`, `ContractTemplateProvision`)
 *   - Versioned MJ Docs (`MJ: Artifacts`, `MJ: Artifact Versions`) for Assembled Contract Drafts,
 *     AI Contract Review Memos, and Executive Summaries
 *   - Contracts (`Contract`) covering BOTH linked `DocumentArtifactID` and null `DocumentArtifactID`
 *   - Strictly relational negotiated overrides (`ContractTemplateModification`)
 *
 * Idempotent across re-runs via stable `CTR-DOCS-WORLD:` notes markers and deterministic artifact names.
 */
import type { BaseEntity } from '@memberjunction/core';
import { Assert, type IntegrationCheckContext } from '@memberjunction/testing-integration/registry';
import {
    ContractEntity,
    ContractTemplateEntity,
    ContractTemplateModificationEntity,
    ContractTemplateProvisionEntity,
    TEMPLATE_DRAFT,
    TEMPLATE_PUBLISHED,
} from '@mj-biz-apps/contracts-entities';
import {
    E_ARTIFACT,
    E_ARTIFACT_TYPE,
    E_ARTIFACT_VERSION,
    E_CONTRACT,
    E_MODIFICATION,
    E_PERSON,
    E_PROVISION,
    E_ROLE,
    E_TEMPLATE,
    FindId,
    FindRows,
    NewContract,
    ProviderOf,
    Quote,
    Reopen,
    RequireSave,
    ResolveContractsFixture,
    UtcDay,
    View,
    type ContractsFixture,
} from '../fixture.js';

export const MJ_DOCS_WORLD_PREFIX = 'CTR-DOCS-WORLD:';

export const MJ_DOCS_WORLD_NOTES = {
    northwindDraftMsa: `${MJ_DOCS_WORLD_PREFIX}northwind-draft-msa`,
    cascadiaReviewMemo: `${MJ_DOCS_WORLD_PREFIX}cascadia-review-memo`,
    meridianExecSummary: `${MJ_DOCS_WORLD_PREFIX}meridian-exec-summary`,
    harborDraftSow: `${MJ_DOCS_WORLD_PREFIX}harbor-draft-sow`,
    northwindChangeOrder: `${MJ_DOCS_WORLD_PREFIX}northwind-change-order`,
    northwindUnlinkedPayLink: `${MJ_DOCS_WORLD_PREFIX}northwind-unlinked-paylink`,
    cascadiaUnlinkedExpired: `${MJ_DOCS_WORLD_PREFIX}cascadia-unlinked-expired`,
    harborUnlinkedTerminated: `${MJ_DOCS_WORLD_PREFIX}harbor-unlinked-terminated`,
} as const;

export const MJ_DOCS_ARTIFACT_NAMES = {
    assembledMsaDraft: 'CTR-DOCS-WORLD: Northwind Assembled MSA Draft',
    aiReviewMemo: 'CTR-DOCS-WORLD: Cascadia AI Contract Review Memo',
    executiveSummary: 'CTR-DOCS-WORLD: Meridian Executive Summary Brief',
    assembledSowDraft: 'CTR-DOCS-WORLD: Harbor Point Assembled SOW Draft',
    changeOrderMemo: 'CTR-DOCS-WORLD: Northwind Change Order Review Memo',
} as const;

export const MJ_DOCS_BAA_TEMPLATE_VERSION = 'CTR-DOCS-BAA-V1';

export type TypedPersonEntity = BaseEntity & {
    ID: string;
    FirstName: string;
    LastName: string;
    Status: string;
    Load(id: string): Promise<boolean>;
};

export type TypedArtifactEntity = BaseEntity & {
    ID: string;
    Name: string;
    Description: string | null;
    TypeID: string;
    UserID: string;
    Visibility: 'Always' | 'System Only';
    Load(id: string): Promise<boolean>;
};

export type TypedArtifactVersionEntity = BaseEntity & {
    ID: string;
    ArtifactID: string;
    VersionNumber: number;
    Name: string | null;
    Comments: string | null;
    Content: string | null;
    ContentMode: 'File' | 'Text';
    UserID: string;
    Load(id: string): Promise<boolean>;
};

export interface MjDocsWorldContractRecord {
    ID: string;
    ContractNumber: string;
    DocumentArtifactID: string | null;
}

export interface ContractsMjDocsWorldState {
    Fixture: ContractsFixture;
    ArtifactTypeID: string;
    RoleCount: number;
    People: {
        elena: string;
        marcus: string;
        priya: string;
        david: string;
    };
    BaaTemplateID: string;
    BaaProvisionIDs: string[];
    Artifacts: {
        assembledMsaDraft: string;
        aiReviewMemo: string;
        executiveSummary: string;
        assembledSowDraft: string;
        changeOrderMemo: string;
    };
    ArtifactVersionCount: number;
    Contracts: Record<keyof typeof MJ_DOCS_WORLD_NOTES, MjDocsWorldContractRecord>;
    ModificationCount: number;
    TotalDomainRecords: number;
}

interface PersonSpec {
    key: keyof ContractsMjDocsWorldState['People'];
    firstName: string;
    lastName: string;
}

const WORLD_PEOPLE: ReadonlyArray<PersonSpec> = [
    { key: 'elena', firstName: 'Elena', lastName: 'Vance' },
    { key: 'marcus', firstName: 'Marcus', lastName: 'Chen' },
    { key: 'priya', firstName: 'Priya', lastName: 'Nair' },
    { key: 'david', firstName: 'David', lastName: 'Okafor' },
];

const BAA_PROVISIONS: ReadonlyArray<{ number: string; title: string; text: string }> = [
    {
        number: '3.1',
        title: 'Protected Health Information Safeguards',
        text: 'Vendor shall maintain administrative, physical, and technical safeguards aligned with HIPAA Security Rule standards.',
    },
    {
        number: '4.2',
        title: 'Breach Notification Window',
        text: 'Vendor shall notify Covered Entity of any confirmed breach of unsecured PHI within five (5) business days of discovery.',
    },
];

let cachedMjDocsWorld: ContractsMjDocsWorldState | null = null;

export function PeekContractsMjDocsWorld(): ContractsMjDocsWorldState | null {
    return cachedMjDocsWorld;
}

export function ResetContractsMjDocsWorldCache(): void {
    cachedMjDocsWorld = null;
}

export async function ResolveArtifactTypeID(ctx: IntegrationCheckContext): Promise<string> {
    const types = await FindRows<{ ID: string; Name: string }>(ctx, E_ARTIFACT_TYPE, '', ['ID', 'Name'], 'Name ASC');
    const chosen =
        types.find((t) => t.Name.toLowerCase() === 'markdown') ??
        types.find((t) => t.Name.toLowerCase().includes('document')) ??
        types[0];
    Assert(!!chosen?.ID, 'MJ: Artifact Types must contain at least one artifact type');
    return chosen.ID;
}

export async function CreateArtifactWithVersions(
    ctx: IntegrationCheckContext,
    artifactTypeID: string,
    name: string,
    description: string,
    versions: ReadonlyArray<{ versionNumber: number; name: string; comments: string; content: string }>,
): Promise<{ artifactID: string; versionIDs: string[] }> {
    let artifactID = await FindId(ctx, E_ARTIFACT, `Name = '${Quote(name)}'`);
    if (!artifactID) {
        const artifact = await ProviderOf(ctx).GetEntityObject<TypedArtifactEntity>(E_ARTIFACT, ctx.User);
        artifact.NewRecord();
        artifact.Name = name;
        artifact.Description = description;
        artifact.TypeID = artifactTypeID;
        artifact.UserID = ctx.User.ID;
        artifact.Visibility = 'Always';
        await RequireSave(artifact, `create artifact ${name}`);
        artifactID = artifact.ID;
    }

    const versionIDs: string[] = [];
    for (const v of versions) {
        let verID = await FindId(
            ctx,
            E_ARTIFACT_VERSION,
            `ArtifactID = '${artifactID}' AND VersionNumber = ${v.versionNumber}`,
        );
        if (!verID) {
            const ver = await ProviderOf(ctx).GetEntityObject<TypedArtifactVersionEntity>(E_ARTIFACT_VERSION, ctx.User);
            ver.NewRecord();
            ver.ArtifactID = artifactID;
            ver.VersionNumber = v.versionNumber;
            ver.Name = v.name;
            ver.Comments = v.comments;
            ver.Content = v.content;
            ver.ContentMode = 'Text';
            ver.UserID = ctx.User.ID;
            await RequireSave(ver, `create artifact version ${name} v${v.versionNumber}`);
            verID = ver.ID;
        }
        versionIDs.push(verID);
    }

    return { artifactID, versionIDs };
}

async function resolvePeople(ctx: IntegrationCheckContext): Promise<ContractsMjDocsWorldState['People']> {
    const out: Partial<ContractsMjDocsWorldState['People']> = {};
    for (const spec of WORLD_PEOPLE) {
        const existing = await FindId(
            ctx,
            E_PERSON,
            `FirstName = '${Quote(spec.firstName)}' AND LastName = '${Quote(spec.lastName)}'`,
        );
        if (existing) {
            out[spec.key] = existing;
            continue;
        }
        const person = await ProviderOf(ctx).GetEntityObject<TypedPersonEntity>(E_PERSON, ctx.User);
        person.NewRecord();
        person.FirstName = spec.firstName;
        person.LastName = spec.lastName;
        person.Status = 'Active';
        await RequireSave(person, `create person ${spec.firstName} ${spec.lastName}`);
        out[spec.key] = person.ID;
    }
    return out as ContractsMjDocsWorldState['People'];
}

async function ensureBaaTemplate(
    ctx: IntegrationCheckContext,
    templateTypeID: string,
): Promise<{ templateID: string; provisionIDs: string[] }> {
    const existing = await FindId(
        ctx,
        E_TEMPLATE,
        `VersionLabel = '${MJ_DOCS_BAA_TEMPLATE_VERSION}' AND Status = '${TEMPLATE_PUBLISHED}'`,
    );
    if (existing) {
        const provs = await FindRows<{ ID: string }>(
            ctx,
            E_PROVISION,
            `ContractTemplateID = '${existing}'`,
            ['ID'],
            'ProvisionSortKey ASC, ProvisionNumber ASC',
        );
        if (provs.length >= 2) {
            return { templateID: existing, provisionIDs: provs.map((p) => p.ID) };
        }
    }

    const template = await ProviderOf(ctx).GetEntityObject<ContractTemplateEntity>(E_TEMPLATE, ctx.User);
    const draftID = await FindId(ctx, E_TEMPLATE, `VersionLabel = '${MJ_DOCS_BAA_TEMPLATE_VERSION}'`);
    if (draftID) {
        Assert(await template.Load(draftID), `could not load BAA template ${draftID}`);
    } else {
        template.NewRecord();
        template.Name = 'Healthcare BAA & Services Agreement (CTR-DOCS-WORLD)';
        template.ContractTemplateTypeID = templateTypeID;
        template.VersionLabel = MJ_DOCS_BAA_TEMPLATE_VERSION;
        template.SourceURL = 'https://contracts.example.test/templates/healthcare-baa-v1';
        template.Description = 'HIPAA-aligned Business Associate and Healthcare Services Agreement template.';
        template.Status = TEMPLATE_DRAFT;
        template.IntroducedDate = UtcDay(-60);
        await RequireSave(template, 'create Healthcare BAA template');
    }

    if (template.Status !== TEMPLATE_PUBLISHED) {
        for (const clause of BAA_PROVISIONS) {
            const already = await FindId(
                ctx,
                E_PROVISION,
                `ContractTemplateID = '${template.ID}' AND ProvisionNumber = '${Quote(clause.number)}'`,
            );
            if (already) continue;
            const provision = await ProviderOf(ctx).GetEntityObject<ContractTemplateProvisionEntity>(E_PROVISION, ctx.User);
            provision.NewRecord();
            provision.ContractTemplateID = template.ID;
            provision.ProvisionNumber = clause.number;
            provision.Title = clause.title;
            provision.ProvisionText = clause.text;
            await RequireSave(provision, `BAA provision ${clause.number}`);
        }
        template.Status = TEMPLATE_PUBLISHED;
        await RequireSave(template, 'publish Healthcare BAA template');
    }

    const provs = await FindRows<{ ID: string }>(
        ctx,
        E_PROVISION,
        `ContractTemplateID = '${template.ID}'`,
        ['ID'],
        'ProvisionSortKey ASC, ProvisionNumber ASC',
    );
    return { templateID: template.ID, provisionIDs: provs.map((p) => p.ID) };
}

async function upsertWorldContract(
    ctx: IntegrationCheckContext,
    fixture: ContractsFixture,
    notes: string,
    description: string,
    orgID: string,
    personID: string,
    documentArtifactID: string | null,
    shape: (contract: ContractEntity) => void,
): Promise<MjDocsWorldContractRecord> {
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
    contract.CustomerOrganizationID = orgID;
    contract.PrimaryContactPersonID = personID;
    contract.CompanyID = fixture.CompanyID;
    contract.DocumentArtifactID = documentArtifactID;
    if (!existingID) {
        contract.ContractTypeID = fixture.OrderFormTypeID;
        contract.ContractTemplateID = fixture.TemplateID;
        contract.AutoRenew = false;
        contract.HasModifications = false;
    }
    shape(contract);
    await RequireSave(contract, notes);
    Assert(!!(contract.ContractNumber ?? '').trim(), `${notes} saved without a ContractNumber`);
    return {
        ID: contract.ID,
        ContractNumber: contract.ContractNumber as string,
        DocumentArtifactID: contract.DocumentArtifactID,
    };
}

async function ensureContractModification(
    ctx: IntegrationCheckContext,
    contractID: string,
    provisionID: string,
    modificationText: string,
    notes: string,
): Promise<void> {
    const existing = await FindId(
        ctx,
        E_MODIFICATION,
        `ContractID = '${contractID}' AND ContractTemplateProvisionID = '${provisionID}'`,
    );
    if (existing) return;

    const contract = await Reopen(ctx, contractID);
    contract.HasModifications = true;
    const mod: ContractTemplateModificationEntity = await contract.Modifications.Create();
    mod.ContractTemplateProvisionID = provisionID;
    mod.ModificationText = modificationText;
    mod.Notes = notes;
    await RequireSave(contract, `save modification on ${contractID}`);
}

export async function LoadContractsMjDocsWorld(ctx: IntegrationCheckContext): Promise<ContractsMjDocsWorldState> {
    const fixture = await ResolveContractsFixture(ctx);

    // Batched lookup of Artifact Types and Roles (Rule 3: RunViews single-request batching)
    const [rolesRes, artifactTypesRes] = await View(ctx).RunViews(
        [
            { EntityName: E_ROLE, Fields: ['ID', 'Name'], OrderBy: 'Name ASC', ResultType: 'simple' },
            { EntityName: E_ARTIFACT_TYPE, Fields: ['ID', 'Name'], OrderBy: 'Name ASC', ResultType: 'simple' },
        ],
        ctx.User,
    );
    Assert(rolesRes.Success, `RunViews Roles failed: ${rolesRes.ErrorMessage ?? 'unknown'}`);
    Assert(artifactTypesRes.Success, `RunViews Artifact Types failed: ${artifactTypesRes.ErrorMessage ?? 'unknown'}`);
    const roleRows = rolesRes.Results as Array<{ ID: string; Name: string }>;
    const typeRows = artifactTypesRes.Results as Array<{ ID: string; Name: string }>;
    const chosenType =
        typeRows.find((t) => t.Name.toLowerCase() === 'markdown') ??
        typeRows.find((t) => t.Name.toLowerCase().includes('document')) ??
        typeRows[0];
    Assert(!!chosenType?.ID, 'No MJ: Artifact Types available for MJ Docs world');
    const artifactTypeID = chosenType.ID;

    const people = await resolvePeople(ctx);
    const baa = await ensureBaaTemplate(ctx, fixture.TemplateTypeID);

    // Create 5 MJ Docs artifacts with 7 total versions
    const draftMsa = await CreateArtifactWithVersions(
        ctx,
        artifactTypeID,
        MJ_DOCS_ARTIFACT_NAMES.assembledMsaDraft,
        'Assembled Contract Draft combining IT MSA clauses with negotiated commercial deviations.',
        [
            {
                versionNumber: 1,
                name: 'Initial Assembled Draft v1',
                comments: 'Initial automated draft assembly.',
                content: '# Assembled Contract Draft — Northwind Association\n\nInitial standard terms assembly.',
            },
            {
                versionNumber: 2,
                name: 'Redline-Incorporated Draft v2',
                comments: 'Incorporated 24-month liability cap and Net-45 invoicing terms.',
                content: '# Assembled Contract Draft — Northwind Association (Rev 2)\n\nIncludes negotiated overrides on Clauses 1.9 and 2.',
            },
        ],
    );
    const reviewMemo = await CreateArtifactWithVersions(
        ctx,
        artifactTypeID,
        MJ_DOCS_ARTIFACT_NAMES.aiReviewMemo,
        'AI Contract Review Memo summarizing HIPAA breach notification deviations and renewal timeline.',
        [
            {
                versionNumber: 1,
                name: 'AI Clause Deviation Memo v1',
                comments: 'Initial AI review against Healthcare BAA baseline.',
                content: '# AI Contract Review Memo — Cascadia Health Society\n\nFlagged 48-hour breach notice request on Clause 4.2.',
            },
            {
                versionNumber: 2,
                name: 'Final Legal Reconciliation Memo v2',
                comments: 'Updated following 72-hour SLA agreement.',
                content: '# AI Contract Review Memo — Cascadia Health Society (Final)\n\nReconciled to 72-hour notification SLA.',
            },
        ],
    );
    const execSummary = await CreateArtifactWithVersions(
        ctx,
        artifactTypeID,
        MJ_DOCS_ARTIFACT_NAMES.executiveSummary,
        'Executive Summary for Meridian Credit Union renewal approval.',
        [
            {
                versionNumber: 1,
                name: 'Executive Brief v1',
                comments: 'Prepared for executive sponsor review.',
                content: '# Executive Summary — Meridian Credit Union\n\n3% annual cap with CarryDiscountOnRenewal enabled.',
            },
        ],
    );
    const sowDraft = await CreateArtifactWithVersions(
        ctx,
        artifactTypeID,
        MJ_DOCS_ARTIFACT_NAMES.assembledSowDraft,
        'Assembled SOW Draft for Harbor Point Institute research onboarding.',
        [
            {
                versionNumber: 1,
                name: 'Working SOW Draft v1',
                comments: 'Draft prior to execution.',
                content: '# Assembled SOW Draft — Harbor Point Institute\n\nPhase 1 & Phase 2 research platform deliverables.',
            },
        ],
    );
    const coMemo = await CreateArtifactWithVersions(
        ctx,
        artifactTypeID,
        MJ_DOCS_ARTIFACT_NAMES.changeOrderMemo,
        'AI Review Memo verifying co-termed site expansion change order lineage.',
        [
            {
                versionNumber: 1,
                name: 'Change Order Lineage Memo v1',
                comments: 'Verified parent MSA alignment.',
                content: '# Change Order Review Memo — Northwind Association\n\nCo-termed with parent active MSA.',
            },
        ],
    );

    const artifactVersionCount =
        draftMsa.versionIDs.length +
        reviewMemo.versionIDs.length +
        execSummary.versionIDs.length +
        sowDraft.versionIDs.length +
        coMemo.versionIDs.length;

    // 8 contracts: 5 with linked DocumentArtifactID, 3 with NULL DocumentArtifactID
    const northwindDraftMsa = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.northwindDraftMsa,
        'Northwind Association — Active MSA with linked Assembled Contract Draft MJ Doc.',
        fixture.Organizations.northwind,
        people.elena,
        draftMsa.artifactID,
        (c) => {
            c.AutoRenew = true;
            c.CarryDiscountOnRenewal = true;
            c.HasModifications = true;
            c.ExecutedDate = UtcDay(-45);
            c.EffectiveDate = UtcDay(-40);
            c.EndDate = UtcDay(325);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
            c.AnnualIncreasePercent = 4;
        },
    );

    const cascadiaReviewMemo = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.cascadiaReviewMemo,
        'Cascadia Health Society — Active Healthcare BAA with linked AI Contract Review Memo MJ Doc.',
        fixture.Organizations.cascadia,
        people.marcus,
        reviewMemo.artifactID,
        (c) => {
            c.ContractTemplateID = baa.templateID;
            c.AutoRenew = true;
            c.HasModifications = true;
            c.ExecutedDate = UtcDay(-200);
            c.EffectiveDate = UtcDay(-195);
            c.EndDate = UtcDay(25);
            c.RenewalNoticeDays = 90;
            c.CancellationWindowDays = 45;
            c.AnnualIncreasePercent = 3;
        },
    );

    const meridianExecSummary = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.meridianExecSummary,
        'Meridian Credit Union — Executed agreement starting next month with Executive Summary MJ Doc.',
        fixture.Organizations.meridian,
        people.priya,
        execSummary.artifactID,
        (c) => {
            c.AutoRenew = true;
            c.CarryDiscountOnRenewal = true;
            c.ExecutedDate = UtcDay(-7);
            c.EffectiveDate = UtcDay(25);
            c.EndDate = UtcDay(390);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
            c.AnnualIncreasePercent = 3;
        },
    );

    const harborDraftSow = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.harborDraftSow,
        'Harbor Point Institute — Draft Statement of Work with linked Assembled SOW Draft MJ Doc.',
        fixture.Organizations.harbor,
        people.david,
        sowDraft.artifactID,
        (c) => {
            c.ContractTypeID = fixture.RootTypeID;
            c.ContractTemplateID = null;
            c.AutoRenew = false;
            c.RenewalNoticeDays = 30;
            c.CancellationWindowDays = 30;
        },
    );

    const northwindChangeOrder = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.northwindChangeOrder,
        'Northwind Association — Change Order linked to AI Review Memo MJ Doc.',
        fixture.Organizations.northwind,
        people.elena,
        coMemo.artifactID,
        (c) => {
            c.ContractTypeID = fixture.ChangeOrderTypeID;
            c.ContractTemplateID = null;
            c.ParentContractID = northwindDraftMsa.ID;
            c.ExecutedDate = UtcDay(-10);
            c.EffectiveDate = UtcDay(-10);
            c.EndDate = UtcDay(325);
        },
    );

    const northwindUnlinkedPayLink = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.northwindUnlinkedPayLink,
        'Northwind Association — Payment Link with NULL DocumentArtifactID.',
        fixture.Organizations.northwind,
        people.elena,
        null,
        (c) => {
            c.ContractTypeID = fixture.PaymentLinkTypeID;
            c.EffectiveDate = UtcDay(-30);
            c.EndDate = UtcDay(335);
        },
    );

    const cascadiaUnlinkedExpired = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.cascadiaUnlinkedExpired,
        'Cascadia Health Society — Expired Order Form with NULL DocumentArtifactID.',
        fixture.Organizations.cascadia,
        people.marcus,
        null,
        (c) => {
            c.ExecutedDate = UtcDay(-420);
            c.EffectiveDate = UtcDay(-415);
            c.EndDate = UtcDay(-15);
            c.RenewalNoticeDays = 60;
            c.CancellationWindowDays = 30;
            c.AnnualIncreasePercent = 3;
        },
    );

    const harborUnlinkedTerminated = await upsertWorldContract(
        ctx,
        fixture,
        MJ_DOCS_WORLD_NOTES.harborUnlinkedTerminated,
        'Harbor Point Institute — Terminated Order Form with NULL DocumentArtifactID and relational modification.',
        fixture.Organizations.harbor,
        people.david,
        null,
        (c) => {
            c.HasModifications = true;
            c.ExecutedDate = UtcDay(-120);
            c.EffectiveDate = UtcDay(-115);
            c.EndDate = UtcDay(245);
            c.TerminatedDate = UtcDay(-5);
            c.RenewalNoticeDays = 30;
            c.CancellationWindowDays = 30;
        },
    );

    // 4 strictly relational ContractTemplateModification rows
    await ensureContractModification(
        ctx,
        northwindDraftMsa.ID,
        fixture.ProvisionIDs[1] ?? fixture.ProvisionIDs[0],
        'Customer shall pay undisputed invoices within forty-five (45) calendar days of receipt.',
        'Finance Controller approved Net-45.',
    );
    await ensureContractModification(
        ctx,
        northwindDraftMsa.ID,
        fixture.ProvisionIDs[fixture.ProvisionIDs.length - 1],
        'Aggregate liability shall not exceed total fees paid in the twenty-four (24) months preceding the claim.',
        'Negotiated by General Counsel; reflected in Assembled Draft v2.',
    );
    await ensureContractModification(
        ctx,
        cascadiaReviewMemo.ID,
        baa.provisionIDs[baa.provisionIDs.length - 1],
        'Vendor shall notify Covered Entity of any confirmed breach of unsecured PHI within seventy-two (72) hours.',
        'Reconciled per AI Contract Review Memo v2.',
    );
    await ensureContractModification(
        ctx,
        harborUnlinkedTerminated.ID,
        fixture.ProvisionIDs[2] ?? fixture.ProvisionIDs[0],
        'Customer holds tax-exempt educational institution status upon providing a valid exemption certificate.',
        'Academic tax exemption override.',
    );

    const totalDomainRecords =
        4 + // organizations
        4 + // people
        2 + // templates (IT MSA + Healthcare BAA)
        fixture.ProvisionIDs.length +
        baa.provisionIDs.length +
        5 + // artifacts
        artifactVersionCount + // 7 artifact versions
        8 + // contracts (5 linked + 3 null)
        4; // relational modifications

    const state: ContractsMjDocsWorldState = {
        Fixture: fixture,
        ArtifactTypeID: artifactTypeID,
        RoleCount: roleRows.length,
        People: people,
        BaaTemplateID: baa.templateID,
        BaaProvisionIDs: baa.provisionIDs,
        Artifacts: {
            assembledMsaDraft: draftMsa.artifactID,
            aiReviewMemo: reviewMemo.artifactID,
            executiveSummary: execSummary.artifactID,
            assembledSowDraft: sowDraft.artifactID,
            changeOrderMemo: coMemo.artifactID,
        },
        ArtifactVersionCount: artifactVersionCount,
        Contracts: {
            northwindDraftMsa,
            cascadiaReviewMemo,
            meridianExecSummary,
            harborDraftSow,
            northwindChangeOrder,
            northwindUnlinkedPayLink,
            cascadiaUnlinkedExpired,
            harborUnlinkedTerminated,
        },
        ModificationCount: 4,
        TotalDomainRecords: totalDomainRecords,
    };
    cachedMjDocsWorld = state;
    return state;
}
