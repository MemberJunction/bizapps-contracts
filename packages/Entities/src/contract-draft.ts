/**
 * @fileoverview `ContractDraft` — the client-side model of a contract being composed.
 *
 * WHY THIS EXISTS. `ContractEntityServer` now composes a whole agreement — contract, terms, each
 * term's coverage and billing plan — and writes it in one transaction. A browser cannot use any of
 * that. The class the client holds is the GENERATED `mjBizAppsContractsContractEntity`, not the
 * server subclass, so `.Terms` does not exist there and the transient children have no way to cross
 * the entity-save boundary as scalar fields. Before this, the UI did the only thing it could: save
 * the contract, then the term, then each line, as separate round trips — and a failure partway left
 * a numbered contract with nothing under it.
 *
 * `ContractDraft` is the other half of the answer: something the UI holds and mutates that knows how
 * to become the payload `Contracts.SaveContract` accepts, which the server then rehydrates into the
 * real entity tree. bizapps-orders solved the identical problem with `OrderDraft`; this is that
 * pattern applied to a three-level tree.
 *
 * ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
 *
 * It does not PRICE anything, and it does not re-implement a single business rule. Escalation
 * ceilings, term numbering, legal status moves, whether coverage fits inside its term — all of that
 * lives in the entity subclasses on the server, on the one path every write takes. A second
 * implementation living next to the UI is the thing that eventually disagrees with the first, and
 * the disagreement surfaces as a contract that the form said was fine and the server refused.
 *
 * What {@link ContractDraft.Validate} checks is only what a form can honestly check without a
 * database: is a required field filled in, do these dates make sense against each other, does this
 * term have any coverage at all. Everything it reports is a REQUIREMENT the user must satisfy before
 * the server will even look at the record — never a judgement about whether the agreement is legal.
 *
 * ── FRAMEWORK-FREE ON PURPOSE ───────────────────────────────────────────────────────────────────
 *
 * No Angular, no DOM, no MJ provider. Three consequences that all matter: the create surface and the
 * edit surface can bind to the SAME instance rather than to copies that drift; the whole model is
 * unit-testable with plain vitest and no harness; and the validation shape below can be lifted into
 * MJ core later without dragging a UI framework behind it.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/* ────────────────────────────────────────────────────────────────────────────
 * Validation — the shape the UI reads
 *
 * A STRUCTURED LIST, never a string. `Section` is what lets a tab show a badge;
 * `Field` is what lets the field itself show a marker; `Severity` separates
 * "you cannot save this" from "look at this". A joined error string can do none
 * of those, which is why every UI that starts with one ends up parsing it.
 * ──────────────────────────────────────────────────────────────────────────── */

/** Which pane of the workspace an issue belongs to. Matches the tab keys exactly. */
export type ContractDraftSection = 'contract' | 'terms' | 'coverage' | 'billing' | 'commitments';

export type ContractDraftSeverity = 'error' | 'warning';

export interface ContractDraftIssue {
    Section: ContractDraftSection;
    /** The field this is about, where there is one. Omitted for whole-section issues. */
    Field?: string;
    Severity: ContractDraftSeverity;
    Message: string;
    /** Which term this concerns, by position, so the UI can point at the right row. */
    TermIndex?: number;
    /** Which coverage line within that term, by position. */
    LineIndex?: number;
}

export interface ContractDraftValidationResult {
    /** False when any issue is an `error`. Warnings never block. */
    IsValid: boolean;
    Issues: ContractDraftIssue[];
}

/* ────────────────────────────────────────────────────────────────────────────
 * Wire shapes
 *
 * These mirror the `Contracts.SaveContract` contract declared in
 * metadata/remote-operations/types/. Re-declared here rather than imported
 * because the generated operation bases only exist after CodeGen has run and
 * this package must build before that. The shapes are structural, so passing
 * ToInput() into the generated operation type-checks AT THE CALL SITE — which
 * is exactly where a drift between the two should be caught.
 * ──────────────────────────────────────────────────────────────────────────── */

