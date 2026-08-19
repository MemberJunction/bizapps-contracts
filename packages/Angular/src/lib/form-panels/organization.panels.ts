/**
 * @fileoverview The customer view (item 11) — delivered ON COMMON'S FORMS, not as a new screen.
 *
 * "Every agreement and document for this customer" is a real need with an obvious home: the Organization
 * record somebody is already looking at. Building a separate org-scoped roster page would mean a second
 * place to look up a customer, and the two would drift.
 *
 * Contracts owns this panel because contracts owns the FK that creates the relationship — the same reason
 * it ships the `.form-chrome.json` inclusion rows. Orders does exactly this with `person-orders.panel.ts`.
 *
 * The grid selects the contract base view, so `State`, `ContractType` and the dates read as names and
 * values rather than ids (D-23) — on someone else's form, where a column of UUIDs would be indefensible.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Component, ViewEncapsulation } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { BaseEntity, RunViewParams } from '@memberjunction/core';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:organization-agreements',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_FOREIGN_ENTITIES.Organization,
        slot: 'after-related',
        sortKey: 90,
        contributionKey: 'agreements',
        relatedEntity: MJC_ENTITIES.Contract,
        relatedJoinField: 'CustomerOrganizationID',
    },
})
@Component({
    selector: 'mjc-organization-agreements-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <div class="mjc-card">
            <h3 class="mjc-card__title">Agreements</h3>
            <p class="mjc-page__intro">
                Every contract with this organisation, live ones first. <strong>New</strong> opens a
                contract already linked to this customer.
            </p>
            <mj-explorer-entity-data-grid
                [Params]="Params"
                [NewRecordValues]="NewValues"
                [ShowToolbar]="true"
                [NavigateOnDoubleClick]="true" />
        </div>
    `,
})
export class MJCOrganizationAgreementsPanel extends BaseFormPanel<BaseEntity> {
    /**
     * `Get('ID')` rather than a typed member, and that is correct HERE specifically: the host record is
     * Common's Organization, whose generated class lives in another app's package. Typing this panel to
     * it would make contracts depend on `@mj-biz-apps/common-entities` for one primary key — a real
     * dependency for a string. The conventions rule (D-26) is about not substituting `.Get()` for a
     * typed member that EXISTS in reach; this one does not.
     */
    public get Params(): RunViewParams | null {
        const id = this.Record?.Get?.('ID');
        if (!id) return null;
        return {
            EntityName: MJC_ENTITIES.Contract,
            ExtraFilter: `CustomerOrganizationID = '${String(id)}'`,
            // Live agreements first, then most-recently-effective. A customer's CURRENT position is
            // the question; history is context underneath it.
            OrderBy: `CASE WHEN State IN ('Active','Executed') THEN 0 ELSE 1 END, EffectiveDate DESC`,
        };
    }

    /**
     * Pre-links a new contract to this organisation.
     *
     * Without it, "New" from a customer's form opens an empty contract and the user retypes the customer
     * they were just looking at — and picks the wrong one often enough to matter.
     */
    public get NewValues(): Record<string, unknown> {
        const id = this.Record?.Get?.('ID');
        return id ? { CustomerOrganizationID: String(id) } : {};
    }
}
