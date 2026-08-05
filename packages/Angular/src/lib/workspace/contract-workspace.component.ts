/**
 * @fileoverview `mjc-contract-workspace` — ONE surface for viewing, editing and creating a contract.
 *
 * WHY THESE WERE MERGED. A contract is never finished being created. A draft gains a term next week,
 * coverage after legal review, a billing schedule when the cadence is agreed. Two separate surfaces
 * force somebody to decide at an arbitrary moment that the thing has stopped being created, and then
 * every entity that appears afterwards becomes an argument about which surface owns it. One surface
 * deletes the argument: a contract being created is simply a draft whose `ID` is null.
 *
 * THE TWO TABBING SYSTEMS, doing different jobs (see also `contract-tabs.model.ts`):
 *   - The workspace-card strip OUTSIDE this component models OPEN DOCUMENTS — several contracts side
 *     by side, each closable, each with its own buffer. A new contract is just a card with no id.
 *   - The tabs INSIDE it are PANES OF ONE CONTRACT. You cannot close Coverage or add a seventh, and
 *     each carries one of three states so the strip teaches the sequence as well as showing it.
 *
 * EVERY ENTITY IS MANAGEABLE HERE. Terms, coverage, billing schedules and commitments are all
 * created, edited and removed from their own pane — that was the gap: four of them previously had a
 * bare grid with no create affordance, so the only way to add one was to navigate out to MJ's
 * generic record form.
 *
 * THE STATE IS A `ContractDraft`, not a pile of fields — one object holding the whole tree, which is
 * what makes an atomic save possible at all (a browser cannot compose the entity's child collections;
 * see the note in contract-draft.ts). The draft also produces the validation this component renders,
 * so the badge on a tab and the marker on a field come from ONE source.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import { ChangeDetectorRef, Component, EventEmitter, Input, Output, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MJButtonDirective, MJTabNavComponent, type TabConfig } from '@memberjunction/ng-ui-components';
import {
    ContractDraft,
    ContractDraftTerm,
    ContractDraftLine,
    ContractDraftSchedule,
    ContractDraftCommitment,
    ContractsSaveContractOperation,
    type ContractDraftIssue,
    type ContractDraftPayload,
} from '@mj-biz-apps/contracts-entities';
import {
    BuildContractTabs,
    CanSave,
    ResolveActiveTab,
    ToTabConfigs,
    type ContractTabDef,
    type ContractTabKey,
} from './contract-tabs.model';

/** A `{ ID, Name }` row for a picker. The shell supplies these; this component never queries. */
export interface WorkspaceLookup {
    ID: string;
    Name: string;
}

/** Every picker list the panes need, supplied once by the shell. */
export interface WorkspaceLookups {
    Types: WorkspaceLookup[];
    Companies: WorkspaceLookup[];
    Organizations: WorkspaceLookup[];
    People: WorkspaceLookup[];
    Users: WorkspaceLookup[];
    Products: WorkspaceLookup[];
    SubscriptionTypes: WorkspaceLookup[];
    PaymentTerms: WorkspaceLookup[];
    Currencies: WorkspaceLookup[];
}

const LINE_TYPES = ['Subscription', 'OneTime', 'Milestone', 'Usage', 'Minimum'] as const;
const BILLING_FREQUENCIES = ['Monthly', 'Quarterly', 'SemiAnnual', 'Annual', 'Milestone', 'Custom'] as const;
const SCHEDULE_TYPES = ['Cadence', 'Milestone', 'Custom'] as const;
const COMMITMENT_TYPES = ['Minimum', 'Prepaid', 'Draw'] as const;
const TRUE_UP_POLICIES = ['BillShortfall', 'Forfeit', 'Rollover'] as const;
const CONTRACT_STATUSES = ['Draft', 'PendingSignature', 'Active', 'Expired', 'Terminated', 'Superseded'] as const;
const TERM_STATUSES = ['Pending', 'PendingSignature', 'Active', 'Completed', 'Terminated'] as const;

