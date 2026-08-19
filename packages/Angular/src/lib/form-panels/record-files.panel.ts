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
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { ScopedRunView } from '../data/provider';

/** One linked file, flattened from the link + the file it points at. */
interface LinkedFile {
    LinkID: string;
    FileID: string;
    Name: string;
    Provider: string | null;
    Status: string | null;
    CreatedAt: string | null;
}

const PANEL_STYLES = `
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

            <div class="drop">
                <i class="fa-solid fa-cloud-arrow-up"></i>
                Attaching files is not wired yet — upload runs through MJ's storage providers, which this panel
                will call once the provider choice is settled.
            </div>

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

/**
 * All of the behaviour. Deliberately knows nothing about contracts — see the file header.
 */
@Component({
    standalone: true,
    imports: [CommonModule, BaseFormsModule],
    selector: 'mjc-record-files-panel',
    styles: [PANEL_STYLES],
    template: PANEL_TEMPLATE,
})
export class RecordFilesPanelBase extends BaseFormPanel implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    public Files: LinkedFile[] = [];
    public IsLoading = true;

    public get HasFiles(): boolean {
        return this.Files.length > 0;
    }

    public async ngOnInit(): Promise<void> {
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

            const ids = links.Results.map((l) => `'${l.FileID}'`).join(',');
            const files = await rv.RunView<{ ID: string; Name: string; ProviderKey: string | null; Status: string | null; __mj_CreatedAt: string | null }>({
                EntityName: ENTITY_FILES,
                Fields: ['ID', 'Name', 'ProviderKey', 'Status', '__mj_CreatedAt'],
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
                };
            });
        } finally {
            this.IsLoading = false;
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
    imports: [CommonModule, BaseFormsModule],
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
    imports: [CommonModule, BaseFormsModule],
    selector: 'mjc-template-files-panel',
    styles: [PANEL_STYLES],
    template: PANEL_TEMPLATE,
})
export class ContractTemplateFilesPanel extends RecordFilesPanelBase {}
