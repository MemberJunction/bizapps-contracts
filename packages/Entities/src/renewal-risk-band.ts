/**
 * @fileoverview `Contract.PredictedRenewalRiskBand` from `Contract.PredictedNonRenewalRisk` (issue #125).
 *
 * The band is a stored column whose description (V202609202354) defines it as derived from the
 * predicted probability: Low under 20%, Medium 20–50%, High 50–80%, Critical 80% or more. The
 * scorer that writes the probability returns no band (MJ's `MLInferenceResultPayload` has `score`,
 * `class`, `drivers` and `scoredAt`), and `class` is the model's label, not one of these four values,
 * so the record process cannot map one. `ContractEntityServer.Save()` derives it here instead, so
 * every path that writes a risk (the record process's write-back, an import, a script) gets the
 * matching band.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/** The four values `CK_Contract_PredictedRenewalRiskBand` allows. */
export type RenewalRiskBand = 'Low' | 'Medium' | 'High' | 'Critical';

/**
 * The band for a predicted non-renewal probability, or null when there is no probability.
 *
 * Rounded to the column's four decimal places (`DECIMAL(5,4)`) first, so the band always agrees
 * with the value the database stores: a raw 0.79996 is stored as 0.8000 and must read Critical.
 * Each lower bound is inclusive, as the column description states for Critical.
 */
export function RenewalRiskBandFor(risk: number | null | undefined): RenewalRiskBand | null {
    if (risk === null || risk === undefined) return null;
    const value = Number(risk);
    if (!Number.isFinite(value)) return null;
    const stored = Math.round(value * 10000) / 10000;
    if (stored >= 0.8) return 'Critical';
    if (stored >= 0.5) return 'High';
    if (stored >= 0.2) return 'Medium';
    return 'Low';
}