export interface ContractDraftLinePayload {
    ID?: string | null;
    ProductID: string;
    LineType: string;
    Quantity: number;
    ContractedUnitPrice?: number | null;
    DiscountPct?: number | null;
    StartDate?: string | null;
    EndDate?: string | null;
    SubscriptionTypeID?: string | null;
    Description?: string | null;
}

export interface ContractDraftSchedulePayload {
    ID?: string | null;
    ScheduleType: string;
    Frequency?: string | null;
    AnchorDate?: string | null;
    IsActive?: boolean;
    Notes?: string | null;
}

export interface ContractDraftCommitmentPayload {
    ID?: string | null;
    CommitmentType: string;
    CommittedAmount: number;
    ConsumedAmount?: number;
    PeriodStart?: string | null;
    PeriodEnd?: string | null;
    TrueUpPolicy?: string;
    Status?: string;
}

export interface ContractDraftTermPayload {
    ID?: string | null;
    StartDate: string;
    EndDate: string;
    Status: string;
    BillingFrequency: string;
    CommittedAmount?: number | null;
    EscalationPercent?: number | null;
    EscalationBasis?: string | null;
    MaxEscalationPercent?: number | null;
    RenewalNoticeDays?: number | null;
    RenewalProbability?: number | null;
    PaymentTermsTypeID?: string | null;
    CurrencyID?: string | null;
    EarlyTerminationDate?: string | null;
    ExecutedDate?: string | null;
    Notes?: string | null;
    Lines: ContractDraftLinePayload[];
    Schedules: ContractDraftSchedulePayload[];
    Commitments: ContractDraftCommitmentPayload[];
}

export interface ContractDraftPayload {
    ID?: string | null;
    ContractNumber?: string | null;
    ContractTypeID: string;
    CompanyID: string;
    CustomerOrganizationID?: string | null;
    CustomerPersonID?: string | null;
    PrimaryContactPersonID?: string | null;
    OwnerUserID?: string | null;
    ParentContractID?: string | null;
    Status: string;
    Description?: string | null;
    EffectiveDate?: string | null;
    ExecutedDate?: string | null;
    PricedAt?: string | null;
    AutoRenew?: boolean;
    CancellationWindowDays?: number | null;
    TerminationPolicy?: string | null;
    ExternalReferenceID?: string | null;
    Terms: ContractDraftTermPayload[];
    /** Ids the user removed. Sent explicitly — absence from the array is not a delete. */
    RemovedTermIDs: string[];
    RemovedLineIDs: string[];
    RemovedScheduleIDs: string[];
    RemovedCommitmentIDs: string[];
}

/* ────────────────────────────────────────────────────────────────────────────
 * The model
 * ──────────────────────────────────────────────────────────────────────────── */

/** A coverage line being composed. `ClientKey` identifies it before it has a database id. */
export class ContractDraftLine implements ContractDraftLinePayload {
    public ClientKey: string;
    public ID: string | null = null;
    public ProductID = '';
    public LineType = 'OneTime';
    public Quantity = 1;
    public ContractedUnitPrice: number | null = null;
    public DiscountPct: number | null = null;
    public StartDate: string | null = null;
    public EndDate: string | null = null;
    public SubscriptionTypeID: string | null = null;
    public Description: string | null = null;

    constructor(key: string) {
        this.ClientKey = key;
    }

    public ToPayload(): ContractDraftLinePayload {
        return {
            ID: this.ID,
            ProductID: this.ProductID,
            LineType: this.LineType,
            Quantity: this.Quantity,
            ContractedUnitPrice: this.ContractedUnitPrice,
            DiscountPct: this.DiscountPct,
            StartDate: this.StartDate,
            EndDate: this.EndDate,
            SubscriptionTypeID: this.SubscriptionTypeID,
            Description: this.Description,
        };
    }
}