@Component({
    selector: 'mjc-contract-workspace',
    standalone: true,
    imports: [CommonModule, FormsModule, MJButtonDirective, MJTabNavComponent],
    styles: [
        `
        .ws { display: flex; flex-direction: column; gap: var(--mj-space-4, 16px); }
        .ws-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
        .ws-id { display: flex; flex-direction: column; gap: 4px; }
        .ws-num { font-size: 18px; font-weight: 600; color: var(--mj-text-primary); }
        .ws-sub { font-size: 13px; color: var(--mj-text-secondary); }
        .ws-actions { display: flex; gap: var(--mj-space-2, 8px); align-items: center; }

        .issues { border: 1px solid var(--mj-border-default); border-left: 3px solid var(--mj-color-danger, #d33);
                  border-radius: var(--mj-radius-md, 6px); padding: 12px 14px; background: var(--mj-bg-surface-card); }
        .issues h4 { margin: 0 0 8px; font-size: 13px; font-weight: 600; color: var(--mj-text-primary); }
        .issues ul { margin: 0; padding-left: 18px; }
        .issues li { font-size: 13px; color: var(--mj-text-secondary); margin-bottom: 4px; }
        .issues li .where { color: var(--mj-text-primary); font-weight: 500; }

        .pane { border: 1px solid var(--mj-border-default); border-radius: var(--mj-radius-lg, 8px);
                background: var(--mj-bg-surface-card); padding: var(--mj-space-4, 16px); }
        .pane-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; gap: 12px; }
        .pane-head h3 { margin: 0; font-size: 14px; font-weight: 600; color: var(--mj-text-primary); }
        .pane-note { font-size: 12.5px; color: var(--mj-text-secondary); margin: 0 0 12px; }

        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px 16px; }
        .fld { display: flex; flex-direction: column; gap: 4px; }
        .fld label { font-size: 12px; font-weight: 500; color: var(--mj-text-secondary); }
        .fld input, .fld select, .fld textarea {
            padding: 7px 9px; font: inherit; font-size: 13px; color: var(--mj-text-primary);
            background: var(--mj-bg-surface); border: 1px solid var(--mj-border-default);
            border-radius: var(--mj-radius-md, 6px);
        }
        .fld.bad input, .fld.bad select { border-color: var(--mj-color-danger, #d33); }
        .fld .msg { font-size: 11.5px; color: var(--mj-color-danger, #d33); }

        .rows { display: flex; flex-direction: column; gap: 10px; }
        .row { border: 1px solid var(--mj-border-default); border-radius: var(--mj-radius-md, 6px);
               padding: 12px; background: var(--mj-bg-surface); }
        .row-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 10px; }
        .row-title { font-size: 13px; font-weight: 600; color: var(--mj-text-primary); }
        .row-title .muted { font-weight: 400; color: var(--mj-text-secondary); }
        .empty { padding: 24px; text-align: center; color: var(--mj-text-secondary); font-size: 13px; }
        .term-pick { display: flex; gap: 8px; align-items: center; margin-bottom: 12px; flex-wrap: wrap; }
        .term-pick label { font-size: 12px; color: var(--mj-text-secondary); }
        `,
    ],
    template: `
    <div class="ws">
      <div class="ws-head">
        <div class="ws-id">
          <span class="ws-num">{{ Draft.ContractNumber || 'New contract' }}</span>
          <span class="ws-sub">
            {{ Draft.IsSaved ? 'Saved' : 'Not yet saved' }}
            <ng-container *ngIf="Draft.Description"> · {{ Draft.Description }}</ng-container>
          </span>
        </div>
        <div class="ws-actions">
          <span class="ws-sub" *ngIf="Message">{{ Message }}</span>
          <button mjButton [disabled]="Saving() || !CanSaveNow" (click)="Save()">
            <i class="fa-solid fa-floppy-disk"></i>
            {{ Saving() ? 'Saving…' : (Draft.IsSaved ? 'Save changes' : 'Create contract') }}
          </button>
        </div>
      </div>

      <!-- The issue list. A red badge on a tab says WHERE; this says WHAT, so a mark is never the
           only clue a user gets. -->
      <div class="issues" *ngIf="BlockingIssues.length">
        <h4>{{ BlockingIssues.length }} thing{{ BlockingIssues.length === 1 ? '' : 's' }} to fix before this can be saved</h4>
        <ul>
          <li *ngFor="let issue of BlockingIssues">
            <span class="where">{{ WhereLabel(issue) }}</span> — {{ issue.Message }}
          </li>
        </ul>
      </div>

      <mj-tab-nav [Tabs]="TabConfigs" [ActiveKey]="ActiveTab()" (TabChange)="SelectTab($event)"></mj-tab-nav>

      <!-- ── Contract ────────────────────────────────────────────────────────────────────────── -->
      <div class="pane" *ngIf="ActiveTab() === 'contract'">
        <div class="pane-head"><h3>The agreement</h3></div>
        <div class="grid">
          <div class="fld" [class.bad]="HasFieldIssue('ContractTypeID')">
            <label>Contract type</label>
            <select [(ngModel)]="Draft.ContractTypeID" (ngModelChange)="Touch()">
              <option value="">Choose…</option>
              <option *ngFor="let t of Lookups.Types" [value]="t.ID">{{ t.Name }}</option>
            </select>
            <span class="msg" *ngIf="FieldIssue('ContractTypeID') as m">{{ m }}</span>
          </div>
          <div class="fld" [class.bad]="HasFieldIssue('CompanyID')">
            <label>Company</label>
            <select [(ngModel)]="Draft.CompanyID" (ngModelChange)="Touch()">
              <option value="">Choose…</option>
              <option *ngFor="let c of Lookups.Companies" [value]="c.ID">{{ c.Name }}</option>
            </select>
            <span class="msg" *ngIf="FieldIssue('CompanyID') as m">{{ m }}</span>
          </div>
          <div class="fld" [class.bad]="HasFieldIssue('CustomerOrganizationID')">
            <label>Customer organization</label>
            <select [(ngModel)]="Draft.CustomerOrganizationID" (ngModelChange)="Touch()">
              <option [ngValue]="null">—</option>
              <option *ngFor="let o of Lookups.Organizations" [value]="o.ID">{{ o.Name }}</option>
            </select>
            <span class="msg" *ngIf="FieldIssue('CustomerOrganizationID') as m">{{ m }}</span>
          </div>
          <div class="fld">
            <label>Customer person</label>
            <select [(ngModel)]="Draft.CustomerPersonID" (ngModelChange)="Touch()">
              <option [ngValue]="null">—</option>
              <option *ngFor="let p of Lookups.People" [value]="p.ID">{{ p.Name }}</option>
            </select>
          </div>
          <div class="fld">
            <label>Status</label>
            <select [(ngModel)]="Draft.Status" (ngModelChange)="Touch()">
              <option *ngFor="let s of ContractStatuses" [value]="s">{{ s }}</option>
            </select>
          </div>
          <div class="fld">
            <label>Effective date</label>
            <input type="date" [(ngModel)]="Draft.EffectiveDate" (ngModelChange)="Touch()" />
          </div>
          <div class="fld">
            <label>Executed date</label>
            <input type="date" [(ngModel)]="Draft.ExecutedDate" (ngModelChange)="Touch()" />
          </div>
          <div class="fld">
            <label>Owner</label>
            <select [(ngModel)]="Draft.OwnerUserID" (ngModelChange)="Touch()">
              <option [ngValue]="null">—</option>
              <option *ngFor="let u of Lookups.Users" [value]="u.ID">{{ u.Name }}</option>
            </select>
          </div>
          <div class="fld">
            <label>External reference</label>
            <input type="text" [(ngModel)]="Draft.ExternalReferenceID" (ngModelChange)="Touch()" />
          </div>
          <div class="fld">
            <label>Auto-renew</label>
            <select [(ngModel)]="Draft.AutoRenew" (ngModelChange)="Touch()">
              <option [ngValue]="false">No</option>
              <option [ngValue]="true">Yes</option>
            </select>
          </div>
          <div class="fld" style="grid-column: 1 / -1;">
            <label>Description</label>
            <textarea rows="2" [(ngModel)]="Draft.Description" (ngModelChange)="Touch()"></textarea>
          </div>
        </div>
      </div>

      <!-- ── Terms ───────────────────────────────────────────────────────────────────────────── -->
      <div class="pane" *ngIf="ActiveTab() === 'terms'">
        <div class="pane-head">
          <h3>Terms</h3>
          <button mjButton (click)="AddTerm()"><i class="fa-solid fa-plus"></i> Add term</button>
        </div>
        <p class="pane-note">
          A term carries the dates, the money and the cadence. The contract header records who agreed;
          the term records what was agreed to.
        </p>
        <div class="empty" *ngIf="!Draft.Terms.length">No terms yet. Add one to get started.</div>
        <div class="rows">
          <div class="row" *ngFor="let term of Draft.Terms; let i = index">
            <div class="row-head">
              <span class="row-title">
                Term {{ term.TermNumber || i + 1 }}
                <span class="muted">· {{ term.Status }}</span>
              </span>
              <button mjButton variant="icon" (click)="RemoveTerm(term)"><i class="fa-solid fa-trash"></i></button>
            </div>
            <div class="grid">
              <div class="fld"><label>Start</label><input type="date" [(ngModel)]="term.StartDate" (ngModelChange)="Touch()" /></div>
              <div class="fld"><label>End</label><input type="date" [(ngModel)]="term.EndDate" (ngModelChange)="Touch()" /></div>
              <div class="fld">
                <label>Status</label>
                <select [(ngModel)]="term.Status" (ngModelChange)="Touch()">
                  <option *ngFor="let s of TermStatuses" [value]="s">{{ s }}</option>
                </select>
              </div>
              <div class="fld">
                <label>Billing frequency</label>
                <select [(ngModel)]="term.BillingFrequency" (ngModelChange)="Touch()">
                  <option *ngFor="let f of BillingFrequencies" [value]="f">{{ f }}</option>
                </select>
              </div>
              <div class="fld"><label>Committed amount</label><input type="number" [(ngModel)]="term.CommittedAmount" (ngModelChange)="Touch()" /></div>
              <div class="fld"><label>Escalation % (fraction)</label><input type="number" step="0.0001" [(ngModel)]="term.EscalationPercent" (ngModelChange)="Touch()" /></div>
              <div class="fld"><label>Ceiling % (fraction)</label><input type="number" step="0.0001" [(ngModel)]="term.MaxEscalationPercent" (ngModelChange)="Touch()" /></div>
              <div class="fld"><label>Renewal notice (days)</label><input type="number" [(ngModel)]="term.RenewalNoticeDays" (ngModelChange)="Touch()" /></div>
              <div class="fld">
                <label>Payment terms</label>
                <select [(ngModel)]="term.PaymentTermsTypeID" (ngModelChange)="Touch()">
                  <option [ngValue]="null">—</option>
                  <option *ngFor="let p of Lookups.PaymentTerms" [value]="p.ID">{{ p.Name }}</option>
                </select>
              </div>
              <div class="fld">
                <label>Currency</label>
                <select [(ngModel)]="term.CurrencyID" (ngModelChange)="Touch()">
                  <option [ngValue]="null">—</option>
                  <option *ngFor="let c of Lookups.Currencies" [value]="c.ID">{{ c.Name }}</option>
                </select>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── Coverage / Billing / Commitments — all scoped to ONE term ────────────────────────── -->
      <div class="pane" *ngIf="IsTermScoped(ActiveTab())">
        <div class="term-pick" *ngIf="Draft.Terms.length > 1">
          <label>Term</label>
          <select [(ngModel)]="SelectedTermIndex" (ngModelChange)="Touch()">
            <option *ngFor="let t of Draft.Terms; let i = index" [ngValue]="i">
              Term {{ t.TermNumber || i + 1 }} ({{ t.StartDate }} → {{ t.EndDate }})
            </option>
          </select>
        </div>

        <ng-container *ngIf="CurrentTerm as term">
          <!-- Coverage -->
          <ng-container *ngIf="ActiveTab() === 'coverage'">
            <div class="pane-head">
              <h3>Coverage</h3>
              <button mjButton (click)="AddLine(term)"><i class="fa-solid fa-plus"></i> Add line</button>
            </div>
            <p class="pane-note">
              What this term entitles the customer to. A contract discount <strong>overrides</strong>
              order-level discounting rather than stacking, so the value here is the operative one.
            </p>
            <div class="empty" *ngIf="!term.Lines.length">No coverage on this term yet.</div>
            <div class="rows">
              <div class="row" *ngFor="let line of term.Lines; let i = index">
                <div class="row-head">
                  <span class="row-title">Line {{ i + 1 }} <span class="muted">· {{ line.LineType }}</span></span>
                  <button mjButton variant="icon" (click)="RemoveLine(term, line)"><i class="fa-solid fa-trash"></i></button>
                </div>
                <div class="grid">
                  <div class="fld">
                    <label>Product</label>
                    <select [(ngModel)]="line.ProductID" (ngModelChange)="Touch()">
                      <option value="">Choose…</option>
                      <option *ngFor="let p of Lookups.Products" [value]="p.ID">{{ p.Name }}</option>
                    </select>
                  </div>
                  <div class="fld">
                    <label>Line type</label>
                    <select [(ngModel)]="line.LineType" (ngModelChange)="Touch()">
                      <option *ngFor="let t of LineTypes" [value]="t">{{ t }}</option>
                    </select>
                  </div>
                  <div class="fld" *ngIf="line.LineType === 'Subscription'">
                    <label>Subscription type</label>
                    <select [(ngModel)]="line.SubscriptionTypeID" (ngModelChange)="Touch()">
                      <option [ngValue]="null">Choose…</option>
                      <option *ngFor="let s of Lookups.SubscriptionTypes" [value]="s.ID">{{ s.Name }}</option>
                    </select>
                  </div>
                  <div class="fld"><label>Quantity</label><input type="number" [(ngModel)]="line.Quantity" (ngModelChange)="Touch()" /></div>
                  <div class="fld"><label>Contracted unit price</label><input type="number" step="0.01" [(ngModel)]="line.ContractedUnitPrice" (ngModelChange)="Touch()" /></div>
                  <div class="fld"><label>Discount (fraction)</label><input type="number" step="0.0001" [(ngModel)]="line.DiscountPct" (ngModelChange)="Touch()" /></div>
                </div>
              </div>
            </div>
          </ng-container>

          <!-- Billing schedules -->
          <ng-container *ngIf="ActiveTab() === 'billing'">
            <div class="pane-head">
              <h3>Billing schedules</h3>
              <button mjButton (click)="AddSchedule(term)"><i class="fa-solid fa-plus"></i> Add schedule</button>
            </div>
            <p class="pane-note">
              A term may carry more than one: a quarterly subscription cadence <em>and</em> a milestone
              schedule for an attached statement of work.
            </p>
            <div class="empty" *ngIf="!term.Schedules.length">No schedule yet — activation will create one from the term's cadence.</div>
            <div class="rows">
              <div class="row" *ngFor="let sched of term.Schedules">
                <div class="row-head">
                  <span class="row-title">{{ sched.ScheduleType }} <span class="muted" *ngIf="sched.Frequency">· {{ sched.Frequency }}</span></span>
                  <button mjButton variant="icon" (click)="RemoveSchedule(term, sched)"><i class="fa-solid fa-trash"></i></button>
                </div>
                <div class="grid">
                  <div class="fld">
                    <label>Type</label>
                    <select [(ngModel)]="sched.ScheduleType" (ngModelChange)="Touch()">
                      <option *ngFor="let t of ScheduleTypes" [value]="t">{{ t }}</option>
                    </select>
                  </div>
                  <div class="fld">
                    <label>Frequency</label>
                    <select [(ngModel)]="sched.Frequency" (ngModelChange)="Touch()">
                      <option [ngValue]="null">—</option>
                      <option *ngFor="let f of BillingFrequencies" [value]="f">{{ f }}</option>
                    </select>
                  </div>
                  <div class="fld"><label>Anchor date</label><input type="date" [(ngModel)]="sched.AnchorDate" (ngModelChange)="Touch()" /></div>
                </div>
              </div>
            </div>
          </ng-container>

          <!-- Commitments -->
          <ng-container *ngIf="ActiveTab() === 'commitments'">
            <div class="pane-head">
              <h3>Commitments</h3>
              <button mjButton (click)="AddCommitment(term)"><i class="fa-solid fa-plus"></i> Add commitment</button>
            </div>
            <p class="pane-note">
              What the customer promised to spend, and what they have spent against it. Over-consumption
              is a real state, not an error — the shortfall is what the billing engine computes.
            </p>
            <div class="empty" *ngIf="!term.Commitments.length">No commitments on this term.</div>
            <div class="rows">
              <div class="row" *ngFor="let commit of term.Commitments">
                <div class="row-head">
                  <span class="row-title">{{ commit.CommitmentType }} <span class="muted">· {{ commit.Status }}</span></span>
                  <button mjButton variant="icon" (click)="RemoveCommitment(term, commit)"><i class="fa-solid fa-trash"></i></button>
                </div>
                <div class="grid">
                  <div class="fld">
                    <label>Type</label>
                    <select [(ngModel)]="commit.CommitmentType" (ngModelChange)="Touch()">
                      <option *ngFor="let t of CommitmentTypes" [value]="t">{{ t }}</option>
                    </select>
                  </div>
                  <div class="fld"><label>Committed</label><input type="number" step="0.01" [(ngModel)]="commit.CommittedAmount" (ngModelChange)="Touch()" /></div>
                  <div class="fld"><label>Consumed</label><input type="number" step="0.01" [(ngModel)]="commit.ConsumedAmount" (ngModelChange)="Touch()" /></div>
                  <div class="fld">
                    <label>True-up policy</label>
                    <select [(ngModel)]="commit.TrueUpPolicy" (ngModelChange)="Touch()">
                      <option *ngFor="let p of TrueUpPolicies" [value]="p">{{ p }}</option>
                    </select>
                  </div>
                  <div class="fld"><label>Period start</label><input type="date" [(ngModel)]="commit.PeriodStart" (ngModelChange)="Touch()" /></div>
                  <div class="fld"><label>Period end</label><input type="date" [(ngModel)]="commit.PeriodEnd" (ngModelChange)="Touch()" /></div>
                </div>
              </div>
            </div>
          </ng-container>
        </ng-container>
      </div>

      <!-- ── The after-the-fact panes. Reachable only on a saved contract; the shell fills them. ── -->
      <div class="pane" *ngIf="IsRecordPane(ActiveTab())">
        <div class="pane-head"><h3>{{ PaneTitle(ActiveTab()) }}</h3></div>
        <ng-content select="[recordPanes]"></ng-content>
      </div>
    </div>
  `,
})
export class MJCContractWorkspaceComponent {
    private readonly cdr = inject(ChangeDetectorRef);

