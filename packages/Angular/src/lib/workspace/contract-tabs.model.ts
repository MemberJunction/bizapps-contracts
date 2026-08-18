/**
 * @fileoverview The workspace's inner tabs, and the THREE states a tab can be in.
 *
 * TWO TABBING SYSTEMS, DOING DIFFERENT JOBS. The workspace card strip on the outside models OPEN
 * DOCUMENTS — several contracts side by side, each closable, each with its own edit buffer. These
 * tabs on the inside are PANES OF ONE CONTRACT: you cannot close Coverage or add a seventh, so
 * those affordances would be lies. Different semantics, different component.
 *
 * ── WHY THREE STATES AND NOT TWO ────────────────────────────────────────────────────────────────
 *
 * A two-state strip (available / has-an-error) cannot express the thing that makes ONE surface work
 * for both creating and viewing. Consider a contract that has not been saved yet: History is not
 * broken, and it is not ready either — it simply cannot exist until there is a record to have a
 * history. Hiding it would leave the user unable to see what is coming; showing it as available
 * would produce an empty pane and a puzzled user.
 *
 *   NEEDS ATTENTION  something required is missing        error badge `!`
 *   AVAILABLE        can be worked on now                 count badge, or nothing
 *   NOT YET          a precondition is unmet              muted, disabled, tooltip says why
 *
 * The third state is what lets the tab strip TEACH THE SEQUENCE. On a blank contract, Coverage is
 * greyed with "add a term first" and Amendments with "available once the contract is saved"; both
 * light up as the work proceeds. Nothing is hidden, so the shape of the whole job is visible from
 * the first moment — which is exactly what made merging the create and view surfaces possible.
 *
 * FRAMEWORK-FREE, like `contract-format.ts` next door: ordinary functions of their arguments, so
 * the state machine is unit-tested without instantiating Angular, and one implementation means a
 * change to how a tab reads happens once.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import type { TabConfig } from '@memberjunction/ng-ui-components';
import type { ContractDraft, ContractDraftSection } from '@mj-biz-apps/contracts-entities';

/** Every pane of a contract, in strip order. */
export type ContractTabKey =
    | 'contract'
    | 'terms'
    | 'coverage'
    | 'billing'
    | 'commitments'
    | 'amendments'
    | 'documents'
    | 'history';

export type ContractTabState = 'needs-attention' | 'available' | 'not-yet';

export interface ContractTabDef {
    Key: ContractTabKey;
    Label: string;
    State: ContractTabState;
    /** Count badge. Null where a number says nothing (the Contract pane has no count). */
    Count: number | null;
    /** Why it is not yet available. Present only in the `not-yet` state. */
    Reason?: string;
}

/** Which draft-validation section feeds which tab. Panes with no validation map to nothing. */
const SECTION_FOR_TAB: Partial<Record<ContractTabKey, ContractDraftSection>> = {
    contract: 'contract',
    terms: 'terms',
    coverage: 'coverage',
    billing: 'billing',
    commitments: 'commitments',
};

/**
 * Build the strip for a draft.
 *
 * @param draft The contract being viewed or composed. A draft with no `ID` is one being created —
 *   which is the ONLY difference between the two surfaces.
 */
