/**
 * @fileoverview Server-side `ContractTerm` — term numbering, the escalation cap, and legal moves.
 *
 * THE ESCALATION CAP IS THE INTERESTING ONE. `MaxEscalationPercent` is a ceiling on
 * `EscalationPercent`, and that rule **cannot be a CHECK constraint** here: CodeGen derives a
 * generated validation method name from the constraint expression, and a constraint naming two
 * columns makes it emit a call to a method it never defines — a build break in generated code that
 * orders already hit and documented. So the rule lives where it can be expressed safely: in `Save()`,
 * on the one path every write takes.
 *
 * That is not a workaround. An uncapped "then-current list price" increase is the single most
 * disputed clause in a B2B renewal; a contract that records a 5% ceiling and then escalates 8%
 * is a contract we would lose an argument about.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseEntity,
    type DatabaseProviderBase,
    RunView,
    type IMetadataProvider,
    type UserInfo,
    ValidationErrorInfo,
    ValidationResult,
    type EntitySaveOptions,
    type IRunViewProvider,
} from '@memberjunction/core';
import { RegisterClass, UUIDsEqual } from '@memberjunction/global';
import { ContractsEngine, LoadContractsEngine } from './ContractsEngine.js';
import { mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';
import { ChildCollection } from './ChildCollection.js';
import { ContractLineEntityServer } from './ContractLineEntityServer.js';
import { ContractBillingScheduleEntityServer } from './ContractBillingScheduleEntityServer.js';
import { ContractCommitmentEntityServer } from './ContractCommitmentEntityServer.js';

const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';
const CONTRACT_ENTITY = 'MJ_BizApps_Contracts: Contracts';
const LINE_ENTITY = 'MJ_BizApps_Contracts: Contract Lines';
const SCHEDULE_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const COMMITMENT_ENTITY = 'MJ_BizApps_Contracts: Contract Commitments';

/** Which term status may follow which. Terminal states have only themselves. */
const LEGAL_MOVES: Readonly<Record<string, readonly string[]>> = {
    Pending: ['Pending', 'PendingSignature', 'Active', 'Terminated'],
    PendingSignature: ['PendingSignature', 'Pending', 'Active', 'Terminated'],
    Active: ['Active', 'Completed', 'Terminated'],
    Completed: ['Completed'],
    Terminated: ['Terminated'],
};

@RegisterClass(BaseEntity, TERM_ENTITY)
export class ContractTermEntityServer extends mjBizAppsContractsContractTermEntity {
    /**
     * OPT IN TO ASYNC VALIDATION. `BaseEntity.DefaultSkipAsyncValidation` is `true`, so `ValidateAsync`
     * is skipped unless an entity asks for it — and a rule placed there without this override simply
     * never runs. That is exactly what happened when the renewal-chain check moved out of `Save()`:
     * cross-contract renewals started saving again, silently, until a test caught it.
     *
     * The cost is one extra read per term save, which is the correct price for a rule that prevents
     * one contract's history from showing another contract's terms.
     */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    /* ── What a term OWNS ────────────────────────────────────────────────────────────────────────
     *
     * Coverage, billing plans and commitments have no meaning apart from the term that grants them,
     * and all three must be written in the same breath as it — a term saved without its coverage is
     * a term that cannot be activated, and a half-written one is worse than none.
     *
     * `DisplayOrder` is assigned positionally on save, the way `JournalEntryEntityServer` assigns
     * `LineNumber`. The other two collections have no sequence and load by creation time, so their
     * order is stable across reads without inventing a column to carry it.
     * ────────────────────────────────────────────────────────────────────────────────────────── */

    private readonly lines = new ChildCollection<ContractLineEntityServer>({
        EntityName: LINE_ENTITY,
        ForeignKeyField: 'ContractTermID',
        OrderBy: 'DisplayOrder ASC',
        ParentID: () => this.ID,
        LinkToParent: (line, termID) => {
            line.ContractTermID = termID;
        },
        Sequence: (line, position) => {
            line.DisplayOrder = position;
        },
    });

    private readonly schedules = new ChildCollection<ContractBillingScheduleEntityServer>({
        EntityName: SCHEDULE_ENTITY,
        ForeignKeyField: 'ContractTermID',
        OrderBy: '__mj_CreatedAt ASC',
        ParentID: () => this.ID,
        LinkToParent: (schedule, termID) => {
            schedule.ContractTermID = termID;
        },
    });

