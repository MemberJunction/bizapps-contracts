/**
 * The boundary between `<input type="date">` and the four DATE columns on Contract.
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
 */
import { FromCalendarDay, ToCalendarDay } from '@mj-biz-apps/common-entities';

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