    /** The contract being viewed or composed. A draft with no `ID` is one being created. */
    @Input() Draft: ContractDraft = new ContractDraft();
    @Input() Lookups: WorkspaceLookups = {
        Types: [], Companies: [], Organizations: [], People: [], Users: [],
        Products: [], SubscriptionTypes: [], PaymentTerms: [], Currencies: [],
    };

    /** Raised after a successful save, carrying what the SERVER wrote. */
    @Output() Saved = new EventEmitter<ContractDraftPayload>();

    // Signals rather than plain fields: under zoneless change detection a plain field set after
    // render trips NG0100, and these all change in response to async work.
    public readonly Saving = signal(false);
    public readonly ActiveTab = signal<ContractTabKey>('contract');
    public Message = '';
    public SelectedTermIndex = 0;

    public readonly LineTypes = LINE_TYPES;
    public readonly BillingFrequencies = BILLING_FREQUENCIES;
    public readonly ScheduleTypes = SCHEDULE_TYPES;
    public readonly CommitmentTypes = COMMITMENT_TYPES;
    public readonly TrueUpPolicies = TRUE_UP_POLICIES;
    public readonly ContractStatuses = CONTRACT_STATUSES;
    public readonly TermStatuses = TERM_STATUSES;

    public get Tabs(): ContractTabDef[] {
        return BuildContractTabs(this.Draft);
    }

