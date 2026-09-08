/**
 * The committed CTR-WORLD portfolio. Set by `contracts-world.CW1`; later bundles in the same
 * process can read it without reloading.
 */
export interface WorldContract {
    ID: string;
    ContractNumber: string;
}

export interface WorldState {
    TemplateID: string;
    Contracts: Record<string, WorldContract>;
}

let cached: WorldState | null = null;

export function SetWorld(world: WorldState): void {
    cached = world;
}

export function World(): WorldState {
    if (!cached) {
        throw new Error('CTR-WORLD is not loaded. Run the contracts-world bundle first.');
    }
    return cached;
}

export function PeekWorld(): WorldState | null {
    return cached;
}
