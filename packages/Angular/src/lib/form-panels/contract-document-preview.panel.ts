/**
 * @fileoverview Optional Assembled Contract Document MJ Doc (`MJ: Artifacts`) preview.
 *
 * Implements the MJ Docs (`MJ: Artifacts`) vs. `MJ: Comments` vs. Quick Notes & Relational Columns
 * architecture rubric (`docs/architecture/mj-docs-rubric.md`):
 *   - Versioned long-form Assembled Contract Drafts, AI Contract Review Memos, and Executive
 *     Summaries live in `MJ: Artifacts` + `MJ: Artifact Versions`, linked via nullable
 *     `Contract.DocumentArtifactID`.
 *   - Atomic `ContractTemplateProvision`, `ContractTemplateModification`, and `Contract.Notes`
 *     remain strictly relational and untouched.
 *   - Signed executed legal PDFs remain in `MJ: Files` (`Executed Agreement` category) via
 *     `MJCContractExecutedAgreementPanel`.
 *
 * Compatible with published `@memberjunction/ng-artifacts@6.3.0-edge.1` (`ArtifactsModule`,
 * `<mj-artifact-viewer-panel>`, `ArtifactIconService`). Never globally caches `MJ: Artifacts` or
 * `MJ: Artifact Versions` in `ContractsEngineBase`.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { CommonModule } from '@angular/common';
import {
    ChangeDetectionStrategy,
    ChangeDetectorRef,
    Component,
    EventEmitter,
    Input,
    OnChanges,
    OnDestroy,
    OnInit,
    Output,
    SimpleChanges,
    ViewEncapsulation,
    inject,
} from '@angular/core';
import { CompositeKey, Metadata, type IMetadataProvider, type UserInfo } from '@memberjunction/core';
import { UserInfoEngine } from '@memberjunction/core-entities';
import { EscapeSQLString, RegisterClassEx } from '@memberjunction/global';
import { ArtifactIconService, ArtifactsModule } from '@memberjunction/ng-artifacts';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import { MJAlertComponent, MJButtonDirective, MJRefreshButtonComponent } from '@memberjunction/ng-ui-components';
import { ContractEntity } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

/** Maximum character length for plain-text summary excerpts in the preview header card. */
const SUMMARY_EXCERPT_MAX_CHARS = 220;

/** Maximum version metadata rows fetched per contract document preview (newest first). */
const MAX_PREVIEW_VERSIONS = 25;

/** User preference key stored via `UserInfoEngine.Instance` (never `localStorage`). */
export const CONTRACT_DOC_PREVIEW_EXPANDED_PREF_KEY = 'mjc.contract.docPreview.expanded';

/** Lightweight `MJ: Artifacts` projection loaded via `ResultType: 'simple'` (no heavy blobs). */
export interface ContractDocumentArtifactSummary {
    ID: string;
    Name: string;
    Description: string | null;
    TypeID: string | null;
    Type: string | null;
    Visibility: string | null;
    __mj_UpdatedAt: string | Date | null;
}

/** Lightweight `MJ: Artifact Versions` projection loaded via `ResultType: 'simple'` (skips `Content`). */
export interface ContractDocumentArtifactVersionSummary {
    ID: string;
    ArtifactID: string;
    VersionNumber: number;
    Name: string | null;
    Description: string | null;
    Comments: string | null;
    __mj_CreatedAt: string | Date | null;
    __mj_UpdatedAt: string | Date | null;
}

/** Deterministic UX state discriminator for the optional Contract MJ Doc preview. */
export type ContractDocumentPreviewStatus =
    | 'unlinked'
    | 'loading'
    | 'linked'
    | 'no-versions'
    | 'restricted';

/** Resolved view-model for a single `Contract.DocumentArtifactID` lookup. */
export interface ContractDocumentPreviewState {
    Status: ContractDocumentPreviewStatus;
    ArtifactID: string | null;
    Artifact: ContractDocumentArtifactSummary | null;
    Versions: ReadonlyArray<ContractDocumentArtifactVersionSummary>;
    LatestVersion: ContractDocumentArtifactVersionSummary | null;
    NoticeMessage: string | null;
}

