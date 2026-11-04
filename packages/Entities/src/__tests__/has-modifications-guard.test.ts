/**
 * The `HasModifications` guard, and specifically the SEAM the two tiers meet at.
 *
 * The rule (ERD §4.4) is monotonic: rows imply the flag, and the flag is never auto-cleared. It is
 * enforced in two places for one reason — a browser can only prove rows exist when it is holding them:
 *
 *   Count > 0                       → rows exist.               Shared class refuses. Certainty.
 *   Count === 0, never saved        → no rows can exist on disk. Shared class allows. Certainty.
 *   Count === 0, saved, LOADED      → rows really are absent.   Shared class allows. Certainty.
 *   Count === 0, saved, NOT loaded  → UNKNOWN.                  Shared class stays silent BY DESIGN;
 *                                                               the SERVER settles it with an EXISTS.
 *
 * That last row is where a real defect lived. The shared class's comment claimed the server settled
 * the unknown case, and no server check existed — so the ordinary path (load a contract, its
 * modifications not loaded, untick the box, save) succeeded and left the flag false with rows in the
 * table. Found on review of PR #9. This file pins the DECISION TABLE, which is the part a future
 * refactor can silently get wrong; the server's `EXISTS` needs a database and is item 13's
 * `contracts-graph-save` bundle.
 *
 * Written against the four states rather than against the implementation, so it stays a valid oracle
 * if the guard is rewritten.
 */
import { describe, expect, it } from 'vitest';
import {
    DocumentNumberingEngine,
    type EntityInfo,
    EntityLifecyclePolicyEngine,
} from '@memberjunction/core';
import { ValidationResult } from '@memberjunction/global';
import {
    CONTRACT_DOCUMENT_NUMBER_POLICY,
    CONTRACT_ENTITY_NAME,
    CONTRACT_LIFECYCLE_POLICY,
    RegisterContractEntityPolicies,
} from '../ContractEntity';
import {
    CONTRACT_TEMPLATE_ENTITY_NAME,
    CONTRACT_TEMPLATE_LIFECYCLE_POLICY,
    RegisterContractTemplateLifecyclePolicy,
} from '../ContractTemplateEntity';

/** The browser-side verdict, extracted so the decision table is testable without a provider. */
type Verdict = 'refuse' | 'allow' | 'defer-to-server';

/**
 * What the shared class does, stated as a function of what it can actually observe.
 *
 * This mirrors `ContractEntity.Validate()` + `modificationsKnownToExist()`. It is a restatement, and
 * that is deliberate: instantiating a `BaseEntity` needs a provider, which would make this a tier-2
 * test and cost a database for a rule that is pure logic. The risk of a restatement drifting is real,
 * so the table below is written from the SPEC (ERD §4.4) rather than read off the code.
 */
function sharedClassVerdict(args: { flag: boolean; count: number; isSaved: boolean; isLoaded: boolean }): Verdict {
    const { flag, count, isSaved, isLoaded } = args;
    if (flag !== false) return 'allow';
    if (count > 0) return 'refuse';
    // Empty. Whether that is knowledge or ignorance depends on whether rows COULD be on disk.
    const knownEmpty = !isSaved || isLoaded;
    return knownEmpty ? 'allow' : 'defer-to-server';
}

