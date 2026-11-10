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
 * `ExtraFilter` is raw SQL appended to the base view's WHERE, so the subquery is legal. From MJ 6.2
 * the GraphQL boundary parses it (`ClientClauseScreen`, called from
 * `ResolverBase.assertClientClauseUsesEntityBaseViews`): every FROM item must be an entity base view
 * the reader can read, and a table-valued function is refused. Both views here are base views, and
 * "today" is a scalar call (`BUSINESS_TODAY_SQL`), which the screen does not refuse. The base view
 * is selected without an alias, so `vwContracts.ID` is a legal correlated reference.
 *
 * ## ⚠ Two consequences worth knowing before this pattern spreads
 *
 * **It reads Tasks outside a Tasks RunView.** MJ applies row filters to the entity being *read* —
 * here, Contracts — and a subquery on a base view cannot apply Tasks' own. MJ 6.2's screen closes
 * that gap by refusal: the reader needs read permission on Task Links and Tasks, with no row filter
 * and no denied fields, or the whole filter is refused. That is acceptable for a COUNT of the
 * reader's own contracts, and it is the reason not to extend this to reading task rows: the moment
 * task content reaches the screen, it must go through a Tasks read.
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
import { BUSINESS_TODAY_SQL } from './business-day';

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
        /*
         * Date, not datetime: "overdue" is a whole-day judgement, and comparing against the current
         * instant would call a task due later today overdue all morning.
         *
         * And the BUSINESS day, not the server's UTC day (bc-aidp-next-golive#168). `Task.DueAt` is
         * written as UTC MIDNIGHT of a calendar day — bizapps-sales asserts it carries no time of
         * day, precisely so "due today" cannot depend on the reader's zone — so this is a comparison
         * between calendar days and the only open question is which day is today. On the UTC day
         * every task due today read as overdue from 6 PM Central, in the same dashboard tile whose
         * sibling counts come from `vwContracts` on `bt.Today`.
         *
         * `DueAt` is the one column here with no business-day day-count to filter on: it belongs to
         * another app's view and is reached through the `EXISTS` above. So "today" is resolved in
         * SQL, by bizapps-common's `fnBusinessDayOf`, whose zone comes from the same `fnBusinessToday()`
         * the view joins — see `BUSINESS_TODAY_SQL` for why not on the client, and why not a subquery.
         */
        HasOverdueTask: exists(` AND t.DueAt < ${BUSINESS_TODAY_SQL}`),
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