/**
 * Null-prototype-safe own-property reader using `Object.prototype.hasOwnProperty.call(...)`
 * so custom-element and `Object.create(null)` records never throw `hasOwnProperty is not a function`.
 */
export function ReadOwnProperty<T extends object, K extends keyof T>(
    target: T | null | undefined,
    key: K,
): T[K] | undefined {
    if (target === null || target === undefined || typeof target !== 'object') {
        return undefined;
    }
    return Object.prototype.hasOwnProperty.call(target, key) ? target[key] : undefined;
}

/**
 * Strips raw Markdown syntax (`###`, `**bold**`, `` `code` ``, fenced blocks, `[label](url)`)
 * into clean plain text so summary cards never leak raw Markdown tokens.
 */
export function StripMarkdownToPlainText(
    raw: string | null | undefined,
    maxChars: number = SUMMARY_EXCERPT_MAX_CHARS,
): string {
    if (typeof raw !== 'string') {
        return '';
    }
    const cleaned = raw
        .replace(/```[\s\S]*?```/g, ' ')
        .replace(/`([^`]+)`/g, '$1')
        .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
        .replace(/^\s{0,3}#{1,6}\s+/gm, '')
        .replace(/^\s*[-*+]\s+/gm, '')
        .replace(/^\s*\d+\.\s+/gm, '')
        .replace(/(\*\*|__)(.*?)\1/g, '$2')
        .replace(/(\*|_)(.*?)\1/g, '$2')
        .replace(/~~(.*?)~~/g, '$1')
        .replace(/^>\s?/gm, '')
        .replace(/\s+/g, ' ')
        .trim();

    if (cleaned.length <= maxChars) {
        return cleaned;
    }
    return `${cleaned.slice(0, Math.max(0, maxChars - 1)).trimEnd()}…`;
}

/**
 * Resolves a Font Awesome 6 Free icon class for a linked contract document summary,
 * delegating to `ArtifactIconService.NormalizeMetadataIcon` when injected.
 */
export function ResolveContractDocumentIconClass(
    summary: Partial<ContractDocumentArtifactSummary> | null | undefined,
    iconService?: ArtifactIconService | null,
): string {
    const typeName = (ReadOwnProperty(summary, 'Type') ?? '').toLowerCase();
    const docName = (ReadOwnProperty(summary, 'Name') ?? '').toLowerCase();

    let rawIcon = 'fa-solid fa-file-contract';
    if (typeName.includes('slide') || typeName.includes('deck') || typeName.includes('presentation')) {
        rawIcon = 'fa-solid fa-display';
    } else if (typeName.includes('report') || typeName.includes('summary') || docName.includes('summary')) {
        rawIcon = 'fa-solid fa-file-lines';
    } else if (typeName.includes('memo') || docName.includes('review') || docName.includes('memo')) {
        rawIcon = 'fa-solid fa-magnifying-glass-chart';
    } else if (typeName.includes('code') || typeName.includes('json')) {
        rawIcon = 'fa-solid fa-file-code';
    }

    if (iconService && typeof iconService.NormalizeMetadataIcon === 'function') {
        return iconService.NormalizeMetadataIcon(rawIcon);
    }
    return rawIcon;
}

/** Normalized unlinked state factory. */
export function BuildUnlinkedDocumentPreviewState(): ContractDocumentPreviewState {
    return {
        Status: 'unlinked',
        ArtifactID: null,
        Artifact: null,
        Versions: [],
        LatestVersion: null,
        NoticeMessage: null,
    };
}

/**
 * Provider-scoped, single-request batched loader for `MJ: Artifacts` and `MJ: Artifact Versions`.
 *
 * Follows the 5-Rule BizApps Performance Standard:
 *   - Single `RunViews([...])` batch with `ResultType: 'simple'` and narrow `Fields`
 *     (never downloads `ArtifactVersion.Content` on the metadata pass; `<mj-artifact-viewer-panel>`
 *     loads version content lazily when rendered).
 *   - Respects caller RLS and entity `CanRead` permissions; never caches unbounded artifacts in
 *     `ContractsEngineBase`.
 */
export async function LoadContractDocumentPreviewState(
    provider: IMetadataProvider | null | undefined,
    documentArtifactId: string | null | undefined,
): Promise<ContractDocumentPreviewState> {
    const normalizedId = typeof documentArtifactId === 'string' ? documentArtifactId.trim() : '';
    if (!normalizedId) {
        return BuildUnlinkedDocumentPreviewState();
    }

    const effectiveProvider = provider ?? Metadata.Provider;
    const currentUser = effectiveProvider?.CurrentUser;
    if (effectiveProvider && currentUser) {
        const artifactEntity = effectiveProvider.EntityByName(MJC_FOREIGN_ENTITIES.Artifact);
        if (artifactEntity && artifactEntity.GetUserPermisions(currentUser).CanRead !== true) {
            return {
                Status: 'restricted',
                ArtifactID: normalizedId,
                Artifact: null,
                Versions: [],
                LatestVersion: null,
                NoticeMessage:
                    'This contract links to an MJ Doc artifact, but your role does not currently have read permission on MJ: Artifacts.',
            };
        }
    }

    const escapedId = EscapeSQLString(normalizedId);
    const rv = ScopedRunView(effectiveProvider);

    try {
        const [artifactResult, versionsResult] = await rv.RunViews([
            {
                EntityName: MJC_FOREIGN_ENTITIES.Artifact,
                Fields: ['ID', 'Name', 'Description', 'TypeID', 'Type', 'Visibility', '__mj_UpdatedAt'],
                ExtraFilter: `ID = '${escapedId}'`,
                MaxRows: 1,
                ResultType: 'simple',
            },
            {
                EntityName: MJC_FOREIGN_ENTITIES.ArtifactVersion,
                Fields: ['ID', 'ArtifactID', 'VersionNumber', 'Name', 'Description', 'Comments', '__mj_CreatedAt', '__mj_UpdatedAt'],
                ExtraFilter: `ArtifactID = '${escapedId}'`,
                OrderBy: 'VersionNumber DESC',
                MaxRows: MAX_PREVIEW_VERSIONS,
                ResultType: 'simple',
            },
        ]);

        if (!artifactResult?.Success) {
            return {
                Status: 'restricted',
                ArtifactID: normalizedId,
                Artifact: null,
                Versions: [],
                LatestVersion: null,
                NoticeMessage:
                    'The linked MJ Doc could not be read under your current permissions or is no longer available.',
            };
        }

        const artifactRows = (artifactResult.Results ?? []) as ContractDocumentArtifactSummary[];
        const artifact = artifactRows[0] ?? null;
        if (!artifact) {
            return {
                Status: 'restricted',
                ArtifactID: normalizedId,
                Artifact: null,
                Versions: [],
                LatestVersion: null,
                NoticeMessage:
                    'An MJ Doc is linked to this contract, but your account cannot access it under current row-level security rules or the artifact was removed.',
            };
        }

        if (!versionsResult?.Success) {
            return {
                Status: 'no-versions',
                ArtifactID: normalizedId,
                Artifact: artifact,
                Versions: [],
                LatestVersion: null,
                NoticeMessage:
                    'Document versions could not be loaded under your current permissions. You can still inspect relational clauses and Contract Notes.',
            };
        }

        const versions = ((versionsResult.Results ?? []) as ContractDocumentArtifactVersionSummary[])
            .slice()
            .sort((a, b) => (b.VersionNumber ?? 0) - (a.VersionNumber ?? 0));

        if (versions.length === 0) {
            return {
                Status: 'no-versions',
                ArtifactID: normalizedId,
                Artifact: artifact,
                Versions: [],
                LatestVersion: null,
                NoticeMessage:
                    'This linked MJ Doc currently has no accessible published versions. Create or publish a version in MJ Docs to preview it inline.',
            };
        }

        return {
            Status: 'linked',
            ArtifactID: normalizedId,
            Artifact: artifact,
            Versions: versions,
            LatestVersion: versions[0] ?? null,
            NoticeMessage: null,
        };
    } catch {
        return {
            Status: 'restricted',
            ArtifactID: normalizedId,
            Artifact: null,
            Versions: [],
            LatestVersion: null,
            NoticeMessage:
                'The linked MJ Doc is temporarily unavailable or restricted. Relational clauses, Contract Notes, and Executed Agreement attachments remain available.',
        };
    }
}

/**
 * Reusable, `OnPush`, semantic-token-only MJ Doc preview component for `Contract.DocumentArtifactID`.
 *
 * Handles all 4 contract lifecycle UX states cleanly:
 *   1. Linked `DocumentArtifactID` with accessible `ArtifactVersion` row(s) -> embedded
 *      `@memberjunction/ng-artifacts` `<mj-artifact-viewer-panel>` preview with version selector.
 *   2. `DocumentArtifactID === null` -> clean empty/unlinked state keeping `Contract.Notes` and
 *      relational clause controls unobstructed.
 *   3. Zero accessible versions or RLS/permission restriction -> non-fatal graceful fallback.
 *   4. Rapid contract switching -> monotonic `loadSequence` counter discarding stale async responses.
 */
@Component({
    selector: 'mjc-contract-document-preview',
    standalone: true,
    changeDetection: ChangeDetectionStrategy.OnPush,
    encapsulation: ViewEncapsulation.None,
    imports: [
        CommonModule,
        ArtifactsModule,
        MJButtonDirective,
        MJAlertComponent,
        MJRefreshButtonComponent,
    ],
    template: `
        <section
            class="mjc-doc-preview"
            [attr.data-doc-status]="State.Status"
            aria-label="Assembled Contract Document Preview">
            <header class="mjc-doc-preview__header">
                <div class="mjc-doc-preview__identity">
                    <span class="mjc-doc-preview__icon" aria-hidden="true">
                        <i [class]="DocumentIconClass"></i>
                    </span>
                    <div class="mjc-doc-preview__heading">
                        <div class="mjc-doc-preview__kicker">MJ Docs · Optional Assembled Draft</div>
                        <h4 class="mjc-doc-preview__title">{{ DisplayTitle }}</h4>
                    </div>
                </div>
                <div class="mjc-doc-preview__actions">
                    <span class="mjc-chip" [ngClass]="StatusChipClass">
                        {{ StatusLabel }}
                    </span>
                    @if (IsSaved && State.ArtifactID) {
                        <mj-refresh-button
                            Variant="flat"
                            Size="sm"
                            [ShowLabel]="false"
                            Title="Reload linked MJ Doc metadata"
                            [Loading]="IsLoading"
                            (Clicked)="Refresh()" />
                    }
                </div>
            </header>

            @if (!IsSaved) {
                <div class="mjc-doc-preview__empty" role="status">
                    <i class="fa-solid fa-file-circle-plus" aria-hidden="true"></i>
                    <div>
                        <strong>Save this contract to preview a linked MJ Doc</strong>
                        <p>
                            Once saved, link an Assembled Contract Draft, AI Contract Review Memo, or Executive
                            Summary via <code>DocumentArtifactID</code>. Relational clauses and
                            <code>Contract.Notes</code> remain available immediately.
                        </p>
                    </div>
                </div>
            } @else if (State.Status === 'loading') {
                <div class="mjc-doc-preview__loading" role="status">
                    <i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>
                    <span>Loading linked MJ Doc metadata…</span>
                </div>
            } @else if (State.Status === 'unlinked') {
                <div class="mjc-doc-preview__empty" role="status">
                    <i class="fa-solid fa-file-lines" aria-hidden="true"></i>
                    <div>
                        <strong>No assembled MJ Doc linked</strong>
                        <p>
                            Attach an optional Assembled Contract Draft, AI Review Memo, or Executive Summary
                            stored in MJ Docs (<code>MJ: Artifacts</code>). Relational clause provisions,
                            negotiated modifications, <code>Contract.Notes</code>, and signed Executed Agreement
                            PDFs remain fully active.
                        </p>
                    </div>
                </div>
            } @else if (State.Status === 'restricted') {
                <div class="mjc-doc-preview__fallback" role="status" data-fallback-kind="restricted">
                    <span class="mjc-doc-preview__fallback-icon" aria-hidden="true">
                        <i class="fa-solid fa-lock"></i>
                    </span>
                    <div class="mjc-doc-preview__fallback-body">
                        <strong>Linked MJ Doc is restricted or unavailable</strong>
                        <p>{{ State.NoticeMessage }}</p>
                    </div>
                </div>
            } @else if (State.Status === 'no-versions') {
                <div class="mjc-doc-preview__fallback" role="status" data-fallback-kind="no-versions">
                    <span class="mjc-doc-preview__fallback-icon" aria-hidden="true">
                        <i class="fa-solid fa-file-circle-question"></i>
                    </span>
                    <div class="mjc-doc-preview__fallback-body">
                        <strong>No accessible document versions yet</strong>
                        <p>{{ State.NoticeMessage }}</p>
                    </div>
                </div>
            } @else if (State.Status === 'linked' && State.Artifact && State.LatestVersion) {
                <div class="mjc-doc-preview__summary">
                    <div class="mjc-doc-preview__meta-row">
                        @if (State.Artifact.Type) {
                            <span class="mjc-chip mjc-chip--info">{{ State.Artifact.Type }}</span>
                        }
                        <span class="mjc-chip mjc-chip--ok">
                            v{{ ActiveVersionNumber }}
                            @if (State.Versions.length > 1) {
                                · {{ State.Versions.length }} versions
                            }
                        </span>
                        @if (State.Artifact.Visibility) {
                            <span class="mjc-chip mjc-chip--muted">{{ State.Artifact.Visibility }}</span>
                        }
                        @if (LatestUpdatedAt) {
                            <span class="mjc-doc-preview__timestamp">
                                Updated {{ LatestUpdatedAt | date: 'mediumDate' }}
                            </span>
                        }
                    </div>

                    @if (SummaryExcerpt) {
                        <p class="mjc-doc-preview__excerpt">{{ SummaryExcerpt }}</p>
                    }

                    @if (State.Versions.length > 1) {
                        <div class="mjc-doc-preview__versions" role="group" aria-label="Document versions">
                            @for (ver of State.Versions; track ver.ID) {
                                <button
                                    type="button"
                                    class="mjc-pill"
                                    [class.mjc-pill--active]="ver.VersionNumber === ActiveVersionNumber"
                                    (click)="SelectVersion(ver.VersionNumber)">
                                    v{{ ver.VersionNumber }}
                                </button>
                            }
                        </div>
                    }

                    <div class="mjc-doc-preview__controls">
                        <button
                            type="button"
                            mjButton
                            variant="outline"
                            size="sm"
                            (click)="ToggleInlinePreview()">
                            <i [class]="IsPreviewExpanded ? 'fa-solid fa-eye-slash' : 'fa-solid fa-eye'" aria-hidden="true"></i>
                            {{ IsPreviewExpanded ? 'Hide Inline Preview' : 'Show Inline Preview' }}
                        </button>
                        <button
                            type="button"
                            mjButton
                            variant="flat"
                            size="sm"
                            (click)="OpenInViewer()">
                            <i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i>
                            Open in MJ Docs
                        </button>
                    </div>
                </div>

                @if (IsPreviewExpanded && State.ArtifactID) {
                    <div class="mjc-doc-preview__viewer" aria-label="Embedded MJ Docs Viewer">
                        <mj-artifact-viewer-panel
                            [artifactId]="State.ArtifactID"
                            [VersionNumber]="ActiveVersionNumber"
                            [CurrentUser]="ResolvedCurrentUser"
                            [ShowHeader]="false"
                            [ShowTabs]="true"
                            [ShowSaveToCollection]="false"
                            [ShowCloseButton]="false"
                            [ShowMaximizeButton]="false"
                            [CanEdit]="false">
                        </mj-artifact-viewer-panel>
                    </div>
                }
            }
        </section>
    `,
    styles: [`
        .mjc-doc-preview {
            display: flex;
            flex-direction: column;
            gap: var(--mj-space-3);
            padding: var(--mj-space-4);
            background: var(--mj-bg-surface-card);
            border: 1px solid var(--mj-border-default);
            border-radius: var(--mj-radius-md);
            color: var(--mj-text-primary);
        }
        .mjc-doc-preview__header {
            display: flex;
            align-items: flex-start;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: var(--mj-space-3);
        }
        .mjc-doc-preview__identity {
            display: flex;
            align-items: center;
            gap: var(--mj-space-3);
            min-width: 0;
        }
        .mjc-doc-preview__icon {
            flex: none;
            width: 36px;
            height: 36px;
            border-radius: var(--mj-radius-sm);
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: var(--mj-status-info-bg);
            color: var(--mj-brand-primary);
            font-size: var(--mj-text-base);
        }
        .mjc-doc-preview__heading {
            min-width: 0;
        }
        .mjc-doc-preview__kicker {
            font-size: var(--mj-text-xs);
            font-weight: 700;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--mj-text-muted);
        }
        .mjc-doc-preview__title {
            margin: 2px 0 0;
            font-size: var(--mj-text-base);
            font-weight: 700;
            color: var(--mj-text-primary);
            overflow-wrap: anywhere;
        }
        .mjc-doc-preview__actions {
            display: flex;
            align-items: center;
            gap: var(--mj-space-2);
        }
        .mjc-doc-preview__loading {
            display: flex;
            align-items: center;
            gap: var(--mj-space-2);
            padding: var(--mj-space-3);
            color: var(--mj-text-muted);
            font-size: var(--mj-text-sm);
        }
        .mjc-doc-preview__empty,
        .mjc-doc-preview__fallback {
            display: flex;
            align-items: flex-start;
            gap: var(--mj-space-3);
            padding: var(--mj-space-4);
            border-radius: var(--mj-radius-md);
            background: var(--mj-bg-surface-sunken);
            border: 1px dashed var(--mj-border-strong);
            color: var(--mj-text-secondary);
            font-size: var(--mj-text-sm);
        }
        .mjc-doc-preview__fallback {
            border-style: solid;
            border-color: var(--mj-status-warning);
            background: var(--mj-status-warning-bg);
            color: var(--mj-status-warning-text);
        }
        .mjc-doc-preview__fallback-icon {
            flex: none;
            font-size: var(--mj-text-base);
            margin-top: 2px;
        }
        .mjc-doc-preview__empty p,
        .mjc-doc-preview__fallback-body p {
            margin: var(--mj-space-1) 0 0;
            line-height: 1.5;
        }
        .mjc-doc-preview__summary {
            display: flex;
            flex-direction: column;
            gap: var(--mj-space-3);
        }
        .mjc-doc-preview__meta-row {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: var(--mj-space-2);
        }
        .mjc-doc-preview__timestamp {
            font-size: var(--mj-text-xs);
            color: var(--mj-text-muted);
        }
        .mjc-doc-preview__excerpt {
            margin: 0;
            font-size: var(--mj-text-sm);
            color: var(--mj-text-secondary);
            line-height: 1.55;
        }
        .mjc-doc-preview__versions {
            display: flex;
            flex-wrap: wrap;
            gap: var(--mj-space-2);
        }
        .mjc-doc-preview__controls {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: var(--mj-space-2);
        }
        .mjc-doc-preview__viewer {
            min-height: 360px;
            border: 1px solid var(--mj-border-default);
            border-radius: var(--mj-radius-md);
            background: var(--mj-bg-surface);
            overflow: hidden;
        }
    `],
})
export class ContractDocumentPreviewComponent implements OnInit, OnChanges, OnDestroy {
    private readonly cdr = inject(ChangeDetectorRef);
    private readonly iconService = inject(ArtifactIconService, { optional: true });
    private readonly navigationService = inject(NavigationService, { optional: true });

    /** Nullable `Contract.DocumentArtifactID` pointing to `[__mj].[Artifact]([ID])`. */
    @Input() public DocumentArtifactID: string | null = null;

    /** Optional joined `Contract.DocumentArtifact` display title fallback. */
    @Input() public DocumentArtifactName: string | null = null;

    /** Optional contract number shown in accessible fallback copy. */
    @Input() public ContractNumber: string | null = null;

    /** Whether the hosting contract record has been persisted. */
    @Input() public IsSaved = true;

    /** Provider scoped to the host form (falls back to `Metadata.Provider`). */
    @Input() public Provider: IMetadataProvider | null = null;

    /** Optional explicit user context forwarded to `<mj-artifact-viewer-panel>`. */
    @Input() public CurrentUser: UserInfo | null = null;

    /** Emitted when the user clicks "Open in MJ Docs". */
    @Output() public OpenArtifactRequested = new EventEmitter<string>();

    public State: ContractDocumentPreviewState = BuildUnlinkedDocumentPreviewState();
    public IsPreviewExpanded = true;
    public SelectedVersionNumber: number | undefined = undefined;

    /** Monotonically increasing request counter that cancels/ignores stale async completions on rapid contract switches. */
    private loadSequence = 0;
    private isDestroyed = false;

    public ngOnInit(): void {
        this.IsPreviewExpanded = this.restoreExpandedPreference();
        void this.LoadPreview();
    }

    public ngOnChanges(changes: SimpleChanges): void {
        if (
            Object.prototype.hasOwnProperty.call(changes, 'DocumentArtifactID') ||
            Object.prototype.hasOwnProperty.call(changes, 'Provider') ||
            Object.prototype.hasOwnProperty.call(changes, 'IsSaved')
        ) {
            this.SelectedVersionNumber = undefined;
            void this.LoadPreview();
        }
    }

    public ngOnDestroy(): void {
        this.isDestroyed = true;
        this.loadSequence++;
    }

    public get IsLoading(): boolean {
        return this.State.Status === 'loading';
    }

    public get DisplayTitle(): string {
        const artifactName = ReadOwnProperty(this.State.Artifact, 'Name');
        if (artifactName) {
            return artifactName;
        }
        if (this.DocumentArtifactName) {
            return this.DocumentArtifactName;
        }
        if (this.ContractNumber) {
            return `Assembled Document — ${this.ContractNumber}`;
        }
        return 'Assembled Contract Document';
    }

    public get DocumentIconClass(): string {
        return ResolveContractDocumentIconClass(this.State.Artifact, this.iconService);
    }

    public get SummaryExcerpt(): string {
        const desc = ReadOwnProperty(this.State.Artifact, 'Description');
        return StripMarkdownToPlainText(desc);
    }

    public get ActiveVersionNumber(): number | undefined {
        return this.SelectedVersionNumber ?? this.State.LatestVersion?.VersionNumber;
    }

    public get LatestUpdatedAt(): string | Date | null {
        return (
            ReadOwnProperty(this.State.LatestVersion, '__mj_UpdatedAt') ??
            ReadOwnProperty(this.State.Artifact, '__mj_UpdatedAt') ??
            null
        );
    }

    public get ResolvedCurrentUser(): UserInfo {
        return (this.CurrentUser ?? this.Provider?.CurrentUser ?? Metadata.Provider.CurrentUser) as UserInfo;
    }

    public get StatusLabel(): string {
        switch (this.State.Status) {
            case 'loading':
                return 'Checking link…';
            case 'linked':
                return 'Linked MJ Doc';
            case 'no-versions':
                return 'No versions';
            case 'restricted':
                return 'Restricted';
            case 'unlinked':
            default:
                return 'Not linked';
        }
    }

    public get StatusChipClass(): string {
        switch (this.State.Status) {
            case 'linked':
                return 'mjc-chip--ok';
            case 'no-versions':
            case 'restricted':
                return 'mjc-chip--warn';
            case 'loading':
                return 'mjc-chip--info';
            case 'unlinked':
            default:
                return 'mjc-chip--muted';
        }
    }

    public async Refresh(): Promise<void> {
        await this.LoadPreview();
    }

    public SelectVersion(versionNumber: number): void {
        this.SelectedVersionNumber = versionNumber;
        this.cdr.markForCheck();
    }

    public ToggleInlinePreview(): void {
        this.IsPreviewExpanded = !this.IsPreviewExpanded;
        this.persistExpandedPreference(this.IsPreviewExpanded);
        this.cdr.markForCheck();
    }

    public OpenInViewer(): void {
        const artifactId = this.State.ArtifactID;
        if (!artifactId) {
            return;
        }
        if (this.OpenArtifactRequested.observed) {
            this.OpenArtifactRequested.emit(artifactId);
            return;
        }
        this.navigationService?.OpenEntityRecord(MJC_FOREIGN_ENTITIES.Artifact, CompositeKey.FromID(artifactId));
    }

    /**
     * Loads the linked `MJ: Artifacts` + `MJ: Artifact Versions` metadata for the current
     * `DocumentArtifactID`. A monotonic request token guarantees stale async completions from a
     * previously selected Contract record are ignored under `ChangeDetectionStrategy.OnPush`.
     */
    public async LoadPreview(): Promise<ContractDocumentPreviewState> {
        const token = ++this.loadSequence;
        const normalizedId = typeof this.DocumentArtifactID === 'string' ? this.DocumentArtifactID.trim() : '';

        if (!this.IsSaved || !normalizedId) {
            const unlinked = BuildUnlinkedDocumentPreviewState();
            this.State = unlinked;
            this.SelectedVersionNumber = undefined;
            this.cdr.markForCheck();
            return unlinked;
        }

        this.State = {
            Status: 'loading',
            ArtifactID: normalizedId,
            Artifact: null,
            Versions: [],
            LatestVersion: null,
            NoticeMessage: null,
        };
        this.cdr.markForCheck();

        const resolved = await LoadContractDocumentPreviewState(this.Provider, normalizedId);

        // Discard stale async completions if the user switched contracts or the view was destroyed.
        if (this.isDestroyed || token !== this.loadSequence) {
            return this.State;
        }

        this.State = resolved;
        if (resolved.LatestVersion) {
            this.SelectedVersionNumber = resolved.LatestVersion.VersionNumber;
        } else {
            this.SelectedVersionNumber = undefined;
        }
        this.cdr.markForCheck();
        return resolved;
    }

    private restoreExpandedPreference(): boolean {
        try {
            const saved = UserInfoEngine.Instance.GetSetting(CONTRACT_DOC_PREVIEW_EXPANDED_PREF_KEY);
            if (saved === 'false') {
                return false;
            }
            if (saved === 'true') {
                return true;
            }
        } catch {
            /* UserInfoEngine unavailable in isolated tests — default to expanded */
        }
        return true;
    }

    private persistExpandedPreference(expanded: boolean): void {
        try {
            UserInfoEngine.Instance.SetSettingDebounced(
                CONTRACT_DOC_PREVIEW_EXPANDED_PREF_KEY,
                expanded ? 'true' : 'false',
            );
        } catch {
            /* UserInfoEngine unavailable — preference simply does not persist */
        }
    }
}

/**
 * Contributed `BaseFormPanel` mounting `<mjc-contract-document-preview>` onto the generated
 * `MJ_BizApps_Contracts: Contracts` form without replacing `@RegisterClass(BaseFormComponent, ...)`.
 */
@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:document-preview',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-related',
        sortKey: 48,
        contributionKey: 'documentPreview',
    },
})
@Component({
    selector: 'mjc-contract-document-preview-panel',
    standalone: true,
    changeDetection: ChangeDetectionStrategy.OnPush,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, ContractDocumentPreviewComponent],
    template: `
        <mj-collapsible-panel
            SectionKey="documentPreview"
            SectionName="Assembled document"
            Icon="fa-solid fa-file-contract"
            [Form]="FormComponent"
            [FormContext]="FormContext">
            <div class="mjc-body">
                <mjc-contract-document-preview
                    [DocumentArtifactID]="DocumentArtifactID"
                    [DocumentArtifactName]="DocumentArtifactName"
                    [ContractNumber]="ContractNumber"
                    [IsSaved]="IsContractSaved"
                    [Provider]="ProviderToUse"
                    [CurrentUser]="CurrentUser"
                    (OpenArtifactRequested)="OnOpenArtifact($event)" />
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractDocumentPreviewPanel extends BaseFormPanel<ContractEntity> {
    public get DocumentArtifactID(): string | null {
        return this.Record?.DocumentArtifactID ?? null;
    }

    public get DocumentArtifactName(): string | null {
        return this.Record?.DocumentArtifact ?? null;
    }

    public get ContractNumber(): string | null {
        return this.Record?.ContractNumber ?? null;
    }

    public get IsContractSaved(): boolean {
        return Boolean(this.Record?.IsSaved);
    }

    public get ProviderToUse(): IMetadataProvider {
        return this.FormComponent?.ProviderToUse ?? Metadata.Provider;
    }

    public get CurrentUser(): UserInfo | null {
        return this.ProviderToUse?.CurrentUser ?? null;
    }

    public OnOpenArtifact(artifactId: string): void {
        if (!artifactId) {
            return;
        }
        this.FormComponent?.OnFormNavigate({
            Kind: 'record',
            EntityName: MJC_FOREIGN_ENTITIES.Artifact,
            PrimaryKey: CompositeKey.FromID(artifactId),
        });
    }
}