/** A billing plan being composed. */
export class ContractDraftSchedule implements ContractDraftSchedulePayload {
    public ClientKey: string;
    public ID: string | null = null;
    public ScheduleType = 'Cadence';
    public Frequency: string | null = null;
    public AnchorDate: string | null = null;
    public IsActive = true;
    public Notes: string | null = null;

    constructor(key: string) {
        this.ClientKey = key;
    }

    public ToPayload(): ContractDraftSchedulePayload {
        return {
            ID: this.ID,
            ScheduleType: this.ScheduleType,
            Frequency: this.Frequency,
            AnchorDate: this.AnchorDate,
            IsActive: this.IsActive,
            Notes: this.Notes,
        };
    }
}

/** A minimum, prepaid balance or draw being composed. */
export class ContractDraftCommitment implements ContractDraftCommitmentPayload {
    public ClientKey: string;
    public ID: string | null = null;
    public CommitmentType = 'Minimum';
    public CommittedAmount = 0;
    public ConsumedAmount = 0;
    public PeriodStart: string | null = null;
    public PeriodEnd: string | null = null;
    public TrueUpPolicy = 'BillShortfall';
    public Status = 'Open';

    constructor(key: string) {
        this.ClientKey = key;
    }

    public ToPayload(): ContractDraftCommitmentPayload {
        return {
            ID: this.ID,
            CommitmentType: this.CommitmentType,
            CommittedAmount: this.CommittedAmount,
            ConsumedAmount: this.ConsumedAmount,
            PeriodStart: this.PeriodStart,
            PeriodEnd: this.PeriodEnd,
            TrueUpPolicy: this.TrueUpPolicy,
            Status: this.Status,
        };
    }
}

/** A term being composed, with everything it owns. */
export class ContractDraftTerm {
    public ClientKey: string;
    public ID: string | null = null;
    public StartDate = '';
    public EndDate = '';
    public Status = 'Pending';
    public BillingFrequency = 'Annual';
    public CommittedAmount: number | null = null;
    public EscalationPercent: number | null = null;
    public EscalationBasis: string | null = null;
    public MaxEscalationPercent: number | null = null;
    public RenewalNoticeDays: number | null = null;
    public RenewalProbability: number | null = null;
    public PaymentTermsTypeID: string | null = null;
    public CurrencyID: string | null = null;
    public EarlyTerminationDate: string | null = null;
    public ExecutedDate: string | null = null;
    public Notes: string | null = null;

    public Lines: ContractDraftLine[] = [];
    public Schedules: ContractDraftSchedule[] = [];
    public Commitments: ContractDraftCommitment[] = [];

    /** Term number as the SERVER derived it, once known. Never set by the client — display only. */
    public TermNumber: number | null = null;

    constructor(key: string) {
        this.ClientKey = key;
    }

    public ToPayload(): ContractDraftTermPayload {
        return {
            ID: this.ID,
            StartDate: this.StartDate,
            EndDate: this.EndDate,
            Status: this.Status,
            BillingFrequency: this.BillingFrequency,
            CommittedAmount: this.CommittedAmount,
            EscalationPercent: this.EscalationPercent,
            EscalationBasis: this.EscalationBasis,
            MaxEscalationPercent: this.MaxEscalationPercent,
            RenewalNoticeDays: this.RenewalNoticeDays,
            RenewalProbability: this.RenewalProbability,
            PaymentTermsTypeID: this.PaymentTermsTypeID,
            CurrencyID: this.CurrencyID,
            EarlyTerminationDate: this.EarlyTerminationDate,
            ExecutedDate: this.ExecutedDate,
            Notes: this.Notes,
            Lines: this.Lines.map((l) => l.ToPayload()),
            Schedules: this.Schedules.map((s) => s.ToPayload()),
            Commitments: this.Commitments.map((c) => c.ToPayload()),
        };
    }
}