    public get TabConfigs(): TabConfig[] {
        return ToTabConfigs(this.Tabs);
    }

    public get CanSaveNow(): boolean {
        return CanSave(this.Draft);
    }

    /** Errors only. A warning is worth seeing but must never read as "you cannot save". */
    public get BlockingIssues(): ContractDraftIssue[] {
        return this.Draft.Validate().Issues.filter((i) => i.Severity === 'error');
    }

    public get CurrentTerm(): ContractDraftTerm | null {
        return this.Draft.Terms[this.SelectedTermIndex] ?? this.Draft.Terms[0] ?? null;
    }

    public IsTermScoped(tab: ContractTabKey): boolean {
        return tab === 'coverage' || tab === 'billing' || tab === 'commitments';
    }

    public IsRecordPane(tab: ContractTabKey): boolean {
        return tab === 'amendments' || tab === 'documents' || tab === 'history';
    }

    public PaneTitle(tab: ContractTabKey): string {
        return this.Tabs.find((t) => t.Key === tab)?.Label ?? '';
    }

    /**
     * Narrowing entry point for MJ's tab component, whose `(TabChange)` is a plain string.
     *
     * Checked against the real strip rather than cast: a cast would compile and then quietly set
     * the active tab to a key that matches no pane, leaving the workspace blank. An unknown key is
     * not ours, and the current tab stays put. The component already refuses to emit for a disabled
     * tab, so this is the second of two guards.
     */
    public SelectTab(key: string): void {
        const match = this.Tabs.find((t) => t.Key === key);
        if (!match || match.State === 'not-yet') return;
        this.ActiveTab.set(match.Key);
        this.cdr.detectChanges();
    }

