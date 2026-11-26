/**
 * Deterministic unit tests for `ContractDocumentPreviewComponent`, `MJCContractDocumentPreviewPanel`,
 * and `LoadContractDocumentPreviewState` (MJ Docs / `MJ: Artifacts` optional contract draft preview).
 *
 * Covers all 4 required UX states plus static hygiene guarantees:
 *   1. Linked `DocumentArtifactID` with one or more `ArtifactVersion` rows -> loads metadata via
 *      a single batched `RunViews([...])` (`ResultType: 'simple'`), strips raw Markdown from summary
 *      excerpts, resolves version badges, and wires `<mj-artifact-viewer-panel>` (`6.3.0-edge.1`).
 *   2. `DocumentArtifactID === null` -> clean unlinked empty state keeping `Contract.Notes` and
 *      relational clause controls unobstructed.
 *   3. `DocumentArtifactID` set with zero accessible `ArtifactVersion` rows or RLS/permission denial
 *      -> graceful non-fatal fallback (`no-versions` / `restricted`) with zero uncaught errors.
 *   4. Rapid Contract record switching -> monotonically tracked `loadSequence` cancels/ignores stale
 *      async completions under `ChangeDetectionStrategy.OnPush`.
 */
import '@angular/compiler';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
    ChangeDetectorRef,
    Injector,
    runInInjectionContext,
    type SimpleChange,
    type SimpleChanges,
} from '@angular/core';
import { describe, expect, it, vi } from 'vitest';
import {
    EntityInfo,
    Metadata,
    RunView,
    UserInfo,
    type IMetadataProvider,
    type RunViewParams,
    type RunViewResult,
} from '@memberjunction/core';
import { UserInfoEngine } from '@memberjunction/core-entities';
import { ArtifactIconService, ArtifactsModule } from '@memberjunction/ng-artifacts';
import { NavigationService } from '@memberjunction/ng-shared';
import {
    CONTRACT_DOC_PREVIEW_EXPANDED_PREF_KEY,
    ContractDocumentPreviewComponent,
    LoadContractDocumentPreviewState,
    MJCContractDocumentPreviewPanel,
    ReadOwnProperty,
    ResolveContractDocumentIconClass,
    StripMarkdownToPlainText,
    type ContractDocumentArtifactSummary,
    type ContractDocumentArtifactVersionSummary,
} from '../lib/form-panels/contract-document-preview.panel';

const PANEL_SRC_PATH = fileURLToPath(
    new URL('../lib/form-panels/contract-document-preview.panel.ts', import.meta.url),
);

class StubChangeDetectorRef extends ChangeDetectorRef {
    public readonly markForCheck = vi.fn();
    public readonly detectChanges = vi.fn();
    public readonly detach = vi.fn();
    public readonly reattach = vi.fn();
    public readonly checkNoChanges = vi.fn();
}

