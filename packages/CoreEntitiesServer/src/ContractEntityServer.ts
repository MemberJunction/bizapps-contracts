/**
 * @fileoverview Server-side `Contract` — the invariants that must hold no matter who writes the row.
 *
 * WHY HERE AND NOT IN A HELPER. `Save()` is the one path every write goes through: the UI, an Action,
 * a fixture, a workflow, an agent. A rule enforced anywhere else is a rule that holds right up until
 * somebody saves the entity directly — which is precisely how a "validated" record ends up invalid.
 *
 * WHAT THE DATABASE CANNOT DO, AND SO LIVES HERE:
 *  - **Legal status MOVES.** `CK_Contract_Status` enforces the legal SET and knows nothing about
 *    transitions, so `Terminated -> Active` and `Superseded -> Draft` both save happily today. A
 *    terminated contract coming back to life keeps its billing schedule and starts invoicing again.
 *  - **Sequence allocation.** `ContractNumber` is unique and human-facing; allocating it needs a
 *    read-modify-write against `ContractSequence` that must not interleave.
 *  - **The pricing lock.** `PricedAt` is the as-of date every price on the agreement resolves from
 *    (master plan §12). A contract saved without one has no defined pricing moment at all.
 *
 * PROVIDER DISCIPLINE: everything goes through `this.ProviderToUse` — the entity's own provider —
 * never `new Metadata()` or a global. A second provider splits the metadata and the class factory,
 * and the failure is silent.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseEntity,
    RunView,
    ValidationErrorInfo,
    ValidationResult,
    type EntitySaveOptions,
    type IMetadataProvider,
    type IRunViewProvider,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type { DatabaseProviderBase } from '@memberjunction/core';
import { mjBizAppsContractsContractEntity } from '@mj-biz-apps/contracts-entities';
import { ChildCollection } from './ChildCollection.js';
import { ContractTermEntityServer } from './ContractTermEntityServer.js';
import { ContractLineEntityServer } from './ContractLineEntityServer.js';
import { ContractBillingScheduleEntityServer } from './ContractBillingScheduleEntityServer.js';
import { ContractCommitmentEntityServer } from './ContractCommitmentEntityServer.js';

const CONTRACT_ENTITY = 'MJ_BizApps_Contracts: Contracts';
const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';
const LINE_ENTITY = 'MJ_BizApps_Contracts: Contract Lines';
const SCHEDULE_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const COMMITMENT_ENTITY = 'MJ_BizApps_Contracts: Contract Commitments';

/**
 * Which status may follow which. Absent from the map means "no move out of here" — a terminal state.
 *
 * `Superseded` is terminal on purpose: a contract that was replaced does not come back. The successor
 * is a different row, named by `SupersededByContractID`.
 */
const LEGAL_MOVES: Readonly<Record<string, readonly string[]>> = {
    Draft: ['Draft', 'PendingSignature', 'Active', 'Terminated'],
    PendingSignature: ['PendingSignature', 'Draft', 'Active', 'Terminated'],
    Active: ['Active', 'Expired', 'Terminated', 'Superseded'],
    Expired: ['Expired', 'Superseded', 'Terminated'],
    Terminated: ['Terminated'],
    Superseded: ['Superseded'],
};

@RegisterClass(BaseEntity, CONTRACT_ENTITY)
export class ContractEntityServer extends mjBizAppsContractsContractEntity {
    /* ── What a contract OWNS ────────────────────────────────────────────────────────────────────
     *
     * A contract IS its terms; the header alone is a filing reference. So the agreement is composed
     * in memory — contract, terms, each term's coverage and billing plan — and written in ONE
     * transaction, exactly as `JournalEntryEntityServer` composes a journal entry with its lines.
     *
     * This replaces what the UI used to do: save the contract, then save a term, then save each
     * line, as separate round trips. A failure partway through that sequence left a NUMBERED
     * contract (the sequence already consumed) with no term under it — a record that looks real,
     * cannot be activated, and nothing cleans up.
     *
     * `TermNumber` is NOT assigned positionally here: `ContractTermEntityServer` derives it from the
     * contract's existing terms, which is the only version that is also correct for a term added to
     * a contract that already has three.
     * ────────────────────────────────────────────────────────────────────────────────────────── */

