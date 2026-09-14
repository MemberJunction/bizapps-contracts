/**
 * @fileoverview Executed agreement — mark WHICH linked file is the signed contract (golive #213).
 *
 * WHY THIS PANEL EXISTS. Since contracts #36 (golive #203 item 16) `vwContracts.IsAwaitingDocument`
 * clears only when a file linked to the contract carries MJ's file category named
 * 'Executed Agreement'. Files themselves attach through MJ's stock Attachments panel on the form
 * toolbar — but at 6.1.0-edge.4 that panel cannot set a file's category: its upload has no dialog to
 * put a checkbox in, its Edit Details writes only name and description, and the form container
 * passes it no default category. So the gate the migration introduced could never be satisfied from
 * the UI, and a contract whose type requires an executed document read "Awaiting document" whatever
 * was attached. This panel closes exactly that gap and nothing else: attach, remove and open stay
 * with the stock panel.
 *
 * THE RE-PAPERING RULE, adopted deliberately (supersede.panel.ts): ALWAYS VISIBLE, not gated on
 * EditMode. Marking writes the FILE, not this record, in its own save — it is not one of the form's
 * fields, so it is available in read mode and shown read-only while the form is editing or the
 * contract is unsaved. A contract with no primary key yet has nothing linked to mark.
 *
 * BY NAME, never by id, for the same reason the view and the migration do it that way: the category
 * row is seeded per database, so a hardcoded UUID stops matching the first time an environment is
 * rebuilt from zero. The one spelling lives in `@mj-biz-apps/contracts-entities` and a test pins it
 * to the migration seed.
 *
 * WHAT "MARKED" MEANS HERE is what the VIEW means: the linked file's category NAME is
 * 'Executed Agreement'. Mark sets `File.CategoryID` to that category's row; Unmark clears it to null
 * (a previous category, if any, is not restored — the stock panel shows and never sets one, so there
 * is nothing to restore in practice). After either write the form re-reads the record, because the
 * header chip and the Overview health line read the PERSISTED view column rather than re-deriving it.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { EscapeSQLString, RegisterClassEx } from '@memberjunction/global';
import { Metadata, type IMetadataProvider, type RunView } from '@memberjunction/core';
import type { MJFileEntity } from '@memberjunction/core-entities';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { MJAlertComponent, MJButtonDirective, MJRefreshButtonComponent } from '@memberjunction/ng-ui-components';
import { ContractEntity, EXECUTED_AGREEMENT_FILE_CATEGORY } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

/** One file linked to this contract, with the loaded entity so Mark/Unmark save exactly the row that was read. */
interface LinkedFile {
    FileID: string;
    Name: string;
    CategoryName: string | null;
    Entity: MJFileEntity;
}

