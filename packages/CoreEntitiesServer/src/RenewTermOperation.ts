/**
 * @fileoverview `Contracts.RenewTerm` — carry an agreement into its next period.
 *
 * THIS IS THE OPERATION THE WHOLE SCHEMA EXISTS FOR. A contract that cannot renew is a document;
 * a contract that renews is a revenue stream. Everything else here — terms, escalation, the line
 * chain — is machinery in service of getting this one transition right.
 *
 * WHAT RENEWAL ACTUALLY IS. A new `ContractTerm`, pointed back at its predecessor through
 * `RenewalOfTermID`, carrying the predecessor's coverage forward with prices escalated by the
 * agreed percentage. The old term is `Completed`, not deleted — the chain is the history, and a
 * renewal that overwrote the prior term would destroy the only record of what was previously agreed.
 *
 * THE ESCALATION CEILING IS ENFORCED, NOT ASSUMED. `MaxEscalationPercent` is the negotiated cap.
 * `ContractTermEntityServer.Save()` refuses a term that exceeds it, and this operation clamps to it
 * before saving rather than proposing a rejected number. An uncapped "then-current list price" bump
 * is the single most disputed clause in a B2B renewal — the one we must never get wrong by accident.
 *
 * PREVIEW BEFORE COMMIT. `PreviewOnly` runs the entire computation and returns exactly what would be
 * created without writing anything. Renewal is the moment a human wants to see the numbers before
 * agreeing to them, and a preview computed by a second copy of the rules would eventually disagree
 * with the real thing. One code path, two exits.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseRemotableOperation,
    type DatabaseProviderBase,
    type IMetadataProvider,
    type IRunViewProvider,
    Metadata,
    RunView,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type {
    mjBizAppsContractsContractTermEntity,
    mjBizAppsContractsContractLineEntity,
    mjBizAppsContractsContractEventEntity,
} from '@mj-biz-apps/contracts-entities';

const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_LINE = 'MJ_BizApps_Contracts: Contract Lines';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';

export interface RenewTermInput {
    /** The term being renewed — becomes the new term's `RenewalOfTermID`. */
    ContractTermID: string;
    /** Compute and return, write nothing. The numbers a human approves before committing. */
    PreviewOnly?: boolean;
    /** Override the term's own escalation for this renewal. Still clamped to the cap. */
    EscalationPercentOverride?: number;
    /** Length of the new term. Defaults to the length of the term being renewed. */
    TermMonths?: number;
}

export interface RenewedLine {
    Description: string;
    PreviousUnitPrice: number | null;
    NewUnitPrice: number | null;
}

export interface RenewTermOutput {
    Success: boolean;
    Message?: string;
    Preview: boolean;
    /** Undefined on a preview — nothing was created. */
    NewContractTermID?: string;
    NewTermNumber?: number;
    StartDate?: string;
    EndDate?: string;
    /** The percentage actually applied, after clamping. A fraction: 0.05 = 5%. */
    AppliedEscalationPercent?: number;
    /** True when the requested escalation was reduced to the term's negotiated ceiling. */
    EscalationWasClamped?: boolean;
    Lines?: RenewedLine[];
}

@RegisterClass(BaseRemotableOperation, 'Contracts.RenewTerm')
export class RenewTermOperation extends BaseRemotableOperation<RenewTermInput, RenewTermOutput> {
    public OperationKey = 'Contracts.RenewTerm';