    private readonly commitments = new ChildCollection<ContractCommitmentEntityServer>({
        EntityName: COMMITMENT_ENTITY,
        ForeignKeyField: 'ContractTermID',
        OrderBy: '__mj_CreatedAt ASC',
        ParentID: () => this.ID,
        LinkToParent: (commitment, termID) => {
            commitment.ContractTermID = termID;
        },
    });

    /** Coverage — what this term entitles the customer to. */
    public get Lines(): readonly ContractLineEntityServer[] {
        return this.lines.Items;
    }

    /** Billing plans. A term may carry more than one: a quarterly cadence AND a milestone schedule. */
    public get Schedules(): readonly ContractBillingScheduleEntityServer[] {
        return this.schedules.Items;
    }

    /** Minimums, prepaid balances and draws. */
    public get Commitments(): readonly ContractCommitmentEntityServer[] {
        return this.commitments.Items;
    }

    /**
     * Whether this term's children are the WHOLE truth, or simply were not asked for.
     *
     * Every cross-child rule is gated on this. A term read as part of a contract roster has empty
     * collections because nothing loaded them — treating that as "no coverage" would refuse an
     * activation that is perfectly valid. See `ChildCollection.IsAuthoritative`.
     */
    public get ChildrenAreLoaded(): boolean {
        return this.lines.IsAuthoritative && this.schedules.IsAuthoritative && this.commitments.IsAuthoritative;
    }

    public AddLine(line: ContractLineEntityServer): void {
        this.lines.Add(line);
    }

    public RemoveLine(lineOrIndex: ContractLineEntityServer | number): void {
        this.lines.Remove(lineOrIndex);
    }

    public async CreateLine(user?: UserInfo): Promise<ContractLineEntityServer> {
        return this.lines.Create(this.ProviderToUse as unknown as IMetadataProvider, user ?? this.ContextCurrentUser);
    }

    public AddSchedule(schedule: ContractBillingScheduleEntityServer): void {
        this.schedules.Add(schedule);
    }

    public RemoveSchedule(scheduleOrIndex: ContractBillingScheduleEntityServer | number): void {
        this.schedules.Remove(scheduleOrIndex);
    }

    public async CreateSchedule(user?: UserInfo): Promise<ContractBillingScheduleEntityServer> {
        return this.schedules.Create(this.ProviderToUse as unknown as IMetadataProvider, user ?? this.ContextCurrentUser);
    }

    public AddCommitment(commitment: ContractCommitmentEntityServer): void {
        this.commitments.Add(commitment);
    }

    public RemoveCommitment(commitmentOrIndex: ContractCommitmentEntityServer | number): void {
        this.commitments.Remove(commitmentOrIndex);
    }

    public async CreateCommitment(user?: UserInfo): Promise<ContractCommitmentEntityServer> {
        return this.commitments.Create(this.ProviderToUse as unknown as IMetadataProvider, user ?? this.ContextCurrentUser);
    }

    /**
     * Declare a NEW term's collections complete without reading anything.
     *
     * Legitimate only before the first save: a record that has never been written has nothing in the
     * database that could be missing, so whatever is in memory IS the whole truth. Called by
     * `ContractEntityServer.CreateTerm` so a contract assembled in memory validates against real
     * coverage rather than skipping the checks as un-hydrated.
     */
    public MarkChildrenAuthoritative(): void {
        this.lines.MarkAuthoritative();
        this.schedules.MarkAuthoritative();
        this.commitments.MarkAuthoritative();
    }

    /**
     * Read this term's coverage, schedules and commitments — three queries, for ONE term.
     *
     * To hydrate a whole contract use `ContractEntityServer.LoadFull()`, which reads each child type
     * once across every term rather than calling this in a loop.
     */
    public async LoadChildren(user?: UserInfo): Promise<void> {
        const provider = this.ProviderToUse as unknown as IRunViewProvider;
        const contextUser = user ?? this.ContextCurrentUser;
        await this.lines.Load(provider, this.ID, contextUser);
        await this.schedules.Load(provider, this.ID, contextUser);
        await this.commitments.Load(provider, this.ID, contextUser);
    }

    /** Bulk-hydration entry point — see `ContractEntityServer.LoadFull()`. */
    public SetLoadedChildren(
        lines: ContractLineEntityServer[],
        schedules: ContractBillingScheduleEntityServer[],
        commitments: ContractCommitmentEntityServer[],
    ): void {
        this.lines.SetLoaded(lines);
        this.schedules.SetLoaded(schedules);
        this.commitments.SetLoaded(commitments);
    }

