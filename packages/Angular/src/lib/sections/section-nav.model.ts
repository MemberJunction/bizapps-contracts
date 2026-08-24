/**
 * @fileoverview The information architecture, as data.
 *
 * Three sections organised by JOB, each a top tab in the Contracts Application
 * (`metadata/applications/.contracts-application.json`) and each owning a LEFT rail over its own
 * sub-pages. MJ's rule: top nav ACROSS sections, left nav WITHIN one.
 *
 * Declaring the rails here rather than inside each component keeps the whole IA readable in one file,
 * puts badge counts in one place, and makes the nav testable without instantiating Angular.
 *
 * WHY THREE AND NOT V1'S THREE. v1's were Contracts / Billing / Setup, and Billing was a peer because
 * "what failed to bill and why" is a different job done by different people. The rebuild deleted
 * billing, so Templates takes the slot — registering the next Master Agreement version and curating
 * its clause list is rare, finance-adjacent legal work, and it has to be findable because the
 * provision list is a PREREQUISITE: nobody can record a modification until it exists.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import type { MJLeftNavSection } from '@memberjunction/ng-ui-components';

/** A sub-page within a section. `Id` is what the rail emits and what the section stores as state. */
export interface MJCSubPage {
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

/**
 * Counts the rails surface as badges, supplied by the section from live data.
 *
 * All three are questions about WORK, not totals: how many contracts need a decision this quarter,
 * how many are missing paper they should have, how many deviations exist. A badge that counted "all
 * contracts" would be a number nobody acts on.
 */
export interface MJCNavBadges {
    /** Contracts whose renewal-notice deadline falls inside the default window. */
    RenewalsDue?: number;
    /** Contracts whose type expects an executed document and none is linked. */
    AwaitingDocuments?: number;
    /** Contracts carrying at least one recorded modification. */
    Modified?: number;
}

/* ────────────────────────────────────────────────────────────────────────────
 * The three rails
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * Contracts — the agreements themselves.
 *
 * Renewals and Awaiting documents are grouped under "Work" because both are worklists: a filtered
 * view of the same list with something to DO about each row. They are rail items rather than sections
 * because they answer questions about contracts, and both are derived-column filters over the same
 * base view — which is exactly why `IsAwaitingDocument` is derived rather than a stored worklist flag.
 */
export const CONTRACTS_SUB_PAGES: MJCSubPage[] = [
    { Id: 'dashboard', Label: 'Dashboard', Icon: 'fa-solid fa-gauge-high', Description: 'What needs attention' },
    { Id: 'list', Label: 'All contracts', Icon: 'fa-solid fa-table-list' },
    { Id: 'renewals', Label: 'Renewals & expiry', Icon: 'fa-solid fa-hourglass-half', Group: 'Work' },
    { Id: 'awaiting', Label: 'Awaiting documents', Icon: 'fa-solid fa-file-circle-question', Group: 'Work' },
    { Id: 'modifications', Label: 'Modifications', Icon: 'fa-solid fa-pen-ruler', Group: 'Work', Description: 'Every deviation, across contracts' },
];

/**
 * Templates — the standard terms, and the clauses that make them up.
 *
 * The rail says "All templates". It used to say "Agreement versions", on the reasoning that a row
 * here is one DATED version of the Master Agreement, never edited in place (signed contracts
 * reference it), and that the word "template" invites editing. Marcelo overruled that on
 * 2026-08-19: the section is already called Templates, so a child item naming a different noun
 * makes the reader work out that the two are the same thing. Parallel with "All provisions"
 * below, and with "All contracts" in the Contracts rail — "All <the thing>" is this app's word
 * for the unfiltered list. The don't-edit-in-place rule is enforced by the schema and stated on
 * the page, which is where it belongs rather than in a nav label.
 */
export const TEMPLATES_SUB_PAGES: MJCSubPage[] = [
    { Id: 'versions', Label: 'All templates', Icon: 'fa-solid fa-file-lines', Description: 'One row per published MA' },
    { Id: 'provisions', Label: 'All provisions', Icon: 'fa-solid fa-list-ol', Description: 'Every clause, across versions' },
];

/** Configuration — the small vocabularies every contract inherits. */
export const CONFIGURATION_SUB_PAGES: MJCSubPage[] = [
    { Id: 'contract-types', Label: 'Contract types', Icon: 'fa-solid fa-tags' },
    { Id: 'template-types', Label: 'Template types', Icon: 'fa-solid fa-sitemap' },
];

/* ────────────────────────────────────────────────────────────────────────────
 * Rendering
 * ──────────────────────────────────────────────────────────────────────────── */

/** Which badge, if any, belongs on a given sub-page. */
function badgeFor(pageId: string, badges: MJCNavBadges): number | undefined {
    switch (pageId) {
        case 'renewals':
            return badges.RenewalsDue;
        case 'awaiting':
            return badges.AwaitingDocuments;
        case 'modifications':
            return badges.Modified;
        default:
            return undefined;
    }
}

/**
 * Turn a page list into the `MJLeftNavSection[]` `<mj-left-nav>` consumes, grouping by `Group`.
 *
 * A zero badge is OMITTED rather than rendered as "0": a badge means "there is something here", and a
 * grey zero trains people to ignore the badge that matters. Same rule as orders.
 */
export function BuildLeftNavSections(pages: MJCSubPage[], badges: MJCNavBadges = {}): MJLeftNavSection[] {
    const sections: MJLeftNavSection[] = [];
    // Insertion order matters: ungrouped items lead, then each group in the order it first appears,
    // which is the order the author wrote them in.
    const byGroup = new Map<string, MJCSubPage[]>();
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
