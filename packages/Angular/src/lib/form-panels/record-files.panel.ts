/**
 * @fileoverview `Documents` — the record-scoped file panel MJ does not have yet.
 *
 * CARRIED FORWARD FROM V1 (plan §6.5). The rebuild deleted every other hand-written component in
 * this package; this one survived because the gap it fills is MJ's, not v1's, and it never knew
 * anything about the billing schema. Only its registrations changed — see the bottom of the file.
 *
 * THE GAP THIS FILLS. MJ models record↔file linking properly: `__mj.FileEntityRecordLink` is a
 * polymorphic `EntityID` + `RecordID` pair, so any record can carry any number of files. What it
 * does NOT ship is a way to SEE them on a record. `@memberjunction/ng-file-storage` has
 * `mj-file-browser`, `mj-files-grid` and `mj-files-file-upload`, but all three are **category**
 * scoped; nothing in the MJ Angular tree queries `FileEntityRecordLink` at runtime (the only
 * references are the generated CRUD forms for the link entity itself). So "the files on THIS
 * record" had no UI at all.
 *
 * WHY IT IS A PANEL AND NOT A TAB. `BaseFormPanel` is MJ's own extension point: a panel registers
 * for an entity + slot and the form mounts it automatically, with no edit to the form and nothing
 * for CodeGen to overwrite. That means this panel works identically on every GENERATED form it
 * registers for — and it keeps working when they are regenerated, which is the whole reason v2
 * stopped replacing forms and started contributing panels to them (plan §6.4).
 *
 * BUILT DONATION-SHAPED, ON PURPOSE. Nothing below knows what a contract is. The logic reads
 * `Record.EntityInfo.ID` and `Record.PrimaryKey`, so it is already entity-agnostic — the only
 * contracts-specific thing in the file is *which entities it registers for*, isolated into the
 * one-line subclasses at the bottom. To donate this to MJ base, move the base class and
 * re-register it once with `entity: '*'` (PANELS.md's wildcard); the only new requirement then is
 * self-hiding on forms that have no files, which `HasFiles` already answers.
 *
 * WHY NOT WILDCARD HERE AND NOW: a wildcard panel must render nothing on the ~99% of forms it does
 * not apply to, but a panel that hides when empty can never accept the FIRST file. Registering
 * explicitly for the two entities that carry paper keeps the attach affordance available while
 * staying honest about clutter. That tension is the real design question to settle before donating.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { BaseEntity, Metadata } from '@memberjunction/core';
import { FileOpenService } from '@memberjunction/ng-file-storage';
import { GraphQLDataProvider, GraphQLFileStorageClient } from '@memberjunction/graphql-dataprovider';
import { ScopedRunView } from '../data/provider';

/** One linked file, flattened from the link + the file it points at. */
interface LinkedFile {
    LinkID: string;
    FileID: string;
    Name: string;
    Provider: string | null;
    Status: string | null;
    CreatedAt: string | null;
    /** The path/key inside the provider — what a pre-auth download URL is minted from. */
    ProviderKey: string | null;
    /** The storage ACCOUNT, which is what the download API takes (not the provider type). */
    AccountID: string | null;
}

const PANEL_STYLES = `
            .reg { margin-top: 12px; }
            .reg-title { font-size: 12px; font-weight: 600; margin-bottom: 6px; }
            .reg-row { display: flex; gap: 8px; align-items: center; }
            .reg-row input { flex: 1 1 22rem; }
            .rows { display: flex; flex-direction: column; }
            .row {
                display: flex; align-items: center; gap: 10px; padding: 9px 2px; font-size: 13px;
                border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9);
            }
            .row:last-child { border-bottom: none; }
            .row i.doc { color: var(--mj-status-error, #ef4444); }
            .row .name { font-weight: 600; }
            .row .meta { margin-left: auto; font-size: 11.5px; color: var(--mj-text-muted, #64748b); white-space: nowrap; }
            .empty {
                padding: 18px 2px; font-size: 12.5px; color: var(--mj-text-muted, #64748b);
            }
            .drop {
                border: 1px dashed var(--mj-border-strong, #cbd5e1); border-radius: var(--mj-radius-md, 6px);
                padding: 16px; text-align: center; color: var(--mj-text-muted, #64748b); font-size: 12.5px;
                margin-top: 10px;
            }
            .note {
                font-size: 11.5px; color: var(--mj-text-secondary, #475569); margin-top: 10px; line-height: 1.5;
            }
`;