    /**
     * Re-evaluate after any edit.
     *
     * Removing the last term greys three tabs, and if the user was on one of them the pane and the
     * strip would disagree. `ResolveActiveTab` moves them somewhere reachable — preferring wherever
     * the work actually is.
     */
    public Touch(): void {
        const resolved = ResolveActiveTab(this.Tabs, this.ActiveTab());
        if (resolved !== this.ActiveTab()) this.ActiveTab.set(resolved);
        if (this.SelectedTermIndex >= this.Draft.Terms.length) this.SelectedTermIndex = 0;
        this.Message = '';
        this.cdr.detectChanges();
    }

    // ── Composition ─────────────────────────────────────────────────────────────────────────────

    public AddTerm(): void {
        const term = this.Draft.AddTerm();
        // A term with no dates fails validation immediately and reads as broken rather than new, so
        // seed a sensible year. The user overwrites it; nobody has to fix a red badge they did not
        // cause.
        const today = new Date();
        const start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
        const end = new Date(start);
        end.setUTCFullYear(end.getUTCFullYear() + 1);
        end.setUTCDate(end.getUTCDate() - 1);
        term.StartDate = start.toISOString().slice(0, 10);
        term.EndDate = end.toISOString().slice(0, 10);
        this.SelectedTermIndex = this.Draft.Terms.length - 1;
        this.Touch();
    }