function createDeferred<T>(): {
    promise: Promise<T>;
    resolve: (value: T) => void;
    reject: (reason?: Error) => void;
} {
    let resolve!: (value: T) => void;
    let reject!: (reason?: Error) => void;
    const promise = new Promise<T>((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
}

function createRunViewStub(
    runViewsImpl: (params: RunViewParams[]) => Promise<RunViewResult[]>,
): {
    rvInstance: RunView;
    runViewsSpy: ReturnType<typeof vi.fn>;
} {
    const rvInstance = new RunView();
    const runViewsSpy = vi.fn(runViewsImpl);
    vi.spyOn(rvInstance, 'RunViews').mockImplementation(runViewsSpy);
    return { rvInstance, runViewsSpy };
}

function createPermissionProvider(canReadArtifact: boolean): IMetadataProvider {
    const baseProvider = Metadata.Provider;
    const mockUser = new UserInfo(undefined, { ID: 'user-legal-ops-1', Name: 'Elena Vance' });
    const entityStub = Object.create(EntityInfo.prototype) as EntityInfo;
    vi.spyOn(entityStub, 'GetUserPermisions').mockReturnValue({
        CanRead: canReadArtifact,
        CanCreate: false,
        CanUpdate: false,
        CanDelete: false,
    });

    const scopedProvider = Object.create(baseProvider ?? Object.prototype) as IMetadataProvider;
    Object.defineProperty(scopedProvider, 'CurrentUser', {
        value: mockUser,
        configurable: true,
    });
    Object.defineProperty(scopedProvider, 'EntityByName', {
        value: (name: string): EntityInfo | undefined => (name === 'MJ: Artifacts' ? entityStub : undefined),
        configurable: true,
    });
    return scopedProvider;
}

function createComponentInDi(): {
    component: ContractDocumentPreviewComponent;
    cdrStub: StubChangeDetectorRef;
    openEntityRecordSpy: ReturnType<typeof vi.fn>;
} {
    const cdrStub = new StubChangeDetectorRef();
    const openEntityRecordSpy = vi.fn();
    const iconServiceStub = { NormalizeMetadataIcon: (icon: string) => icon };
    const navigationStub = { OpenEntityRecord: openEntityRecordSpy };

    const injector = Injector.create({
        providers: [
            { provide: ChangeDetectorRef, useValue: cdrStub },
            { provide: ArtifactIconService, useValue: iconServiceStub },
            { provide: NavigationService, useValue: navigationStub },
        ],
    });

    const component = runInInjectionContext(injector, () => new ContractDocumentPreviewComponent());
    return { component, cdrStub, openEntityRecordSpy };
}

describe('ContractDocumentPreviewComponent & LoadContractDocumentPreviewState', () => {
    it('loads a linked DocumentArtifactID with versions in one batched RunViews call and renders @memberjunction/ng-artifacts metadata', async () => {
        const artifactID = 'aaaaaaaa-1111-4111-8111-111111111111';
        const artifactRow: ContractDocumentArtifactSummary = {
            ID: artifactID,
            Name: 'Northwind Association — Assembled MSA Draft',
            Description: '### Summary\n**Master Services Agreement** with `Net 45` negotiated terms and [Schedule A](https://example.test/a).',
            TypeID: 'type-md',
            Type: 'Markdown',
            Visibility: 'Organization',
            __mj_UpdatedAt: '2026-11-26T14:00:00.000Z',
        };
        const versionRows: ContractDocumentArtifactVersionSummary[] = [
            {
                ID: 'ver-2',
                ArtifactID: artifactID,
                VersionNumber: 2,
                Name: 'Redlined Draft v2',
                Description: 'Includes negotiated liability cap.',
                Comments: 'Reviewed by Legal Ops',
                __mj_CreatedAt: '2026-11-26T14:00:00.000Z',
                __mj_UpdatedAt: '2026-11-26T14:00:00.000Z',
            },
            {
                ID: 'ver-1',
                ArtifactID: artifactID,
                VersionNumber: 1,
                Name: 'Initial Draft v1',
                Description: 'Generated from IT MSA v1.',
                Comments: null,
                __mj_CreatedAt: '2026-11-25T10:00:00.000Z',
                __mj_UpdatedAt: '2026-11-25T10:00:00.000Z',
            },
        ];

        const provider = createPermissionProvider(true);
        const { rvInstance, runViewsSpy } = createRunViewStub(async () => [
            { Success: true, Results: [artifactRow] } as RunViewResult,
            { Success: true, Results: versionRows } as RunViewResult,
        ]);
        const rvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(rvInstance);

        try {
            const { component, cdrStub, openEntityRecordSpy } = createComponentInDi();
            component.Provider = provider;
            component.DocumentArtifactID = artifactID;
            component.IsSaved = true;

            const resolved = await component.LoadPreview();

            expect(runViewsSpy).toHaveBeenCalledTimes(1);
            const batchArgs = runViewsSpy.mock.calls[0]?.[0] as RunViewParams[];
            expect(batchArgs).toHaveLength(2);
            expect(batchArgs[0].EntityName).toBe('MJ: Artifacts');
            expect(batchArgs[0].ResultType).toBe('simple');
            expect(batchArgs[1].EntityName).toBe('MJ: Artifact Versions');
            expect(batchArgs[1].ResultType).toBe('simple');
            expect(batchArgs[1].Fields).not.toContain('Content');

            expect(resolved.Status).toBe('linked');
            expect(component.State.Status).toBe('linked');
            expect(component.DisplayTitle).toBe('Northwind Association — Assembled MSA Draft');
            expect(component.ActiveVersionNumber).toBe(2);
            expect(component.StatusLabel).toBe('Linked MJ Doc');
            expect(component.SummaryExcerpt).toBe(
                'Summary Master Services Agreement with Net 45 negotiated terms and Schedule A.',
            );
            expect(component.SummaryExcerpt).not.toMatch(/###|\*\*|`|\[[^\]]+\]\(/);
            expect(cdrStub.markForCheck).toHaveBeenCalled();

            // Switching versions updates ActiveVersionNumber and triggers OnPush markForCheck.
            component.SelectVersion(1);
            expect(component.ActiveVersionNumber).toBe(1);

            // Opening in MJ Docs falls back to NavigationService.OpenEntityRecord when no parent listener exists.
            component.OpenInViewer();
            expect(openEntityRecordSpy).toHaveBeenCalledTimes(1);
            expect(openEntityRecordSpy.mock.calls[0]?.[0]).toBe('MJ: Artifacts');
        } finally {
            rvSpy.mockRestore();
        }
    });

    it('renders a clean unlinked empty state when DocumentArtifactID is null without issuing RunViews', async () => {
        const provider = createPermissionProvider(true);
        const { rvInstance, runViewsSpy } = createRunViewStub(async () => []);
        const rvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(rvInstance);

        try {
            const { component, cdrStub } = createComponentInDi();
            component.Provider = provider;
            component.DocumentArtifactID = null;
            component.ContractNumber = 'CTR-000105';
            component.IsSaved = true;

            const resolved = await component.LoadPreview();

            expect(runViewsSpy).not.toHaveBeenCalled();
            expect(resolved.Status).toBe('unlinked');
            expect(component.State.Status).toBe('unlinked');
            expect(component.State.Artifact).toBeNull();
            expect(component.State.Versions).toEqual([]);
            expect(component.StatusLabel).toBe('Not linked');
            expect(component.DisplayTitle).toBe('Assembled Document — CTR-000105');
            expect(cdrStub.markForCheck).toHaveBeenCalled();
        } finally {
            rvSpy.mockRestore();
        }
    });

    it('gracefully handles an Artifact with zero accessible ArtifactVersion rows without throwing', async () => {
        const artifactID = 'bbbbbbbb-2222-4222-8222-222222222222';
        const provider = createPermissionProvider(true);
        const { rvInstance } = createRunViewStub(async () => [
            {
                Success: true,
                Results: [
                    {
                        ID: artifactID,
                        Name: 'Empty Draft Artifact',
                        Description: null,
                        TypeID: null,
                        Type: 'Markdown',
                        Visibility: 'Private',
                        __mj_UpdatedAt: null,
                    },
                ],
            } as RunViewResult,
            { Success: true, Results: [] } as RunViewResult,
        ]);
        const rvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(rvInstance);

        try {
            const { component } = createComponentInDi();
            component.Provider = provider;
            component.DocumentArtifactID = artifactID;

            const resolved = await component.LoadPreview();

            expect(resolved.Status).toBe('no-versions');
            expect(component.State.Status).toBe('no-versions');
            expect(component.State.Artifact?.Name).toBe('Empty Draft Artifact');
            expect(component.ActiveVersionNumber).toBeUndefined();
            expect(component.StatusLabel).toBe('No versions');
            expect(component.State.NoticeMessage).toContain('no accessible published versions');
        } finally {
            rvSpy.mockRestore();
        }
    });

    it('gracefully handles RLS-restricted or permission-denied Artifacts with zero uncaught errors', async () => {
        const artifactID = 'cccccccc-3333-4333-8333-333333333333';

        // Case 1: Entity metadata denies CanRead on MJ: Artifacts -> short-circuits without RunViews.
        const deniedProvider = createPermissionProvider(false);
        const { rvInstance: deniedRv, runViewsSpy: deniedSpy } = createRunViewStub(async () => []);
        const deniedRvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(deniedRv);
        try {
            const deniedState = await LoadContractDocumentPreviewState(deniedProvider, artifactID);
            expect(deniedSpy).not.toHaveBeenCalled();
            expect(deniedState.Status).toBe('restricted');
            expect(deniedState.NoticeMessage).toContain('read permission');
        } finally {
            deniedRvSpy.mockRestore();
        }

        // Case 2: RLS returns 0 rows for the artifact ID.
        const rlsProvider = createPermissionProvider(true);
        const { rvInstance: rlsRv } = createRunViewStub(async () => [
            { Success: true, Results: [] } as RunViewResult,
            { Success: true, Results: [] } as RunViewResult,
        ]);
        const rlsRvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(rlsRv);

        try {
            const { component } = createComponentInDi();
            component.Provider = rlsProvider;
            component.DocumentArtifactID = artifactID;
            const resolved = await component.LoadPreview();

            expect(resolved.Status).toBe('restricted');
            expect(component.State.Status).toBe('restricted');
            expect(component.StatusLabel).toBe('Restricted');
            expect(component.State.NoticeMessage).toContain('row-level security');
        } finally {
            rlsRvSpy.mockRestore();
        }
    });

    it('short-circuits malformed non-UUID DocumentArtifactID values to restricted without calling RunViews', async () => {
        const provider = createPermissionProvider(true);
        const { rvInstance, runViewsSpy } = createRunViewStub(async () => []);
        const rvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(rvInstance);

        try {
            const malformedValues = [
                'not-a-valid-uuid',
                "' OR 1=1 --",
                '12345',
                'aaaaaaaa-1111-4111-8111-11111111111z',
            ];

            for (const malformedId of malformedValues) {
                const state = await LoadContractDocumentPreviewState(provider, malformedId);
                expect(state.Status).toBe('restricted');
                expect(state.ArtifactID).toBe(malformedId);
                expect(state.Artifact).toBeNull();
                expect(state.Versions).toEqual([]);
                expect(state.LatestVersion).toBeNull();
                expect(state.NoticeMessage).toContain('malformed');
            }

            const { component } = createComponentInDi();
            component.Provider = provider;
            component.DocumentArtifactID = 'malformed-artifact-id';
            component.IsSaved = true;

            const componentState = await component.LoadPreview();
            expect(componentState.Status).toBe('restricted');
            expect(component.State.Status).toBe('restricted');
            expect(component.StatusLabel).toBe('Restricted');
            expect(runViewsSpy).not.toHaveBeenCalled();
        } finally {
            rvSpy.mockRestore();
        }
    });

    it('cancels/ignores stale async load completions when rapidly switching Contract records under OnPush', async () => {
        const firstArtifactID = '11111111-aaaa-4aaa-8aaa-111111111111';
        const secondArtifactID = '22222222-bbbb-4bbb-8bbb-222222222222';
        const firstDeferred = createDeferred<RunViewResult[]>();
        const secondDeferred = createDeferred<RunViewResult[]>();

        let callCount = 0;
        const provider = createPermissionProvider(true);
        const { rvInstance } = createRunViewStub(async () => {
            callCount++;
            return callCount === 1 ? firstDeferred.promise : secondDeferred.promise;
        });
        const rvSpy = vi.spyOn(RunView, 'FromMetadataProvider').mockReturnValue(rvInstance);

        try {
            const { component, cdrStub } = createComponentInDi();
            component.Provider = provider;
            component.IsSaved = true;

            // Start load for Contract A (slow response)
            component.DocumentArtifactID = firstArtifactID;
            const loadA = component.LoadPreview();

            // Immediately switch to Contract B before Contract A resolves
            component.DocumentArtifactID = secondArtifactID;
            const changes: SimpleChanges = {
                DocumentArtifactID: {
                    previousValue: firstArtifactID,
                    currentValue: secondArtifactID,
                    firstChange: false,
                    isFirstChange: () => false,
                } as SimpleChange,
            };
            component.ngOnChanges(changes);

            // Resolve Contract B FIRST
            secondDeferred.resolve([
                {
                    Success: true,
                    Results: [
                        {
                            ID: secondArtifactID,
                            Name: 'Contract B — Executive Summary',
                            Description: 'Active contract document',
                            TypeID: 'type-md',
                            Type: 'Markdown',
                            Visibility: 'Organization',
                            __mj_UpdatedAt: '2026-11-26T15:00:00.000Z',
                        },
                    ],
                } as RunViewResult,
                {
                    Success: true,
                    Results: [
                        {
                            ID: 'ver-b-3',
                            ArtifactID: secondArtifactID,
                            VersionNumber: 3,
                            Name: 'Summary v3',
                            Description: null,
                            Comments: null,
                            __mj_CreatedAt: '2026-11-26T15:00:00.000Z',
                            __mj_UpdatedAt: '2026-11-26T15:00:00.000Z',
                        },
                    ],
                } as RunViewResult,
            ]);

            await vi.waitFor(() => {
                expect(component.State.ArtifactID).toBe(secondArtifactID);
                expect(component.State.Status).toBe('linked');
            });

            const markCountAfterB = cdrStub.markForCheck.mock.calls.length;

            // Now resolve Contract A LATE — it MUST be discarded and never overwrite Contract B!
            firstDeferred.resolve([
                {
                    Success: true,
                    Results: [
                        {
                            ID: firstArtifactID,
                            Name: 'Contract A — STALE Draft',
                            Description: 'Should never overwrite Contract B',
                            TypeID: 'type-md',
                            Type: 'Markdown',
                            Visibility: 'Organization',
                            __mj_UpdatedAt: '2026-11-20T10:00:00.000Z',
                        },
                    ],
                } as RunViewResult,
                {
                    Success: true,
                    Results: [
                        {
                            ID: 'ver-a-1',
                            ArtifactID: firstArtifactID,
                            VersionNumber: 1,
                            Name: 'Stale v1',
                            Description: null,
                            Comments: null,
                            __mj_CreatedAt: '2026-11-20T10:00:00.000Z',
                            __mj_UpdatedAt: '2026-11-20T10:00:00.000Z',
                        },
                    ],
                } as RunViewResult,
            ]);

            await loadA;

            expect(component.State.ArtifactID).toBe(secondArtifactID);
            expect(component.State.Artifact?.Name).toBe('Contract B — Executive Summary');
            expect(component.ActiveVersionNumber).toBe(3);
            expect(cdrStub.markForCheck.mock.calls.length).toBe(markCountAfterB);

            // Destroy cancels any future in-flight responses cleanly.
            component.ngOnDestroy();
        } finally {
            rvSpy.mockRestore();
        }
    });

    it('persists expand/collapse preference via UserInfoEngine.Instance (never localStorage) and guards null-prototype objects', () => {
        const getSettingSpy = vi
            .spyOn(UserInfoEngine.Instance, 'GetSetting')
            .mockReturnValue('false');
        const setSettingSpy = vi
            .spyOn(UserInfoEngine.Instance, 'SetSettingDebounced')
            .mockImplementation(() => undefined);

        try {
            const { component } = createComponentInDi();
            component.DocumentArtifactID = null;
            component.ngOnInit();

            expect(getSettingSpy).toHaveBeenCalledWith(CONTRACT_DOC_PREVIEW_EXPANDED_PREF_KEY);
            expect(component.IsPreviewExpanded).toBe(false);

            component.ToggleInlinePreview();
            expect(component.IsPreviewExpanded).toBe(true);
            expect(setSettingSpy).toHaveBeenCalledWith(CONTRACT_DOC_PREVIEW_EXPANDED_PREF_KEY, 'true');
        } finally {
            getSettingSpy.mockRestore();
            setSettingSpy.mockRestore();
        }

        // Null-prototype safety via Object.prototype.hasOwnProperty.call
        const nullProto: Partial<ContractDocumentArtifactSummary> = Object.assign(
            Object.create(null) as Partial<ContractDocumentArtifactSummary>,
            { Type: 'Executive Summary', Name: 'Board Review Memo' },
        );
        expect(ReadOwnProperty(nullProto, 'Type')).toBe('Executive Summary');
        expect(ResolveContractDocumentIconClass(nullProto)).toBe('fa-solid fa-file-lines');

        // Plain-text Markdown stripper
        expect(
            StripMarkdownToPlainText('## Heading\n- **Bold** item with `code` and [link](https://x.test)\n```ts\nconst x = 1;\n```'),
        ).toBe('Heading Bold item with code and link');
    });

    it('uses only published @memberjunction/ng-artifacts@6.3.0-edge.1 exports and exposes MJCContractDocumentPreviewPanel', () => {
        expect(ArtifactsModule).toBeDefined();
        expect(ArtifactIconService).toBeDefined();
        expect(MJCContractDocumentPreviewPanel).toBeDefined();
        expect(Metadata).toBeDefined();

        const src = readFileSync(PANEL_SRC_PATH, 'utf8');
        expect(src).toContain("from '@memberjunction/ng-artifacts'");
        expect(src).toContain('<mj-artifact-viewer-panel');
        expect(src).toContain('ChangeDetectionStrategy.OnPush');
        expect(src).toContain('Object.prototype.hasOwnProperty.call');
        expect(src).not.toMatch(/MJEmbeddedDocPanelComponent|MJArtifactSlideoverComponent|MJRecordDocsListComponent|ArtifactRelatedPanelComponent/);
    });
});
