/**
 * @fileoverview Custom form panel for `ContractType`'s "Default Contract Terms" section (#149).
 *
 * WHY THIS PANEL REPLACES THE GENERATED `defaultContractTerms` SECTION:
 * `ContractType.DefaultAutoRenew` is a nullable `BIT` whose three states each have distinct meaning
 * when seeding a new contract (`ContractEntity.SeedRenewalDefaultsFromType()`):
 *
 *   · `null`  — "No default (leave contract unchanged)" — the contract's `AutoRenew` keeps its
 *               own starting value.
 *   · `true`  — "Yes — auto-renews by default" — seeds `Contract.AutoRenew = true`.
 *   · `false` — "No — does not auto-renew by default" — seeds `Contract.AutoRenew = false`.
 *
 * CodeGen emits `<mj-form-field FieldName="DefaultAutoRenew" Type="checkbox">`, which binds a
 * two-state checkbox: once a user clicks it, `DefaultAutoRenew` can only alternate between `true`
 * and `false` and can never be returned to `null` ("No default") through the UI. Worse, a fresh
 * `null` renders as unchecked — visually indistinguishable from an explicit `false` default.
 *
 * This panel replaces `defaultContractTerms` (`replacesSectionKey: 'defaultContractTerms'`),
 * renders `DefaultAutoRenew` as an explicit three-state `<select>`, and keeps the three numeric
 * default fields (`DefaultRenewalNoticeDays`, `DefaultCancellationWindowDays`,
 * `DefaultAnnualIncreasePercent`) on standard `<mj-form-field>` controls.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Component, ViewEncapsulation } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { ContractTypeEntity } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';
import {
    DEFAULT_AUTO_RENEW_OPTIONS,
    FormatDefaultAutoRenew,
    ParseDefaultAutoRenewOption,
    ToDefaultAutoRenewOption,
    type DefaultAutoRenewChoice,
    type DefaultAutoRenewOption,
} from './contract-type-defaults';

export {
    DEFAULT_AUTO_RENEW_OPTIONS,
    FormatDefaultAutoRenew,
    ParseDefaultAutoRenewOption,
    ToDefaultAutoRenewOption,
    type DefaultAutoRenewChoice,
    type DefaultAutoRenewOption,
};

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:contract-type-defaults',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.ContractType,
        slot: 'after-fields',
        sortKey: 80,
        contributionKey: 'defaultContractTerms',
        replacesSectionKey: 'defaultContractTerms',
    },
})
@Component({
    selector: 'mjc-contract-type-defaults-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    styles: [`
        .mjc-ct-defaults-grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: var(--mj-space-3) var(--mj-space-5);
            padding: var(--mj-space-2) var(--mj-space-4) var(--mj-space-4);
        }
        @media (max-width: 800px) {
            .mjc-ct-defaults-grid { grid-template-columns: 1fr; }
        }
        .mjc-ct-select {
            width: 100%;
            min-height: 36px;
            padding: 6px 10px;
            border: 1px solid var(--mj-border-default);
            border-radius: var(--mj-radius-sm, 6px);
            background: var(--mj-bg-surface, var(--mj-bg-page));
            color: var(--mj-text-primary);
            font: inherit;
        }
        .mjc-ct-hint {
            margin-top: 4px;
            font-size: var(--mj-text-xs, 0.78rem);
            color: var(--mj-text-muted);
        }
    `],
    template: `
        <mj-collapsible-panel
            SectionKey="defaultContractTerms"
            SectionName="Default Contract Terms"
            Icon="fa fa-sliders-h"
            [Form]="FormComponent"
            [FormContext]="FormContext">
            <div class="mjc-ct-defaults-grid">
                <div class="mj-forms-field">
                    <label class="mj-forms-field-label" for="mjc-default-auto-renew">Default Auto Renew</label>
                    <div class="mj-forms-field-control">
                        @if (EditMode) {
                            <select
                                id="mjc-default-auto-renew"
                                class="mjc-ct-select"
                                [ngModel]="AutoRenewOption"
                                (ngModelChange)="OnAutoRenewChange($event)"
                                aria-label="Default Auto Renew">
                                @for (opt of Options; track opt.value) {
                                    <option [ngValue]="opt.value">{{ opt.label }}</option>
                                }
                            </select>
                            <div class="mjc-ct-hint">
                                Seeds Contract.AutoRenew on a new contract of this type. Choose "No default" to leave new contracts unchanged.
                            </div>
                        } @else {
                            <span class="mj-forms-field-value">{{ AutoRenewLabel }}</span>
                        }
                    </div>
                </div>

                <mj-form-field
                    [Record]="Record"
                    [ShowLabel]="true"
                    FieldName="DefaultRenewalNoticeDays"
                    Type="number"
                    [EditMode]="EditMode"
                    [FormContext]="FormContext">
                </mj-form-field>

                <mj-form-field
                    [Record]="Record"
                    [ShowLabel]="true"
                    FieldName="DefaultCancellationWindowDays"
                    Type="number"
                    [EditMode]="EditMode"
                    [FormContext]="FormContext">
                </mj-form-field>

                <mj-form-field
                    [Record]="Record"
                    [ShowLabel]="true"
                    FieldName="DefaultAnnualIncreasePercent"
                    Type="number"
                    [EditMode]="EditMode"
                    [FormContext]="FormContext">
                </mj-form-field>
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractTypeDefaultsPanel extends BaseFormPanel<ContractTypeEntity> {
    public readonly Options = DEFAULT_AUTO_RENEW_OPTIONS;

    public get AutoRenewOption(): DefaultAutoRenewChoice {
        return ToDefaultAutoRenewOption(this.Record?.DefaultAutoRenew);
    }

    public get AutoRenewLabel(): string {
        return FormatDefaultAutoRenew(this.Record?.DefaultAutoRenew);
    }

    public OnAutoRenewChange(choice: string | null | undefined): void {
        if (!this.Record) return;
        this.Record.DefaultAutoRenew = ParseDefaultAutoRenewOption(choice);
    }
}