describe('HasModifications — the browser refuses only what it can prove', () => {
    it('refuses a false flag when staged rows exist', () => {
        // Composing in the browser: Create() adds rows but does NOT mark the collection loaded, so
        // IsLoaded is false here and must not matter. Count is the proof.
        expect(sharedClassVerdict({ flag: false, count: 2, isSaved: false, isLoaded: false })).toBe('refuse');
    });

    it('refuses a false flag when loaded rows exist', () => {
        expect(sharedClassVerdict({ flag: false, count: 3, isSaved: true, isLoaded: true })).toBe('refuse');
    });

    it('allows a false flag on a new contract with no rows — there cannot be any on disk', () => {
        expect(sharedClassVerdict({ flag: false, count: 0, isSaved: false, isLoaded: false })).toBe('allow');
    });

    it('allows a false flag when the collection was loaded and is genuinely empty', () => {
        expect(sharedClassVerdict({ flag: false, count: 0, isSaved: true, isLoaded: true })).toBe('allow');
    });

    it('DEFERS on a saved contract whose collection was never loaded — this is the defect seam', () => {
        // The ordinary form load. The browser cannot tell "no modifications" from "not fetched", so
        // staying silent is right — but only because the server settles it. Before the server check
        // existed, this case silently SAVED, leaving the flag false with rows in the table.
        expect(sharedClassVerdict({ flag: false, count: 0, isSaved: true, isLoaded: false })).toBe('defer-to-server');
    });

    it('never blocks a TRUE flag, whatever the collection looks like', () => {
        // The rule is one-directional: rows imply the flag, the flag does not imply rows. A person may
        // mark a contract modified before recording anything — that is the flag's whole purpose, to say
        // "go read the PDF" before the work is done.
        for (const count of [0, 1]) {
            for (const isSaved of [true, false]) {
                for (const isLoaded of [true, false]) {
                    expect(sharedClassVerdict({ flag: true, count, isSaved, isLoaded })).toBe('allow');
                }
            }
        }
    });

    it('leaves exactly one state to the server, and it is the ambiguous one', () => {
        const deferred: string[] = [];
        for (const count of [0, 1]) {
            for (const isSaved of [true, false]) {
                for (const isLoaded of [true, false]) {
                    if (sharedClassVerdict({ flag: false, count, isSaved, isLoaded }) === 'defer-to-server') {
                        deferred.push(`count=${count} saved=${isSaved} loaded=${isLoaded}`);
                    }
                }
            }
        }
        // If this ever grows, the server has more to settle than it knows about — which is precisely
        // how the original defect happened.
        expect(deferred).toEqual(['count=0 saved=true loaded=false']);
    });
});

/**
 * The save-populated-field rule, which the create path could not work without.
 *
 * `ContractNumber` is NOT NULL in metadata and minted by the server on first save, so the generated
 * check fires on every new record. Left in place it refused the save with "Contract Number cannot be
 * null" — a field the user cannot fill and the server was about to. Found by attempting a create in a
 * real browser; nothing in the type-check, the build or the other tests could see it.
 *
 * The asymmetry is the rule: suppressed BEFORE the first save, enforced after. So the test covers both
 * sides — a rule that only suppressed would hide a genuinely missing number forever.
 */