    private readonly terms = new ChildCollection<ContractTermEntityServer>({
        EntityName: TERM_ENTITY,
        ForeignKeyField: 'ContractID',
        OrderBy: 'TermNumber ASC',
        ParentID: () => this.ID,
        LinkToParent: (term, contractID) => {
            term.ContractID = contractID;
        },
        CascadeDelete: async (term, user) => {
            await term.DeleteChildren(user);
        },
    });

    /** The chain of periods this agreement runs for. Empty until loaded — see {@link TermsAreLoaded}. */
    public get Terms(): readonly ContractTermEntityServer[] {
        return this.terms.Items;
    }

    /**
     * Whether {@link Terms} is the whole truth rather than simply un-asked-for.
     *
     * Every rule below that reasons about terms is gated on this. A contract in a roster of twenty
     * does not load its terms; reading that as "has no terms" would refuse edits to perfectly valid
     * live contracts. See `ChildCollection.IsAuthoritative`.
     */
    public get TermsAreLoaded(): boolean {
        return this.terms.IsAuthoritative;
    }

    public AddTerm(term: ContractTermEntityServer): void {
        this.terms.Add(term);
    }

    /** Detach a term. On the next save it is deleted, its coverage and schedules going first. */
    public RemoveTerm(termOrIndex: ContractTermEntityServer | number): void {
        this.terms.Remove(termOrIndex);
    }

    /**
     * A new term on this contract, ready to be filled in.
     *
     * Its own collections are marked authoritative immediately: a term that has never been saved has
     * nothing in the database that could be missing, so its coverage rules should be ENFORCED on
     * what is in memory rather than skipped as un-hydrated. Without this an Active term could be
     * composed with no lines and save.
     */
    public async CreateTerm(user?: UserInfo): Promise<ContractTermEntityServer> {
        const term = await this.terms.Create(
            this.ProviderToUse as unknown as IMetadataProvider,
            user ?? this.ContextCurrentUser,
        );
        term.MarkChildrenAuthoritative();
        return term;
    }

    /**
     * Declare a NEW contract's term collection complete. Valid only before the first save.
     */
    public MarkTermsAuthoritative(): void {
        this.terms.MarkAuthoritative();
    }

    /**
     * Load the terms only — one query. The default depth for anything that shows a contract's shape
     * without opening it.
     */
    public async LoadTerms(user?: UserInfo): Promise<readonly ContractTermEntityServer[]> {
        return this.terms.Load(this.ProviderToUse as unknown as IRunViewProvider, this.ID, user ?? this.ContextCurrentUser);
    }

