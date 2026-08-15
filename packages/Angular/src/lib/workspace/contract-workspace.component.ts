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
import { BaseFormsModule, MJFormPresenterService } from '@memberjunction/ng-base-forms';
import {
    ContractDraft,
    ContractDraftTerm,
    ContractDraftLine,
    ContractDraftSchedule,
    ContractDraftCommitment,
    ContractsSaveContractOperation,
    ContractsActivateTermOperation,
    ContractsRenewTermOperation,
    ContractsTerminateContractOperation,
    ContractsAmendTermOperation,
    type ContractDraftIssue,
    type ContractDraftPayload,
    type AmendTermOutput,
    type RenewTermOutput,
    type TerminateContractOutput,
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
/**
 * A contract type, plus the escalation ceiling every term of that type is judged against.
 *
 * Carried on the lookup because the ceiling moved onto the TYPE on 2026-08-05, so the ONLY way the
 * workspace can flag an over-cap escalation as it is typed is to know the selected type's ceiling.
 */
export interface WorkspaceTypeLookup extends WorkspaceLookup {
    DefaultMaxEscalationPercent?: number | null;
}

export interface WorkspaceLookups {
    Types: WorkspaceTypeLookup[];
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
    imports: [CommonModule, FormsModule, MJButtonDirective, MJTabNavComponent, BaseFormsModule],
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
    <!-- NO HEADER OR ACTION BAR HERE. Both belong to mj-workspace-card, which frames this
         component: the identity band goes in its [workspaceHeader] slot and the primary verb in its
         standardised footer, so every workspace in the family carries the same chrome in the same
         place rather than each hand-rolling its own.
         (No backticks in a template comment — they close the template literal.) -->
    <div class="ws">

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

      <!-- TERMINATION IS PREVIEWED FIRST, because which billing events are cancelled and which are
           retained is a money question: periods already covered are still owed, and events already
           Generated or Invoiced are never touched. The split comes back from the operation. -->
      <div class="issues" *ngIf="Op.Termination" style="border-left-color: var(--mj-color-warning, #c80);">
        <h4>Terminating this contract</h4>
        <ul>
          <li>Billing events that would be CANCELLED: {{ Op.Termination.BillingEventsCancelled ?? 0 }}</li>
          <li>Billing events RETAINED — periods already covered are still owed: {{ Op.Termination.BillingEventsRetained ?? 0 }}</li>
          <li>Terms that would move to Terminated: {{ Op.Termination.TermsTerminated ?? 0 }}</li>
          <li *ngIf="Op.Termination.Message">{{ Op.Termination.Message }}</li>
        </ul>
        <div class="fld" style="margin-top:10px; max-width:420px;">
          <label>Why is this being terminated?</label>
          <input type="text" [(ngModel)]="TerminationReason" placeholder="Recorded on the audit trail" />
        </div>
        <div style="display:flex; gap:8px; margin-top:10px;">
          <button mjButton [disabled]="Op.Busy || !TerminationReason.trim()" (click)="CommitTermination()">Terminate this contract</button>
          <button mjButton variant="flat" (click)="CancelPreview()">Cancel</button>
        </div>
      </div>

      <mj-tab-nav [Tabs]="TabConfigs" [ActiveKey]="ActiveTab()" (TabChange)="SelectTab($event)"></mj-tab-nav>

      <!-- ── Contract ────────────────────────────────────────────────────────────────────────── -->
      <div class="pane" *ngIf="ActiveTab() === 'contract'">
        <div class="pane-head"><h3>The agreement</h3></div>
        <div class="grid">
          <div class="fld" [class.bad]="HasFieldIssue('ContractTypeID')">
            <label>Contract type</label>
            <select [(ngModel)]="Draft.ContractTypeID" (ngModelChange)="TypeChanged()">
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
            <label>Renewal notice (days)</label>
            <input type="number" [(ngModel)]="Draft.RenewalNoticeDays" (ngModelChange)="Touch()" />
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
        <div class="empty" *ngIf="!Draft.Terms.length">No terms yet. Add one to get started.</div>
        <div class="rows">
          <div class="row" *ngFor="let term of Draft.Terms; let i = index">
            <div class="row-head">
              <span class="row-title">
                Term {{ term.TermNumber || i + 1 }}
                <span class="muted">· {{ term.Status }}</span>
              </span>
              <span style="display:flex; gap:6px; align-items:center;">
                <!-- THE LIFECYCLE, where the terms are. Every one drives the app's OWN typed
                     operation client: the escalation ceiling, the date arithmetic and the
                     cancelled/retained split all come back FROM the operation, so the UI holds no
                     copy of the rules that could agree today and drift tomorrow. -->
                <button mjButton variant="flat" *ngIf="CanActivate(term)" [disabled]="Op.Busy" (click)="Activate(term)">
                  <i class="fa-solid fa-play"></i> Activate
                </button>
                <button mjButton variant="flat" *ngIf="CanRenew(term)" [disabled]="Op.Busy" (click)="PreviewRenewal(term)">
                  <i class="fa-solid fa-rotate"></i> Renew…
                </button>
                <button mjButton variant="flat" *ngIf="CanAmend(term)" [disabled]="Op.Busy" (click)="StartAmendment(term)">
                  <i class="fa-solid fa-file-pen"></i> Add product…
                </button>
                <button mjButton variant="flat" *ngIf="term.ID" [title]="'Open this term in its own form'" (click)="OpenForm(TERM_ENTITY, term.ID, 'Term ' + (term.TermNumber || ''))">
                  <i class="fa-solid fa-up-right-from-square"></i> Form
                </button>
                <button mjButton variant="icon" (click)="RemoveTerm(term)"><i class="fa-solid fa-trash"></i></button>
              </span>
            </div>

            <!-- A PREVIEW IS THE REAL COMPUTATION WITH THE WRITE SUPPRESSED, so the numbers a person
                 approves are the numbers that get written. -->
            <div class="issues" *ngIf="Op.Renewal && Op.TermID === term.ID" style="border-left-color: var(--mj-brand-primary); margin-bottom: 12px;">
              <h4>Renewing term {{ term.TermNumber }}</h4>
              <ul>
                <li>New term: {{ Op.Renewal.StartDate }} → {{ Op.Renewal.EndDate }}</li>
                <li *ngIf="Op.Renewal.AppliedEscalationPercent != null">
                  Escalation applied: {{ (Op.Renewal.AppliedEscalationPercent * 100).toFixed(2) }}%
                  <ng-container *ngIf="Op.Renewal.EscalationWasClamped"> (capped by the term's ceiling)</ng-container>
                </li>
                <li *ngIf="Op.Renewal.Message">{{ Op.Renewal.Message }}</li>
              </ul>
              <div style="display:flex; gap:8px; margin-top:10px;">
                <button mjButton [disabled]="Op.Busy" (click)="CommitRenewal(term)">Renew this term</button>
                <button mjButton variant="flat" (click)="CancelPreview()">Cancel</button>
              </div>
            </div>

            <!-- CO-TERMING (plan §5.4). The new product's coverage ends with the TERM, so it lands
                 on the SAME renewal date as everything else the customer already has — which is the
                 thing standalone subscriptions structurally cannot do. -->
            <div class="issues" *ngIf="Amend.TermID === term.ID" style="border-left-color: var(--mj-brand-primary); margin-bottom: 12px;">
              <h4>Add a product to term {{ term.TermNumber }}, mid-term</h4>
              <div class="grid">
                <div class="fld">
                  <label>Product</label>
                  <select [(ngModel)]="Amend.ProductID">
                    <option value="">Choose…</option>
                    <option *ngFor="let p of Lookups.Products" [value]="p.ID">{{ p.Name }}</option>
                  </select>
                </div>
                <div class="fld">
                  <label>Line type</label>
                  <select [(ngModel)]="Amend.LineType">
                    <option *ngFor="let t of LineTypes" [value]="t">{{ t }}</option>
                  </select>
                </div>
                <div class="fld" *ngIf="Amend.LineType === 'Subscription'">
                  <label>Subscription type</label>
                  <select [(ngModel)]="Amend.SubscriptionTypeID">
                    <option [ngValue]="null">Choose…</option>
                    <option *ngFor="let st of Lookups.SubscriptionTypes" [value]="st.ID">{{ st.Name }}</option>
                  </select>
                </div>
                <div class="fld"><label>Quantity</label><input type="number" [(ngModel)]="Amend.Quantity" /></div>
                <div class="fld"><label>Contracted unit price</label><input type="number" step="0.01" [(ngModel)]="Amend.ContractedUnitPrice" /></div>
                <div class="fld"><label>Effective date</label><input type="date" [(ngModel)]="Amend.EffectiveDate" /></div>
                <div class="fld" style="grid-column: 1 / -1;">
                  <label>What changed, and why</label>
                  <input type="text" [(ngModel)]="Amend.Description" placeholder="Recorded on the amendment and the audit trail" />
                </div>
              </div>
              <ul *ngIf="Amend.Preview">
                <li>Coverage would run {{ Amend.Preview.StubStart }} → {{ Amend.Preview.StubEnd }} — co-termed with the rest of the agreement</li>
                <li>{{ Amend.Preview.StubDays }} days, prorated on the next billing event</li>
              </ul>
              <div style="display:flex; gap:8px; margin-top:10px;">
                <button mjButton variant="flat" [disabled]="Op.Busy || !CanPreviewAmendment" (click)="PreviewAmendment(term)">Preview</button>
                <button mjButton [disabled]="Op.Busy || !Amend.Preview || !Amend.Description.trim()" (click)="CommitAmendment(term)">Add it</button>
                <button mjButton variant="flat" (click)="CancelAmendment()">Cancel</button>
              </div>
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
            <div class="empty" *ngIf="!term.Lines.length">No coverage on this term yet.</div>
            <div class="rows">
              <div class="row" *ngFor="let line of term.Lines; let i = index">
                <div class="row-head">
                  <span class="row-title">Line {{ i + 1 }} <span class="muted">· {{ line.LineType }}</span></span>
                  <span style="display:flex; gap:6px;">
                    <button mjButton variant="flat" *ngIf="line.ID" [title]="'Open this line in its own form'" (click)="OpenForm(LINE_ENTITY, line.ID, 'Coverage line ' + (i + 1))">
                      <i class="fa-solid fa-up-right-from-square"></i> Form
                    </button>
                    <button mjButton variant="icon" (click)="RemoveLine(term, line)"><i class="fa-solid fa-trash"></i></button>
                  </span>
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
            <div class="empty" *ngIf="!term.Schedules.length">No schedule yet — activation will create one from the term's cadence.</div>
            <div class="rows">
              <div class="row" *ngFor="let sched of term.Schedules">
                <div class="row-head">
                  <span class="row-title">{{ sched.ScheduleType }} <span class="muted" *ngIf="sched.Frequency">· {{ sched.Frequency }}</span></span>
                  <span style="display:flex; gap:6px;">
                    <button mjButton variant="flat" *ngIf="sched.ID" [title]="'Open this schedule in its own form'" (click)="OpenForm(SCHEDULE_ENTITY, sched.ID, 'Billing schedule')">
                      <i class="fa-solid fa-up-right-from-square"></i> Form
                    </button>
                    <button mjButton variant="icon" (click)="RemoveSchedule(term, sched)"><i class="fa-solid fa-trash"></i></button>
                  </span>
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
            <div class="empty" *ngIf="!term.Commitments.length">No commitments on this term.</div>
            <div class="rows">
              <div class="row" *ngFor="let commit of term.Commitments">
                <div class="row-head">
                  <span class="row-title">{{ commit.CommitmentType }} <span class="muted">· {{ commit.Status }}</span></span>
                  <span style="display:flex; gap:6px;">
                    <button mjButton variant="flat" *ngIf="commit.ID" [title]="'Open this commitment in its own form'" (click)="OpenForm(COMMITMENT_ENTITY, commit.ID, 'Commitment')">
                      <i class="fa-solid fa-up-right-from-square"></i> Form
                    </button>
                    <button mjButton variant="icon" (click)="RemoveCommitment(term, commit)"><i class="fa-solid fa-trash"></i></button>
                  </span>
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
    /**
     * MJ's 4-layer form architecture.
     *
     * A SAVED row opens ITS OWN registered form as a slide-in — the priority-2 custom form for that
     * entity — rather than another hand-built field set here. One definition of what a term or a
     * line looks like, reused everywhere, with the generated validation attached to it; and a change
     * to that definition reaches every surface at once instead of the ones somebody remembered.
     *
     * The inline fields in each pane are NOT a competing editor. They exist because a row being
     * COMPOSED has no record yet — a form needs something to open — so the draft is how a contract
     * is assembled and the form is how a saved record is edited. The strip says which is which: the
     * form button appears only once the row exists.
     */
    private readonly forms = inject(MJFormPresenterService);

    /** The contract being viewed or composed. A draft with no `ID` is one being created. */
    @Input() Draft: ContractDraft = new ContractDraft();
    @Input() Lookups: WorkspaceLookups = {
        Types: [], Companies: [], Organizations: [], People: [], Users: [],
        Products: [], SubscriptionTypes: [], PaymentTerms: [], Currencies: [],
    };

    /** Raised after a successful save, carrying what the SERVER wrote. */
    @Output() Saved = new EventEmitter<ContractDraftPayload>();

    /**
     * Raised when a lifecycle operation changed the contract on the server and the draft in hand is
     * therefore stale. The shell owns loading, so it re-reads rather than this component patching
     * fields locally — which is how a UI and its record quietly diverge.
     */
    @Output() ReloadRequested = new EventEmitter<string>();

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
     * not ours, and the current tab stays put.
     *
     * THIS IS THE ONLY GUARD, not the second of two. It used to say the component refuses to emit
     * for a disabled tab; that was never true — MJ's `mj-tab-nav` has no disabled state, renders
     * every tab as a clickable button, and emits for all of them (see `ToTabConfigs`). So the
     * `State === 'not-yet'` rejection below is the whole of the protection: a user CAN click a
     * blocked tab, and this is what makes the click do nothing.
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
    /**
     * The contract type changed, so the escalation ceiling the draft validates against changed too.
     *
     * Without this, switching from a type with no ceiling to one that caps at 3% would leave a 5%
     * escalation showing green until the server refused it — the client hint judging the number
     * against the ceiling of a type the contract no longer has.
     */
    public TypeChanged(): void {
        const type = this.Lookups.Types.find((t) => t.ID === this.Draft.ContractTypeID);
        this.Draft.TypeCeilingPercent = type?.DefaultMaxEscalationPercent ?? null;
        this.Touch();
    }

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

    // ── MJ's 4-layer forms ──────────────────────────────────────────────────────────────────────

    public readonly TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';
    public readonly LINE_ENTITY = 'MJ_BizApps_Contracts: Contract Lines';
    public readonly SCHEDULE_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Schedules';
    public readonly COMMITMENT_ENTITY = 'MJ_BizApps_Contracts: Contract Commitments';

    /**
     * Open a saved row in ITS OWN registered form, as a slide-in.
     *
     * `AfterSaved()` resolves with the record when something was written and null when the person
     * cancelled — so a cancel must NOT reload (that would make the cancel look like it did
     * something) and a save MUST, or the pane shows stale values beside a form that just changed
     * them.
     */
    public async OpenForm(entityName: string, recordID: string | null, title: string): Promise<void> {
        if (!recordID) return;
        const ref = this.forms.Open({
            EntityName: entityName,
            RecordId: recordID,
            Presentation: 'slide-in',
            EditMode: true,
            Title: title,
        });
        const saved = await ref.AfterSaved();
        if (!saved) return;
        this.Message = `${title} saved.`;
        this.ReloadRequested.emit(this.Draft.ID ?? '');
    }

    // ── Lifecycle operations ────────────────────────────────────────────────────────────────────
    //
    // These drive the app's OWN typed operation clients, generated from metadata into the
    // browser-safe Entities package. The UI decides only WHEN to offer them; what they DO — the
    // escalation ceiling, the date arithmetic, which billing events are cancelled versus retained —
    // is the operation's, and asking it twice (preview, then commit) is how the person sees the real
    // numbers before agreeing to them.

    public Op: {
        Busy: boolean;
        TermID: string | null;
        Renewal: RenewTermOutput | null;
        Termination: TerminateContractOutput | null;
    } = { Busy: false, TermID: null, Renewal: null, Termination: null };

    /** Only a term that has not started can be activated. */
    public CanActivate(term: ContractDraftTerm): boolean {
        return !!term.ID && (term.Status === 'Pending' || term.Status === 'PendingSignature');
    }

    /** Only a running term can be renewed — and only once, which the operation itself enforces. */
    public CanRenew(term: ContractDraftTerm): boolean {
        return !!term.ID && term.Status === 'Active';
    }

    public TerminationReason = '';

    /** A contract that has already ended cannot end again. */
    public get CanTerminate(): boolean {
        return this.Draft.IsSaved && this.Draft.Status !== 'Terminated' && this.Draft.Status !== 'Superseded';
    }

    /**
     * The real computation, write suppressed — so the person sees exactly which billing events go
     * and which stay before agreeing to it.
     */
    public async PreviewTermination(): Promise<void> {
        if (!this.Draft.ID) return;
        await this.runOp(async () => {
            const result = await new ContractsTerminateContractOperation().Execute({
                ContractID: this.Draft.ID!,
                Reason: this.TerminationReason.trim() || 'Preview',
                PreviewOnly: true,
            });
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'Could not preview the termination.';
                return;
            }
            this.Op.Termination = output;
        });
    }

    public async CommitTermination(): Promise<void> {
        if (!this.Draft.ID || !this.TerminationReason.trim()) return;
        await this.runOp(async () => {
            const result = await new ContractsTerminateContractOperation().Execute({
                ContractID: this.Draft.ID!,
                Reason: this.TerminationReason.trim(),
            });
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'Termination failed.';
                return;
            }
            this.Message = output.Message ?? 'Contract terminated.';
            this.TerminationReason = '';
            this.CancelPreview();
            this.ReloadRequested.emit(this.Draft.ID!);
        });
    }

    /** A running term can take a mid-term change. */
    public CanAmend(term: ContractDraftTerm): boolean {
        return !!term.ID && term.Status === 'Active';
    }

    public Amend: {
        TermID: string | null;
        ProductID: string;
        LineType: string;
        SubscriptionTypeID: string | null;
        Quantity: number;
        ContractedUnitPrice: number | null;
        EffectiveDate: string;
        Description: string;
        Preview: AmendTermOutput | null;
    } = {
        TermID: null, ProductID: '', LineType: 'Subscription', SubscriptionTypeID: null,
        Quantity: 1, ContractedUnitPrice: null, EffectiveDate: '', Description: '', Preview: null,
    };

    public get CanPreviewAmendment(): boolean {
        if (!this.Amend.ProductID) return false;
        if (this.Amend.LineType === 'Subscription' && !this.Amend.SubscriptionTypeID) return false;
        return true;
    }

    public StartAmendment(term: ContractDraftTerm): void {
        this.Amend = {
            TermID: term.ID,
            ProductID: '',
            LineType: 'Subscription',
            SubscriptionTypeID: null,
            Quantity: 1,
            ContractedUnitPrice: null,
            // Today by default: a mid-term change is normally happening now, and the stub runs from
            // here to the term's end.
            EffectiveDate: new Date().toISOString().slice(0, 10),
            Description: '',
            Preview: null,
        };
        this.cdr.detectChanges();
    }

    public CancelAmendment(): void {
        this.Amend.TermID = null;
        this.Amend.Preview = null;
        this.cdr.detectChanges();
    }

    /** The real computation, write suppressed — so the co-term window is seen before it is agreed. */
    public async PreviewAmendment(term: ContractDraftTerm): Promise<void> {
        if (!term.ID) return;
        await this.runOp(async () => {
            const result = await new ContractsAmendTermOperation().Execute(this.amendInput(term.ID!, true));
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'Could not preview the amendment.';
                return;
            }
            this.Amend.Preview = output;
        });
    }

    public async CommitAmendment(term: ContractDraftTerm): Promise<void> {
        if (!term.ID || !this.Amend.Description.trim()) return;
        await this.runOp(async () => {
            const result = await new ContractsAmendTermOperation().Execute(this.amendInput(term.ID!, false));
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'The amendment failed.';
                return;
            }
            this.Message = output.Message ?? 'Amendment applied.';
            this.CancelAmendment();
            this.ReloadRequested.emit(this.Draft.ID ?? '');
        });
    }

    private amendInput(termID: string, previewOnly: boolean) {
        return {
            ContractTermID: termID,
            AmendmentType: 'AddProduct',
            Description: this.Amend.Description.trim() || 'Product added mid-term',
            EffectiveDate: this.Amend.EffectiveDate || undefined,
            ProductID: this.Amend.ProductID,
            LineType: this.Amend.LineType,
            Quantity: this.Amend.Quantity,
            ContractedUnitPrice: this.Amend.ContractedUnitPrice,
            SubscriptionTypeID: this.Amend.SubscriptionTypeID,
            PreviewOnly: previewOnly,
        };
    }

    public CancelPreview(): void {
        this.Op.Renewal = null;
        this.Op.Termination = null;
        this.Op.TermID = null;
        this.cdr.detectChanges();
    }

    /**
     * Activation is not a status flip: the operation also creates the billing schedule and the
     * events its cadence implies. A term marked Active with no schedule bills nothing, and nobody
     * notices until a quarter closes light.
     */
    public async Activate(term: ContractDraftTerm): Promise<void> {
        if (!term.ID) return;
        await this.runOp(async () => {
            const result = await new ContractsActivateTermOperation().Execute({ ContractTermID: term.ID! });
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'Activation failed.';
                return;
            }
            this.Message = output.Message ?? `Term activated — ${output.ScheduledDates?.length ?? 0} billing events scheduled.`;
            await this.reload(term);
        });
    }

    /** The real computation, write suppressed. */
    public async PreviewRenewal(term: ContractDraftTerm): Promise<void> {
        if (!term.ID) return;
        await this.runOp(async () => {
            const result = await new ContractsRenewTermOperation().Execute({ ContractTermID: term.ID!, PreviewOnly: true });
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'Could not preview the renewal.';
                return;
            }
            this.Op.Renewal = output;
            this.Op.TermID = term.ID!;
        });
    }

    public async CommitRenewal(term: ContractDraftTerm): Promise<void> {
        if (!term.ID) return;
        await this.runOp(async () => {
            const result = await new ContractsRenewTermOperation().Execute({ ContractTermID: term.ID! });
            const output = result?.Output;
            if (!output?.Success) {
                this.Message = output?.Message ?? result?.ErrorMessage ?? 'Renewal failed.';
                return;
            }
            this.Message = output.Message ?? 'Renewed.';
            this.CancelPreview();
            await this.reload(term);
        });
    }

    private async runOp(body: () => Promise<void>): Promise<void> {
        this.Op.Busy = true;
        this.Message = '';
        this.cdr.detectChanges();
        try {
            await body();
        } catch (e) {
            this.Message = e instanceof Error ? e.message : String(e);
        } finally {
            this.Op.Busy = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * An operation changed the contract on the server — status moves, a new term, a new schedule —
     * so the draft in hand is stale. Ask the shell to reload rather than patching fields locally,
     * which is how a UI and its record quietly diverge.
     */
    private async reload(_term: ContractDraftTerm): Promise<void> {
        this.ReloadRequested.emit(this.Draft.ID ?? '');
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