describe('ContractNumber is suppressed before the first save and enforced after', () => {
    /** Mirrors ContractEntity.dropSavePopulatedFieldErrors, written from the rule rather than the code. */
    const isSuppressed = (source: string, isSaved: boolean) => !isSaved && source === 'ContractNumber';

    it('suppresses the NOT NULL error on an unsaved record — the create path depends on it', () => {
        expect(isSuppressed('ContractNumber', false)).toBe(true);
    });

    it('ENFORCES it on a saved record, where an empty number is a real defect', () => {
        expect(isSuppressed('ContractNumber', true)).toBe(false);
    });

    it('suppresses nothing else, on either side of the first save', () => {
        // The other three NOT NULL foreign keys are the user's to supply, and refusing them is correct
        // — that refusal is what a create form is FOR.
        for (const field of ['ContractTypeID', 'CompanyID', 'CustomerOrganizationID', 'AutoRenew', 'HasModifications']) {
            expect(isSuppressed(field, false), `${field} must NOT be suppressed`).toBe(false);
            expect(isSuppressed(field, true), `${field} must NOT be suppressed`).toBe(false);
        }
    });

    it('registers CONTRACT_DOCUMENT_NUMBER_POLICY on DocumentNumberingEngine for ContractNumber', () => {
        RegisterContractEntityPolicies();
        const entityInfo = { Name: CONTRACT_ENTITY_NAME, Settings: [] } as never;
        const policies = DocumentNumberingEngine.Instance.ResolvePolicies(entityInfo);
        expect(policies).toContainEqual(CONTRACT_DOCUMENT_NUMBER_POLICY);
        expect(DocumentNumberingEngine.Instance.WillAutoPopulateOnCreate(entityInfo, 'ContractNumber')).toBe(true);
        expect(DocumentNumberingEngine.Instance.WillAutoPopulateOnCreate(entityInfo, 'ContractTypeID')).toBe(false);

        const now = new Date('2026-08-21T00:00:00Z');
        expect(
            DocumentNumberingEngine.Instance.FormatPattern(
                CONTRACT_DOCUMENT_NUMBER_POLICY,
                1,
                { EntityInfo: entityInfo } as never,
                undefined,
                now,
                2026,
            ),
        ).toBe('CTR-000001');
        expect(
            DocumentNumberingEngine.Instance.FormatPattern(
                CONTRACT_DOCUMENT_NUMBER_POLICY,
                1234567,
                { EntityInfo: entityInfo } as never,
                undefined,
                now,
                2026,
            ),
        ).toBe('CTR-1234567');

        // Rejects manual CTR-#### collisions on unsaved records while allowing custom non-colliding references
        const collidingResult = new ValidationResult();
        collidingResult.Success = true;
        DocumentNumberingEngine.Instance.ValidateAutoNumberFields(
            {
                IsSaved: false,
                EntityInfo: entityInfo,
                GetFieldByName: (name: string) =>
                    name === 'ContractNumber' ? { Name: 'ContractNumber', Value: 'CTR-000042', Dirty: true } : null,
            } as never,
            collidingResult,
        );
        expect(collidingResult.Success).toBe(false);

        const customRefResult = new ValidationResult();
        customRefResult.Success = true;
        DocumentNumberingEngine.Instance.ValidateAutoNumberFields(
            {
                IsSaved: false,
                EntityInfo: entityInfo,
                GetFieldByName: (name: string) =>
                    name === 'ContractNumber' ? { Name: 'ContractNumber', Value: 'EXT-2026-99', Dirty: true } : null,
            } as never,
            customRefResult,
        );
        expect(customRefResult.Success).toBe(true);
    });

    it('registers CONTRACT_LIFECYCLE_POLICY and CONTRACT_TEMPLATE_LIFECYCLE_POLICY on EntityLifecyclePolicyEngine', () => {
        RegisterContractEntityPolicies();
        RegisterContractTemplateLifecyclePolicy();

        const contractInfo = { Name: CONTRACT_ENTITY_NAME, Settings: [] } as EntityInfo;
        expect(EntityLifecyclePolicyEngine.Instance.ResolvePolicy(contractInfo)).toEqual(CONTRACT_LIFECYCLE_POLICY);

        // Terminal states Terminated and Superseded refuse outbound transitions
        const terminatedTransition = new ValidationResult();
        terminatedTransition.Success = true;
        EntityLifecyclePolicyEngine.Instance.ValidateLifecycleOnEntity(
            {
                IsSaved: true,
                Dirty: true,
                EntityInfo: contractInfo,
                Fields: [],
                GetFieldByName: (name: string) =>
                    name === 'State'
                        ? { Name: 'State', Dirty: true, OldValue: 'Terminated', Value: 'Active' }
                        : null,
            } as never,
            undefined,
            terminatedTransition,
        );
        expect(terminatedTransition.Success).toBe(false);
        expect(terminatedTransition.Errors[0]?.Message).toContain("terminal state 'Terminated'");

        // ContractTemplate allows Draft -> Published and refuses Published -> Draft
        const templateInfo = { Name: CONTRACT_TEMPLATE_ENTITY_NAME, Settings: [] } as EntityInfo;
        expect(EntityLifecyclePolicyEngine.Instance.ResolvePolicy(templateInfo)).toEqual(
            CONTRACT_TEMPLATE_LIFECYCLE_POLICY,
        );

        const publishResult = new ValidationResult();
        publishResult.Success = true;
        EntityLifecyclePolicyEngine.Instance.ValidateLifecycleOnEntity(
            {
                IsSaved: true,
                Dirty: true,
                EntityInfo: templateInfo,
                Fields: [],
                GetFieldByName: (name: string) =>
                    name === 'Status'
                        ? { Name: 'Status', Dirty: true, OldValue: 'Draft', Value: 'Published' }
                        : null,
            } as never,
            undefined,
            publishResult,
        );
        expect(publishResult.Success).toBe(true);

        const unpublishResult = new ValidationResult();
        unpublishResult.Success = true;
        EntityLifecyclePolicyEngine.Instance.ValidateLifecycleOnEntity(
            {
                IsSaved: true,
                Dirty: true,
                EntityInfo: templateInfo,
                Fields: [],
                GetFieldByName: (name: string) =>
                    name === 'Status'
                        ? { Name: 'Status', Dirty: true, OldValue: 'Published', Value: 'Draft' }
                        : null,
            } as never,
            undefined,
            unpublishResult,
        );
        expect(unpublishResult.Success).toBe(false);
    });
});
