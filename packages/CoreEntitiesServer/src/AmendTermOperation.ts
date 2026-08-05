/**
 * @fileoverview `Contracts.AmendTerm` — change a LIVE term, mid-flight.
 *
 * AN AMENDMENT CHANGES A RUNNING TERM; A RENEWAL STARTS A NEW ONE. The schema calls conflating the
 * two "the single most common contract-model mistake", and the distinction is the whole reason this
 * operation is separate from `RenewTerm`: a customer who adds fifty seats in month four has not
 * started a new agreement, and forcing that through a renewal would restart their term, re-date
 * their renewal notice and re-baseline their escalation.
 *
 * ── CO-TERMING, WHICH IS THE POINT ──────────────────────────────────────────────────────────────
 *
 * Master plan §5.4, precisely: adding a product mid-term creates a `ContractAmendment` plus a
 * `ContractLine` whose `StartDate` is the amendment date and whose `EndDate` is the TERM's end date.
 * The stub period prorates on the next billing event, so the new product lands on the SAME renewal
 * date as everything else the customer already has.
 *
 * That is the capability standalone subscriptions structurally cannot provide — each one carries its
 * own clock, so a customer accumulates a drawer of unrelated renewal dates — and it is why the
 * contract owns the calendar.
 *
 * ── WHAT THIS OPERATION DELIBERATELY REFUSES ────────────────────────────────────────────────────
 *
 * `ContractAmendment` records THAT a term changed, when, of what kind, and who approved it. It does
 * not record WHAT the change was beyond a description — there are no columns for "which line" or "to
 * what value". So `AddProduct` and `Coterm` can be applied from their input, and `ChangeQuantity`,
 * `ChangePrice` and `PartialTerminate` cannot: the operation would have to guess which line the
 * amendment meant.
 *
 * Those are refused with the reason rather than half-implemented. A silent partial application is
 * exactly the failure this app cannot afford — it produces an amendment marked Applied against a
 * term nothing actually changed on. Logged answer-first in plans/QUESTIONS.md (Q2).
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseRemotableOperation,
    type DatabaseProviderBase,
    type IMetadataProvider,
    Metadata,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type { mjBizAppsContractsContractEventEntity } from '@mj-biz-apps/contracts-entities';
import { ContractAmendmentEntityServer } from './ContractAmendmentEntityServer.js';
import type { ContractTermEntityServer } from './ContractTermEntityServer.js';

const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_AMENDMENT = 'MJ_BizApps_Contracts: Contract Amendments';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';

/** The kinds this operation can actually apply. See the module note for why the others are refused. */
const APPLICABLE_TYPES: readonly string[] = ['AddProduct', 'Coterm'];

export interface AmendTermInput {
    ContractTermID: string;
    /** `AddProduct` or `Coterm`. Others are refused with the reason. */
    AmendmentType: string;
    /** Why. Recorded on the amendment and on the lifecycle event. */
    Description: string;
    /** ISO date (YYYY-MM-DD). Defaults to today. The co-term stub starts here. */
    EffectiveDate?: string;
    /** The product being added mid-term. */
    ProductID?: string;
    Quantity?: number;
    ContractedUnitPrice?: number | null;
    /** Required when the added line is a Subscription — orders cannot materialise one without it. */
    SubscriptionTypeID?: string | null;
    LineType?: string;
    /** The approval task, where one was required. */
    ApprovalTaskID?: string | null;
    /** Compute and report, write nothing. */
    PreviewOnly?: boolean;
}

export interface AmendTermOutput {
    Success: boolean;
    Message?: string;
    Preview: boolean;
    ContractTermID?: string;
    AmendmentID?: string;
    AmendmentNumber?: number;
    /** The co-term stub that would be, or was, created. */
    LineID?: string;
    /** ISO dates (YYYY-MM-DD) — the stub's window, ending with the TERM. */
    StubStart?: string;
    StubEnd?: string;
    /** How many days of the term the stub covers, which is what the proration is of. */
    StubDays?: number;
}

@RegisterClass(BaseRemotableOperation, 'Contracts.AmendTerm')
export class AmendTermOperation extends BaseRemotableOperation<AmendTermInput, AmendTermOutput> {
    public OperationKey = 'Contracts.AmendTerm';

