/**
 * Tier 1 — the pure presentation helpers.
 *
 * These replace this package's `echo "No tests configured yet"` stub, which passed vacuously and
 * therefore proved nothing. The cases below are chosen for what can actually be WRONG rather than
 * for line coverage: the null-versus-zero distinctions, the rounding, and the malformed input that
 * would otherwise take a page down.
 */
import { describe, it, expect } from 'vitest';
import {
    statusTone,
    eventTone,
    eventLabel,
    eventDetail,
    percentToFraction,
    fractionToPercent,
    termFill,
    coverageSubtotal,
} from '../contract-format';

describe('statusTone', () => {
    it('reads Active and Completed as success', () => {
        expect(statusTone('Active')).toBe('ok');
        expect(statusTone('Completed')).toBe('ok');
    });

    it('reads Expired, Superseded and Skipped as WARNINGS, not errors', () => {
        // Each is an outcome someone should look at, not a fault. Colouring them red would cry wolf
        // on every contract that ever ends normally.
        expect(statusTone('Expired')).toBe('warn');
        expect(statusTone('Superseded')).toBe('warn');
        expect(statusTone('Skipped')).toBe('warn');
    });

    it('reads Terminated, Failed and Rejected as errors — each was cut short or refused', () => {
        expect(statusTone('Terminated')).toBe('err');
        expect(statusTone('Failed')).toBe('err');
        expect(statusTone('Rejected')).toBe('err');
    });

    it('covers the billing-event and amendment vocabularies too, since they share the badge', () => {
        expect(statusTone('Generated')).toBe('ok');
        expect(statusTone('Applied')).toBe('ok');
        expect(statusTone('Scheduled')).toBe('info');
        expect(statusTone('Open')).toBe('info');
    });

    it('returns an EMPTY class for null and the unrecognised, not "info"', () => {
        // This is a CSS class name: '' is the neutral pill. Defaulting to 'info' would colour an
        // unknown state blue as though it meant something.
        expect(statusTone(null)).toBe('');
        expect(statusTone(undefined)).toBe('');
        expect(statusTone('SomethingNew')).toBe('');
    });
});

describe('eventLabel', () => {
    it('turns the stored vocabulary into sentences', () => {
        expect(eventLabel('TermRenewed')).toBe('Term renewed');
        expect(eventLabel('BillingEventFailed')).toBe('Billing event failed');
        expect(eventLabel('ContractSuperseded')).toBe('Superseded by a replacement');
    });

    it('falls back to the RAW value for an unmapped type, so it looks wrong rather than invisible', () => {
        // The vocabulary is CHECK-constrained, so this can only happen when someone widens the
        // constraint and forgets the label. An empty string would hide that; the raw enum shows it.
        expect(eventLabel('SomeNewType')).toBe('SomeNewType');
    });
});

describe('eventTone', () => {
    it('colours failure and rejection as errors', () => {
        expect(eventTone('BillingEventFailed')).toBe('err');
        expect(eventTone('SignatureRejected')).toBe('err');
        expect(eventTone('ContractTerminated')).toBe('err');
    });

    it('colours the good transitions as success', () => {
        expect(eventTone('TermActivated')).toBe('ok');
        expect(eventTone('TermRenewed')).toBe('ok');
        expect(eventTone('ContractExecuted')).toBe('ok');
    });

    it('colours endings that are nobody-s fault as warnings', () => {
        expect(eventTone('ContractExpired')).toBe('warn');
        expect(eventTone('ContractSuperseded')).toBe('warn');
    });
});

describe('eventDetail', () => {
    it('pulls the readable parts of a renewal payload, in order', () => {
        const phrases = eventDetail(
            JSON.stringify({
                renewalOfTermNumber: 2,
                appliedEscalationPercent: 0.04,
                escalationWasClamped: false,
                lineCount: 3,
            }),
        );
        expect(phrases).toEqual(['renewed from term 2', '+4.00% applied', '3 line(s) carried forward']);
    });

    it('says so when an escalation was capped', () => {
        const phrases = eventDetail(JSON.stringify({ appliedEscalationPercent: 0.05, escalationWasClamped: true }));
        expect(phrases).toContain('capped at the negotiated ceiling');
    });

    it('formats the percentage to two decimals rather than dumping the fraction', () => {
        expect(eventDetail(JSON.stringify({ appliedEscalationPercent: 0.0667 }))).toEqual(['+6.67% applied']);
    });

    it('omits a zero retained-count instead of saying "0 retained"', () => {
        const phrases = eventDetail(JSON.stringify({ billingEventsCancelled: 2, billingEventsRetained: 0 }));
        expect(phrases).toEqual(['2 future billing event(s) cancelled']);
    });

    it('includes a non-zero retained count, because that number changes what the reader concludes', () => {
        const phrases = eventDetail(JSON.stringify({ billingEventsCancelled: 2, billingEventsRetained: 2 }));
        expect(phrases).toEqual(['2 future billing event(s) cancelled', '2 retained']);
    });

    it('returns nothing for null, empty, malformed JSON and non-objects — and never throws', () => {
        // A history entry with no detail is a far smaller problem than a History tab that will not
        // render, so bad payload data degrades rather than propagates.
        expect(eventDetail(null)).toEqual([]);
        expect(eventDetail('')).toEqual([]);
        expect(eventDetail('{not json')).toEqual([]);
        expect(eventDetail('null')).toEqual([]);
        expect(eventDetail('"a string"')).toEqual([]);
        expect(eventDetail('42')).toEqual([]);
    });

    it('ignores keys of the wrong type rather than rendering "term undefined"', () => {
        expect(eventDetail(JSON.stringify({ termNumber: 'three', reason: 42 }))).toEqual([]);
    });

    it('skips a blank reason', () => {
        expect(eventDetail(JSON.stringify({ reason: '   ' }))).toEqual([]);
    });
});