    /**
     * Load the WHOLE agreement — terms, and every term's coverage, schedules and commitments.
     *
     * FOUR QUERIES, whatever the term count: one for the terms, then one per child type filtered on
     * `ContractTermID IN (...)` and distributed across the terms in memory. Calling
     * `term.LoadChildren()` in a loop instead would be 1 + 3n, which is the RunView-in-a-loop
     * anti-pattern; `JournalEntryEntityServer.hydrateLineDimensions` is the precedent for doing it
     * this way.
     *
     * This is the deliberate opposite of `Load()`, which stays shallow. A roster of twenty contracts
     * must not drag several hundred coverage rows nobody will look at into memory — that is the
     * whole reason the tree loads lazily.
     */
    public async LoadFull(user?: UserInfo): Promise<void> {
        const contextUser = user ?? this.ContextCurrentUser;
        const terms = await this.LoadTerms(contextUser);
        if (terms.length === 0) return;

        const termIDs = terms.map((t) => t.ID).filter(Boolean);
        const inList = termIDs.map((id) => `'${id}'`).join(',');
        const provider = this.ProviderToUse as unknown as IRunViewProvider;
        const rv = new RunView(provider);

        // RunViews (plural) — three independent reads in ONE round trip rather than three.
        const [lineResult, scheduleResult, commitmentResult] = await rv.RunViews(
            [
                { EntityName: LINE_ENTITY, ExtraFilter: `ContractTermID IN (${inList})`, OrderBy: 'DisplayOrder ASC', ResultType: 'entity_object' },
                { EntityName: SCHEDULE_ENTITY, ExtraFilter: `ContractTermID IN (${inList})`, OrderBy: '__mj_CreatedAt ASC', ResultType: 'entity_object' },
                { EntityName: COMMITMENT_ENTITY, ExtraFilter: `ContractTermID IN (${inList})`, OrderBy: '__mj_CreatedAt ASC', ResultType: 'entity_object' },
            ],
            contextUser,
        );

        // Loud on failure, for the reason `ChildCollection.Load` is: a hydrate that quietly returns
        // nothing presents itself as a contract with no coverage, and a renewal or a billing run
        // built from that is wrong in a way nothing downstream can catch.
        for (const [label, result] of [
            ['coverage', lineResult],
            ['billing schedules', scheduleResult],
            ['commitments', commitmentResult],
        ] as const) {
            if (!result?.Success) {
                throw new Error(`Could not load ${label} for contract ${this.ContractNumber ?? this.ID}: ${result?.ErrorMessage ?? 'unknown error'}`);
            }
        }

        const lines = ContractEntityServer.groupByTerm(lineResult.Results as ContractLineEntityServer[]);
        const schedules = ContractEntityServer.groupByTerm(scheduleResult.Results as ContractBillingScheduleEntityServer[]);
        const commitments = ContractEntityServer.groupByTerm(commitmentResult.Results as ContractCommitmentEntityServer[]);

        for (const term of terms) {
            const key = term.ID.toLowerCase();
            term.SetLoadedChildren(lines.get(key) ?? [], schedules.get(key) ?? [], commitments.get(key) ?? []);
        }
    }

    /** Distribute a flat child read across its parent terms. Keys are lower-cased — UUID casing varies by path. */
    private static groupByTerm<TChild extends { ContractTermID: string }>(children: TChild[]): Map<string, TChild[]> {
        const byTerm = new Map<string, TChild[]>();
        for (const child of children ?? []) {
            const key = child.ContractTermID.toLowerCase();
            const bucket = byTerm.get(key);
            if (bucket) bucket.push(child);
            else byTerm.set(key, [child]);
        }
        return byTerm;
    }

