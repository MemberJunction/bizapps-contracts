/**
 * Unit tests for the contract-grid preset state machine (#155).
 *
 * Covers all three arrival timings:
 *   1. `ApplyPreset` before `ngOnInit` (`Pills` empty) parks the preset ID and flushes once
 *      synchronous pills are populated;
 *   2. `ApplyPreset('has-open-task')` stays parked across synchronous `ngOnInit` and flushes when
 *      `addOpenTaskPill` appends `'has-open-task'`;
 *   3. `ApplyPreset` on an already-initialized (cached) page applies immediately.
 */
import { describe, expect, it } from 'vitest';
import { ApplyGridPreset, FlushPendingGridPreset, type GridPillIdentity } from '../grid-preset';

const SYNC_ALL_CONTRACTS_PILLS: readonly GridPillIdentity[] = [
    { Id: 'open' },
    { Id: 'active' },
    { Id: 'executed' },
    { Id: 'modified' },
    { Id: 'special-terms' },
    { Id: 'all' },
];

const RENEWALS_PILLS: readonly GridPillIdentity[] = [
    { Id: 'next120' },
    { Id: 'notice-open' },
    { Id: 'notice-missed' },
    { Id: 'auto' },
    { Id: 'cancellation' },
];

describe('ApplyGridPreset & FlushPendingGridPreset (#155)', () => {
    it('parks a preset received before ngOnInit (Pills = []) and flushes it once synchronous pills exist', () => {
        // 1. Section creates the page and calls ApplyPreset('notice-open') before ngOnInit runs.
        const beforeInit = ApplyGridPreset([], null, 'notice-open');
        expect(beforeInit).toEqual({
            activePillId: null,
            pendingPresetId: 'notice-open',
            applied: false,
        });

        // 2. ngOnInit populates Pills, defaults ActivePillId to Pills[0].Id ('next120'), then flushes.
        const afterInit = FlushPendingGridPreset(RENEWALS_PILLS, 'next120', beforeInit.pendingPresetId);
        expect(afterInit).toEqual({
            activePillId: 'notice-open',
            pendingPresetId: null,
            applied: true,
        });
    });

    it('keeps "has-open-task" parked through synchronous ngOnInit and flushes when addOpenTaskPill appends it', () => {
        // 1. Dashboard "To process" tile navigates with preset 'has-open-task' before ngOnInit.
        const beforeInit = ApplyGridPreset([], null, 'has-open-task');
        expect(beforeInit).toEqual({
            activePillId: null,
            pendingPresetId: 'has-open-task',
            applied: false,
        });

        // 2. Synchronous ngOnInit populates standard pills (without 'has-open-task') and attempts flush.
        const syncFlush = FlushPendingGridPreset(SYNC_ALL_CONTRACTS_PILLS, 'open', beforeInit.pendingPresetId);
        expect(syncFlush).toEqual({
            activePillId: 'open',
            pendingPresetId: 'has-open-task',
            applied: false,
        });

        // 3. Async addOpenTaskPill appends 'has-open-task' and flushes the parked preset.
        const withTaskPill: readonly GridPillIdentity[] = [
            ...SYNC_ALL_CONTRACTS_PILLS,
            { Id: 'has-open-task' },
        ];
        const asyncFlush = FlushPendingGridPreset(
            withTaskPill,
            syncFlush.activePillId,
            syncFlush.pendingPresetId,
        );
        expect(asyncFlush).toEqual({
            activePillId: 'has-open-task',
            pendingPresetId: null,
            applied: true,
        });
    });

    it('applies immediately on a cached page whose Pills are already populated, without toggling off an active pill', () => {
        const applied = ApplyGridPreset(SYNC_ALL_CONTRACTS_PILLS, 'open', 'special-terms');
        expect(applied).toEqual({
            activePillId: 'special-terms',
            pendingPresetId: null,
            applied: true,
        });

        // Re-applying the already-active pill keeps it active (unlike SelectPill which toggles).
        const reapplied = ApplyGridPreset(SYNC_ALL_CONTRACTS_PILLS, 'special-terms', 'special-terms');
        expect(reapplied).toEqual({
            activePillId: 'special-terms',
            pendingPresetId: null,
            applied: true,
        });

        // Passing null clears the active pill and any parked preset.
        const cleared = ApplyGridPreset(SYNC_ALL_CONTRACTS_PILLS, 'special-terms', null);
        expect(cleared).toEqual({
            activePillId: null,
            pendingPresetId: null,
            applied: true,
        });
    });

    it('returns applied: false when FlushPendingGridPreset is called with no pending preset', () => {
        expect(FlushPendingGridPreset(RENEWALS_PILLS, 'next120', null)).toEqual({
            activePillId: 'next120',
            pendingPresetId: null,
            applied: false,
        });
    });
});