export function BuildContractTabs(draft: ContractDraft): ContractTabDef[] {
    const errored = new Set(draft.SectionsWithErrors);
    const saved = draft.IsSaved;
    const hasTerm = draft.Terms.length > 0;
    // AN AMENDMENT NEEDS A RUNNING TERM, NOT MERELY A SAVED CONTRACT. This gate used to be `saved`,
    // which was wrong in the direction that is hardest to notice: too PERMISSIVE. A saved contract
    // whose terms are all Pending showed Amendments as available, and the pane then offered nothing
    // that could work — `CanAmend` requires an Active term and `Contracts.AmendTerm` refuses one that
    // is not running. An enabled control that cannot act is worse than a disabled one, because the
    // disabled one at least says why.
    const hasRunningTerm = draft.Terms.some((t) => !!t.ID && t.Status === 'Active');

    /** A tab that is reachable: red when its section has an error, plain otherwise. */
    const live = (Key: ContractTabKey, Label: string, Count: number | null): ContractTabDef => {
        const section = SECTION_FOR_TAB[Key];
        const hasError = !!section && errored.has(section);
        return { Key, Label, Count, State: hasError ? 'needs-attention' : 'available' };
    };

    /** A tab whose precondition is unmet. The reason is not optional — see the note below. */
    const blocked = (Key: ContractTabKey, Label: string, Reason: string): ContractTabDef => ({
        Key,
        Label,
        Count: null,
        State: 'not-yet',
        Reason,
    });

    return [
        // The Contract pane is always reachable. It is where the fields live that everything else
        // depends on, so blocking it could leave a contract with no way to become valid.
        live('contract', 'Contract', null),

        live('terms', 'Terms', draft.Terms.length || null),

        // Coverage hangs off a term. Without one there is nothing for a line to attach to — the
        // foreign key is NOT NULL — so this is a genuine precondition, not a style choice.
        hasTerm
            ? live('coverage', 'Coverage', draft.LineCount || null)
            : blocked('coverage', 'Coverage', 'Add a term first — coverage is what a term entitles the customer to.'),

        hasTerm
            ? live('billing', 'Billing', draft.ScheduleCount || null)
            : blocked('billing', 'Billing', 'Add a term first — a billing schedule belongs to a term.'),

        hasTerm
            ? live('commitments', 'Commitments', draft.CommitmentCount || null)
            : blocked('commitments', 'Commitments', 'Add a term first — a commitment is measured over a term.'),

        // The three below describe things that HAPPENED, so they need a record for them to have
        // happened to. On an unsaved draft they are visible-but-unreachable rather than hidden, so
        // the strip shows the whole shape of a contract from the first moment.
        //
        // These three stay greyed on a new contract, because a new contract is seeded with a term
        // (see MJCContractsSectionComponent.NewContract). Coverage, billing and commitments are
        // things a person sets WHILE creating an agreement, so gating them behind a separate step was
        // a form getting in the way of the work. What remains is not a choice: an amendment changes a
        // term that is RUNNING, a file attaches to a saved RecordID, and there is no history until
        // something has happened.
        //
        // The three preconditions are genuinely DIFFERENT and are not interchangeable — saving a
        // contract does not make a term run, which is precisely the distinction the amendment gate
        // used to lose.
        hasRunningTerm
            ? live('amendments', 'Amendments', null)
            : blocked(
                  'amendments',
                  'Amendments',
                  saved
                      ? 'Available once a term is Active — an amendment changes a term that is RUNNING. Activate a term first.'
                      : 'Available once the contract is saved and a term is Active — an amendment changes a term that is already running.',
              ),

        saved
            ? live('documents', 'Documents', null)
            : blocked('documents', 'Documents', 'Available once the contract is saved — a document attaches to a saved record.'),

        saved
            ? live('history', 'History', null)
            : blocked('history', 'History', 'Available once the contract is saved — there is no history until something has happened.'),
    ];
}

/**
 * The same strip, shaped for MJ's tab component.
 *
 * THE BADGE CARRIES MEANING, NOT DECORATION. A bare dot is a signifier with nothing attached — only
 * a screen reader would learn what it meant, so a sighted user sees a mark and has to guess. `!` in
 * the same slot the count uses reads as attention-needed on sight, and severity is carried by
 * colour rather than by a second element competing with the number.
 *
 * NO DISABLED STATE IS EMITTED — deliberately, since 2026-08-14 (MJ 6 conversion). MJ's `TabConfig`
 * is `key | label | icon | badge | badgeVariant`; it has no `disabled`/`disabledReason`, and
 * `mj-tab-nav` renders every tab as a plain clickable button. We used to set both fields anyway.
 * That was never doing anything — the component ignored them — so a `not-yet` tab has ALWAYS
 * rendered enabled and unexplained at runtime; only the type erasure hid it from us.
 *
 * The gating itself is NOT gone. `ContractTabDef.State` / `.Reason` still carry it (see
 * {@link BuildContractTabs}), and {@link ResolveActiveTab} still refuses to land on an unreachable
 * tab. What is missing is only the VISUAL affordance. Restoring it is two lines here once MJ's
 * `mj-tab-nav` gains the disabled state (commit `2acd4dc7cb`, unmerged) — tracked in
 * `plans/BACKLOG.md` B-2. Contracts is moving to custom forms + the MJ record system, so the UI
 * treatment gets revisited there rather than being rebuilt against this component.
 */
export function ToTabConfigs(tabs: ContractTabDef[]): TabConfig[] {
    return tabs.map((tab) => ({
        key: tab.Key,
        label: tab.Label,
        badge: tab.Count ?? (tab.State === 'needs-attention' ? '!' : null),
        badgeVariant: tab.State === 'needs-attention' ? ('error' as const) : ('default' as const),
    }));
}

/**
 * Where to land when the current tab is unreachable.
 *
 * Removing the last term greys out Coverage, Billing and Commitments — and if the user was ON one
 * of those, leaving it selected would show a pane the strip says is unavailable. Falling back to
 * the first tab that needs attention (or Contract) puts them where the work is.
 */
export function ResolveActiveTab(tabs: ContractTabDef[], current: ContractTabKey): ContractTabKey {
    const active = tabs.find((t) => t.Key === current);
    if (active && active.State !== 'not-yet') return current;
    return tabs.find((t) => t.State === 'needs-attention')?.Key ?? 'contract';
}

/** Whether anything anywhere blocks a save. Drives the Save button's enabled state. */
export function CanSave(draft: ContractDraft): boolean {
    return draft.Validate().IsValid;
}