describe('percentToFraction / fractionToPercent', () => {
    it('converts a typed percentage to the fraction the column stores', () => {
        expect(percentToFraction(4)).toBe(0.04);
        expect(percentToFraction(4.5)).toBe(0.045);
        expect(percentToFraction(100)).toBe(1);
    });

    it('rounds to the column scale so 4.5 stores exactly, not as 0.045000000000000005', () => {
        // The naive 4.5 / 100 is not exactly 0.045 in binary floating point. DECIMAL(7,4) has four
        // decimal places, so rounding there is both correct and what the column will hold anyway.
        expect(percentToFraction(4.5)).toBe(0.045);
        expect(Object.is(percentToFraction(4.5), 0.045)).toBe(true);
    });

    it('keeps null as null — blank is an absence, zero is a claim', () => {
        // Writing 0 for "they left it blank" asserts THERE IS NO ESCALATION, which is a different
        // fact about a contract than "nobody said".
        expect(percentToFraction(null)).toBeNull();
        expect(percentToFraction(undefined)).toBeNull();
    });

    it('refuses NaN and Infinity rather than storing them', () => {
        expect(percentToFraction(Number.NaN)).toBeNull();
        expect(percentToFraction(Number.POSITIVE_INFINITY)).toBeNull();
    });

    it('round-trips a stored fraction back to a typed percentage', () => {
        expect(fractionToPercent(0.04)).toBe(4);
        expect(fractionToPercent(0.0667)).toBe(6.67);
        expect(fractionToPercent(null)).toBeNull();
    });

    it('survives a there-and-back trip without drifting', () => {
        for (const pct of [0, 1, 3, 4.5, 6.67, 12.25, 100]) {
            expect(fractionToPercent(percentToFraction(pct))).toBe(pct);
        }
    });
});

describe('termFill', () => {
    it('distinguishes the live term from the finished and the not-yet-started', () => {
        expect(termFill('Active')).toBe('now');
        expect(termFill('Completed')).toBe('done');
        expect(termFill('Pending')).toBe('next');
        expect(termFill(null)).toBe('next');
    });

    it('draws Terminated the same as Completed, because the BAR answers "is it over?"', () => {
        // Why it ended is carried by the status text on the bar and by the badge tone, which do
        // distinguish them. Only these three fill classes have styling; inventing a fourth here
        // would render an unstyled bar.
        expect(termFill('Terminated')).toBe('done');
    });
});

describe('coverageSubtotal', () => {
    const line = (price: number | null, qty: number | null = 1, disc: number | null = null) => ({
        Quantity: qty,
        ContractedUnitPrice: price,
        DiscountPercent: disc,
    });

    it('adds up quantity times price', () => {
        expect(coverageSubtotal([line(1000, 2), line(250, 1)])).toBe(2250);
    });

    it('applies a discount as a percentage', () => {
        expect(coverageSubtotal([line(1000, 1, 10)])).toBe(900);
    });

    it('EXCLUDES catalog-priced lines rather than counting them as zero', () => {
        // A null price means "resolve from the catalog". Treating it as zero would understate the
        // coverage and show a total that is confidently wrong — worse than showing an incomplete one
        // and saying how many were left out, which is what the UI does.
        expect(coverageSubtotal([line(1000), line(null), line(500)])).toBe(1500);
    });

    it('treats a missing quantity as one, since a line covers something by definition', () => {
        expect(coverageSubtotal([line(1000, null)])).toBe(1000);
    });

    it('rounds to cents at the point the number is decided', () => {
        // 250.50 less 3% is 242.985 — a third decimal place that must not reach a currency display.
        expect(coverageSubtotal([line(250.5, 1, 3)])).toBe(242.99);
    });

    it('is zero for no lines and for lines that are all catalog-priced', () => {
        expect(coverageSubtotal([])).toBe(0);
        expect(coverageSubtotal([line(null), line(null)])).toBe(0);
    });
});
