/**
 * Pure agent-context and client-tool builders for the Contracts dashboard and worklist grids (#154).
 *
 * Kept free of `@angular/*` imports so unit tests can verify context shaping and tool handler
 * behavior directly in Node.
 */

export interface DashboardAgentTileSummary {
    Id: string;
    Label: string;
    Count: number | null;
    Detail: string | null;
    Tone: string;
    GoTo: { PageId: string; Preset?: string } | null;
}

export interface DashboardAgentContextInput {
    SelectedCompanyIDs: readonly string[];
    AvailableCompanies: ReadonlyArray<{ ID: string; Name: string }>;
    Tiles: readonly DashboardAgentTileSummary[];
    CountError: string | null;
    GridExtraFilter: string;
}

export interface GridAgentPillSummary {
    Id: string;
    Label: string;
    Filter: string;
    Count?: number;
    Hint?: string;
}

export interface GridAgentContextInput {
    PageKey: string;
    ActivePillId: string | null;
    PendingPresetId: string | null;
    SearchText: string;
    PageFilter: string;
    ExtraFilter: string;
    OrderBy: string;
    Pills: readonly GridAgentPillSummary[];
}

export interface AgentClientToolDefinition {
    Name: string;
    Description: string;
    ParameterSchema: Record<string, unknown>;
    Handler: (params: Record<string, unknown>) => Promise<unknown>;
}

/**
 * Build the structured `SetAgentContext` payload for `MJCContractsDashboardPageComponent` (#154).
 */
export function BuildDashboardAgentContext(input: DashboardAgentContextInput): Record<string, unknown> {
    return {
        Surface: 'contracts-dashboard',
        SelectedCompanyIDs: [...input.SelectedCompanyIDs],
        AvailableCompanies: input.AvailableCompanies.map((c) => ({ ID: c.ID, Name: c.Name })),
        Tiles: input.Tiles.map((t) => ({
            Id: t.Id,
            Label: t.Label,
            Count: t.Count,
            Detail: t.Detail,
            Tone: t.Tone,
            TargetPageId: t.GoTo?.PageId ?? null,
            TargetPreset: t.GoTo?.Preset ?? null,
        })),
        CountError: input.CountError,
        GridExtraFilter: input.GridExtraFilter,
    };
}

/**
 * Build the structured `SetAgentContext` payload for `MJCContractGridPageBase` subclasses (#154).
 */
export function BuildGridAgentContext(input: GridAgentContextInput): Record<string, unknown> {
    const activePill = input.Pills.find((p) => p.Id === input.ActivePillId) ?? null;
    return {
        Surface: input.PageKey,
        ActivePillId: input.ActivePillId,
        ActivePillLabel: activePill?.Label ?? null,
        PendingPresetId: input.PendingPresetId,
        SearchText: input.SearchText,
        PageFilter: input.PageFilter,
        ExtraFilter: input.ExtraFilter,
        OrderBy: input.OrderBy,
        Pills: input.Pills.map((p) => ({
            Id: p.Id,
            Label: p.Label,
            Count: p.Count ?? null,
            Hint: p.Hint ?? null,
        })),
    };
}
