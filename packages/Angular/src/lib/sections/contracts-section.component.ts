/**
 * @fileoverview The Contracts Explorer tab — the app's front door.
 *
 * Registered with `@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')`, which is the
 * name the Application's `DefaultNavItems` references in
 * `metadata/applications/.contracts-application.json`. That pairing IS the wiring: Explorer reads the
 * nav metadata, asks the class factory for the driver class, and mounts this as a tab. Neither half
 * works alone — metadata without a registered class gives a dead tab, and a registered class without
 * metadata never appears at all.
 *
 * IT USES MJ'S GRID, NOT A HAND-ROLLED TABLE. `<mj-explorer-entity-data-grid>` is the same component
 * bizapps-orders uses in ~85 places. Taking it rather than writing our own means we inherit sorting,
 * paging, the toolbar, column formatting, selection — and, critically, **navigation**: the grid ships
 * `NavigateOnDoubleClick` (default true), so opening a row in the record viewer is native behaviour
 * we did not write and cannot get wrong. A bespoke table would have been a worse copy of all of it.
 *
 * The only thing this component adds is the CONTEXT the grid cannot know: which contract is selected,
 * and therefore which terms and billing events belong beside it. That is done by handing each child
 * grid a filtered `RunViewParams` — still MJ's grid, just aimed.
 *
 * DATA ACCESS is `RunView` params only (master plan §11.1). No bespoke fetch, no hand-rolled GraphQL.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import { Component, inject, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RegisterClass } from '@memberjunction/global';
import { BaseResourceComponent } from '@memberjunction/ng-shared';
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { RunViewParams } from '@memberjunction/core';
import type { ResourceData } from '@memberjunction/core-entities';
import type { AfterRowClickEventArgs } from '@memberjunction/ng-entity-viewer';

/** Entity names, declared once — a typo in a template string fails at runtime, not at build. */
const ENTITY_CONTRACTS = 'MJ_BizApps_Contracts: Contracts';
const ENTITY_TERMS = 'MJ_BizApps_Contracts: Contract Terms';
const ENTITY_LINES = 'MJ_BizApps_Contracts: Contract Lines';
const ENTITY_EVENTS = 'MJ_BizApps_Contracts: Contract Billing Events';

@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')
@Component({
    selector: 'mjc-contracts-section',
    standalone: true,
    imports: [CommonModule, BaseFormsModule],
    styles: [
        `
            :host {
                display: block;
                height: 100%;
                overflow: auto;
                background: var(--mj-bg-page, #f8fafc);
                color: var(--mj-text-primary, #1e293b);
            }
            .wrap { padding: 20px 24px 40px; }
            .head { margin-bottom: 16px; }
            .head h1 { margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -0.01em; }
            .head .sub { margin: 4px 0 0; font-size: 13px; color: var(--mj-text-secondary, #475569); max-width: 80ch; }
            .card {
                background: var(--mj-bg-surface, #fff);
                border: 1px solid var(--mj-border-default, #e2e8f0);
                border-radius: var(--mj-radius-lg, 10px);
                overflow: hidden;
                margin-bottom: 16px;
            }
            .card-head {
                display: flex; align-items: center; gap: 10px; padding: 12px 16px;
                border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9);
                font-weight: 700; font-size: 13.5px;
            }
            .card-head .right {
                margin-left: auto; font-weight: 400; font-size: 12.5px;
                color: var(--mj-text-secondary, #475569);
            }
            .hint {
                padding: 10px 16px; font-size: 12.5px;
                color: var(--mj-text-secondary, #475569);
                background: var(--mj-status-info-bg, #eff6ff);
                border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9);
            }
            .empty { padding: 26px 16px; text-align: center; color: var(--mj-text-muted, #64748b); font-size: 13px; }
            .cols { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; align-items: start; }
        `,
    ],
    template: `
        <div class="wrap">
            <div class="head">
                <h1>Contracts</h1>
                <p class="sub">
                    Every agreement this organization has committed to. <strong>Double-click a contract</strong> to open it in
                    the record viewer; single-click to see its terms, coverage and billing below.
                </p>
            </div>

            <div class="card">
                <div class="card-head">
                    All contracts
                    <span class="right" *ngIf="SelectedContractNumber">selected: {{ SelectedContractNumber }}</span>
                </div>
                <mj-explorer-entity-data-grid
                    [Params]="ContractsParams"
                    [Height]="320"
                    (AfterRowClick)="OnContractClick($event)"
                ></mj-explorer-entity-data-grid>
            </div>

            <ng-container *ngIf="SelectedContractID; else pickOne">
                <div class="card">
                    <div class="card-head">Terms</div>
                    <mj-explorer-entity-data-grid
                        [Params]="TermsParams"
                        [Height]="240"
                        (AfterRowClick)="OnTermClick($event)"
                    ></mj-explorer-entity-data-grid>
                </div>

                <div class="cols" *ngIf="SelectedTermID">
                    <div class="card">
                        <div class="card-head">Coverage<span class="right">term {{ SelectedTermNumber }}</span></div>
                        <mj-explorer-entity-data-grid [Params]="LinesParams" [Height]="240"></mj-explorer-entity-data-grid>
                    </div>
                    <div class="card">
                        <div class="card-head">Billing events<span class="right">term {{ SelectedTermNumber }}</span></div>
                        <mj-explorer-entity-data-grid [Params]="EventsParams" [Height]="240"></mj-explorer-entity-data-grid>
                    </div>
                </div>

                <div class="card" *ngIf="!SelectedTermID">
                    <div class="empty">Select a term to see its coverage and billing events.</div>
                </div>
            </ng-container>

            <ng-template #pickOne>
                <div class="card">
                    <div class="empty">Select a contract above to see its terms.</div>
                </div>
            </ng-template>
        </div>
    `,
})
export class MJCContractsSectionComponent extends BaseResourceComponent {
    private readonly cdr = inject(ChangeDetectorRef);

