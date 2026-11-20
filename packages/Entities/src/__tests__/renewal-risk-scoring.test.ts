/**
 * The renewal-risk scoring bench in `demo-data/` against the rules it depends on (issues #125, #126).
 *
 *   · #125: MJ's write-back reads target fields only from `OutputMapping.fields`, and the scorer's
 *     result has no `band`. The band comes from `RenewalRiskBandFor`, which the server subclass
 *     applies on save, using the thresholds the column description states.
 *   · #126: the training pipeline selects the features the shipped models were fitted on, which
 *     each model records in `Lineage.featureSteps`.
 *
 * No database: these read the committed JSON and call the pure function.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { RenewalRiskBandFor } from '../renewal-risk-band.js';

const DEMO = fileURLToPath(new URL('../../../../demo-data/', import.meta.url));

type SyncRecord = { fields: Record<string, unknown>; primaryKey: { ID: string } };
const readRecords = (rel: string): SyncRecord[] => JSON.parse(readFileSync(`${DEMO}${rel}`, 'utf8')) as SyncRecord[];

describe('RenewalRiskBandFor (#125)', () => {
    it('returns null when there is no probability', () => {
        expect(RenewalRiskBandFor(null)).toBeNull();
        expect(RenewalRiskBandFor(undefined)).toBeNull();
        expect(RenewalRiskBandFor(Number.NaN)).toBeNull();
    });

    it('bands at 20%, 50% and 80%, each lower bound inclusive', () => {
        expect(RenewalRiskBandFor(0)).toBe('Low');
        expect(RenewalRiskBandFor(0.1999)).toBe('Low');
        expect(RenewalRiskBandFor(0.2)).toBe('Medium');
        expect(RenewalRiskBandFor(0.4999)).toBe('Medium');
        expect(RenewalRiskBandFor(0.5)).toBe('High');
        expect(RenewalRiskBandFor(0.7999)).toBe('High');
        expect(RenewalRiskBandFor(0.8)).toBe('Critical');
        expect(RenewalRiskBandFor(1)).toBe('Critical');
    });

    it('bands the value the DECIMAL(5,4) column stores, not the raw score', () => {
        expect(RenewalRiskBandFor(0.79996)).toBe('Critical');
        expect(RenewalRiskBandFor(0.19994)).toBe('Low');
    });
});

describe('renewal-risk record process OutputMapping (#125)', () => {
    const [process] = readRecords('record-processes/.record-processes.json');
    const mapping = JSON.parse(String(process.fields.OutputMapping)) as Record<string, unknown>;

    it('puts the write-back fields under `fields`, the only key MJ write-back reads', () => {
        expect(Object.keys(mapping)).toEqual(['fields']);
        expect(mapping.fields).toEqual({
            PredictedNonRenewalRisk: '$.score',
            PredictedRenewalScoredAt: '$.scoredAt',
        });
    });

    it('stays Disabled with its schedule off until a model has an artifact', () => {
        expect(process.fields.Status).toBe('Disabled');
        expect(process.fields.ScheduleEnabled).toBe(false);
    });
});

describe('renewal-risk training pipeline (#126)', () => {
    const [pipeline] = readRecords('ml-training-pipelines/.ml-training-pipelines.json');
    const models = readRecords('ml-models/.ml-models.json');

    it('has the feature steps every shipped model was fitted with', () => {
        const steps = JSON.parse(String(pipeline.fields.FeatureSteps));
        expect(models.length).toBeGreaterThan(0);
        for (const model of models) {
            expect(model.fields.PipelineID).toBe(pipeline.primaryKey.ID);
            const lineage = JSON.parse(String(model.fields.Lineage)) as { featureSteps: unknown };
            expect(steps).toEqual(lineage.featureSteps);
        }
    });

    it('selects every feature in each model FeatureSchema', () => {
        const steps = JSON.parse(String(pipeline.fields.FeatureSteps)) as { Steps: Array<{ Id: string; Columns?: string[] }> };
        const selected = steps.Steps.find((s) => s.Id === 'select-features')?.Columns ?? [];
        for (const model of models) {
            const schema = JSON.parse(String(model.fields.FeatureSchema)) as Array<{ Name: string }>;
            expect([...selected].sort()).toEqual(schema.map((f) => f.Name).sort());
        }
    });
});