    public RemoveTerm(term: ContractDraftTerm): void {
        this.Draft.RemoveTerm(term);
        this.Touch();
    }

    public AddLine(term: ContractDraftTerm): void {
        this.Draft.AddLine(term);
        this.Touch();
    }

    public RemoveLine(term: ContractDraftTerm, line: ContractDraftLine): void {
        this.Draft.RemoveLine(term, line);
        this.Touch();
    }

    public AddSchedule(term: ContractDraftTerm): void {
        const schedule = this.Draft.AddSchedule(term);
        schedule.Frequency = term.BillingFrequency;
        this.Touch();
    }

    public RemoveSchedule(term: ContractDraftTerm, schedule: ContractDraftSchedule): void {
        this.Draft.RemoveSchedule(term, schedule);
        this.Touch();
    }

    public AddCommitment(term: ContractDraftTerm): void {
        const commitment = this.Draft.AddCommitment(term);
        commitment.PeriodStart = term.StartDate;
        commitment.PeriodEnd = term.EndDate;
        this.Touch();
    }

    public RemoveCommitment(term: ContractDraftTerm, commitment: ContractDraftCommitment): void {
        this.Draft.RemoveCommitment(term, commitment);
        this.Touch();
    }

    // ── Field-level markers ─────────────────────────────────────────────────────────────────────

