/**
 * contracts-mj-docs — Cross-stack integration checks for Contract.DocumentArtifactID (MJ Docs / MJ: Artifacts).
 *
 * Exercises BOTH SQL Server and PostgreSQL through canonical MJ BaseEntity, RunView/RunViews,
 * ContractEntityServer, and ContractsEngineBase paths:
 *   DOC1 — Multi-domain world density (>= 20 real records across orgs, people, roles, templates,
 *          provisions, modifications, MJ: Artifacts, MJ: Artifact Versions, linked & null Contracts)
 *   DOC2 — Linking Contract.DocumentArtifactID to multi-version MJ: Artifacts & verifying joined
 *          DocumentArtifact projection + ArtifactVersion ordering
 *   DOC3 — Relational coexistence: ContractTemplateProvision, ContractTemplateModification, and
 *          Contract.Notes stay queryable while setting, updating, and clearing DocumentArtifactID to null
 *   DOC4 — Executed Paper boundary: linking DocumentArtifactID does NOT clear IsAwaitingDocument
 *          (signed PDFs live in MJ: Files under 'Executed Agreement')
 *   DOC5 — Adversarial invalid FK rejection: non-existent DocumentArtifactID UUID refused by
 *          FK_Contract_DocumentArtifact with zero orphaned header/modification rows
 *   DOC6 — Backward-compatible NULL DocumentArtifactID create, update, and read round-trip
 *   DOC7 — Adversarial RLS/permission gating, zero-version Artifact fallback, and ContractsEngineBase
 *          non-caching boundary for unbounded MJ: Artifacts
 */
import { randomUUID } from 'node:crypto';
import { UserInfo } from '@memberjunction/core';
import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration/registry';
import { CONTRACTS_ENGINE_ENTITIES, ContractsEngineBase } from '@mj-biz-apps/contracts-entities';
import {
    E_ARTIFACT,
    E_ARTIFACT_VERSION,
    E_CONTRACT,
    E_MODIFICATION,
    E_PROVISION,
    FindId,
    FindRows,
    InRolledBackTransaction,
    NewContract,
    ProviderOf,
    Quote,
    RefuseSave,
    Reopen,
    RequireSave,
    ResolveContractsFixture,
    UtcDay,
    View,
} from '../fixture.js';
import {
    CreateArtifactWithVersions,
    LoadContractsMjDocsWorld,
    MJ_DOCS_ARTIFACT_NAMES,
    MJ_DOCS_WORLD_NOTES,
    ResolveArtifactTypeID,
    type TypedArtifactEntity,
} from '../world/contracts-mj-docs-world.js';

type Ctx = IntegrationCheckContext;

interface ContractDocumentProjection {
    ID: string;
    ContractNumber: string | null;
    DocumentArtifactID: string | null;
    DocumentArtifact: string | null;
    Notes: string | null;
    IsAwaitingDocument: boolean | null;
}

interface ArtifactVersionProjection {
    ID: string;
    ArtifactID: string;
    VersionNumber: number;
    Name: string | null;
    Content: string | null;
}

interface ModificationProjection {
    ID: string;
    ContractID: string;
    ContractTemplateProvisionID: string;
    ModificationText: string;
}