/** The view's predicate, in TypeScript: `fc.Name = 'Executed Agreement'` under a case-insensitive collation. */
function isExecutedAgreementCategory(categoryName: string | null | undefined): boolean {
    return (categoryName ?? '').trim().toLowerCase() === EXECUTED_AGREEMENT_FILE_CATEGORY.toLowerCase();
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:executed-agreement',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        // `after-fields` puts this in the FIELD-panel band, which the left-nav chrome collapses into the
        // single "Details" rail item, next to Re-papering (sortKey 40; higher sorts earlier).
        slot: 'after-fields',
        sortKey: 45,
        // MUST equal the panel's SectionKey — the container resolves chrome by this and builds rail
        // groups from that (see metadata/entities/.entities.json).
        contributionKey: 'executedAgreement',
    },
})
@Component({
    selector: 'mjc-contract-executed-agreement-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, MJButtonDirective, MJAlertComponent, MJRefreshButtonComponent],
    template: `
        <mj-collapsible-panel
            SectionKey="executedAgreement"
            SectionName="Executed agreement"
            Icon="fa-solid fa-file-circle-check"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <!-- Mirrors mj-form-field's markup so this reads as an ordinary form line. It cannot BE an
                 mj-form-field: the value it edits lives on MJ: Files, not on this record. -->
            <div class="mj-forms-field">
                <div class="mjc-exec-head">
                    <label class="mj-forms-field-label">Executed agreement</label>
                    <!-- Files attach through the toolbar's Attachments panel, which tells this panel nothing:
                         closing it refreshes only the toolbar count. Without this, a file attached a moment
                         ago is not listed until the record is reloaded. -->
                    @if (Record.IsSaved) {
                        <mj-refresh-button Variant="flat" Size="sm" [ShowLabel]="false"
                                           Title="Reload the linked files"
                                           [Loading]="Loading" [Disabled]="Busy"
                                           (Clicked)="Refresh()" />
                    }
                </div>
                <div class="mj-forms-field-control">
                    @let files = Files;

                    @if (Loading) {
                        <div class="mjc-hint">Loading linked files…</div>
                    } @else if (LoadError) {
                        <mj-alert Variant="warning" Size="sm" [Message]="LoadError" />
                    } @else if (!files.length) {
                        <span class="mj-forms-field-value">—</span>
                        @if (Record.IsSaved) {
                            <div class="mjc-hint">
                                No files are linked to this contract. Attach the signed PDF with the Attachments
                                button on the toolbar, then mark it here.
                            </div>
                        }
                    } @else {
                        <table class="mjc-grid">
                            <thead>
                                <tr><th>File</th><th>Category</th><th></th></tr>
                            </thead>
                            <tbody>
                                @for (f of files; track f.FileID) {
                                    <tr>
                                        <td>{{ f.Name }}</td>
                                        <td>
                                            @if (IsExecutedAgreement(f)) {
                                                <span class="mjc-chip mjc-chip--ok">
                                                    <i class="fa-solid fa-file-circle-check" aria-hidden="true"></i> Executed agreement
                                                </span>
                                            } @else if (f.CategoryName) {
                                                <span class="mjc-chip mjc-chip--muted">{{ f.CategoryName }}</span>
                                            } @else {
                                                <span class="mjc-muted">—</span>
                                            }
                                        </td>
                                        <td>
                                            @if (CanMark) {
                                                @if (IsExecutedAgreement(f)) {
                                                    <button mjButton variant="flat" size="sm" type="button" [disabled]="Busy"
                                                            (click)="Unmark(f)"
                                                            [attr.aria-label]="'Unmark ' + f.Name + ' as the executed agreement'">
                                                        Unmark
                                                    </button>
                                                } @else {
                                                    <button mjButton variant="primary" size="sm" type="button"
                                                            [disabled]="Busy || !CategoryID"
                                                            (click)="Mark(f)"
                                                            [attr.aria-label]="'Mark ' + f.Name + ' as the executed agreement'">
                                                        Mark as executed agreement
                                                    </button>
                                                }
                                            }
                                        </td>
                                    </tr>
                                }
                            </tbody>
                        </table>
                    }

                    <!-- The Re-papering rule: read-only while editing or unsaved, with the same two chips. -->
                    @if (ReadOnly) {
                        <span class="mjc-chip mjc-chip--muted">
                            {{ Record.IsSaved ? 'Finish editing to change' : 'Save this contract first' }}
                        </span>
                    } @else {
                        @if (!CanUpdateFiles) {
                            <div class="mjc-hint">
                                Marking a file changes its category on MJ: Files, which your roles cannot update.
                                Ask an administrator to grant update permission on MJ: Files.
                            </div>
                        } @else if (CategoryMissing) {
                            <mj-alert Variant="warning" Size="sm"
                                      [Message]="'The file category named ' + CategoryName + ' does not exist on this database, so nothing can be marked. The contracts migration V202609010100 seeds it.'" />
                        }
                        @if (Unreadable) {
                            <div class="mjc-hint">
                                {{ Unreadable }} linked file(s) could not be read and are not listed — reading MJ: Files needs
                                read permission on that entity.
                            </div>
                        }
                        @if (ActionError) { <mj-alert Variant="error" Size="sm" [Message]="ActionError" /> }
                        @if (ActionOk) { <mj-alert Variant="success" Size="sm" [Message]="ActionOk" /> }
                    }

                    <div class="mjc-hint">
                        “Awaiting document” clears when a linked file is marked as the executed agreement. Attaching,
                        removing and opening files stays with the Attachments button on the toolbar.
                    </div>
                </div>
            </div>
        </mj-collapsible-panel>
    `,
    styles: [`
        .mjc-exec-head { display: flex; align-items: center; justify-content: space-between; gap: var(--mj-space-2); }
    `],
})
export class MJCContractExecutedAgreementPanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

    /** The category's display name, for copy. */
    public readonly CategoryName = EXECUTED_AGREEMENT_FILE_CATEGORY;
    /** The `MJ: File Categories` row named {@link EXECUTED_AGREEMENT_FILE_CATEGORY}, resolved per load; null when absent. */
    public CategoryID: string | null = null;
    /** True after a successful load that found no category row — a database the migration has not reached. */
    public CategoryMissing = false;
    public Loading = false;
    /** True while a Mark/Unmark is in flight, so a button cannot be double-fired. */
    public Busy = false;
    /** Why the list is empty, when the reason is a failed read rather than genuinely nothing. */
    public LoadError = '';
    public ActionError = '';
    /** Confirmation, so a working mark is never indistinguishable from a silent no-op. */
    public ActionOk = '';
    /** Links whose file row did not come back — most likely no read permission on MJ: Files. */
    public Unreadable = 0;

    private _files: LinkedFile[] = [];
    /**
     * WHICH contract the list was loaded for, not merely whether it was (the #28 item 23 lesson): the
     * form reuses this instance when it navigates to another contract, and a boolean would keep the
     * previous contract's files on screen.
     */
    private loadedFor: string | null = null;

    /** The linked files. Loaded on first read; no EditMode gate, because the panel is always shown. */
    public get Files(): LinkedFile[] {
        const id = this.Record?.ID;
        if (id && this.loadedFor !== id) {
            this.loadedFor = id;
            void this.load();
        }
        return this._files;
    }

    /** Read-only while the form is editing or the contract has never been saved — the Re-papering rule. */
    public get ReadOnly(): boolean {
        return this.EditMode || !this.Record?.IsSaved;
    }

    /** Whether the buttons render at all: writable, permitted, and a category row to point at. */
    public get CanMark(): boolean {
        return !this.ReadOnly && this.CanUpdateFiles && !this.LoadError;
    }

    /**
     * Whether this user may change a file's category — the `MJ: Files` entity's update permission, which
     * is the platform's own allow/deny aggregation across the user's roles. FALSE on any doubt: a hidden
     * button and a sentence saying why beat a button that fails.
     */
    public get CanUpdateFiles(): boolean {
        const provider = this.provider;
        const user = provider.CurrentUser;
        if (!user) return false;
        const files = provider.EntityByName(MJC_FOREIGN_ENTITIES.File);
        return files?.GetUserPermisions(user).CanUpdate === true;
    }

    public IsExecutedAgreement(file: LinkedFile): boolean {
        return isExecutedAgreementCategory(file.CategoryName);
    }

    /** The form's toolbar Refresh, or a refresh this panel triggered after a write: re-read the list. */
    public override OnRecordRefreshed(): void {
        void this.load();
    }

    /** The panel's own refresh button — the list only, since attaching a file does not change the record. */
    public async Refresh(): Promise<void> {
        this.ActionOk = '';
        this.ActionError = '';
        await this.load();
    }

    public async Mark(file: LinkedFile): Promise<void> {
        if (!this.CategoryID) return;
        await this.setCategory(file, this.CategoryID, `Marked — ${file.Name} is the executed agreement.`);
    }

    public async Unmark(file: LinkedFile): Promise<void> {
        await this.setCategory(file, null, `Unmarked — ${file.Name} is no longer the executed agreement.`);
    }

    /** The host form's provider, so this panel reads and writes wherever the record it is showing came from. */
    private get provider(): IMetadataProvider {
        return this.FormComponent?.ProviderToUse ?? Metadata.Provider;
    }

    /**
     * Write the category on the FILE, then re-read the RECORD. `Save()` does not throw; it returns false
     * and leaves the reason on `LatestResult`. On failure the in-memory entity is reverted so the row
     * does not claim a category the database refused.
     */
    private async setCategory(file: LinkedFile, categoryID: string | null, okMessage: string): Promise<void> {
        this.Busy = true;
        this.ActionError = '';
        this.ActionOk = '';
        try {
            file.Entity.CategoryID = categoryID;
            if (!(await file.Entity.Save())) {
                file.Entity.Revert();
                throw new Error(file.Entity.LatestResult?.CompleteMessage || 'The file could not be saved.');
            }
            this.ActionOk = okMessage;
            await this.reReadRecord();
        } catch (e) {
            this.ActionError = e instanceof Error ? e.message : String(e);
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * The header chip and the Overview read `IsAwaitingDocument` off the PERSISTED view column, so the
     * record has to come back from the database. `RefreshRecord()` also notifies every panel through
     * `OnRecordRefreshed`, which is how this list reloads; when it declines (editing, unsaved, or no
     * form host) the list is reloaded directly so the row at least shows what was written.
     */
    private async reReadRecord(): Promise<void> {
        const refreshed = this.FormComponent ? await this.FormComponent.RefreshRecord() : false;
        if (!refreshed) await this.load();
    }

    /** Category row, then links, then the files they name — three reads, the last two skipped when nothing is linked. */
    private async load(): Promise<void> {
        if (!this.Record?.IsSaved) return;
        this.Loading = true;
        try {
            const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
            await this.resolveCategory(rv);
            this._files = await this.loadLinkedFiles(rv);
            // A later success clears an earlier failure, and clears it HERE rather than at the top of the
            // try, so a reload does not blank the explanation while it is in flight.
            this.LoadError = '';
        } catch (e) {
            // Do NOT swallow this: an empty list and a failed read look identical on screen, and the
            // difference is the whole diagnosis.
            this._files = [];
            this.LoadError = `Could not read the files linked to this contract: ${e instanceof Error ? e.message : String(e)}`;
            this.loadedFor = null; // let the next read retry
        } finally {
            this.Loading = false;
            this.cdr.detectChanges();
        }
    }

    /** The category the view resolves on, looked up the way the view does it: by Name. */
    private async resolveCategory(rv: RunView): Promise<void> {
        const r = await rv.RunView<{ ID: string; Name: string }>({
            EntityName: MJC_FOREIGN_ENTITIES.FileCategory,
            Fields: ['ID', 'Name'],
            ExtraFilter: `Name = '${EscapeSQLString(EXECUTED_AGREEMENT_FILE_CATEGORY)}'`,
            ResultType: 'simple',
        });
        if (!r?.Success) throw new Error(r?.ErrorMessage || 'file categories could not be read');
        this.CategoryID = r.Results[0]?.ID ?? null;
        this.CategoryMissing = !this.CategoryID;
    }

    /**
     * The links for THIS record, then the files they name — through MJ's polymorphic
     * `MJ: File Entity Record Links` (EntityID + RecordID), which is where the view looks too.
     * `entity_object` on the files is load-bearing: Mark/Unmark save the very entity that was read.
     */
    private async loadLinkedFiles(rv: RunView): Promise<LinkedFile[]> {
        const entityID = this.Record.EntityInfo.ID;
        const links = await rv.RunView<{ ID: string; FileID: string }>({
            EntityName: MJC_FOREIGN_ENTITIES.FileEntityRecordLink,
            Fields: ['ID', 'FileID'],
            ExtraFilter: `EntityID = '${EscapeSQLString(entityID)}' AND RecordID = '${EscapeSQLString(this.Record.ID)}'`,
            ResultType: 'simple',
        });
        if (!links?.Success) throw new Error(links?.ErrorMessage || 'file links could not be read');
        this.Unreadable = 0;
        if (!links.Results.length) return [];

        const ids = links.Results.map((l) => `'${EscapeSQLString(l.FileID)}'`).join(',');
        const files = await rv.RunView<MJFileEntity>({
            EntityName: MJC_FOREIGN_ENTITIES.File,
            ExtraFilter: `ID IN (${ids})`,
            OrderBy: 'Name ASC',
            ResultType: 'entity_object',
        });
        if (!files?.Success) throw new Error(files?.ErrorMessage || 'file details could not be read');
        this.Unreadable = Math.max(0, links.Results.length - files.Results.length);
        return files.Results.map((f) => ({ FileID: f.ID, Name: f.Name, CategoryName: f.Category, Entity: f }));
    }
}