/**
 * A contract being composed, and the single object both the create surface and the edit surface
 * bind to.
 *
 * There is deliberately no separate "new contract" type. A contract being created is a draft whose
 * `ID` is null; one being edited is a draft whose `ID` is set. That is what lets the workspace show
 * the same tabs, in the same order, for both — and it is why the two surfaces could be merged at
 * all.
 */
export class ContractDraft {
    public ID: string | null = null;
    public ContractNumber: string | null = null;
    public ContractTypeID = '';
    public CompanyID = '';
    public CustomerOrganizationID: string | null = null;
    public CustomerPersonID: string | null = null;
    public PrimaryContactPersonID: string | null = null;
    public OwnerUserID: string | null = null;
    public ParentContractID: string | null = null;
    public Status = 'Draft';
    public Description: string | null = null;
    public EffectiveDate: string | null = null;
    public ExecutedDate: string | null = null;
    public PricedAt: string | null = null;
    public AutoRenew = false;
    public CancellationWindowDays: number | null = null;
    public TerminationPolicy: string | null = null;
    public ExternalReferenceID: string | null = null;

    public Terms: ContractDraftTerm[] = [];

    /**
     * What the user removed.
     *
     * Tracked explicitly rather than inferred from absence, because the two are not the same thing:
     * a term missing from the payload might have been removed, or might simply never have been
     * loaded. Inferring deletion from absence means a lazily loaded contract deletes everything the
     * client did not happen to hold — which is a data-loss bug that tests pass right through.
     */
    public RemovedTermIDs: string[] = [];
    public RemovedLineIDs: string[] = [];
    public RemovedScheduleIDs: string[] = [];
    public RemovedCommitmentIDs: string[] = [];

    private keySeed = 0;

    /** A stable client-side key. Not a database id and never sent as one. */
    private nextKey(prefix: string): string {
        this.keySeed += 1;
        return `${prefix}-${this.keySeed}`;
    }

    public AddTerm(): ContractDraftTerm {
        const term = new ContractDraftTerm(this.nextKey('term'));
        this.Terms.push(term);
        return term;
    }

    public RemoveTerm(term: ContractDraftTerm): void {
        const index = this.Terms.indexOf(term);
        if (index < 0) return;
        this.Terms.splice(index, 1);
        if (term.ID) this.RemovedTermIDs.push(term.ID);
        // The children go with it. Their ids are recorded too, so a server that processes removals
        // before terms does not trip the foreign key.
        for (const line of term.Lines) if (line.ID) this.RemovedLineIDs.push(line.ID);
        for (const schedule of term.Schedules) if (schedule.ID) this.RemovedScheduleIDs.push(schedule.ID);
        for (const commitment of term.Commitments) if (commitment.ID) this.RemovedCommitmentIDs.push(commitment.ID);
    }

    public AddLine(term: ContractDraftTerm): ContractDraftLine {
        const line = new ContractDraftLine(this.nextKey('line'));
        term.Lines.push(line);
        return line;
    }

    public RemoveLine(term: ContractDraftTerm, line: ContractDraftLine): void {
        const index = term.Lines.indexOf(line);
        if (index < 0) return;
        term.Lines.splice(index, 1);
        if (line.ID) this.RemovedLineIDs.push(line.ID);
    }

    public AddSchedule(term: ContractDraftTerm): ContractDraftSchedule {
        const schedule = new ContractDraftSchedule(this.nextKey('sched'));
        term.Schedules.push(schedule);
        return schedule;
    }

    public RemoveSchedule(term: ContractDraftTerm, schedule: ContractDraftSchedule): void {
        const index = term.Schedules.indexOf(schedule);
        if (index < 0) return;
        term.Schedules.splice(index, 1);
        if (schedule.ID) this.RemovedScheduleIDs.push(schedule.ID);
    }

    public AddCommitment(term: ContractDraftTerm): ContractDraftCommitment {
        const commitment = new ContractDraftCommitment(this.nextKey('commit'));
        term.Commitments.push(commitment);
        return commitment;
    }

