/**
 * @fileoverview Pure presentation helpers for the contracts UI — no Angular, no MJ, no I/O.
 *
 * These were methods on the section component. They are extracted here because they are ordinary
 * functions of their arguments: given a status they return a tone, given a payload they return
 * phrases. Nothing about them needs a component instance, and keeping them inside one made a
 * 1,700-line class longer for no benefit.
 *
 * This is decomposition, not a test seam. The distinction matters: a test seam is production code
 * added or widened *so that a test can reach it*, which the test protocol forbids. Nothing here is
 * new or more visible than it was — the same logic, moved to where a function that takes a string
 * and returns a string belongs. That it is now trivially unit-testable is a consequence of the code
 * being better shaped, not the reason for the shape.
 *
 * @module @mj-biz-apps/contracts-ng
 */

/**
 * A status's visual tone — MJ's four semantic status colours, or `''` for no badge styling.
 *
 * The empty default is load-bearing: it is a CSS class name, and `.badge` with no modifier is the
 * neutral pill. Returning `'info'` for anything unrecognised would colour unknown states blue as
 * though they meant something.
 */
export type Tone = 'ok' | 'warn' | 'err' | 'info' | '';

/**
 * The tone for a status from ANY of this app's status columns — contract, term, billing event and
 * amendment all render through the same badge, so one map covers all four vocabularies.
 *
 * `Expired`, `Superseded` and `Skipped` are WARNINGS rather than errors: each is an outcome someone
 * should look at, not a fault. `Terminated`, `Failed` and `Rejected` are errors because each means
 * something was cut short or refused.
 */
export function statusTone(status: string | null | undefined): Tone {
    switch (status) {
        case 'Active':
        case 'Generated':
        case 'Completed':
        case 'Applied':
            return 'ok';
        case 'PendingSignature':
        case 'Pending':
        case 'Scheduled':
        case 'Open':
            return 'info';
        case 'Failed':
        case 'Terminated':
        case 'Rejected':
            return 'err';
        case 'Expired':
        case 'Superseded':
        case 'Skipped':
            return 'warn';
        default:
            return '';
    }
}

/** The tone for a lifecycle event type. Failure and rejection read as errors; endings as warnings. */
export function eventTone(eventType: string): Tone {
    if (/Failed|Rejected/.test(eventType)) return 'err';
    if (/Terminated/.test(eventType)) return 'err';
    if (/Activated|Executed|Renewed/.test(eventType)) return 'ok';
    if (/Expired|Superseded/.test(eventType)) return 'warn';
    return 'info';
}

/**
 * A human sentence for an event type.
 *
 * The vocabulary is closed by a CHECK constraint, so this map is exhaustive by construction — but it
 * still falls back to the raw value rather than an empty string, because a new type added to the
 * CHECK and not added here should look wrong, not invisible.
 */
const EVENT_LABELS: Readonly<Record<string, string>> = {
    ContractCreated: 'Contract created',
    ContractExecuted: 'Contract executed',
    ContractTerminated: 'Contract terminated',
    ContractSuperseded: 'Superseded by a replacement',
    ContractExpired: 'Contract expired',
    SentForSignature: 'Sent for signature',
    SignatureRejected: 'Signature rejected',
    TermActivated: 'Term activated',
    TermRenewed: 'Term renewed',
    TermCompleted: 'Term completed',
    TermTerminated: 'Term terminated',
    AmendmentApplied: 'Amendment applied',
    BillingEventGenerated: 'Billing event generated',
    BillingEventFailed: 'Billing event failed',
};

export function eventLabel(eventType: string): string {
    return EVENT_LABELS[eventType] ?? eventType;
}

/**
 * The parts of an event payload worth reading, as short phrases.
 *
 * A WHITELIST, deliberately, rather than a dump of every key: an audit trail people actually read
 * beats one that is technically complete. Malformed JSON yields no phrases rather than throwing —
 * a history entry with no detail is a much smaller problem than a history tab that will not render.
 */