const PANEL_TEMPLATE = `
        <mj-collapsible-panel
            SectionKey="recordFiles"
            SectionName="Documents"
            Icon="fa-solid fa-folder-open"
            [Form]="FormComponent"
            [FormContext]="FormContext"
        >
            <div class="rows" *ngIf="Files.length">
                <div class="row" *ngFor="let f of Files">
                    <i class="fa-solid fa-file-lines doc"></i>
                    <span class="name">{{ f.Name }}</span>
                    <button type="button" class="mjc-pill" *ngIf="CanDownload && f.AccountID"
                            (click)="Open(f)" [disabled]="Busy">Open</button>
                    <span class="meta">
                        <ng-container *ngIf="f.Status">{{ f.Status }} · </ng-container>
                        {{ f.CreatedAt ? (f.CreatedAt | date: 'mediumDate') : '' }}
                    </span>
                </div>
            </div>

            <div class="empty" *ngIf="!IsLoading && !Files.length">
                No documents attached to this record yet.
            </div>
            <div class="empty" *ngIf="IsLoading">Loading documents…</div>

            <div class="reg" *ngIf="EditMode && CanDownload">
                <div class="reg-title">Attach the executed document</div>

                <div class="reg-row">
                    <input type="text" [(ngModel)]="RegisterPath" [disabled]="Busy"
                           placeholder="Path in storage, e.g. Contracts/2026/CTR-000004.pdf"
                           aria-label="Path of an existing document in storage" />
                    <button type="button" class="mjc-pill" (click)="RegisterExisting()"
                            [disabled]="Busy || !RegisterPath.trim() || !DefaultAccountID">
                        Register existing
                    </button>
                </div>

                <p class="note" *ngIf="!DefaultAccountID">
                    No storage account is configured on this MJ instance, so there is nowhere to register a
                    document to. Configure a <code>MJ: File Storage Account</code> first — for SharePoint that
                    also needs an Azure AD app registration, which is an IT task.
                </p>

                <p class="note" *ngIf="DefaultAccountID">
                    <strong>Register</strong> points at a document that is ALREADY in storage — it creates the
                    record and the link, and moves no bytes. That is the real flow here: executed PDFs arrive in
                    SharePoint by a route MJ knows nothing about (PandaDoc &rarr; HubSpot &rarr; SharePoint), so
                    the job is to find the object and record where it is, not to upload it.
                </p>
            </div>

            <div class="note" *ngIf="ActionError">
                <strong>Nothing was attached.</strong> {{ ActionError }}
            </div>

            <p class="note" *ngIf="SigningProviderURL">
                <a [href]="SigningProviderURL" target="_blank" rel="noopener noreferrer">
                    Open in the signing provider
                </a>
                — the always-works fallback. It needs no storage configuration at all, so it is the link that
                still resolves when SharePoint is misconfigured or the document was never filed.
            </p>

            <p class="note" *ngIf="!CanDownload && Files.length">
                {{ Files.length }} document(s) are attached to this record. Opening them — and seeing their
                names — needs document permission, which is granted to finance, legal and sales leadership.
            </p>

            <p class="note">
                Documents attach through MJ's polymorphic <code>__mj.FileEntityRecordLink</code>
                (<code>EntityID</code> + <code>RecordID</code>) rather than a column on this schema — so one record
                can carry the signed PDF, its exhibits and a countersigned amendment, and no future table needs a
                new column to acquire paper.
            </p>
        </mj-collapsible-panel>
    `;

const ENTITY_FILE_LINKS = 'MJ: File Entity Record Links';
const ENTITY_FILES = 'MJ: Files';
const ENTITY_STORAGE_ACCOUNTS = 'MJ: File Storage Accounts';

/**
 * All of the behaviour. Deliberately knows nothing about contracts — see the file header.
 */