    /**
     * Delete everything hanging off this term, so the term itself can be deleted.
     *
     * Hydrates first: the children have to be KNOWN before they can be removed, and a term whose
     * lines were never loaded would otherwise be refused by the foreign key with a constraint name
     * for an error message. Runs inside whatever transaction the caller opened.
     */
    public async DeleteChildren(user?: UserInfo): Promise<void> {
        if (!this.ChildrenAreLoaded) await this.LoadChildren(user);
        // Written out rather than looped: the three collections are differently typed, and a loop
        // over them widens `Remove`'s parameter to the union of all three child types, which no
        // single element satisfies.
        for (const commitment of [...this.commitments.Items]) this.commitments.Remove(commitment);
        for (const schedule of [...this.schedules.Items]) this.schedules.Remove(schedule);
        for (const line of [...this.lines.Items]) this.lines.Remove(line);
        await this.saveChildren(user);
    }

    /** Synchronous rules — everything decidable from this row alone. */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkStatusTransition(result);
        this.checkEscalationCap(result);
        return result;
    }

    /**
     * Cross-record rules go here, not in `Validate()`: the renewal-chain check must READ the row it
     * points at, and `Validate()` is synchronous. `Save()` runs both and merges the errors.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkRenewalChainIntegrity(result);
        await this.checkHasCoverageWhenActive(result);
        return result;
    }

    /**
     * An Active term must actually entitle the customer to something.
     *
     * A term with no coverage bills nothing and grants nothing — it is an agreement in name only,
     * and the billing engine assembling a draft from its lines would produce an empty bill or
     * nothing at all, with no error to explain either.
     *
     * The gates mirror `ContractEntityServer.checkActiveHasATerm` exactly, for the same reasons —
     * see the long note there. In short: the rule can only newly break on the activation itself, on
     * a new record, or when lines are being removed; in-memory coverage answers it for free; and
     * only what is left costs a query. Editing a lazily loaded live term costs nothing.
     */
    private async checkHasCoverageWhenActive(result: ValidationResult): Promise<void> {
        if ((this.Status as unknown as string) !== 'Active') return;
        if (!this.becameActive() && this.IsSaved && !this.lines.HasPendingDeletes) return;
        if (this.Lines.length > 0) return;

        if (this.IsSaved) {
            const persisted = await this.countPersistedLines();
            if (persisted > 0) return;
        }

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Status',
                'An Active term must have at least one coverage line — it is what the term entitles the ' +
                    'customer to. Without one there is nothing to bill and nothing to deliver, and a billing ' +
                    'run against it would produce an empty draft with no error to explain why.',
                this.Status,
            ),
        );
    }

    /** Whether THIS save is the one turning the term Active (including a term born Active). */
    private becameActive(): boolean {
        if (!this.IsSaved) return true;
        return !!this.Fields.find((f) => f.Name === 'Status')?.Dirty;
    }

    /**
     * Whether this term has any coverage on disk that will SURVIVE this save. One row at most;
     * never loads them all.
     *
     * The doomed rows are excluded deliberately: validation runs BEFORE the deletions are applied,
     * so a plain count still sees the line being removed and reports coverage that is about to
     * vanish. That is how stripping the last line off an Active term passed the first time.
     */
    private async countPersistedLines(): Promise<number> {
        const doomed = this.lines.PendingDeleteIDs;
        const survivingOnly = doomed.length
            ? ` AND ID NOT IN (${doomed.map((id) => `'${id}'`).join(',')})`
            : '';
        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ID: string }>(
            {
                EntityName: LINE_ENTITY,
                Fields: ['ID'],
                ExtraFilter: `ContractTermID='${this.ID}'${survivingOnly}`,
                MaxRows: 1,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not check this term's coverage: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        return res.Results?.length ?? 0;
    }

    /**
     * Save the term and everything it owns, atomically.
     *
     * THE TRANSACTION IS CONDITIONAL. Most saves edit one field on one loaded term and touch no
     * children at all; opening a transaction for those buys nothing and costs a round trip. When
     * there ARE children to write, header and children go together or not at all — a term whose
     * coverage half-saved is a term that can be activated with the wrong entitlement.
     *
     * NESTING IS SAFE AND EXPECTED. `ContractEntityServer.Save()` calls this from inside its own
     * transaction; `SQLServerDataProvider` turns the inner `BeginTransaction` into a SAVEPOINT and
     * an inner rollback unwinds only to that savepoint, leaving the outer transaction alive to be
     * rolled back by the contract's own handler. So a failing term rolls back its own children, then
     * the exception propagates and takes the whole contract with it — which is what should happen.
     */
    public override async Save(options?: EntitySaveOptions): Promise<boolean> {

        // TERM NUMBERING IS DERIVED, NOT TYPED. A term's number is its position in the contract's
        // chain; asking a caller to supply it invites the duplicate that the unique index on
        // (ContractID, TermNumber) then rejects at the worst possible moment.
        //
        // Inside a contract's transaction this read SEES the sibling terms already inserted by the
        // same transaction — the provider routes reads through the active transaction — so three
        // terms created together number 1, 2, 3 rather than colliding on 1.
        if (!this.IsSaved && (this.TermNumber === null || this.TermNumber === undefined || this.TermNumber <= 0)) {
            this.TermNumber = await this.nextTermNumber();
        }

        if (!this.IsSaved) {
            await this.applyContractTypeDefaults();
        }

        if (!this.hasChildWrites) {
            return super.Save(options);
        }

        const provider = this.ProviderToUse as unknown as DatabaseProviderBase;
        try {
            await provider.BeginTransaction();

            // FORCE VALIDATION WHEN ONLY CHILDREN CHANGED.
            //
            // `BaseEntity._InnerSave` skips its entire body — validation included — when the record
            // is not dirty (baseEntity.ts: `if (_options.IgnoreDirtyState || initialDirtyState ||
            // _options.ReplayOnly)`). A save that removes a child touches NO field on this row, so
            // without this the parent's cross-child rules never run: stripping the last coverage
            // line off an Active term validated nothing and saved happily.
            //
            // The cost is a no-op UPDATE of an unchanged row, which is the right price for having
            // the rule actually run on the one edit that can break it.
            const saveOptions = this.Dirty ? options : { ...(options ?? {}), IgnoreDirtyState: true } as EntitySaveOptions;

            const savedHeader = await super.Save(saveOptions);
            if (!savedHeader) {
                throw new Error(
                    `Could not save term: ${this.LatestResult?.CompleteMessage ?? 'unknown error'}`,
                );
            }
            await this.saveChildren(this.ContextCurrentUser, options);

            await provider.CommitTransaction();
            return true;
        } catch (e) {
            await provider.RollbackTransaction();
            throw e;
        }
    }

    /** Whether any owned collection would touch the database. */
    private get hasChildWrites(): boolean {
        return this.lines.HasPendingWrites || this.schedules.HasPendingWrites || this.commitments.HasPendingWrites;
    }

    /**
     * Write the three collections. Coverage leads because the other two describe how it is billed,
     * so a failure in a schedule leaves a readable partial state in the rollback log.
     */
    private async saveChildren(user?: UserInfo, options?: EntitySaveOptions): Promise<void> {
        const contextUser = user ?? this.ContextCurrentUser;
        await this.lines.Save(this.ID, contextUser, options);
        await this.schedules.Save(this.ID, contextUser, options);
        await this.commitments.Save(this.ID, contextUser, options);
    }


    /**
     * The cap rule. Both are fractions (0.05 = 5%), and a null cap means "uncapped" — deliberately
     * permitted, because plenty of real agreements have no ceiling and pretending otherwise would
     * make them unrecordable.
     */
    private checkEscalationCap(result: ValidationResult): void {
        const pct = this.EscalationPercent;
        const cap = this.MaxEscalationPercent;
        if (pct === null || pct === undefined || cap === null || cap === undefined) return;
        if (pct <= cap) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'EscalationPercent',
                `An escalation of ${(pct * 100).toFixed(2)}% exceeds this term's negotiated cap of ` +
                    `${(cap * 100).toFixed(2)}%. Either lower the escalation or raise the cap — the cap is what ` +
                    `the contract says, so changing it is a negotiation, not a correction.`,
                pct,
            ),
        );
    }

    /**
     * A term may only renew a term on the SAME contract.
     *
     * The FK blocks only self-reference, so `A.Term1` could be recorded as the renewal of `B.Term3`
     * and it saved. The renewal chain is this app's continuity model and the workspace's term history
     * walks it — a cross-contract link makes that walk surface **another customer's terms** inside
     * this contract's history. That is a data-leak shape, not just an inconsistency.
     *
     * This cannot be a CHECK constraint: the rule compares a column on this row to a column on the
     * row it points at, and a CHECK cannot see another row.
     */
    private async checkRenewalChainIntegrity(result: ValidationResult): Promise<void> {
        if (!this.RenewalOfTermID || !this.ContractID) return;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ContractID: string; TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['ContractID', 'TermNumber'],
                ExtraFilter: `ID='${this.RenewalOfTermID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not verify the renewal chain: ${res?.ErrorMessage ?? 'unknown error'}`);
        }

        const parent = res.Results?.[0];
        // A missing predecessor is left to the FK to reject — that is its job, and duplicating the
        // error here would produce two different messages for one condition.
        if (!parent) return;

        if (UUIDsEqual(parent.ContractID, this.ContractID)) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'RenewalOfTermID',
                `This term is recorded as renewing term ${parent.TermNumber} of a DIFFERENT contract. ` +
                    `A renewal chain cannot cross contracts — walking it would surface another contract's ` +
                    `terms as this one's history.`,
                this.RenewalOfTermID,
            ),
        );
    }

    private checkStatusTransition(result: ValidationResult): void {
        if (!this.IsSaved) return;
        const field = this.Fields.find((f) => f.Name === 'Status');
        const previous = field?.OldValue as string | undefined;
        const next = this.Status as unknown as string;
        if (!previous || previous === next) return;
        if ((LEGAL_MOVES[previous] ?? []).includes(next)) return;

        const allowed = (LEGAL_MOVES[previous] ?? []).filter((s) => s !== previous);
        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Status',
                `A term cannot move from ${previous} to ${next}. ` +
                    (allowed.length ? `Legal moves are: ${allowed.join(', ')}.` : `${previous} is a terminal state.`),
                next,
            ),
        );
    }

    /**
     * Fill a NEW term's unset ceiling and notice period from its contract type.
     *
     * This is what "configuration as data" means in practice: `ContractType` carries
     * `DefaultMaxEscalationPercent` and `DefaultRenewalNoticeDays` precisely so the engine READS them
     * rather than branching on a type's name, and a term created without them should get what its
     * type prescribes instead of silently having no ceiling at all — which is the uncapped
     * "then-current list price" case the cap exists to prevent.
     *
     * NEW RECORDS ONLY, and only fields the caller left unset. Both halves matter:
     *
     *  - On an EXISTING term, retrofitting a default would CHANGE AN AGREEMENT. A term that was
     *    negotiated without a ceiling has no ceiling; that is a fact about the contract, not a gap.
     *  - A RENEWAL is unaffected by construction: `RenewTerm` copies the prior term's values forward,
     *    so it always supplies them and this never fires. A renewal inherits from the agreement it
     *    continues, never from the type — the type's defaults describe how a NEW term starts.
     */
    private async applyContractTypeDefaults(): Promise<void> {
        const needsCap = this.MaxEscalationPercent === null || this.MaxEscalationPercent === undefined;
        const needsNotice = this.RenewalNoticeDays === null || this.RenewalNoticeDays === undefined;
        if ((!needsCap && !needsNotice) || !this.ContractID) return;

        const provider = this.ProviderToUse as unknown as IMetadataProvider;
        await LoadContractsEngine(provider, this.ContextCurrentUser);

        // The term knows its contract, not its type, so the type has to be resolved through it. One
        // read for the contract; the type itself comes from the cache.
        const rv = new RunView(provider as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ContractTypeID: string }>(
            {
                EntityName: CONTRACT_ENTITY,
                Fields: ['ContractTypeID'],
                ExtraFilter: `ID='${this.ContractID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        // A failed read must not silently skip the defaults — a term quietly created without its
        // ceiling is exactly the outcome this method exists to prevent.
        if (!res?.Success) {
            throw new Error(`Could not read the contract's type to apply its defaults: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const contractTypeID = res.Results?.[0]?.ContractTypeID;
        if (!contractTypeID) return;

        const engine = ContractsEngine.Instance;
        if (needsCap) this.MaxEscalationPercent = engine.DefaultMaxEscalationFor(contractTypeID);
        if (needsNotice) this.RenewalNoticeDays = engine.DefaultRenewalNoticeDaysFor(contractTypeID);
    }

    /** max(TermNumber) + 1 for this contract, via RunView on this entity's own provider. */
    private async nextTermNumber(): Promise<number> {
        if (!this.ContractID) return 1;
        // The entity's OWN provider, cast to the RunView surface — never a global Metadata.
        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['TermNumber'],
                ExtraFilter: `ContractID='${this.ContractID}'`,
                OrderBy: 'TermNumber DESC',
                MaxRows: 1,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        // RunView reports failure via Success and never throws; a failed read must not silently
        // hand back 1 and collide with an existing term.
        if (!res?.Success) {
            throw new Error(`Could not determine the next term number: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const highest = res.Results?.[0]?.TermNumber ?? 0;
        return Number(highest) + 1;
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractTermEntityServer(): void {
    /* intentionally empty */
}