export function eventDetail(payload: string | null | undefined): string[] {
    if (!payload) return [];
    let p: Record<string, unknown>;
    try {
        p = JSON.parse(payload) as Record<string, unknown>;
    } catch {
        return [];
    }
    if (!p || typeof p !== 'object') return [];

    const out: string[] = [];
    if (typeof p.reason === 'string' && p.reason.trim()) out.push(p.reason);
    if (typeof p.termNumber === 'number') out.push(`term ${p.termNumber}`);
    if (typeof p.renewalOfTermNumber === 'number') out.push(`renewed from term ${p.renewalOfTermNumber}`);
    if (typeof p.appliedEscalationPercent === 'number') out.push(`+${(p.appliedEscalationPercent * 100).toFixed(2)}% applied`);
    if (p.escalationWasClamped === true) out.push('capped at the negotiated ceiling');
    if (typeof p.occurrences === 'number') out.push(`${p.occurrences} billing event(s) scheduled`);
    if (typeof p.lineCount === 'number') out.push(`${p.lineCount} line(s) carried forward`);
    if (typeof p.billingEventsCancelled === 'number') out.push(`${p.billingEventsCancelled} future billing event(s) cancelled`);
    if (typeof p.billingEventsRetained === 'number' && p.billingEventsRetained > 0) out.push(`${p.billingEventsRetained} retained`);
    if (typeof p.effectiveDate === 'string') out.push(`effective ${p.effectiveDate}`);
    return out;
}

/**
 * Convert a percentage as typed by a person (4.5 meaning 4.5%) to the fraction the schema stores
 * (0.045). Every percent column in this schema is `DECIMAL(7,4)` holding a fraction.
 *
 * Returns null for null/undefined/empty and for values that are not finite numbers — writing 0 for
 * "they left it blank" would be a claim (no escalation) rather than an absence, and those are
 * different facts about a contract.
 */
export function percentToFraction(value: number | null | undefined): number | null {
    if (value === null || value === undefined) return null;
    if (!Number.isFinite(value)) return null;
    // Rounded to the column's scale so 4.5 stores as exactly 0.045 rather than 0.045000000000000005.
    return Math.round((value / 100) * 10000) / 10000;
}

/** The inverse, for showing a stored fraction in a field a person types percentages into. */
export function fractionToPercent(value: number | null | undefined): number | null {
    if (value === null || value === undefined) return null;
    if (!Number.isFinite(value)) return null;
    return Math.round(value * 100 * 100) / 100;
}

/**
 * The fill class for a term's timeline bar: `now` for the live term, `done` for one that has ended
 * either way, `next` for one that has not started.
 *
 * Separate from {@link statusTone} on purpose even though the inputs overlap: a timeline bar and a
 * status pill are different visual languages, and collapsing them would mean a change to one
 * silently changing the other.
 *
 * Completed and Terminated deliberately share `done`. The bar answers "is this period over?", and to
 * that question they are the same; WHY it ended is carried by the status text on the bar and by its
 * badge tone, which do distinguish them.
 */
export function termFill(status: string | null | undefined): 'now' | 'done' | 'next' {
    if (status === 'Active') return 'now';
    if (status === 'Completed' || status === 'Terminated') return 'done';
    return 'next';
}

/**
 * The priced subtotal of a set of coverage lines.
 *
 * Lines with no unit price are EXCLUDED rather than counted as zero: a null price means "resolve
 * from the catalog", so including it as zero would understate the coverage and present a total that
 * is confidently wrong. The caller is expected to say how many were left out.
 */
export function coverageSubtotal(
    lines: readonly { Quantity: number | null; ContractedUnitPrice: number | null; DiscountPercent: number | null }[],
): number {
    const total = lines.reduce((sum, l) => {
        if (l.ContractedUnitPrice === null || l.ContractedUnitPrice === undefined) return sum;
        const gross = l.ContractedUnitPrice * (l.Quantity ?? 1);
        return sum + gross * (1 - (l.DiscountPercent ?? 0) / 100);
    }, 0);
    // Money rounds to cents at the point it is decided, not where it is displayed.
    return Math.round((total + Number.EPSILON) * 100) / 100;
}