    public FieldIssue(field: string): string | null {
        return this.BlockingIssues.find((i) => i.Field === field && i.TermIndex === undefined)?.Message ?? null;
    }

    public HasFieldIssue(field: string): boolean {
        return !!this.FieldIssue(field);
    }

    /** Where an issue lives, for the list above the tabs. */
    public WhereLabel(issue: ContractDraftIssue): string {
        const pane = this.Tabs.find((t) => t.Key === (issue.Section as ContractTabKey))?.Label ?? issue.Section;
        if (issue.TermIndex === undefined) return pane;
        const termNumber = this.Draft.Terms[issue.TermIndex]?.TermNumber ?? issue.TermIndex + 1;
        if (issue.LineIndex === undefined) return `${pane}, term ${termNumber}`;
        return `${pane}, term ${termNumber}, line ${issue.LineIndex + 1}`;
    }

    // ── Save ────────────────────────────────────────────────────────────────────────────────────

    /**
     * ONE call writes the whole agreement.
     *
     * The operation drives the same entity tree a server-side caller would, in one transaction, so a
     * failure anywhere leaves nothing behind — not a numbered contract with no term, which is what
     * the previous save-then-save-then-save sequence produced.
     */
    public async Save(): Promise<void> {
        if (!this.CanSaveNow || this.Saving()) return;
        this.Saving.set(true);
        this.Message = '';
        this.cdr.detectChanges();

        try {
            const op = new ContractsSaveContractOperation();
            const result = await op.Execute({ Contract: this.Draft.ToInput() });
            const output = result?.Output;

            if (!output?.Success || !output.Contract) {
                // The server's reason, verbatim. Paraphrasing it here would produce a second
                // vocabulary for the same refusal.
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'The contract could not be saved.';
                return;
            }

            // Rebuild from what the server WROTE, so the surface shows the derived values — the
            // allocated number, each term's number, the defaulted pricing date — rather than the
            // client's guesses at them.
            this.Draft = ContractDraft.FromPayload(output.Contract);
            this.Message = 'Saved.';
            this.Saved.emit(output.Contract);
        } catch (e) {
            this.Message = e instanceof Error ? e.message : String(e);
        } finally {
            this.Saving.set(false);
            this.Touch();
        }
    }
}