    public RemoveCommitment(term: ContractDraftTerm, commitment: ContractDraftCommitment): void {
        const index = term.Commitments.indexOf(commitment);
        if (index < 0) return;
        term.Commitments.splice(index, 1);
        if (commitment.ID) this.RemovedCommitmentIDs.push(commitment.ID);
    }

    /** Total coverage lines across every term — what the Coverage tab badges. */
    public get LineCount(): number {
        return this.Terms.reduce((sum, t) => sum + t.Lines.length, 0);
    }

    public get ScheduleCount(): number {
        return this.Terms.reduce((sum, t) => sum + t.Schedules.length, 0);
    }

    public get CommitmentCount(): number {
        return this.Terms.reduce((sum, t) => sum + t.Commitments.length, 0);
    }

    /** Whether this draft describes a contract that already exists. */
    public get IsSaved(): boolean {
        return !!this.ID;
    }

    public ToInput(): ContractDraftPayload {
        return {
            ID: this.ID,
            ContractNumber: this.ContractNumber,
            ContractTypeID: this.ContractTypeID,
            CompanyID: this.CompanyID,
            CustomerOrganizationID: this.CustomerOrganizationID,
            CustomerPersonID: this.CustomerPersonID,
            PrimaryContactPersonID: this.PrimaryContactPersonID,
            OwnerUserID: this.OwnerUserID,
            ParentContractID: this.ParentContractID,
            Status: this.Status,
            Description: this.Description,
            EffectiveDate: this.EffectiveDate,
            ExecutedDate: this.ExecutedDate,
            PricedAt: this.PricedAt,
            AutoRenew: this.AutoRenew,
            CancellationWindowDays: this.CancellationWindowDays,
            TerminationPolicy: this.TerminationPolicy,
            ExternalReferenceID: this.ExternalReferenceID,
            Terms: this.Terms.map((t) => t.ToPayload()),
            RemovedTermIDs: [...this.RemovedTermIDs],
            RemovedLineIDs: [...this.RemovedLineIDs],
            RemovedScheduleIDs: [...this.RemovedScheduleIDs],
            RemovedCommitmentIDs: [...this.RemovedCommitmentIDs],
        };
    }

    /**
     * What a form can honestly check without a database.
     *
     * Everything here is a REQUIREMENT — a thing the user must supply before the server can even
     * consider the record — or a self-evident contradiction between two fields the user just typed.
     * Nothing here decides whether the agreement is legal; that is the entity's job and duplicating
     * it would produce two answers that agree today.
     */
    public Validate(): ContractDraftValidationResult {
        const issues: ContractDraftIssue[] = [];

        const require = (value: unknown, field: string, message: string): void => {
            const missing = value === null || value === undefined || value === '';
            if (missing) issues.push({ Section: 'contract', Field: field, Severity: 'error', Message: message });
        };

        require(this.ContractTypeID, 'ContractTypeID', 'Choose a contract type — it supplies the term length, cadence and escalation ceiling every term inherits.');
        require(this.CompanyID, 'CompanyID', 'Choose the company this contract belongs to.');

        // The customer is an either/or, and the database says so (CK_Contract_CustomerXor). Saying
        // it here means the user finds out while filling the form rather than on submit.
        if (!this.CustomerOrganizationID && !this.CustomerPersonID) {
            issues.push({
                Section: 'contract',
                Field: 'CustomerOrganizationID',
                Severity: 'error',
                Message: 'Name the customer — either an organization or a person.',
            });
        } else if (this.CustomerOrganizationID && this.CustomerPersonID) {
            issues.push({
                Section: 'contract',
                Field: 'CustomerOrganizationID',
                Severity: 'error',
                Message: 'A contract has one customer: an organization OR a person, not both.',
            });
        }

        if (this.Status === 'Active' && this.Terms.length === 0) {
            issues.push({
                Section: 'terms',
                Severity: 'error',
                Message: 'An active contract needs at least one term — the term carries the dates, the money and the coverage.',
            });
        }

        this.Terms.forEach((term, termIndex) => this.validateTerm(term, termIndex, issues));

        return { IsValid: !issues.some((i) => i.Severity === 'error'), Issues: issues };
    }