    /**
     * VALIDATION, NOT A SAVE GUARD. These rules used to live in `Save()` as an early `return false`
     * plus a `console.error`, which refused correctly and told the user nothing: the UI showed
     * "Save failed: unknown error" because no error had been recorded anywhere it could read.
     *
     * `Save()` calls `Validate()` and puts its errors on `LatestResult`, so putting the rules here
     * means every caller — the form, an operation, an agent — gets the actual reason.
     */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkStatusTransition(result);
        this.checkActiveHasATerm(result);
        return result;
    }

    /**
     * An Active contract must have at least one term.
     *
     * The header carries the parties and the paper; the TERM carries the dates, the money and the
     * coverage. An Active contract with no term is live in name only — it cannot bill, cannot renew,
     * and reports as current in every roster.
     *
     * Gated on hydration for the same reason the term's coverage rule is: on a lazily loaded
     * contract `Terms` is empty because nothing asked for it, and refusing that would break every
     * edit to every live contract.
     */
    private checkActiveHasATerm(result: ValidationResult): void {
        if ((this.Status as unknown as string) !== 'Active') return;
        if (!this.TermsAreLoaded) return;
        if (this.Terms.length > 0) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Status',
                'An Active contract needs at least one term. The header records who agreed and on what ' +
                    'paper; the term records the dates, the money and the coverage — so a contract active ' +
                    'without one cannot bill or renew, while reporting as current everywhere.',
                this.Status,
            ),
        );
    }

    /**
     * Save the agreement — header, terms, and everything the terms own — in ONE transaction.
     *
     * ONE TRANSACTION COVERS THE NUMBER TOO. `ContractNumber` is allocated by a read-modify-write
     * against the sequence, and it belongs inside the same transaction as the rest: allocated
     * outside it, a failed save strands the number; allocated in a transaction of its own, a later
     * failure commits an allocation for a contract that does not exist. Inside, a rollback returns
     * it. (The provider makes an inner `BeginTransaction` a savepoint, so the terms' own
     * transactions nest correctly beneath this one.)
     *
     * The transaction is skipped entirely when there is nothing to coordinate — an already-numbered
     * contract with no pending term writes is a single-row update and should cost one round trip.
     */
    public override async Save(options?: EntitySaveOptions): Promise<boolean> {
        // The pricing moment. Defaulted rather than demanded: a contract created today is priced
        // today, and someone entering older paper overrides it. What must not happen is a contract
        // with no as-of date, because then "the catalog price" has no defined meaning (§12).
        if (!this.PricedAt) {
            this.PricedAt = new Date();
        }

        const needsNumber = !this.ContractNumber || !this.ContractNumber.trim();
        if (!needsNumber && !this.terms.HasPendingWrites) {
            return super.Save(options);
        }

        const provider = this.ProviderToUse as unknown as DatabaseProviderBase;
        try {
            await provider.BeginTransaction();

            if (needsNumber) {
                this.ContractNumber = await this.allocateContractNumber(provider);
            }

            const savedHeader = await super.Save(options);
            if (!savedHeader) {
                throw new Error(`Could not save contract: ${this.LatestResult?.CompleteMessage ?? 'unknown error'}`);
            }

            // Each term saves its own coverage, schedules and commitments as part of its Save().
            await this.terms.Save(this.ID, this.ContextCurrentUser, options);

            await provider.CommitTransaction();
            return true;
        } catch (e) {
            await provider.RollbackTransaction();
            throw e;
        }
    }

    /**
     * A save is legal when the status is unchanged, or when the move is in {@link LEGAL_MOVES}.
     * A brand-new record may start in any state the CHECK allows — the map governs MOVES, not births.
     */
    private checkStatusTransition(result: ValidationResult): void {
        if (!this.IsSaved) return;

        const field = this.Fields.find((f) => f.Name === 'Status');
        const previous = field?.OldValue as string | undefined;
        const next = this.Status as unknown as string;
        if (!previous || previous === next) return;

        const allowed = LEGAL_MOVES[previous] ?? [];
        if (allowed.includes(next)) return;

        // The message names the legal alternatives, because "that is not allowed" leaves the person
        // to guess what is. A terminal state says so outright rather than listing nothing.
        const others = allowed.filter((s) => s !== previous);
        const detail = others.length
            ? `Legal moves from ${previous} are: ${others.join(', ')}.`
            : `${previous} is a terminal state — nothing follows it.`;
        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo('Status', `A contract cannot move from ${previous} to ${next}. ${detail}`, next),
        );
    }

    /**
     * `CTR-{seq}` from the singleton `ContractSequence` row. Read-modify-write inside the caller's
     * transaction, so two concurrent creates cannot take the same number.
     */
    private async allocateContractNumber(provider: DatabaseProviderBase): Promise<string> {
        // OUTPUT ... INTO, not a bare OUTPUT: CodeGen puts an __mj_UpdatedAt trigger on every table,
        // and SQL Server refuses a bare OUTPUT clause on a table that has enabled triggers.
        const rows = await provider.ExecuteSQL(
            `DECLARE @allocated TABLE (Allocated INT);
             UPDATE __mj_BizAppsContracts.ContractSequence
                SET NextSequenceNumber = NextSequenceNumber + 1
             OUTPUT deleted.NextSequenceNumber INTO @allocated(Allocated);
             SELECT Allocated FROM @allocated;`,
        );
        const allocated = Array.isArray(rows) && rows.length ? Number((rows[0] as { Allocated: number }).Allocated) : NaN;
        if (!Number.isFinite(allocated)) {
            throw new Error('ContractSequence produced no number — is the singleton row missing?');
        }
        return `CTR-${String(allocated).padStart(6, '0')}`;
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractEntityServer(): void {
    /* intentionally empty */
}