    protected async InternalExecute(
        input: AmendTermInput,
        provider: IMetadataProvider,
        user: UserInfo,
    ): Promise<AmendTermOutput> {
        const preview = !!input?.PreviewOnly;
        if (!input?.ContractTermID) {
            return { Success: false, Preview: preview, Message: 'ContractTermID is required.' };
        }
        if (!input.Description?.trim()) {
            // An amendment with no description is a change to an agreement that nobody can explain
            // later, which is the same failure as a Failed billing event with no reason.
            return { Success: false, Preview: preview, Message: 'An amendment must say what changed and why.' };
        }
        if (!APPLICABLE_TYPES.includes(input.AmendmentType)) {
            return {
                Success: false,
                Preview: preview,
                Message:
                    `This operation can apply ${APPLICABLE_TYPES.join(' and ')} amendments. ` +
                    `'${input.AmendmentType}' records WHAT KIND of change happened, but ContractAmendment ` +
                    'carries no columns saying which line changed or to what value — so applying it would ' +
                    'mean guessing, and a wrong guess produces an amendment marked Applied against a term ' +
                    'nothing actually changed on. Raised as Q2 for Andrew.',
            };
        }
        if (!input.ProductID) {
            return { Success: false, Preview: preview, Message: 'Adding a product mid-term needs the product.' };
        }

        const md = new Metadata();
        const term = await md.GetEntityObject<ContractTermEntityServer>(E_TERM, user);
        if (!(await term.Load(input.ContractTermID))) {
            return { Success: false, Preview: preview, Message: `Contract term ${input.ContractTermID} was not found.` };
        }
        // The entity enforces this too, on every writer. Checking here as well means the CALLER gets
        // the reason before anything is attempted, rather than as a save failure halfway through.
        if ((term.Status as unknown as string) !== 'Active') {
            return {
                Success: false,
                Preview: preview,
                Message:
                    `An amendment changes a term that is RUNNING, and term ${term.TermNumber} is ` +
                    `${term.Status}. ` +
                    (term.Status === 'Pending' || term.Status === 'PendingSignature'
                        ? 'That term has not started, so change the term itself.'
                        : 'That term has ended — renew into a new term instead of rewriting a settled period.'),
            };
        }

        const effective = AmendTermOperation.asDate(input.EffectiveDate) ?? new Date();
        const termStart = term.StartDate instanceof Date ? term.StartDate : new Date(term.StartDate);
        const termEnd = term.EndDate instanceof Date ? term.EndDate : new Date(term.EndDate);

        if (effective.getTime() < termStart.getTime() || effective.getTime() > termEnd.getTime()) {
            return {
                Success: false,
                Preview: preview,
                Message:
                    `The amendment date ${AmendTermOperation.iso(effective)} falls outside term ` +
                    `${term.TermNumber} (${AmendTermOperation.iso(termStart)} to ${AmendTermOperation.iso(termEnd)}). ` +
                    'A mid-term change has to happen during the term.',
            };
        }

        // THE STUB: from the amendment date to the TERM's end, so the new product lands on the same
        // renewal date as everything else the customer already has.
        const stubStart = AmendTermOperation.iso(effective)!;
        const stubEnd = AmendTermOperation.iso(termEnd)!;
        const stubDays = Math.round((termEnd.getTime() - effective.getTime()) / 86_400_000) + 1;

        if (preview) {
            return {
                Success: true,
                Preview: true,
                ContractTermID: term.ID,
                StubStart: stubStart,
                StubEnd: stubEnd,
                StubDays: stubDays,
                Message:
                    `Adds coverage from ${stubStart} to ${stubEnd} — ${stubDays} day${stubDays === 1 ? '' : 's'}, ` +
                    'co-termed with the rest of the agreement and prorated on the next billing event.',
            };
        }

        const db = Metadata.Provider as unknown as DatabaseProviderBase;
        try {
            await db.BeginTransaction();

            // The amendment first: it is the record that the change was authorised, and the line is
            // what the change DID. Writing the line without the amendment would leave coverage
            // nobody can account for.
            const amendment = await md.GetEntityObject<ContractAmendmentEntityServer>(E_AMENDMENT, user);
            amendment.NewRecord();
            amendment.ContractTermID = term.ID;
            amendment.EffectiveDate = effective;
            amendment.AmendmentType = input.AmendmentType as typeof amendment.AmendmentType;
            amendment.Description = input.Description.trim();
            amendment.ApprovalTaskID = input.ApprovalTaskID ?? null;
            // Applied, not Draft: this operation IS the application. An amendment left Draft after
            // its line exists would say the change is still pending when it has already happened.
            amendment.Status = input.ApprovalTaskID ? 'Applied' : 'Applied';
            if (!(await amendment.Save())) {
                throw new Error(`Could not record the amendment: ${amendment.LatestResult?.CompleteMessage ?? 'unknown error'}`);
            }

            // The co-term stub, through the TERM's own collection so the term's rules run on it.
            await term.LoadChildren(user);
            const line = await term.CreateLine(user);
            line.ProductID = input.ProductID;
            line.LineType = (input.LineType ?? 'Subscription') as typeof line.LineType;
            line.Quantity = input.Quantity ?? 1;
            line.ContractedUnitPrice = input.ContractedUnitPrice ?? null;
            line.SubscriptionTypeID = input.SubscriptionTypeID ?? null;
            line.StartDate = effective;
            line.EndDate = termEnd;
            line.Description = input.Description.trim();

            if (!(await term.Save())) {
                throw new Error(`Could not add the co-term line: ${term.LatestResult?.CompleteMessage ?? 'unknown error'}`);
            }

            const log = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
            log.NewRecord();
            log.ContractID = term.ContractID;
            log.ContractTermID = term.ID;
            log.EventType = 'AmendmentApplied';
            log.EventDate = new Date();
            log.PerformedByUserID = user?.ID ?? null;
            log.Payload = JSON.stringify({
                AmendmentID: amendment.ID,
                AmendmentNumber: amendment.AmendmentNumber,
                AmendmentType: input.AmendmentType,
                ProductID: input.ProductID,
                StubStart: stubStart,
                StubEnd: stubEnd,
                StubDays: stubDays,
            });
            if (!(await log.Save())) {
                throw new Error(`Could not write the amendment audit event: ${log.LatestResult?.CompleteMessage ?? 'unknown error'}`);
            }

            await db.CommitTransaction();
            return {
                Success: true,
                Preview: false,
                ContractTermID: term.ID,
                AmendmentID: amendment.ID,
                AmendmentNumber: amendment.AmendmentNumber,
                LineID: line.ID,
                StubStart: stubStart,
                StubEnd: stubEnd,
                StubDays: stubDays,
                Message: `Amendment ${amendment.AmendmentNumber} applied — coverage co-termed to ${stubEnd}.`,
            };
        } catch (e) {
            await db.RollbackTransaction();
            return { Success: false, Preview: false, Message: e instanceof Error ? e.message : String(e) };
        }
    }

    private static asDate(value: string | null | undefined): Date | null {
        if (!value) return null;
        const d = new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    private static iso(value: Date | null): string | null {
        return value ? value.toISOString().slice(0, 10) : null;
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadAmendTermOperation(): void {
    /* intentionally empty */
}