export const ContractDocumentArtifactChecks: NamedCheck[] = [
    {
        Id: 'contracts-mj-docs.DOC1',
        Name: 'DOC1 — multi-domain MJ Docs world seeds >= 20 real records across linked & null contracts',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const world = await LoadContractsMjDocsWorld(ctx);

            Assert(
                world.TotalDomainRecords >= 20,
                `Expected >= 20 seeded multi-domain records, found ${world.TotalDomainRecords}`,
            );
            Assert(world.RoleCount >= 1, 'Expected at least 1 MJ: Roles row in governance catalog');
            Assert(world.ArtifactVersionCount >= 7, `Expected >= 7 ArtifactVersion rows, found ${world.ArtifactVersionCount}`);

            // Verify all 8 world contracts via batched RunViews
            const [contractsRes, modsRes] = await View(ctx).RunViews(
                [
                    {
                        EntityName: E_CONTRACT,
                        ExtraFilter: `Notes LIKE 'CTR-DOCS-WORLD:%'`,
                        Fields: ['ID', 'ContractNumber', 'DocumentArtifactID', 'DocumentArtifact', 'Notes'],
                        ResultType: 'simple',
                    },
                    {
                        EntityName: E_MODIFICATION,
                        ExtraFilter: `ContractID IN ('${world.Contracts.northwindDraftMsa.ID}', '${world.Contracts.cascadiaReviewMemo.ID}', '${world.Contracts.harborUnlinkedTerminated.ID}')`,
                        Fields: ['ID', 'ContractID', 'ContractTemplateProvisionID', 'ModificationText'],
                        ResultType: 'simple',
                    },
                ],
                ctx.User,
            );
            Assert(contractsRes.Success, `DOC1 contracts RunViews failed: ${contractsRes.ErrorMessage ?? 'unknown'}`);
            Assert(modsRes.Success, `DOC1 modifications RunViews failed: ${modsRes.ErrorMessage ?? 'unknown'}`);

            const rows = contractsRes.Results as ContractDocumentProjection[];
            AssertEqual(rows.length, Object.keys(MJ_DOCS_WORLD_NOTES).length, 'DOC1 expected all 8 MJ Docs world contracts');

            const linked = rows.filter((r) => r.DocumentArtifactID !== null);
            const unlinked = rows.filter((r) => r.DocumentArtifactID === null);
            AssertEqual(linked.length, 5, 'DOC1 expected 5 contracts with linked DocumentArtifactID');
            AssertEqual(unlinked.length, 3, 'DOC1 expected 3 contracts with NULL DocumentArtifactID');

            const msaRow = rows.find((r) => r.Notes === MJ_DOCS_WORLD_NOTES.northwindDraftMsa);
            Assert(!!msaRow, 'DOC1 missing Northwind Draft MSA row');
            AssertEqual(
                msaRow.DocumentArtifact,
                MJ_DOCS_ARTIFACT_NAMES.assembledMsaDraft,
                'DOC1 joined DocumentArtifact name mismatch on vwContracts',
            );

            const modRows = modsRes.Results as ModificationProjection[];
            Assert(modRows.length >= 4, `DOC1 expected >= 4 relational modification rows, found ${modRows.length}`);
        },
    },
    {
        Id: 'contracts-mj-docs.DOC2',
        Name: 'DOC2 — linking DocumentArtifactID persists, joins DocumentArtifact name, and resolves multi-version ArtifactVersions',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const fixture = await ResolveContractsFixture(ctx);
            const artifactTypeID = await ResolveArtifactTypeID(ctx);

            await InRolledBackTransaction(ctx, async () => {
                const suffix = randomUUID().slice(0, 8);
                const artifactName = `IT-DOC2-Assembled-Draft-${suffix}`;
                const { artifactID } = await CreateArtifactWithVersions(
                    ctx,
                    artifactTypeID,
                    artifactName,
                    'Integration test assembled contract draft.',
                    [
                        {
                            versionNumber: 1,
                            name: 'Draft v1',
                            comments: 'Initial version',
                            content: '# Draft v1\n\nStandard clauses.',
                        },
                        {
                            versionNumber: 2,
                            name: 'Draft v2',
                            comments: 'Redline update',
                            content: '# Draft v2\n\nNegotiated liability cap.',
                        },
                    ],
                );

                const contract = await NewContract(ctx, fixture, (c) => {
                    c.Notes = `IT-DOC2-${suffix}`;
                    c.DocumentArtifactID = artifactID;
                    c.AutoRenew = true;
                });
                await RequireSave(contract, 'DOC2 save contract with DocumentArtifactID');

                const reopened = await Reopen(ctx, contract.ID);
                AssertEqual(
                    reopened.DocumentArtifactID?.toLowerCase(),
                    artifactID.toLowerCase(),
                    'DOC2 reopened DocumentArtifactID mismatch',
                );
                AssertEqual(reopened.DocumentArtifact, artifactName, 'DOC2 reopened joined DocumentArtifact name mismatch');

                const [projRes, versionsRes] = await View(ctx).RunViews(
                    [
                        {
                            EntityName: E_CONTRACT,
                            ExtraFilter: `ID = '${contract.ID}'`,
                            Fields: ['ID', 'DocumentArtifactID', 'DocumentArtifact', 'Notes'],
                            ResultType: 'simple',
                        },
                        {
                            EntityName: E_ARTIFACT_VERSION,
                            ExtraFilter: `ArtifactID = '${artifactID}'`,
                            Fields: ['ID', 'ArtifactID', 'VersionNumber', 'Name', 'Content'],
                            OrderBy: 'VersionNumber ASC',
                            ResultType: 'simple',
                        },
                    ],
                    ctx.User,
                );
                Assert(projRes.Success && versionsRes.Success, 'DOC2 batched RunViews failed');
                const versions = versionsRes.Results as ArtifactVersionProjection[];
                AssertEqual(versions.length, 2, 'DOC2 expected 2 ArtifactVersions');
                AssertEqual(versions[0].VersionNumber, 1, 'DOC2 first version should be v1');
                AssertEqual(versions[1].VersionNumber, 2, 'DOC2 second version should be v2');
            });
        },
    },
    {
        Id: 'contracts-mj-docs.DOC3',
        Name: 'DOC3 — relational clauses & Notes stay SQL-queryable across DocumentArtifactID set, swap, and clear-to-null',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const fixture = await ResolveContractsFixture(ctx);
            const artifactTypeID = await ResolveArtifactTypeID(ctx);

            await InRolledBackTransaction(ctx, async () => {
                const suffix = randomUUID().slice(0, 8);
                const firstArt = await CreateArtifactWithVersions(
                    ctx,
                    artifactTypeID,
                    `IT-DOC3-Draft-${suffix}`,
                    'Initial draft',
                    [{ versionNumber: 1, name: 'v1', comments: 'draft', content: '# Draft' }],
                );
                const secondArt = await CreateArtifactWithVersions(
                    ctx,
                    artifactTypeID,
                    `IT-DOC3-Memo-${suffix}`,
                    'AI review memo',
                    [{ versionNumber: 1, name: 'v1', comments: 'memo', content: '# Review Memo' }],
                );

                const notesText = `IT-DOC3-relational-notes-${suffix}`;
                const contract = await NewContract(ctx, fixture, (c) => {
                    c.Notes = notesText;
                    c.HasModifications = true;
                    c.DocumentArtifactID = firstArt.artifactID;
                });
                const mod = await contract.Modifications.Create();
                mod.ContractTemplateProvisionID = fixture.ProvisionIDs[0];
                mod.ModificationText = 'Negotiated relational clause preserved independently of MJ Doc.';
                await RequireSave(contract, 'DOC3 create contract + modification + first artifact');

                // Swap to second artifact
                const loaded1 = await Reopen(ctx, contract.ID);
                loaded1.DocumentArtifactID = secondArt.artifactID;
                await RequireSave(loaded1, 'DOC3 swap DocumentArtifactID to memo');
                const loaded2 = await Reopen(ctx, contract.ID);
                AssertEqual(
                    loaded2.DocumentArtifactID?.toLowerCase(),
                    secondArt.artifactID.toLowerCase(),
                    'DOC3 swapped DocumentArtifactID did not persist',
                );
                AssertEqual(loaded2.Notes, notesText, 'DOC3 Notes mutated unexpectedly');
                AssertEqual(loaded2.Modifications.Count, 1, 'DOC3 relational modification lost on artifact swap');

                // Clear back to NULL (exercises @DocumentArtifactID_Clear = 1 on spUpdateContract)
                loaded2.DocumentArtifactID = null;
                await RequireSave(loaded2, 'DOC3 clear DocumentArtifactID back to null');
                const loaded3 = await Reopen(ctx, contract.ID);
                AssertEqual(loaded3.DocumentArtifactID, null, 'DOC3 clearing DocumentArtifactID to null failed');
                AssertEqual(loaded3.DocumentArtifact, null, 'DOC3 joined DocumentArtifact should be null after clear');
                AssertEqual(loaded3.Notes, notesText, 'DOC3 Notes lost after clearing DocumentArtifactID');

                const [provRows, modRows] = await View(ctx).RunViews(
                    [
                        {
                            EntityName: E_PROVISION,
                            ExtraFilter: `ID = '${fixture.ProvisionIDs[0]}'`,
                            Fields: ['ID', 'ProvisionNumber', 'Title'],
                            ResultType: 'simple',
                        },
                        {
                            EntityName: E_MODIFICATION,
                            ExtraFilter: `ContractID = '${contract.ID}'`,
                            Fields: ['ID', 'ModificationText'],
                            ResultType: 'simple',
                        },
                    ],
                    ctx.User,
                );
                Assert(provRows.Success && provRows.Results.length === 1, 'DOC3 relational provision query failed');
                Assert(modRows.Success && modRows.Results.length === 1, 'DOC3 relational modification query failed');
            });
        },
    },
    {
        Id: 'contracts-mj-docs.DOC4',
        Name: 'DOC4 — linking DocumentArtifactID does NOT clear IsAwaitingDocument (distinct from Executed Agreement files)',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const fixture = await ResolveContractsFixture(ctx);
            const artifactTypeID = await ResolveArtifactTypeID(ctx);

            await InRolledBackTransaction(ctx, async () => {
                const suffix = randomUUID().slice(0, 8);
                const draft = await CreateArtifactWithVersions(
                    ctx,
                    artifactTypeID,
                    `IT-DOC4-Draft-${suffix}`,
                    'Unexecuted draft artifact',
                    [{ versionNumber: 1, name: 'v1', comments: 'draft', content: '# Unexecuted Draft' }],
                );

                const contract = await NewContract(ctx, fixture, (c) => {
                    c.Notes = `IT-DOC4-${suffix}`;
                    c.ContractTypeID = fixture.OrderFormTypeID; // RequiresExecutedDocument = true
                    c.ExecutedDate = UtcDay(-5);
                    c.EffectiveDate = UtcDay(-3);
                    c.EndDate = UtcDay(180);
                    c.DocumentArtifactID = draft.artifactID;
                });
                await RequireSave(contract, 'DOC4 save executed contract with DocumentArtifactID only');

                const rows = await FindRows<ContractDocumentProjection>(
                    ctx,
                    E_CONTRACT,
                    `ID = '${contract.ID}'`,
                    ['ID', 'DocumentArtifactID', 'IsAwaitingDocument'],
                );
                AssertEqual(rows.length, 1, 'DOC4 contract projection not found');
                Assert(
                    Boolean(rows[0].IsAwaitingDocument) === true,
                    'DOC4 linking DocumentArtifactID must NOT clear IsAwaitingDocument without an Executed Agreement file',
                );
            });
        },
    },
    {
        Id: 'contracts-mj-docs.DOC5',
        Name: 'DOC5 — adversarial invalid/missing DocumentArtifactID UUID is rejected by FK_Contract_DocumentArtifact',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const fixture = await ResolveContractsFixture(ctx);
            const notes = `IT-DOC5-bad-fk-${randomUUID()}`;

            await InRolledBackTransaction(ctx, async () => {
                const bogusArtifactID = randomUUID();
                const contract = await NewContract(ctx, fixture, (c) => {
                    c.Notes = notes;
                    c.DocumentArtifactID = bogusArtifactID;
                });

                await RefuseSave(
                    contract,
                    'DOC5 invalid DocumentArtifactID FK',
                    /FK_Contract_DocumentArtifact|foreign key|violates foreign key|conflicted/i,
                );
            });

            // Verify after transaction close (works identically on PostgreSQL where a failed
            // INSERT aborts the current transaction block until ROLLBACK).
            const leftover = await FindId(ctx, E_CONTRACT, `Notes = '${Quote(notes)}'`);
            Assert(!leftover, `DOC5 wrote orphaned contract row ${leftover} despite FK violation`);
        },
    },
    {
        Id: 'contracts-mj-docs.DOC6',
        Name: 'DOC6 — backward-compatible NULL DocumentArtifactID contract saves, updates, and reads cleanly',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const fixture = await ResolveContractsFixture(ctx);

            await InRolledBackTransaction(ctx, async () => {
                const notes = `IT-DOC6-null-${randomUUID()}`;
                const contract = await NewContract(ctx, fixture, (c) => {
                    c.Notes = notes;
                    c.DocumentArtifactID = null;
                });
                await RequireSave(contract, 'DOC6 save contract with null DocumentArtifactID');

                const reopened = await Reopen(ctx, contract.ID);
                AssertEqual(reopened.DocumentArtifactID, null, 'DOC6 expected DocumentArtifactID === null');
                AssertEqual(reopened.DocumentArtifact, null, 'DOC6 expected joined DocumentArtifact === null');

                reopened.Description = 'Updated legacy contract with no MJ Doc attached';
                await RequireSave(reopened, 'DOC6 update contract with null DocumentArtifactID');

                const finalRead = await Reopen(ctx, contract.ID);
                AssertEqual(finalRead.DocumentArtifactID, null, 'DOC6 expected null after update');
                AssertEqual(finalRead.Description, 'Updated legacy contract with no MJ Doc attached', 'DOC6 update lost');
            });
        },
    },
    {
        Id: 'contracts-mj-docs.DOC7',
        Name: 'DOC7 — zero-version Artifact fallback, permission gating, and ContractsEngineBase non-caching boundary',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const fixture = await ResolveContractsFixture(ctx);
            const artifactTypeID = await ResolveArtifactTypeID(ctx);

            // 1. Verify ContractsEngineBase never caches MJ: Artifacts / MJ: Artifact Versions
            const managedNames: readonly string[] = Object.values(CONTRACTS_ENGINE_ENTITIES);
            Assert(!managedNames.includes(E_ARTIFACT), 'DOC7 ContractsEngineBase must NOT cache MJ: Artifacts');
            Assert(!managedNames.includes(E_ARTIFACT_VERSION), 'DOC7 ContractsEngineBase must NOT cache MJ: Artifact Versions');

            await ContractsEngineBase.Instance.Config(false, ctx.User, ProviderOf(ctx));
            Assert(
                ContractsEngineBase.Instance.ContractTypes.length > 0,
                'DOC7 ContractsEngineBase should warm bounded ContractTypes cleanly',
            );

            // 2. Verify restricted / unprivileged user context has no CanRead permission on Contracts/Artifacts
            const restrictedUser = new UserInfo(ProviderOf(ctx), {
                ID: randomUUID(),
                Name: 'Unprivileged Tenant Probe',
                Email: 'unprivileged-probe@example.test',
                Type: 'User',
                IsActive: true,
                UserRoles: [],
            });
            const artifactEntityInfo = ProviderOf(ctx).EntityByName(E_ARTIFACT);
            Assert(!!artifactEntityInfo, 'DOC7 MJ: Artifacts entity metadata must exist');
            const restrictedPerms = artifactEntityInfo.GetUserPermisions(restrictedUser);
            AssertEqual(
                restrictedPerms.CanRead,
                false,
                'DOC7 unprivileged user with zero roles must NOT have CanRead on MJ: Artifacts',
            );
            const ownerPerms = artifactEntityInfo.GetUserPermisions(ctx.User);
            AssertEqual(ownerPerms.CanRead, true, 'DOC7 owner user must have CanRead on MJ: Artifacts');

            // 3. Verify Artifact with ZERO ArtifactVersion rows links cleanly and returns 0 versions without throwing
            await InRolledBackTransaction(ctx, async () => {
                const suffix = randomUUID().slice(0, 8);
                const emptyArtifact = await ProviderOf(ctx).GetEntityObject<TypedArtifactEntity>(E_ARTIFACT, ctx.User);
                emptyArtifact.NewRecord();
                emptyArtifact.Name = `IT-DOC7-ZeroVersions-${suffix}`;
                emptyArtifact.Description = 'Artifact with zero versions to test graceful empty fallback.';
                emptyArtifact.TypeID = artifactTypeID;
                emptyArtifact.UserID = ctx.User.ID;
                emptyArtifact.Visibility = 'Always';
                await RequireSave(emptyArtifact, 'DOC7 save zero-version artifact');

                const contract = await NewContract(ctx, fixture, (c) => {
                    c.Notes = `IT-DOC7-${suffix}`;
                    c.DocumentArtifactID = emptyArtifact.ID;
                });
                await RequireSave(contract, 'DOC7 link contract to zero-version artifact');

                const versions = await FindRows<ArtifactVersionProjection>(
                    ctx,
                    E_ARTIFACT_VERSION,
                    `ArtifactID = '${emptyArtifact.ID}'`,
                    ['ID', 'ArtifactID', 'VersionNumber'],
                );
                AssertEqual(versions.length, 0, 'DOC7 zero-version artifact should return 0 versions cleanly');
            });
        },
    },
];

for (const check of ContractDocumentArtifactChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-mj-docs', {
    Setup: async () => undefined,
    Teardown: async () => undefined,
});