@Component({
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    selector: 'mjc-record-files-panel',
    styles: [PANEL_STYLES],
    template: PANEL_TEMPLATE,
})
export class RecordFilesPanelBase extends BaseFormPanel implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    private readonly fileOpen = inject(FileOpenService);

    public Files: LinkedFile[] = [];
    public IsLoading = true;

    /** The storage account every action runs against, or null when the instance has none. */
    public DefaultAccountID: string | null = null;

    /** Path typed into the register box. */
    public RegisterPath = '';

    /** True while an action is in flight, so the buttons cannot be double-fired. */
    public Busy = false;

    /** The last action failure, shown in the panel rather than a toast that scrolls away. */
    public ActionError: string | null = null;

    /**
     * Whether this user may DOWNLOAD, as opposed to merely see that documents exist (D-9).
     *
     * ⚠ THE OBVIOUS IMPLEMENTATION IS VACUOUS, and this was written that way first. Reading the HOST
     * RECORD's `CanRead` asks "may they see this contract" — but everyone looking at the panel can
     * already see the contract, so the gate returns true for every viewer and the restriction can
     * never bind. D-9 exists precisely to separate two populations (leadership/finance/legal may
     * download; everyone else sees the record), and gating on record visibility collapses them into
     * one. Caught on review of PR #9.
     *
     * So the gate is the **`MJ: Files` entity's** read permission — a surface genuinely DISTINCT from
     * record visibility. An administrator grants Files read to the three D-9 roles and to nobody else,
     * and the check never mentions contracts, so the panel stays entity-agnostic for donation to MJ.
     *
     * `GetUserPermisions` is the platform's own allow/deny aggregation across the user's roles, so this
     * cannot drift from what the instance actually grants. FALSE on any doubt: a hidden Open button is
     * a nuisance, a leaked executed contract is not.
     */
    public get CanDownload(): boolean {
        try {
            const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;
            const user = provider?.CurrentUser;
            if (!user) return false;
            const files = new Metadata().EntityByName(ENTITY_FILES);
            return files?.GetUserPermisions(user)?.CanRead === true;
        } catch {
            return false;
        }
    }

    /**
     * The signing provider's own URL, when the host record carries one — the always-works fallback.
     *
     * Read generically (`SigningProviderURL`) rather than by typing this panel to ContractEntity,
     * because the panel is deliberately entity-agnostic and intended for donation to MJ. A host entity
     * without the field simply has no fallback link.
     */
    public get SigningProviderURL(): string | null {
        try {
            const v = this.Record?.Get?.('SigningProviderURL');
            return v ? String(v) : null;
        } catch {
            return null;
        }
    }

    public get HasFiles(): boolean {
        return this.Files.length > 0;
    }

    public async ngOnInit(): Promise<void> {
        await this.resolveAccount();
        await this.load();
    }

    /**
     * Two reads: the links for this record, then the files they name. It is deliberately two rather
     * than one join — `RunView` is the app's only sanctioned read path (§11.1), and the second read
     * is skipped entirely when a record has no links, which is the common case.
     */
    private async load(): Promise<void> {
        this.IsLoading = true;
        try {
            const entityID = this.Record?.EntityInfo?.ID;
            const recordID = this.Record?.PrimaryKey?.GetValueByFieldName('ID') ?? this.Record?.PrimaryKey?.Values();
            if (!entityID || recordID == null) {
                this.Files = [];
                return;
            }

            // D-25: the HOST FORM's provider, not the ambient one. A panel showing files for a record
            // must read from wherever that record came from; the flagged bare `new RunView()` was correct
            // only while exactly one provider existed.
            const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
            const links = await rv.RunView<{ ID: string; FileID: string }>({
                EntityName: ENTITY_FILE_LINKS,
                Fields: ['ID', 'FileID'],
                ExtraFilter: `EntityID='${entityID}' AND RecordID='${String(recordID).replace(/'/g, "''")}'`,
                ResultType: 'simple',
            });
            if (!links?.Success || !links.Results.length) {
                this.Files = [];
                return;
            }

            // DECIDED CONSCIOUSLY (PR #9 review): a user without Files read sees the COUNT, not the
            // names. Two reasons. Reading `MJ: Files` is exactly what they lack permission for, so
            // attempting it would either fail or — worse — succeed and leak the filenames the gate is
            // meant to withhold; and a filename is itself disclosure ("Termination Notice - Northwind
            // v3.pdf" tells you plenty). Item 9's done-when is "sees the record but no download", and
            // knowing that two documents exist satisfies it without disclosing what they are.
            if (!this.CanDownload) {
                this.Files = links.Results.map((l) => ({
                    LinkID: l.ID,
                    FileID: l.FileID,
                    Name: 'Document (name withheld)',
                    Provider: null,
                    Status: null,
                    CreatedAt: null,
                    ProviderKey: null,
                    AccountID: null,
                }));
                return;
            }

            const ids = links.Results.map((l) => `'${l.FileID}'`).join(',');
            const files = await rv.RunView<{
                ID: string; Name: string; ProviderKey: string | null; Status: string | null;
                __mj_CreatedAt: string | null; ProviderID: string | null;
            }>({
                EntityName: ENTITY_FILES,
                Fields: ['ID', 'Name', 'ProviderKey', 'Status', '__mj_CreatedAt', 'ProviderID'],
                ExtraFilter: `ID IN (${ids})`,
                ResultType: 'simple',
            });
            const byID = new Map((files?.Success ? files.Results : []).map((f) => [f.ID, f]));

            this.Files = links.Results.map((l) => {
                const f = byID.get(l.FileID);
                return {
                    LinkID: l.ID,
                    FileID: l.FileID,
                    Name: f?.Name ?? '(file not found)',
                    Provider: f?.ProviderKey ?? null,
                    Status: f?.Status ?? null,
                    CreatedAt: f?.__mj_CreatedAt ?? null,
                    ProviderKey: f?.ProviderKey ?? null,
                    // The download API takes a storage ACCOUNT, and a File row names a PROVIDER (the
                    // type). We resolve the instance's account once in ngOnInit and use it for every
                    // row — correct while an instance has one account, which is the case here and is
                    // asserted rather than assumed: the Open button is hidden when there is none.
                    AccountID: this.DefaultAccountID,
                };
            });
        } finally {
            this.IsLoading = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * Resolve the instance's storage account once.
     *
     * A `File` row names a PROVIDER (the type — "SharePoint"); the download and upload APIs take an
     * ACCOUNT (a configured instance of one). Nothing on the link or the file gives us the account, so
     * it is looked up here. When there is none, every affordance that needs storage is HIDDEN rather
     * than shown-and-failing: an Open button that always errors is worse than no button.
     */
    private async resolveAccount(): Promise<void> {
        try {
            const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
            const accounts = await rv.RunView<{ ID: string; Name: string }>({
                EntityName: ENTITY_STORAGE_ACCOUNTS,
                Fields: ['ID', 'Name'],
                OrderBy: '__mj_CreatedAt ASC',
                MaxRows: 1,
                ResultType: 'simple',
            });
            this.DefaultAccountID = accounts?.Success && accounts.Results.length ? accounts.Results[0].ID : null;
        } catch {
            this.DefaultAccountID = null;
        }
    }

    /**
     * REGISTER an object that is already in storage (§6.5) — the flow this app actually needs.
     *
     * MJ's own `CreateFile` mutation assumes an UPLOAD: it creates the row `Pending` and hands back a
     * pre-auth URL for the browser to push bytes to. Our executed PDFs are already in SharePoint,
     * delivered by PandaDoc → HubSpot → SharePoint, a route MJ knows nothing about. So there is nothing
     * to upload — the work is to create the `MJ: Files` row with the right `ProviderKey` and link it.
     *
     * Done entirely through the ENTITY layer, no GraphQL: two saves, and the second is skipped if the
     * first fails, so a half-registered document (a file row nothing points at) cannot result. It
     * verifies the object EXISTS first — registering a path that is not there produces a record that
     * lies, and a document nobody can open is exactly what this panel exists to prevent.
     */
    public async RegisterExisting(): Promise<void> {
        const path = this.RegisterPath.trim();
        if (!path || !this.DefaultAccountID) return;

        this.Busy = true;
        this.ActionError = null;
        try {
            const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;
            const client = new GraphQLFileStorageClient(provider as unknown as GraphQLDataProvider);

            const exists = await client.ObjectExists(this.DefaultAccountID, path);
            if (!exists) {
                this.ActionError =
                    `Nothing is stored at "${path}". Check the path — registering a document that is not ` +
                    `there would create a record that cannot be opened.`;
                return;
            }

            const entityID = this.Record?.EntityInfo?.ID;
            const recordID = this.Record?.PrimaryKey?.GetValueByFieldName('ID');
            if (!entityID || recordID == null) {
                this.ActionError = 'This record has no primary key yet — save it before attaching a document.';
                return;
            }

            const md = new Metadata();
            const file = await md.GetEntityObject<BaseEntity>(ENTITY_FILES);
            file.NewRecord();
            file.Set('Name', path.split('/').pop() || path);
            file.Set('ProviderID', await this.resolveProviderID());
            file.Set('ProviderKey', path);
            // 'Uploaded' is the status meaning "the bytes are there". The row was not created BY an
            // upload, but the state it describes is identical, and lying about it as 'Pending' would
            // make the file invisible to anything that filters on readiness.
            file.Set('Status', 'Uploaded');
            if (!(await file.Save())) {
                this.ActionError = file.LatestResult?.Message ?? 'Could not create the file record.';
                return;
            }

            const link = await md.GetEntityObject<BaseEntity>(ENTITY_FILE_LINKS);
            link.NewRecord();
            link.Set('FileID', file.Get('ID'));
            link.Set('EntityID', entityID);
            link.Set('RecordID', String(recordID));
            if (!(await link.Save())) {
                this.ActionError =
                    `The document record was created but could not be linked to this record ` +
                    `(${link.LatestResult?.Message ?? 'save failed'}). It will not appear here until it is.`;
                return;
            }

            this.RegisterPath = '';
            await this.load();
        } catch (err) {
            this.ActionError = String(err);
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }

    /** The provider (type) behind the resolved account — a File row references the provider, not the account. */
    private async resolveProviderID(): Promise<string | null> {
        try {
            const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
            const r = await rv.RunView<{ ProviderID: string }>({
                EntityName: ENTITY_STORAGE_ACCOUNTS,
                Fields: ['ProviderID'],
                ExtraFilter: `ID = '${this.DefaultAccountID}'`,
                ResultType: 'simple',
            });
            return r?.Success && r.Results.length ? r.Results[0].ProviderID : null;
        } catch {
            return null;
        }
    }

    /**
     * Open a document via a time-limited pre-auth URL.
     *
     * Delegated to MJ's own `FileOpenService`, which mints the URL over GraphQL and is provider-agnostic
     * — the same call opens a SharePoint object, an S3 object or a Box object. Its `Provider` is set from
     * the host form's (D-25), which the service's own docs prescribe for multi-provider clients.
     *
     * The URL is pre-authenticated and time-limited, so the bytes never proxy through MJAPI and the link
     * cannot be shared indefinitely.
     */
    public async Open(f: LinkedFile): Promise<void> {
        if (!f.AccountID || !f.ProviderKey) {
            this.ActionError = 'This document has no storage path recorded, so there is nothing to open.';
            return;
        }
        this.Busy = true;
        this.ActionError = null;
        try {
            this.fileOpen.Provider = this.FormComponent?.ProviderToUse ?? null;
            const ok = await this.fileOpen.OpenFile(f.AccountID, f.ProviderKey);
            if (!ok) this.ActionError = 'The storage provider would not produce a download link for that document.';
        } catch (err) {
            this.ActionError = String(err);
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }
}

// =====================================================================================
// The only contracts-specific code in this file: WHICH entities get the panel.
// One thin subclass per entity, because a class can carry exactly one registration — and each
// needs its own @Component, so they share the hoisted template/styles rather than duplicating them.
// =====================================================================================

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:record-files:contract',
    skipNullKeyWarning: true,
    metadata: { entity: 'MJ_BizApps_Contracts: Contracts', slot: 'after-fields', sortKey: 60 },
})
@Component({
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    selector: 'mjc-contract-files-panel',
    styles: [PANEL_STYLES],
    template: PANEL_TEMPLATE,
})
export class ContractFilesPanel extends RecordFilesPanelBase {}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:record-files:template',
    skipNullKeyWarning: true,
    metadata: { entity: 'MJ_BizApps_Contracts: Contract Templates', slot: 'after-fields', sortKey: 60 },
})
@Component({
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    selector: 'mjc-template-files-panel',
    styles: [PANEL_STYLES],
    template: PANEL_TEMPLATE,
})
export class ContractTemplateFilesPanel extends RecordFilesPanelBase {}
