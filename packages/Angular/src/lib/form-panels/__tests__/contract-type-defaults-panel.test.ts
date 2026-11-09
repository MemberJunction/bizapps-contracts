/**
 * Unit tests for `ContractType.DefaultAutoRenew` three-state helpers and
 * `MJCContractTypeDefaultsPanel` registration (#149).
 */
import { describe, expect, it } from 'vitest';
import {
    DEFAULT_AUTO_RENEW_OPTIONS,
    FormatDefaultAutoRenew,
    ParseDefaultAutoRenewOption,
    ToDefaultAutoRenewOption,
} from '../contract-type-defaults';

describe('ToDefaultAutoRenewOption / ParseDefaultAutoRenewOption (#149)', () => {
    it('maps null and undefined to "none" and round-trips back to null', () => {
        expect(ToDefaultAutoRenewOption(null)).toBe('none');
        expect(ToDefaultAutoRenewOption(undefined)).toBe('none');
        expect(ParseDefaultAutoRenewOption('none')).toBeNull();
        expect(ParseDefaultAutoRenewOption(null)).toBeNull();
        expect(ParseDefaultAutoRenewOption(undefined)).toBeNull();
    });

    it('maps true to "yes" and round-trips back to true', () => {
        expect(ToDefaultAutoRenewOption(true)).toBe('yes');
        expect(ParseDefaultAutoRenewOption('yes')).toBe(true);
    });

    it('maps false to "no" and round-trips back to false', () => {
        expect(ToDefaultAutoRenewOption(false)).toBe('no');
        expect(ParseDefaultAutoRenewOption('no')).toBe(false);
    });

    it('FormatDefaultAutoRenew renders distinct labels for null, true, and false', () => {
        const nullLabel = FormatDefaultAutoRenew(null);
        const trueLabel = FormatDefaultAutoRenew(true);
        const falseLabel = FormatDefaultAutoRenew(false);

        expect(nullLabel).toContain('No default');
        expect(trueLabel).toContain('Yes');
        expect(falseLabel).toContain('No —');
        expect(new Set([nullLabel, trueLabel, falseLabel]).size).toBe(3);
        expect(DEFAULT_AUTO_RENEW_OPTIONS.map((o) => o.value)).toEqual(['none', 'yes', 'no']);
    });
});

describe('MJCContractTypeDefaultsPanel wiring (#149)', () => {
    it('replaces the generated defaultContractTerms section on ContractType and uses a 3-state select', async () => {
        const { readFile } = await import('node:fs/promises');
        const source = await readFile(new URL('../contract-type.panels.ts', import.meta.url), 'utf8');

        expect(source).toContain("key: 'contracts:contract-type-defaults'");
        expect(source).toContain('entity: MJC_ENTITIES.ContractType');
        expect(source).toContain("replacesSectionKey: 'defaultContractTerms'");
        expect(source).toContain('<select');
        expect(source).toContain('(ngModelChange)="OnAutoRenewChange($event)"');
        expect(source).toContain('FieldName="DefaultRenewalNoticeDays"');
        expect(source).toContain('FieldName="DefaultCancellationWindowDays"');
        expect(source).toContain('FieldName="DefaultAnnualIncreasePercent"');
    });
});
