/**
 * @fileoverview The one definition of "this contract has an open processing task".
 *
 * WHY THIS IS A FILE AND NOT TWO INLINE STRINGS. The dashboard's "To process" tile and the All
 * Contracts "Has open task" pill must count the same rows — the tile's entire promise is that
 * clicking it lands on the list it just counted. Written twice they agree until one is edited, and
 * the failure is silent: a tile saying 7 over a list showing 5 reads as a stale page rather than a
 * bug. One exported builder, two callers.
 *
 * ## Why a correlated subquery rather than three reads
 *
 * Tasks live in ANOTHER APP's schema, and `Task Links` carries `EntityID` / `RecordID` while the
 * status and due date live on `Tasks`. There is no single view to filter, so the alternatives are a
 * SQL `EXISTS` inside `ExtraFilter`, or reading task ids into memory and passing `ID IN (…)`. The
 * second is not a worklist filter — an `IN` list has to be capped, and a capped filter quietly hides
 * work, which is the one thing a work queue must not do.
 *
 * `ExtraFilter` is raw SQL appended to the base view's WHERE, so the subquery is legal. MJ screens
 * it with a keyword denylist (`DatabaseProviderBase.ValidateUserProvidedSQLClause`) covering
 * `insert / update / delete / exec / drop / -- / union / xp_ / ; / waitfor` — `SELECT`, `EXISTS` and
 * `JOIN` are not on it. (The stricter validator that DOES block `EXISTS` governs aggregate
 * expressions, not filters.) The base view is selected without an alias, so `vwContracts.ID` is a
 * legal correlated reference.
 *
 * ## ⚠ Two consequences worth knowing before this pattern spreads
 *
 * **It bypasses MJ's permission and RLS model for Tasks.** MJ applies entity permissions and row
 * filters to the entity being *read* — here, Contracts. Nothing checks the reader against Tasks, so
 * a user with no access to Tasks still gets a count shaped by them. That is an acceptable trade for
 * a COUNT of the reader's own contracts, and it is the reason not to extend this to reading task
 * rows: the moment task content reaches the screen, it must go through a Tasks read.
 *
 * **Nothing here is hardcoded except the type code.** Schema and view names come from MJ's metadata
 * rather than string literals, so an app that is not installed produces `null` (and a dashboard tile
 * that renders "—") instead of SQL naming a schema that does not exist.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Metadata, type IMetadataProvider } from '@memberjunction/core';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from './entity-names';
import { ScopedRunView } from './provider';

/**
 * The task type sales raises on Close-Won for finance to work through.
 *
 * Addressed by CODE, not by name or id: the row is seeded by bizapps-sales
 * (`metadata/task-types/.task-types.json`) and `CloseWonTaskService` writes this exact code, so the
 * code is the contract between the two apps. A display name is content and can be edited; an id
 * differs per database.
 */
export const MJC_TASK_CODE_CONTRACT_PROCESSING = 'CONTRACT_PROCESSING';

/** Statuses that mean the task is done with, in the Tasks app's own vocabulary. */
const CLOSED_TASK_STATUSES = ['Completed', 'Cancelled'] as const;

/** The two filter fragments the dashboard and the pill share. */
export interface MJCOpenTaskFilters {
    /** Contracts with at least one open Contract Processing task. */
    HasOpenTask: string;
    /** The same, narrowed to tasks whose due date has passed. */
    HasOverdueTask: string;
}

/**
 * Build the shared fragments, or `null` when they cannot be built.
 *
 * `null` is returned — rather than a filter that matches nothing — when bizapps-tasks is not
 * installed, or when the CONTRACT_PROCESSING type row is missing. The distinction matters at the
 * call site: a filter matching nothing renders a confident `0`, while `null` lets the caller render
 * "—". "We cannot tell" and "there is no work" are different answers, and only one of them is safe
 * to show a person whose job is working the queue.
 */
export async function BuildOpenTaskFilters(
    provider?: IMetadataProvider | null,
): Promise<MJCOpenTaskFilters | null> {
    const entities = (provider ?? Metadata.Provider)?.Entities ?? [];
    const contracts = entities.find((e) => e.Name === MJC_ENTITIES.Contract);
    const taskLinks = entities.find((e) => e.Name === MJC_FOREIGN_ENTITIES.TaskLink);
    const tasks = entities.find((e) => e.Name === MJC_FOREIGN_ENTITIES.Task);

    // Any of these missing means the Tasks app is not on this host. Not an error — contracts is
    // installable without it, and the tile simply has nothing to say.
    if (!contracts?.ID || !taskLinks?.BaseView || !tasks?.BaseView) return null;

    const typeID = await resolveContractProcessingTypeID(provider);
    if (!typeID) return null;

    const linkView = qualified(taskLinks.SchemaName, taskLinks.BaseView);
    const taskView = qualified(tasks.SchemaName, tasks.BaseView);
    const contractView = qualified(contracts.SchemaName, contracts.BaseView);
    const closed = CLOSED_TASK_STATUSES.map((s) => `'${s}'`).join(',');

    /**
     * `RecordID` is nvarchar — it holds a primary key of any shape, since a link can point at any
     * entity — so the contract's uniqueidentifier is CAST rather than compared directly. Without the
     * cast SQL Server applies its own conversion and the comparison becomes non-sargable at best.
     */
    const exists = (extra: string): string =>
        `EXISTS (SELECT 1 FROM ${linkView} tl ` +
        `INNER JOIN ${taskView} t ON t.ID = tl.TaskID ` +
        `WHERE tl.RecordID = CAST(${contractView}.ID AS nvarchar(255)) ` +
        `AND tl.EntityID = '${contracts.ID}' ` +
        `AND t.TypeID = '${typeID}' ` +
        `AND t.Status NOT IN (${closed})${extra})`;

    return {
        HasOpenTask: exists(''),
        // Date, not datetime: "overdue" is a whole-day judgement, and comparing against the current
        // instant would call a task due later today overdue all morning.
        HasOverdueTask: exists(' AND t.DueAt < CAST(GETUTCDATE() AS date)'),
    };
}

/**
 * Code → id, once.
 *
 * The Tasks base view exposes the type's NAME but not its CODE, so the id cannot be reached by
 * filtering Tasks directly — it takes a read against Task Types. Comparing on the name instead would
 * make an editable label load-bearing.
 */
async function resolveContractProcessingTypeID(provider?: IMetadataProvider | null): Promise<string | null> {
    try {
        const result = await ScopedRunView(provider).RunView<{ ID: string }>({
            EntityName: MJC_FOREIGN_ENTITIES.TaskType,
            ExtraFilter: `Code = '${MJC_TASK_CODE_CONTRACT_PROCESSING}'`,
            ResultType: 'simple',
            Fields: ['ID'],
            MaxRows: 1,
        });
        return result?.Success ? (result.Results?.[0]?.ID ?? null) : null;
    } catch {
        // The entity exists but could not be read — same answer as "not installed" from here, and the
        // caller renders "—" either way.
        return null;
    }
}

/** `[schema].[view]`, with the schema omitted when metadata does not carry one. */
function qualified(schema: string | null | undefined, view: string): string {
    return schema ? `[${schema}].[${view}]` : `[${view}]`;
}