    public SelectedContractID: string | null = null;
    public SelectedContractNumber: string | null = null;
    public SelectedTermID: string | null = null;
    public SelectedTermNumber: string | null = null;

    /** The roster. Unfiltered — the grid's own toolbar does the searching and sorting. */
    public ContractsParams: RunViewParams = {
        EntityName: ENTITY_CONTRACTS,
        OrderBy: 'ContractNumber',
    };

    public TermsParams: RunViewParams = { EntityName: ENTITY_TERMS };
    public LinesParams: RunViewParams = { EntityName: ENTITY_LINES };
    public EventsParams: RunViewParams = { EntityName: ENTITY_EVENTS };

    public override async GetResourceDisplayName(_data: ResourceData): Promise<string> {
        return 'Contracts';
    }

    public override async GetResourceIconClass(_data: ResourceData): Promise<string> {
        return 'fa-solid fa-file-signature';
    }

    public OnContractClick(args: AfterRowClickEventArgs): void {
        const row = args?.row as Record<string, unknown> | undefined;
        const id = row?.['ID'];
        if (typeof id !== 'string') {
            return;
        }
        this.SelectedContractID = id;
        this.SelectedContractNumber = typeof row?.['ContractNumber'] === 'string' ? (row['ContractNumber'] as string) : null;

        // Reassigning the params object (rather than mutating it) is what makes the child grid
        // reload — an in-place edit would not trip Angular's input change detection.
        this.TermsParams = {
            EntityName: ENTITY_TERMS,
            ExtraFilter: `ContractID='${id}'`,
            OrderBy: 'TermNumber',
        };

        this.SelectedTermID = null;
        this.SelectedTermNumber = null;
        this.cdr.detectChanges();
    }

    public OnTermClick(args: AfterRowClickEventArgs): void {
        const row = args?.row as Record<string, unknown> | undefined;
        const id = row?.['ID'];
        if (typeof id !== 'string') {
            return;
        }
        this.SelectedTermID = id;
        const num = row?.['TermNumber'];
        this.SelectedTermNumber = num == null ? null : String(num);

        this.LinesParams = {
            EntityName: ENTITY_LINES,
            ExtraFilter: `ContractTermID='${id}'`,
            OrderBy: 'DisplayOrder',
        };
        this.EventsParams = {
            EntityName: ENTITY_EVENTS,
            ExtraFilter: `ContractTermID='${id}'`,
            OrderBy: 'ScheduledDate',
        };
        this.cdr.detectChanges();
    }
}
