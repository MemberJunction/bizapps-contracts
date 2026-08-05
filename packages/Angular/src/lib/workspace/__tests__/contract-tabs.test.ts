/**
 * Tier 1 — the workspace tab state machine.
 *
 * Framework-free, so this is plain vitest with no harness: the whole point of the state machine
 * living in its own module rather than inside the component.
 *
 * The three states are the reason one surface can serve both creating and viewing, so each is
 * asserted directly, along with the transitions between them as a contract is assembled.
 */

import { describe, expect, it } from 'vitest';
import { ContractDraft } from '@mj-biz-apps/contracts-entities';
import {
    BuildContractTabs,
    CanSave,
    ResolveActiveTab,
    ToTabConfigs,
    type ContractTabKey,
} from '../contract-tabs.model';

/** A draft with the required header fields filled in, so only the tab logic is under test. */
function validHeader(): ContractDraft {
    const draft = new ContractDraft();
    draft.ContractTypeID = 'type-1';
    draft.CompanyID = 'company-1';
    draft.CustomerOrganizationID = 'org-1';
    draft.Status = 'Draft';
    return draft;
}

function tab(draft: ContractDraft, key: ContractTabKey) {
    const found = BuildContractTabs(draft).find((t) => t.Key === key);
    if (!found) throw new Error(`no tab '${key}' in the strip`);
    return found;
}

describe('BuildContractTabs — the three states', () => {
    it('greys the term-dependent panes on a contract with no term, and says why', () => {
        const draft = validHeader();

        for (const key of ['coverage', 'billing', 'commitments'] as const) {
            const t = tab(draft, key);
            expect(t.State).toBe('not-yet');
            // A disabled control with no explanation is the commonest wizard failure.
            expect(t.Reason).toContain('Add a term first');
        }
    });

    it('greys the after-the-fact panes until the contract is saved', () => {
        const draft = validHeader();

        for (const key of ['amendments', 'documents', 'history'] as const) {
            expect(tab(draft, key).State).toBe('not-yet');
            expect(tab(draft, key).Reason).toContain('once the contract is saved');
        }
    });

    it('keeps the Contract pane reachable always — it is where a contract becomes valid', () => {
        // Blocking it could leave a contract with no way to fix whatever is wrong with it.
        expect(tab(new ContractDraft(), 'contract').State).not.toBe('not-yet');
    });

    it('lights up the term-dependent panes the moment a term exists', () => {
        const draft = validHeader();
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';

        for (const key of ['coverage', 'billing', 'commitments'] as const) {
            expect(tab(draft, key).State).toBe('available');
        }
        // Still not saved, so these stay blocked — the two preconditions are independent.
        expect(tab(draft, 'history').State).toBe('not-yet');
    });

    it('lights up the after-the-fact panes once the draft carries an id', () => {
        const draft = validHeader();
        draft.ID = 'contract-1';

        for (const key of ['amendments', 'documents', 'history'] as const) {
            expect(tab(draft, key).State).toBe('available');
        }
    });
});

describe('BuildContractTabs — needs-attention', () => {
    it('marks the Contract pane when a required header field is missing', () => {
        const draft = new ContractDraft(); // nothing filled in
        expect(tab(draft, 'contract').State).toBe('needs-attention');
    });

    it('marks Terms when an active contract has none', () => {
        const draft = validHeader();
        draft.Status = 'Active';
        expect(tab(draft, 'terms').State).toBe('needs-attention');
    });

    it('marks Coverage when an active term has no lines', () => {
        const draft = validHeader();
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';
        term.Status = 'Active';

        expect(tab(draft, 'coverage').State).toBe('needs-attention');
    });

    it('counts rather than flagging when a pane is populated and valid', () => {
        const draft = validHeader();
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';
        const line = draft.AddLine(term);
        line.ProductID = 'product-1';
        line.Quantity = 1;

        const coverage = tab(draft, 'coverage');
        expect(coverage.State).toBe('available');
        expect(coverage.Count).toBe(1);
        expect(tab(draft, 'terms').Count).toBe(1);
    });
});

describe('ToTabConfigs', () => {
    it('renders an error as "!" rather than a bare dot when there is no count', () => {
        const draft = new ContractDraft();
        const contract = ToTabConfigs(BuildContractTabs(draft)).find((t) => t.key === 'contract');

        // A bare dot carries no meaning to a sighted user; "!" in the badge slot reads on sight.
        expect(contract?.badge).toBe('!');
        expect(contract?.badgeVariant).toBe('error');
    });

    it('prefers the count over "!" when a pane has both a number and a problem', () => {
        const draft = validHeader();
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';
        term.Status = 'Active'; // no lines -> coverage errors
        const line = draft.AddLine(term);
        line.ProductID = ''; // ...and the one line is incomplete

        const coverage = ToTabConfigs(BuildContractTabs(draft)).find((t) => t.key === 'coverage');
        expect(coverage?.badge).toBe(1);
        // The colour still carries the severity, so nothing is lost by showing the number.
        expect(coverage?.badgeVariant).toBe('error');
    });

    it('always ships a reason with a disabled tab', () => {
        const configs = ToTabConfigs(BuildContractTabs(new ContractDraft()));
        for (const config of configs.filter((c) => c.disabled)) {
            expect(config.disabledReason).toBeTruthy();
        }
    });

    it('leaves reachable tabs enabled', () => {
        const draft = validHeader();
        draft.ID = 'contract-1';
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';

        const configs = ToTabConfigs(BuildContractTabs(draft));
        expect(configs.every((c) => !c.disabled)).toBe(true);
    });
});

describe('ResolveActiveTab', () => {
    it('leaves a reachable tab alone', () => {
        const draft = validHeader();
        draft.ID = 'contract-1';
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';

        expect(ResolveActiveTab(BuildContractTabs(draft), 'coverage')).toBe('coverage');
    });

    it('moves off a tab that has just become unreachable', () => {
        // Removing the last term greys Coverage. Staying there would show a pane the strip says is
        // unavailable — the state and the content would disagree.
        const draft = new ContractDraft(); // no terms, nothing filled in
        expect(ResolveActiveTab(BuildContractTabs(draft), 'coverage')).not.toBe('coverage');
    });

    it('lands on the pane that needs attention rather than merely the first one', () => {
        const draft = new ContractDraft();
        // The header is incomplete, so Contract is where the work is.
        expect(ResolveActiveTab(BuildContractTabs(draft), 'history')).toBe('contract');
    });

    it('stays put when the tab is reachable and nothing needs attention', () => {
        const draft = validHeader();
        draft.ID = 'contract-1';
        // The term matters: without one, Coverage is `not-yet` and the resolver correctly moves
        // off it. An earlier version of this test omitted the term and then expected to stay on
        // Coverage — asserting a precondition it had not set up.
        const term = draft.AddTerm();
        term.StartDate = '2030-01-01';
        term.EndDate = '2030-12-31';

        expect(ResolveActiveTab(BuildContractTabs(draft), 'coverage')).toBe('coverage');
    });
});

describe('CanSave', () => {
    it('refuses a draft missing its required fields', () => {
        expect(CanSave(new ContractDraft())).toBe(false);
    });

    it('allows a complete draft', () => {
        expect(CanSave(validHeader())).toBe(true);
    });

    it('refuses when a customer is named twice', () => {
        const draft = validHeader();
        draft.CustomerPersonID = 'person-1'; // already has an organization
        expect(CanSave(draft)).toBe(false);
    });
});
