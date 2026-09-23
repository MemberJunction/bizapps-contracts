/**
 * The boundary between the UI and the four DATE columns on Contract — reading, writing and RENDERING.
 *
 * `ExecutedDate`, `EffectiveDate`, `EndDate` and `TerminatedDate` are SQL `DATE` columns: calendar
 * days with no time and no zone. The driver hands one back as a `Date` at UTC midnight, so it is
 * read from its UTC parts and written back as UTC midnight — anything local-parts-shaped files the
 * day into the previous one for every user west of Greenwich (bc-aidp-next-golive#168).
 *
 * These are free functions rather than methods on `MJCContractDatesPanel` for one reason: the panel
 * is an Angular component and cannot be constructed outside a JIT/AOT host, so the rule that matters
 * could not be tested without booting Angular. The panel delegates to them and keeps its method
 * names and template bindings.
 *
 * `DateAsText` is here for the same reason and joins the same doctrine from the DISPLAY side. The
 * panel read the stored day correctly into the `<input>` and then rendered the read-only view through
 * Angular's `| date` pipe, which formats in the VIEWER'S zone — so one screen showed `31 Dec` in edit
 * mode and `30 Dec` out of it. Four other panels rendered the same columns the same way.
 */
import { FromCalendarDay, ToCalendarDay, UTC_ZONE } from '@mj-biz-apps/common-entities';

/** The four DATE columns the dates panel edits. */
export type ContractDateField = 'ExecutedDate' | 'EffectiveDate' | 'EndDate' | 'TerminatedDate';

/**
 * The `yyyy-MM-dd` an `<input type="date">` needs, or '' when there is nothing readable to show.
 *
 * Never throws and never re-bases: an offset-bearing stored string is the day it was written as, not
 * the day it converts to in the reader's zone.
 */
export function DateAsInput(value: Date | string | null | undefined): string {
    return ToCalendarDay(value) ?? '';
}

/**
 * UTC midnight of the picked day — the shape a `DATE` column round-trips as — or null when the input
 * is empty or unreadable. Unreadable clears rather than throwing: the panel writes straight onto the
 * entity from an `ngModelChange`, and a `RangeError` there would surface as a dead form.
 */
export function InputAsDate(value: string): Date | null {
    const day = ToCalendarDay(value);
    return day === null ? null : FromCalendarDay(day);
}

/**
 * A stored calendar day as text for a read-only field, or an em dash when there is nothing to show.
 *
 * WHY NOT `| date: 'd MMM y'`. Angular's date pipe formats in the VIEWER'S LOCAL ZONE. A `DATE`
 * column arrives at UTC midnight, so west of Greenwich the pipe renders the PREVIOUS day: the dates
 * panel showed `2026-12-31` in the `<input type="date">` (which `DateAsInput` reads from UTC parts,
 * correctly) and `30 Dec 2026` in the read-only `<div>` immediately after leaving edit mode. Same
 * column, same record, two different days on one screen — and the read-only rendering is the one a
 * person quotes into an email.
 *
 * `timeZone: 'UTC'` is the load-bearing option: `FromCalendarDay` re-anchors to UTC midnight, and
 * without it the formatter would re-interpret that instant in the viewer's zone and slide the day
 * back again one call later.
 *
 * A `DATETIMEOFFSET` is a different thing and must NOT come through here — an instant has no day
 * independent of a zone and is still shown in the viewer's local time. This is for the four `DATE`
 * columns and for `RenewalNoticeDeadline`, which is `DATE` arithmetic over two of them.
 *
 * The locale is the viewer's (`undefined`), matching `dateLabel` in `contract-form.panels.ts` — which
 * this now backs, so the same date reads the same way in the hero, the Overview panel and the Dates
 * tab. Only the ZONE is forced.
 */
export function DateAsText(value: Date | string | null | undefined): string {
    const day = ToCalendarDay(value);
    if (day === null) return '—';
    return FromCalendarDay(day).toLocaleDateString(undefined, {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        timeZone: UTC_ZONE,
    });
}
