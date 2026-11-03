/**
 * Pure state-machine helpers for contract-grid filter-pill presets (#155).
 *
 * Kept free of Angular imports so unit tests can exercise all three arrival timings directly:
 *   1. `ApplyPreset` called before `ngOnInit` (when `Pills` is still `[]`), flushed once synchronous
 *      pills are initialized;
 *   2. `ApplyPreset('has-open-task')` remaining parked across synchronous `ngOnInit` and flushing
 *      only when the async `addOpenTaskPill` read appends `'has-open-task'`;
 *   3. `ApplyPreset` called on an already-initialized (cached) page, applying immediately.
 */

export interface GridPillIdentity {
    readonly Id: string;
}

export interface GridPresetState {
    readonly activePillId: string | null;
    readonly pendingPresetId: string | null;
    /** True when the preset matched an available pill (or cleared the pill) and should trigger a rebuild. */
    readonly applied: boolean;
}

/**
 * Apply a host-requested preset pill ID against the currently available `pills` (#155).
 */
export function ApplyGridPreset(
    pills: readonly GridPillIdentity[],
    currentActivePillId: string | null,
    pillId: string | null,
): GridPresetState {
    if (pillId && !pills.some((p) => p.Id === pillId)) {
        return {
            activePillId: currentActivePillId,
            pendingPresetId: pillId,
            applied: false,
        };
    }
    return {
        activePillId: pillId,
        pendingPresetId: null,
        applied: true,
    };
}

/**
 * Flush a parked `pendingPresetId` once `pills` has been populated or extended (#155).
 */
export function FlushPendingGridPreset(
    pills: readonly GridPillIdentity[],
    currentActivePillId: string | null,
    pendingPresetId: string | null,
): GridPresetState {
    if (!pendingPresetId) {
        return {
            activePillId: currentActivePillId,
            pendingPresetId: null,
            applied: false,
        };
    }
    return ApplyGridPreset(pills, currentActivePillId, pendingPresetId);
}
