/**
 * Pure three-state helpers for `ContractType.DefaultAutoRenew` (#149).
 *
 * Kept free of `@angular/*` imports so unit tests can exercise all three states (`null`, `true`,
 * `false`) directly in Node without triggering `@angular/common` JIT initialization.
 */

export type DefaultAutoRenewChoice = 'none' | 'yes' | 'no';

export interface DefaultAutoRenewOption {
    value: DefaultAutoRenewChoice;
    label: string;
}

export const DEFAULT_AUTO_RENEW_OPTIONS: readonly DefaultAutoRenewOption[] = [
    { value: 'none', label: 'No default — leave contract unchanged' },
    { value: 'yes', label: 'Yes — auto-renews by default' },
    { value: 'no', label: 'No — does not auto-renew by default' },
] as const;

/**
 * Map a nullable boolean `DefaultAutoRenew` value to its three-state select key.
 */
export function ToDefaultAutoRenewOption(value: boolean | null | undefined): DefaultAutoRenewChoice {
    if (value === true) return 'yes';
    if (value === false) return 'no';
    return 'none';
}

/**
 * Map a three-state select key back to the nullable boolean stored on `ContractType.DefaultAutoRenew`.
 */
export function ParseDefaultAutoRenewOption(choice: string | null | undefined): boolean | null {
    if (choice === 'yes') return true;
    if (choice === 'no') return false;
    return null;
}

/**
 * Read-mode label for `ContractType.DefaultAutoRenew` that distinguishes `null` from `false`.
 */
export function FormatDefaultAutoRenew(value: boolean | null | undefined): string {
    const key = ToDefaultAutoRenewOption(value);
    return DEFAULT_AUTO_RENEW_OPTIONS.find((o) => o.value === key)?.label ?? DEFAULT_AUTO_RENEW_OPTIONS[0].label;
}
