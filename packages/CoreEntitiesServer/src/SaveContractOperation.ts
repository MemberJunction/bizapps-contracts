/**
 * @fileoverview `Contracts.SaveContract` — compose a whole agreement from one payload, atomically.
 *
 * WHY THIS OPERATION EXISTS. `ContractEntityServer` composes a contract with its terms, coverage,
 * billing plans and commitments and writes them in one transaction — but a BROWSER cannot use any
 * of that. The client holds the GENERATED `mjBizAppsContractsContractEntity`, not the server
 * subclass, so `.Terms` does not exist there and transient children have no way to cross the
 * entity-save boundary as scalar fields. The UI's only option was to save the contract, then the
 * term, then each line as separate round trips, and a failure partway left a numbered contract with
 * nothing under it.
 *
 * So this is the bridge: `ContractDraft.ToInput()` on the client, rehydrated here into the real
 * entity tree, saved once. Every rule still lives in the entity subclasses — this operation
 * REHYDRATES and DELEGATES, it does not decide anything. If you find yourself adding a business rule
 * here, it belongs in the entity, where the fixtures and the agents and the next operation will all
 * get it too.
 *
 * REMOTE OPERATIONS ARE FOR THE FRONT END. Another app calling from the server side does not need
 * this — it constructs `ContractEntityServer` and calls `Save()` directly, which is both simpler and
 * typed. The operation exists because the browser cannot do that, and for no other reason.
 *
 * REMOVALS ARE EXPLICIT. The payload names what to delete rather than letting the server infer it
 * from absence. Inferring would mean a client that loaded a contract lazily — holding two of its
 * five terms — silently deletes the other three on save. That is a data-loss bug of exactly the kind
 * that passes every test written against a fully-loaded fixture.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseRemotableOperation,
    type IMetadataProvider,
    Metadata,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type {
    ContractDraftCommitmentPayload,
    ContractDraftLinePayload,
    ContractDraftPayload,
    ContractDraftSchedulePayload,
    ContractDraftTermPayload,
} from '@mj-biz-apps/contracts-entities';
import { ContractEntityServer } from './ContractEntityServer.js';
import type { ContractTermEntityServer } from './ContractTermEntityServer.js';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';

export interface SaveContractInput {
    Contract: ContractDraftPayload;
}

export interface SaveContractOutput {
    Success: boolean;
    Message?: string;
    /** The saved agreement, with everything the SERVER derived filled in. */
    Contract?: ContractDraftPayload;
    /**
     * Field-level reasons on failure, in the same shape the client's own validator produces, so one
     * renderer displays both. A save that fails with a joined string forces the UI to either parse
     * it or show a paragraph where a field marker belongs.
     */
    Issues?: { Section: string; Field?: string; Message: string }[];
}

@RegisterClass(BaseRemotableOperation, 'Contracts.SaveContract')
export class SaveContractOperation extends BaseRemotableOperation<SaveContractInput, SaveContractOutput> {
    public OperationKey = 'Contracts.SaveContract';

    protected async InternalExecute(
        input: SaveContractInput,
        provider: IMetadataProvider,
        user: UserInfo,
    ): Promise<SaveContractOutput> {
        const payload = input?.Contract;
        if (!payload) {
            return { Success: false, Message: 'A contract payload is required.' };
        }
        if (!payload.ContractTypeID || !payload.CompanyID) {
            return {
                Success: false,
                Message: 'A contract needs a type and a company.',
                Issues: [
                    ...(payload.ContractTypeID ? [] : [{ Section: 'contract', Field: 'ContractTypeID', Message: 'Choose a contract type.' }]),
                    ...(payload.CompanyID ? [] : [{ Section: 'contract', Field: 'CompanyID', Message: 'Choose a company.' }]),
                ],
            };
        }

        const md = new Metadata();
        const contract = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);

        if (payload.ID) {
            if (!(await contract.Load(payload.ID))) {
                return { Success: false, Message: `Contract ${payload.ID} was not found.` };
            }
            // The WHOLE tree, because the save has to know what already exists in order to update
            // rather than duplicate it — and because removals are matched against it.
            await contract.LoadFull(user);
        } else {
            contract.NewRecord();
            // A brand-new contract's collection is complete by construction: nothing is in the
            // database that could be missing from it. Without this the cross-child rules would
            // treat it as un-hydrated and skip.
            contract.MarkTermsAuthoritative();
        }

        this.applyHeader(contract, payload);

        try {
            await this.applyTerms(contract, payload, user);
        } catch (e) {
            return { Success: false, Message: e instanceof Error ? e.message : String(e) };
        }

