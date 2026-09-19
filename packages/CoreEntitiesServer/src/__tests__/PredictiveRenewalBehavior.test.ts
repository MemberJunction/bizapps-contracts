import { describe, expect, it } from 'vitest';
import type { ContractEntity } from '@mj-biz-apps/contracts-entities';
import { ComputePredictiveRenewalRiskBand, ContractEntityServer } from '../ContractEntityServer.js';

describe('ComputePredictiveRenewalRiskBand', () => {
    it('returns null for null, undefined, or NaN', () => {
        expect(ComputePredictiveRenewalRiskBand(null)).toBeNull();
        expect(ComputePredictiveRenewalRiskBand(undefined)).toBeNull();
        expect(ComputePredictiveRenewalRiskBand(NaN)).toBeNull();
    });

    it('classifies non-renewal risk < 0.20 as Low', () => {
        expect(ComputePredictiveRenewalRiskBand(0)).toBe('Low');
        expect(ComputePredictiveRenewalRiskBand(0.05)).toBe('Low');
        expect(ComputePredictiveRenewalRiskBand(0.1999)).toBe('Low');
    });

    it('classifies non-renewal risk between 0.20 and 0.50 as Medium', () => {
        expect(ComputePredictiveRenewalRiskBand(0.20)).toBe('Medium');
        expect(ComputePredictiveRenewalRiskBand(0.35)).toBe('Medium');
        expect(ComputePredictiveRenewalRiskBand(0.4999)).toBe('Medium');
    });

    it('classifies non-renewal risk between 0.50 and 0.80 as High', () => {
        expect(ComputePredictiveRenewalRiskBand(0.50)).toBe('High');
        expect(ComputePredictiveRenewalRiskBand(0.65)).toBe('High');
        expect(ComputePredictiveRenewalRiskBand(0.7999)).toBe('High');
    });

    it('classifies non-renewal risk >= 0.80 as Critical', () => {
        expect(ComputePredictiveRenewalRiskBand(0.80)).toBe('Critical');
        expect(ComputePredictiveRenewalRiskBand(0.95)).toBe('Critical');
        expect(ComputePredictiveRenewalRiskBand(1.0)).toBe('Critical');
    });
});

describe('ContractEntityServer.syncPredictiveRenewalFieldsPreSave', () => {
    it('synchronizes risk band when risk probability is set and risk band is missing', () => {
        const mockContract: {
            PredictedNonRenewalRisk: number | null;
            PredictedRenewalRiskBand: ContractEntity['PredictedRenewalRiskBand'];
            GetFieldByName: (name: string) => { Dirty: boolean } | null;
        } = {
            PredictedNonRenewalRisk: 0.65,
            PredictedRenewalRiskBand: null,
            GetFieldByName: () => ({ Dirty: false }),
        };

        ContractEntityServer.prototype.syncPredictiveRenewalFieldsPreSave.call(mockContract);
        expect(mockContract.PredictedRenewalRiskBand).toBe('High');
    });

    it('synchronizes risk band when risk probability is dirty even if risk band already exists', () => {
        const mockContract: {
            PredictedNonRenewalRisk: number | null;
            PredictedRenewalRiskBand: ContractEntity['PredictedRenewalRiskBand'];
            GetFieldByName: (name: string) => { Dirty: boolean } | null;
        } = {
            PredictedNonRenewalRisk: 0.85,
            PredictedRenewalRiskBand: 'Low',
            GetFieldByName: () => ({ Dirty: true }),
        };

        ContractEntityServer.prototype.syncPredictiveRenewalFieldsPreSave.call(mockContract);
        expect(mockContract.PredictedRenewalRiskBand).toBe('Critical');
    });

    it('clears risk band when risk probability is cleared and dirty', () => {
        const mockContract: {
            PredictedNonRenewalRisk: number | null;
            PredictedRenewalRiskBand: ContractEntity['PredictedRenewalRiskBand'];
            GetFieldByName: (name: string) => { Dirty: boolean } | null;
        } = {
            PredictedNonRenewalRisk: null,
            PredictedRenewalRiskBand: 'High',
            GetFieldByName: () => ({ Dirty: true }),
        };

        ContractEntityServer.prototype.syncPredictiveRenewalFieldsPreSave.call(mockContract);
        expect(mockContract.PredictedRenewalRiskBand).toBeNull();
    });

    it('leaves risk band alone when risk probability is not dirty and risk band is present', () => {
        const mockContract: {
            PredictedNonRenewalRisk: number | null;
            PredictedRenewalRiskBand: ContractEntity['PredictedRenewalRiskBand'];
            GetFieldByName: (name: string) => { Dirty: boolean } | null;
        } = {
            PredictedNonRenewalRisk: 0.15,
            PredictedRenewalRiskBand: 'High',
            GetFieldByName: () => ({ Dirty: false }),
        };

        ContractEntityServer.prototype.syncPredictiveRenewalFieldsPreSave.call(mockContract);
        expect(mockContract.PredictedRenewalRiskBand).toBe('High');
    });
});