    private validateTerm(term: ContractDraftTerm, termIndex: number, issues: ContractDraftIssue[]): void {
        const at = (Section: ContractDraftSection, Field: string | undefined, Message: string, Severity: ContractDraftSeverity = 'error') =>
            issues.push({ Section, Field, Severity, Message, TermIndex: termIndex });

        if (!term.StartDate) at('terms', 'StartDate', 'A term needs a start date.');
        if (!term.EndDate) at('terms', 'EndDate', 'A term needs an end date.');
        if (term.StartDate && term.EndDate && term.EndDate < term.StartDate) {
            at('terms', 'EndDate', 'A term cannot end before it starts.');
        }
        if (!term.BillingFrequency) at('terms', 'BillingFrequency', 'Choose how often this term bills.');

        // The escalation ceiling. The server enforces this too, and that is the copy that counts —
        // this one exists so the number turns red as it is typed rather than on submit.
        if (
            term.EscalationPercent !== null &&
            term.MaxEscalationPercent !== null &&
            term.EscalationPercent > term.MaxEscalationPercent
        ) {
            at(
                'terms',
                'EscalationPercent',
                `An escalation of ${(term.EscalationPercent * 100).toFixed(2)}% exceeds this term's ceiling of ${(term.MaxEscalationPercent * 100).toFixed(2)}%.`,
            );
        }

        if (term.Status === 'Active' && term.Lines.length === 0) {
            at('coverage', undefined, 'An active term needs at least one coverage line — it is what the customer is entitled to.');
        }

        term.Lines.forEach((line, lineIndex) => {
            const atLine = (Field: string, Message: string) =>
                issues.push({ Section: 'coverage', Field, Severity: 'error', Message, TermIndex: termIndex, LineIndex: lineIndex });

            if (!line.ProductID) atLine('ProductID', 'Choose a product for this coverage line.');
            if (line.Quantity === null || line.Quantity === undefined || line.Quantity < 0) {
                atLine('Quantity', 'Quantity cannot be negative.');
            }
            if (line.LineType === 'Subscription' && !line.SubscriptionTypeID) {
                atLine('SubscriptionTypeID', 'A subscription line must say which kind of subscription it creates — billing cannot materialise one without it.');
            }
            if (line.LineType !== 'Subscription' && line.SubscriptionTypeID) {
                atLine('SubscriptionTypeID', `A subscription type belongs only on a Subscription line; this line is ${line.LineType}.`);
            }
            if (line.StartDate && line.EndDate && line.EndDate < line.StartDate) {
                atLine('EndDate', 'Coverage cannot end before it starts.');
            }
            if (line.DiscountPct !== null && (line.DiscountPct < 0 || line.DiscountPct > 1)) {
                atLine('DiscountPct', 'A discount is a fraction between 0 and 1 (0.10 is 10%).');
            }
        });

        term.Schedules.forEach((schedule, index) => {
            if (schedule.ScheduleType === 'Cadence' && !schedule.Frequency) {
                issues.push({
                    Section: 'billing',
                    Field: 'Frequency',
                    Severity: 'error',
                    Message: 'A cadence schedule needs a frequency — it is the thing the schedule iterates.',
                    TermIndex: termIndex,
                    LineIndex: index,
                });
            }
        });

        term.Commitments.forEach((commitment, index) => {
            if (commitment.CommittedAmount === null || commitment.CommittedAmount < 0) {
                issues.push({
                    Section: 'commitments',
                    Field: 'CommittedAmount',
                    Severity: 'error',
                    Message: 'A commitment amount cannot be negative.',
                    TermIndex: termIndex,
                    LineIndex: index,
                });
            }
        });
    }