        try {
            const saved = await contract.Save();
            if (!saved) {
                return {
                    Success: false,
                    Message: contract.LatestResult?.CompleteMessage ?? 'The contract could not be saved.',
                    Issues: this.issuesFromResult(contract),
                };
            }
        } catch (e) {
            // The entity throws when a CHILD fails, having already rolled the tree back. The message
            // carries the child's own reason, which is the useful part.
            return { Success: false, Message: e instanceof Error ? e.message : String(e) };
        }

        // Re-read rather than trusting what is in memory: the server DERIVED several values during
        // the save (the contract number, each term's number, the defaulted PricedAt), and the client
        // needs those, not its own guesses.
        const fresh = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
        await fresh.Load(contract.ID);
        await fresh.LoadFull(user);

        return { Success: true, Contract: this.toPayload(fresh) };
    }

    // ── Rehydration ─────────────────────────────────────────────────────────────────────────────

    private applyHeader(contract: ContractEntityServer, payload: ContractDraftPayload): void {
        contract.ContractTypeID = payload.ContractTypeID;
        contract.CompanyID = payload.CompanyID;
        contract.CustomerOrganizationID = payload.CustomerOrganizationID ?? null;
        contract.CustomerPersonID = payload.CustomerPersonID ?? null;
        contract.PrimaryContactPersonID = payload.PrimaryContactPersonID ?? null;
        contract.OwnerUserID = payload.OwnerUserID ?? null;
        contract.ParentContractID = payload.ParentContractID ?? null;
        contract.Status = payload.Status as typeof contract.Status;
        contract.Description = payload.Description ?? null;
        contract.EffectiveDate = SaveContractOperation.toDate(payload.EffectiveDate);
        contract.ExecutedDate = SaveContractOperation.toDate(payload.ExecutedDate);
        contract.AutoRenew = !!payload.AutoRenew;
        contract.CancellationWindowDays = payload.CancellationWindowDays ?? null;
        contract.TerminationPolicy = payload.TerminationPolicy ?? null;
        contract.ExternalReferenceID = payload.ExternalReferenceID ?? null;

        // PricedAt is only taken from the client when the client actually supplied one — the entity
        // defaults it to now otherwise, and overwriting that default with null would leave the
        // agreement with no defined pricing moment (master plan §12).
        const pricedAt = SaveContractOperation.toDate(payload.PricedAt);
        if (pricedAt) contract.PricedAt = pricedAt;

        // ContractNumber is NEVER taken from the client on a new contract: it is allocated from the
        // sequence inside the save transaction. Honouring a client-supplied one would let two
        // browsers claim the same human-facing number.
        if (payload.ID && payload.ContractNumber) contract.ContractNumber = payload.ContractNumber;
    }

    /**
     * Match the payload's terms against what is loaded: update the ones that exist, create the ones
     * that do not, and remove the ones the client named.
     */
    private async applyTerms(
        contract: ContractEntityServer,
        payload: ContractDraftPayload,
        user: UserInfo,
    ): Promise<void> {
        const removedTerms = new Set((payload.RemovedTermIDs ?? []).map((id) => id.toLowerCase()));
        for (const existing of [...contract.Terms]) {
            if (removedTerms.has(existing.ID.toLowerCase())) contract.RemoveTerm(existing);
        }

        const byID = new Map(contract.Terms.map((t) => [t.ID.toLowerCase(), t]));

        for (const termPayload of payload.Terms ?? []) {
            const term = termPayload.ID ? byID.get(termPayload.ID.toLowerCase()) : undefined;
            if (termPayload.ID && !term) {
                // A named term that is not on this contract. Refuse rather than silently create a
                // new one — the id came from somewhere, and quietly inventing a duplicate hides
                // whatever went wrong upstream.
                throw new Error(`Term ${termPayload.ID} does not belong to this contract.`);
            }
            const target = term ?? (await contract.CreateTerm(user));
            this.applyTerm(target, termPayload);
            await this.applyTermChildren(target, termPayload, payload, user);
        }
    }

    private applyTerm(term: ContractTermEntityServer, payload: ContractDraftTermPayload): void {
        term.StartDate = SaveContractOperation.toDate(payload.StartDate) ?? term.StartDate;
        term.EndDate = SaveContractOperation.toDate(payload.EndDate) ?? term.EndDate;
        term.Status = payload.Status as typeof term.Status;
        term.BillingFrequency = payload.BillingFrequency as typeof term.BillingFrequency;
        term.CommittedAmount = payload.CommittedAmount ?? null;
        term.EscalationPercent = payload.EscalationPercent ?? null;
        term.EscalationBasis = (payload.EscalationBasis ?? null) as typeof term.EscalationBasis;
        term.MaxEscalationPercent = payload.MaxEscalationPercent ?? null;
        term.RenewalNoticeDays = payload.RenewalNoticeDays ?? null;
        term.RenewalProbability = payload.RenewalProbability ?? null;
        term.PaymentTermsTypeID = payload.PaymentTermsTypeID ?? null;
        term.CurrencyID = payload.CurrencyID ?? null;
        term.EarlyTerminationDate = SaveContractOperation.toDate(payload.EarlyTerminationDate);
        term.ExecutedDate = SaveContractOperation.toDate(payload.ExecutedDate);
        term.Notes = payload.Notes ?? null;
    }

    private async applyTermChildren(
        term: ContractTermEntityServer,
        termPayload: ContractDraftTermPayload,
        payload: ContractDraftPayload,
        user: UserInfo,
    ): Promise<void> {
        const removedLines = new Set((payload.RemovedLineIDs ?? []).map((id) => id.toLowerCase()));
        for (const line of [...term.Lines]) {
            if (removedLines.has(line.ID.toLowerCase())) term.RemoveLine(line);
        }
        const linesByID = new Map(term.Lines.map((l) => [l.ID.toLowerCase(), l]));
        for (const linePayload of termPayload.Lines ?? []) {
            const line = linePayload.ID ? linesByID.get(linePayload.ID.toLowerCase()) : undefined;
            const target = line ?? (await term.CreateLine(user));
            target.ProductID = linePayload.ProductID;
            target.LineType = linePayload.LineType as typeof target.LineType;
            target.Quantity = linePayload.Quantity;
            target.ContractedUnitPrice = linePayload.ContractedUnitPrice ?? null;
            target.DiscountPct = linePayload.DiscountPct ?? null;
            target.StartDate = SaveContractOperation.toDate(linePayload.StartDate);
            target.EndDate = SaveContractOperation.toDate(linePayload.EndDate);
            target.SubscriptionTypeID = linePayload.SubscriptionTypeID ?? null;
            target.Description = linePayload.Description ?? null;
        }

        const removedSchedules = new Set((payload.RemovedScheduleIDs ?? []).map((id) => id.toLowerCase()));
        for (const schedule of [...term.Schedules]) {
            if (removedSchedules.has(schedule.ID.toLowerCase())) term.RemoveSchedule(schedule);
        }
        const schedulesByID = new Map(term.Schedules.map((s) => [s.ID.toLowerCase(), s]));
        for (const schedulePayload of termPayload.Schedules ?? []) {
            const schedule = schedulePayload.ID ? schedulesByID.get(schedulePayload.ID.toLowerCase()) : undefined;
            const target = schedule ?? (await term.CreateSchedule(user));
            target.ScheduleType = schedulePayload.ScheduleType as typeof target.ScheduleType;
            target.Frequency = (schedulePayload.Frequency ?? null) as typeof target.Frequency;
            target.AnchorDate = SaveContractOperation.toDate(schedulePayload.AnchorDate);
            target.IsActive = schedulePayload.IsActive ?? true;
            target.Notes = schedulePayload.Notes ?? null;
        }

        const removedCommitments = new Set((payload.RemovedCommitmentIDs ?? []).map((id) => id.toLowerCase()));
        for (const commitment of [...term.Commitments]) {
            if (removedCommitments.has(commitment.ID.toLowerCase())) term.RemoveCommitment(commitment);
        }
        const commitmentsByID = new Map(term.Commitments.map((c) => [c.ID.toLowerCase(), c]));
        for (const commitmentPayload of termPayload.Commitments ?? []) {
            const commitment = commitmentPayload.ID ? commitmentsByID.get(commitmentPayload.ID.toLowerCase()) : undefined;
            const target = commitment ?? (await term.CreateCommitment(user));
            target.CommitmentType = commitmentPayload.CommitmentType as typeof target.CommitmentType;
            target.CommittedAmount = commitmentPayload.CommittedAmount;
            target.ConsumedAmount = commitmentPayload.ConsumedAmount ?? 0;
            target.PeriodStart = SaveContractOperation.toDate(commitmentPayload.PeriodStart);
            target.PeriodEnd = SaveContractOperation.toDate(commitmentPayload.PeriodEnd);
            target.TrueUpPolicy = (commitmentPayload.TrueUpPolicy ?? 'BillShortfall') as typeof target.TrueUpPolicy;
            target.Status = (commitmentPayload.Status ?? 'Open') as typeof target.Status;
        }
    }

    // ── Serialisation back to the client ────────────────────────────────────────────────────────

    private toPayload(contract: ContractEntityServer): ContractDraftPayload {
        return {
            ID: contract.ID,
            ContractNumber: contract.ContractNumber,
            ContractTypeID: contract.ContractTypeID,
            CompanyID: contract.CompanyID,
            CustomerOrganizationID: contract.CustomerOrganizationID,
            CustomerPersonID: contract.CustomerPersonID,
            PrimaryContactPersonID: contract.PrimaryContactPersonID,
            OwnerUserID: contract.OwnerUserID,
            ParentContractID: contract.ParentContractID,
            Status: contract.Status,
            Description: contract.Description,
            EffectiveDate: SaveContractOperation.toISO(contract.EffectiveDate),
            ExecutedDate: SaveContractOperation.toISO(contract.ExecutedDate),
            PricedAt: SaveContractOperation.toISO(contract.PricedAt),
            AutoRenew: contract.AutoRenew,
            CancellationWindowDays: contract.CancellationWindowDays,
            TerminationPolicy: contract.TerminationPolicy,
            ExternalReferenceID: contract.ExternalReferenceID,
            Terms: contract.Terms.map((term) => this.termToPayload(term)),
            RemovedTermIDs: [],
            RemovedLineIDs: [],
            RemovedScheduleIDs: [],
            RemovedCommitmentIDs: [],
        };
    }

    private termToPayload(term: ContractTermEntityServer): ContractDraftTermPayload {
        const lines: ContractDraftLinePayload[] = term.Lines.map((l) => ({
            ID: l.ID,
            ProductID: l.ProductID,
            LineType: l.LineType,
            Quantity: l.Quantity,
            ContractedUnitPrice: l.ContractedUnitPrice,
            DiscountPct: l.DiscountPct,
            StartDate: SaveContractOperation.toISO(l.StartDate),
            EndDate: SaveContractOperation.toISO(l.EndDate),
            SubscriptionTypeID: l.SubscriptionTypeID,
            Description: l.Description,
        }));
        const schedules: ContractDraftSchedulePayload[] = term.Schedules.map((s) => ({
            ID: s.ID,
            ScheduleType: s.ScheduleType,
            Frequency: s.Frequency,
            AnchorDate: SaveContractOperation.toISO(s.AnchorDate),
            IsActive: s.IsActive,
            Notes: s.Notes,
        }));
        const commitments: ContractDraftCommitmentPayload[] = term.Commitments.map((c) => ({
            ID: c.ID,
            CommitmentType: c.CommitmentType,
            CommittedAmount: c.CommittedAmount,
            ConsumedAmount: c.ConsumedAmount,
            PeriodStart: SaveContractOperation.toISO(c.PeriodStart),
            PeriodEnd: SaveContractOperation.toISO(c.PeriodEnd),
            TrueUpPolicy: c.TrueUpPolicy,
            Status: c.Status,
        }));

        return {
            ID: term.ID,
            StartDate: SaveContractOperation.toISO(term.StartDate) ?? '',
            EndDate: SaveContractOperation.toISO(term.EndDate) ?? '',
            Status: term.Status,
            BillingFrequency: term.BillingFrequency,
            CommittedAmount: term.CommittedAmount,
            EscalationPercent: term.EscalationPercent,
            EscalationBasis: term.EscalationBasis,
            MaxEscalationPercent: term.MaxEscalationPercent,
            RenewalNoticeDays: term.RenewalNoticeDays,
            RenewalProbability: term.RenewalProbability,
            PaymentTermsTypeID: term.PaymentTermsTypeID,
            CurrencyID: term.CurrencyID,
            EarlyTerminationDate: SaveContractOperation.toISO(term.EarlyTerminationDate),
            ExecutedDate: SaveContractOperation.toISO(term.ExecutedDate),
            Notes: term.Notes,
            Lines: lines,
            Schedules: schedules,
            Commitments: commitments,
        };
    }

    /** Validation errors, in the shape the client's own validator produces. */
    private issuesFromResult(contract: ContractEntityServer): { Section: string; Field?: string; Message: string }[] {
        const errors = contract.LatestResult?.Errors ?? [];
        return errors.map((e) => ({
            // The server does not know which PANE a field belongs to; the client maps it. 'contract'
            // is the honest default — better a badge on the wrong tab than an error with no home.
            Section: 'contract',
            Field: e?.Source ?? undefined,
            Message: e?.Message ?? String(e),
        }));
    }

    /** ISO date string -> Date. UTC throughout, per the repo convention. */
    private static toDate(value: string | null | undefined): Date | null {
        if (!value) return null;
        const d = new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    /** Date -> ISO date-part, which is what a DATE column means and what a date input reads. */
    private static toISO(value: Date | string | null | undefined): string | null {
        if (!value) return null;
        const d = value instanceof Date ? value : new Date(value);
        return Number.isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadSaveContractOperation(): void {
    /* intentionally empty */
}
