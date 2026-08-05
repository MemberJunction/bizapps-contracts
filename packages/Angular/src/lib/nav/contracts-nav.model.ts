/**
 * @fileoverview The information architecture, as data.
 *
 * THREE SECTIONS, ORGANISED BY JOB rather than by entity. MJ's rule is top nav across sections, left
 * nav within one — so each of these is a top-level entry owning a rail over its own pages.
 *
 *   Contracts — the agreement itself: find one, open one, write one, amend one.
 *   Billing   — the money the agreement produces: what is due, what is planned, what was promised.
 *   Setup     — the configuration every contract inherits.
 *
 * WHY BILLING IS ITS OWN SECTION rather than a page under Contracts. The daily question about a
 * billing worklist ("what failed, and why") has nothing to do with the daily question about a
 * contract ("what did we agree"). They are different jobs done by different people at different
 * times, and filing one under the other makes the smaller one invisible. This mirrors orders, which
 * splits Receivables out of Orders for exactly the same reason.
 *
 * DECLARING THE RAILS HERE rather than inside each component keeps the whole IA readable in one
 * file, lets a badge count be injected from one place, and makes the nav testable without
 * instantiating Angular.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import type { MJLeftNavSection } from '@memberjunction/ng-ui-components';

/** A top-level section. `Id` is what the section switcher emits and what the shell stores. */
export interface ContractsSection {
    Id: string;
    Label: string;
    Icon: string;
}

/** A page within a section. `Id` doubles as the shell's page-state key. */
export interface ContractsSubPage {
    /** Stable key. Persisted as user state, so renaming one resets people's place. */
    Id: string;
    Label: string;
    /** Font Awesome class. */
    Icon: string;
    /** Optional muted second line in the rail. */
    Description?: string;
    /** Rail group header. Items sharing a group render under one heading. */
    Group?: string;
}

/** Live counts the rails surface as badges. Supplied by the shell from real data. */
export interface ContractsNavBadges {
    /** Billing events that failed and are waiting on somebody. */
    BillingFailed?: number;
    /** Billing events due on or before today. */
    BillingDue?: number;
    /** Terms whose renewal notice window is open. */
    RenewalsDue?: number;
    /** Amendments waiting for an approval decision. */
    AmendmentsPending?: number;
}

export const CONTRACTS_SECTIONS: ContractsSection[] = [
    { Id: 'contracts', Label: 'Contracts', Icon: 'fa-solid fa-file-signature' },
    { Id: 'billing', Label: 'Billing', Icon: 'fa-solid fa-conveyor-belt' },
    { Id: 'setup', Label: 'Setup', Icon: 'fa-solid fa-sliders' },
];

/** Contracts — the agreement. */
export const CONTRACTS_SUB_PAGES: ContractsSubPage[] = [
    { Id: 'dashboard', Label: 'Dashboard', Icon: 'fa-solid fa-gauge-high', Description: 'Is anything about to lapse?' },
    { Id: 'list', Label: 'All contracts', Icon: 'fa-solid fa-table-list' },
    { Id: 'workspace', Label: 'Workspace', Icon: 'fa-solid fa-layer-group', Description: 'Open, edit and create' },
    { Id: 'renewals', Label: 'Renewals due', Icon: 'fa-solid fa-rotate', Group: 'Work' },
    { Id: 'amendments', Label: 'Amendments', Icon: 'fa-solid fa-file-pen', Group: 'Work' },
];

/**
 * Billing — the money.
 *
 * Schedules and commitments get their own pages here because both are cross-contract questions:
 * "what will bill next month" and "who is behind on what they committed to" are not answered by
 * opening one agreement at a time.
 */
export const BILLING_SUB_PAGES: ContractsSubPage[] = [
    { Id: 'worklist', Label: 'Billing worklist', Icon: 'fa-solid fa-list-check', Description: 'Due, generated and failed' },
    { Id: 'schedules', Label: 'Schedules', Icon: 'fa-solid fa-calendar-days', Description: 'What bills, and when' },
    { Id: 'commitments', Label: 'Commitments', Icon: 'fa-solid fa-hand-holding-dollar', Description: 'Consumed versus committed' },
];

/** Setup — the configuration every contract inherits. */
export const SETUP_SUB_PAGES: ContractsSubPage[] = [
    { Id: 'types', Label: 'Contract types', Icon: 'fa-solid fa-sliders', Description: 'Defaults and rules' },
];

/** The rail for a section id. Unknown ids give an empty rail rather than throwing. */
export function SubPagesFor(sectionId: string): ContractsSubPage[] {
    switch (sectionId) {
        case 'contracts':
            return CONTRACTS_SUB_PAGES;
        case 'billing':
            return BILLING_SUB_PAGES;
        case 'setup':
            return SETUP_SUB_PAGES;
        default:
            return [];
    }
}

/** The page a section opens on. */
export function DefaultPageFor(sectionId: string): string {
    return SubPagesFor(sectionId)[0]?.Id ?? '';
}

/** Which badge, if any, belongs on a page. */
function badgeFor(pageId: string, badges: ContractsNavBadges): number | undefined {
    switch (pageId) {
        case 'worklist':
            // The FAILED count, not the due count. A due event is the system working; a failed one
            // is a person's problem, and a badge means "there is something here for you".
            return badges.BillingFailed;
        case 'renewals':
            return badges.RenewalsDue;
        case 'amendments':
            return badges.AmendmentsPending;
        default:
            return undefined;
    }
}

/**
 * Turn a page list into the `MJLeftNavSection[]` `<mj-left-nav>` consumes, grouping by each page's
 * `Group` and dropping zero badges.
 *
 * A zero badge is omitted rather than rendered as "0": a badge means "there is something here", and
 * a grey zero is noise that trains people to ignore the badge that matters.
 */
export function BuildLeftNavSections(pages: ContractsSubPage[], badges: ContractsNavBadges = {}): MJLeftNavSection[] {
    const sections: MJLeftNavSection[] = [];
    // Insertion order matters: the ungrouped items lead, then each group in the order it first
    // appears, which is the order the author wrote them in.
    const byGroup = new Map<string, ContractsSubPage[]>();
    for (const page of pages) {
        const key = page.Group ?? '';
        const list = byGroup.get(key);
        if (list) list.push(page);
        else byGroup.set(key, [page]);
    }

    for (const [group, groupPages] of byGroup) {
        sections.push({
            label: group || undefined,
            items: groupPages.map((page) => {
                const badge = badgeFor(page.Id, badges);
                return {
                    id: page.Id,
                    label: page.Label,
                    icon: page.Icon,
                    description: page.Description,
                    ...(badge ? { badge } : {}),
                };
            }),
        });
    }
    return sections;
}