    protected async InternalExecute(
        input: RenewTermInput,
        provider: IMetadataProvider,
        user: UserInfo,
    ): Promise<RenewTermOutput> {
        const preview = input?.PreviewOnly === true;

        if (!input?.ContractTermID || !/^[0-9a-f-]{36}$/i.test(input.ContractTermID)) {
            return { Success: false, Preview: preview, Message: 'A valid ContractTermID is required.' };
        }

        const md = new Metadata();
        const prior = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        if (!(await prior.Load(input.ContractTermID))) {
            return { Success: false, Preview: preview, Message: `Contract term ${input.ContractTermID} was not found.` };
        }

        const priorStatus = prior.Status as unknown as string;
        if (priorStatus === 'Terminated') {
            return { Success: false, Preview: preview, Message: 'A terminated term cannot be renewed.' };
        }
        if (priorStatus === 'Pending' || priorStatus === 'PendingSignature') {
            return {
                Success: false,
                Preview: preview,
                Message: `Term ${prior.TermNumber} has not started yet (${priorStatus}) — activate it before renewing it.`,
            };
        }

        const rv = new RunView(provider as unknown as IRunViewProvider);

        // Refuse a second renewal of the same term. Without this, two clicks produce two successor
        // terms with overlapping dates, both billing — a double-charge that looks like valid data.
        const existing = await rv.RunView<{ ID: string; TermNumber: number }>(
            { EntityName: E_TERM, Fields: ['ID', 'TermNumber'], ExtraFilter: `RenewalOfTermID='${prior.ID}'`, ResultType: 'simple' },
            user,
        );
        if (!existing?.Success) {
            return { Success: false, Preview: preview, Message: `Could not check for an existing renewal: ${existing?.ErrorMessage ?? 'unknown error'}` };
        }
        if ((existing.Results?.length ?? 0) > 0) {
            return {
                Success: false,
                Preview: preview,
                Message: `Term ${prior.TermNumber} has already been renewed by term ${existing.Results?.[0]?.TermNumber}.`,
            };
        }

        // ---- The computation. Identical on both paths; only the exit differs. -------------------

        const requested = input.EscalationPercentOverride ?? prior.EscalationPercent ?? 0;
        const cap = prior.MaxEscalationPercent;
        const clamped = cap !== null && cap !== undefined && requested > cap;
        const applied = clamped ? cap : requested;

        const start = addDays(prior.EndDate, 1);
        const months = input.TermMonths ?? monthsBetween(prior.StartDate, prior.EndDate);
        const end = addDays(addMonths(start, months), -1);

        const priorLines = await rv.RunView<mjBizAppsContractsContractLineEntity>(
            { EntityName: E_LINE, ExtraFilter: `ContractTermID='${prior.ID}'`, OrderBy: 'DisplayOrder', ResultType: 'entity_object' },
            user,
        );
        if (!priorLines?.Success) {
            return { Success: false, Preview: preview, Message: `Could not read the term's coverage: ${priorLines?.ErrorMessage ?? 'unknown error'}` };
        }
        const source = (priorLines.Results ?? []) as mjBizAppsContractsContractLineEntity[];

        const escalate = (p: number | null | undefined): number | null =>
            p === null || p === undefined ? null : round2(p * (1 + applied));

        const lines: RenewedLine[] = source.map((l) => ({
            Description: l.Description ?? '(no description)',
            PreviousUnitPrice: l.ContractedUnitPrice ?? null,
            NewUnitPrice: escalate(l.ContractedUnitPrice),
        }));

        const summary =
            `Term ${(prior.TermNumber ?? 0) + 1}: ${fmt(start)} – ${fmt(end)}, ` +
            `${lines.length} line(s) at ${(applied * 100).toFixed(2)}%` +
            (clamped ? ` (reduced from ${(requested * 100).toFixed(2)}% by the term's cap)` : '');

        if (preview) {
            return {
                Success: true,
                Preview: true,
                Message: `Preview — ${summary}. Nothing was written.`,
                NewTermNumber: (prior.TermNumber ?? 0) + 1,
                StartDate: fmt(start),
                EndDate: fmt(end),
                AppliedEscalationPercent: applied,
                EscalationWasClamped: clamped,
                Lines: lines,
            };
        }

        // ---- Commit. One transaction: the new term, every line, the prior term's close, the log. --

        const db = provider as unknown as DatabaseProviderBase;
        try {
            await db.BeginTransaction();

            const next = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
            next.NewRecord();
            next.ContractID = prior.ContractID;
            next.RenewalOfTermID = prior.ID;
            next.StartDate = start;
            next.EndDate = end;
            next.Status = 'Pending'; // Deliberately NOT Active — activation is its own reviewed step.
            // The negotiated shape carries forward: cadence, escalation and its ceiling, notice
            // period, payment terms, currency. `AutoRenew` is deliberately absent — it lives on the
            // Contract, not the term, because it is a property of the agreement rather than a period.
            next.BillingFrequency = prior.BillingFrequency;
            next.BillingAnchorMonth = prior.BillingAnchorMonth;
            next.BillingAnchorDay = prior.BillingAnchorDay;
            next.EscalationPercent = prior.EscalationPercent;
            next.EscalationBasis = prior.EscalationBasis;
            next.MaxEscalationPercent = prior.MaxEscalationPercent;
            next.RenewalNoticeDays = prior.RenewalNoticeDays;
            next.PaymentTermsTypeID = prior.PaymentTermsTypeID;
            next.CurrencyID = prior.CurrencyID;
            // The committed amount escalates with the prices it commits to.
            next.CommittedAmount = prior.CommittedAmount === null || prior.CommittedAmount === undefined
                ? prior.CommittedAmount
                : round2(prior.CommittedAmount * (1 + applied));
            // TermNumber is derived by ContractTermEntityServer — never supplied here.
            if (!(await next.Save())) {
                await db.RollbackTransaction();
                return { Success: false, Preview: false, Message: `Could not create the renewal term: ${next.LatestResult?.CompleteMessage ?? 'unknown error'}` };
            }

            for (const l of source) {
                const copy = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINE, user);
                copy.NewRecord();
                copy.ContractTermID = next.ID;
                copy.DisplayOrder = l.DisplayOrder;
                copy.Description = l.Description;
                copy.LineType = l.LineType;
                copy.ProductID = l.ProductID;
                copy.SubscriptionTypeID = l.SubscriptionTypeID;
                copy.Quantity = l.Quantity;
                copy.ContractedUnitPrice = escalate(l.ContractedUnitPrice);
                copy.DiscountPct = l.DiscountPct;
                // Line dates are NOT copied. They are a window INSIDE the old term, so carrying them
                // verbatim would date the new term's coverage to a period that has already elapsed.
                // Null means "the whole term", which is what a renewed line means by default; a line
                // that genuinely needs a narrower window is set deliberately by a human afterwards.
                //
                // `SubscriptionID` is likewise not carried: it points at the live orders-side
                // subscription created for the PRIOR period. The renewal's subscription is created
                // when the renewal is activated and billed, not inherited from its predecessor.
                if (!(await copy.Save())) {
                    await db.RollbackTransaction();
                    return { Success: false, Preview: false, Message: `Could not carry line ${l.DisplayOrder} forward: ${copy.LatestResult?.CompleteMessage ?? 'unknown error'}` };
                }
            }

            // The prior term is finished, not deleted — the chain IS the history.
            if ((prior.Status as unknown as string) === 'Active') {
                prior.Status = 'Completed';
                if (!(await prior.Save())) {
                    await db.RollbackTransaction();
                    return { Success: false, Preview: false, Message: `Could not close the prior term: ${prior.LatestResult?.CompleteMessage ?? 'unknown error'}` };
                }
            }

            const log = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
            log.NewRecord();
            log.ContractID = prior.ContractID;
            log.ContractTermID = next.ID;
            log.EventType = 'TermRenewed';
            log.EventDate = new Date();
            log.PerformedByUserID = user.ID;
            log.Payload = JSON.stringify({
                renewalOfTermID: prior.ID,
                renewalOfTermNumber: prior.TermNumber,
                appliedEscalationPercent: applied,
                requestedEscalationPercent: requested,
                escalationWasClamped: clamped,
                lineCount: lines.length,
            });
            if (!(await log.Save())) {
                await db.RollbackTransaction();
                return { Success: false, Preview: false, Message: `Could not write the lifecycle event: ${log.LatestResult?.CompleteMessage ?? 'unknown error'}` };
            }

            await db.CommitTransaction();
            return {
                Success: true,
                Preview: false,
                Message: `Renewed — ${summary}.`,
                NewContractTermID: next.ID,
                NewTermNumber: next.TermNumber ?? undefined,
                StartDate: fmt(start),
                EndDate: fmt(end),
                AppliedEscalationPercent: applied,
                EscalationWasClamped: clamped,
                Lines: lines,
            };
        } catch (e) {
            await db.RollbackTransaction();
            return { Success: false, Preview: false, Message: `Renewal failed and was rolled back: ${e instanceof Error ? e.message : String(e)}` };
        }
    }
}

function addDays(d: Date, n: number): Date {
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + n));
}

/** Month arithmetic that clamps to the target month's last day instead of rolling over into the next. */
function addMonths(d: Date, n: number): Date {
    const target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + n, 1));
    const lastOfMonth = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
    target.setUTCDate(Math.min(d.getUTCDate(), lastOfMonth));
    return target;
}

/** Whole months in `[start, end]`, floored at 1 — a term is never zero months long. */
function monthsBetween(start: Date, end: Date): number {
    const months = (end.getUTCFullYear() - start.getUTCFullYear()) * 12 + (end.getUTCMonth() - start.getUTCMonth());
    return Math.max(1, end.getUTCDate() >= start.getUTCDate() ? months + 1 : months);
}

/** Money rounds to cents at the point it is decided, not at the point it is displayed. */
function round2(n: number): number {
    return Math.round((n + Number.EPSILON) * 100) / 100;
}

function fmt(d: Date): string {
    return d.toISOString().slice(0, 10);
}

/** Tree-shaking anchor. */
export function LoadRenewTermOperation(): void {
    /* intentionally empty */
}