    /** The sections carrying at least one error — what puts a red badge on a tab. */
    public get SectionsWithErrors(): ContractDraftSection[] {
        const sections = new Set<ContractDraftSection>();
        for (const issue of this.Validate().Issues) {
            if (issue.Severity === 'error') sections.add(issue.Section);
        }
        return [...sections];
    }

    /** Every issue for one section, in order — what a pane lists above its fields. */
    public IssuesFor(section: ContractDraftSection): ContractDraftIssue[] {
        return this.Validate().Issues.filter((i) => i.Section === section);
    }

    /**
     * Rebuild a draft from what the server returned, so the surface that just saved shows exactly
     * what was written — including the values the server DERIVED (the contract number, term
     * numbers, the defaulted pricing date) rather than the client's guess at them.
     */
    public static FromPayload(payload: ContractDraftPayload): ContractDraft {
        const draft = new ContractDraft();
        draft.ID = payload.ID ?? null;
        draft.ContractNumber = payload.ContractNumber ?? null;
        draft.ContractTypeID = payload.ContractTypeID;
        draft.CompanyID = payload.CompanyID;
        draft.CustomerOrganizationID = payload.CustomerOrganizationID ?? null;
        draft.CustomerPersonID = payload.CustomerPersonID ?? null;
        draft.PrimaryContactPersonID = payload.PrimaryContactPersonID ?? null;
        draft.OwnerUserID = payload.OwnerUserID ?? null;
        draft.ParentContractID = payload.ParentContractID ?? null;
        draft.Status = payload.Status;
        draft.Description = payload.Description ?? null;
        draft.EffectiveDate = payload.EffectiveDate ?? null;
        draft.ExecutedDate = payload.ExecutedDate ?? null;
        draft.PricedAt = payload.PricedAt ?? null;
        draft.AutoRenew = payload.AutoRenew ?? false;
        draft.CancellationWindowDays = payload.CancellationWindowDays ?? null;
        draft.TerminationPolicy = payload.TerminationPolicy ?? null;
        draft.ExternalReferenceID = payload.ExternalReferenceID ?? null;

        for (const termPayload of payload.Terms ?? []) {
            const term = draft.AddTerm();
            term.ID = termPayload.ID ?? null;
            term.StartDate = termPayload.StartDate;
            term.EndDate = termPayload.EndDate;
            term.Status = termPayload.Status;
            term.BillingFrequency = termPayload.BillingFrequency;
            term.CommittedAmount = termPayload.CommittedAmount ?? null;
            term.EscalationPercent = termPayload.EscalationPercent ?? null;
            term.EscalationBasis = termPayload.EscalationBasis ?? null;
            term.MaxEscalationPercent = termPayload.MaxEscalationPercent ?? null;
            term.RenewalNoticeDays = termPayload.RenewalNoticeDays ?? null;
            term.RenewalProbability = termPayload.RenewalProbability ?? null;
            term.PaymentTermsTypeID = termPayload.PaymentTermsTypeID ?? null;
            term.CurrencyID = termPayload.CurrencyID ?? null;
            term.EarlyTerminationDate = termPayload.EarlyTerminationDate ?? null;
            term.ExecutedDate = termPayload.ExecutedDate ?? null;
            term.Notes = termPayload.Notes ?? null;

            for (const linePayload of termPayload.Lines ?? []) {
                const line = draft.AddLine(term);
                Object.assign(line, linePayload);
            }
            for (const schedulePayload of termPayload.Schedules ?? []) {
                const schedule = draft.AddSchedule(term);
                Object.assign(schedule, schedulePayload);
            }
            for (const commitmentPayload of termPayload.Commitments ?? []) {
                const commitment = draft.AddCommitment(term);
                Object.assign(commitment, commitmentPayload);
            }
        }

        // A rebuilt draft has no pending removals — whatever was removed has been written.
        draft.RemovedTermIDs = [];
        draft.RemovedLineIDs = [];
        draft.RemovedScheduleIDs = [];
        draft.RemovedCommitmentIDs = [];
        return draft;
    }
}
