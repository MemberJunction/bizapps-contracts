/**
 * @fileoverview R-8 — turning a foreign-key violation into a sentence.
 *
 * Every FK in this schema is `NO_ACTION`, which is the correct behaviour: a delete that would orphan
 * data is refused. The problem is only that it reaches the user as a constraint name. Four entities
 * need the same treatment and differ ONLY in which rows to count, so this is one guard parameterised
 * by the dependencies rather than four copies of the same shape drifting apart — the review test from
 * ORCHESTRATION.md ("if I had to change this logic, how many places would I have to find?").
 *
 * ## Why `Delete()` and not a validation hook
 *
 * `BaseEntity` has no delete-side counterpart to `Validate()` — no `ValidateDelete`, no `BeforeDelete`,
 * no vetoable event. Verified by reading `_InnerDelete`, which runs no validation at all where
 * `_InnerSave` runs `Validate()`/`ValidateAsync()` first. So the only seam is overriding `Delete()`.
 * Filed upstream as [MJ#3971](https://github.com/MemberJunction/MJ/issues/3971), and a fix is already
 * authored there; when it lands, these overrides become `ValidateDeleteAsync()` bodies and this file
 * shrinks rather than disappears.
 *
 * ## Why it REGISTERS A RESULT and returns false, instead of throwing
 *
 * `bizapps-accounting`'s two precedents (`JournalEntryTypeEntityServer`, `JournalEntryLineEntityServer`)
 * **throw**. That works, and it is not what this does, deliberately:
 *
 *   · `Delete()` is declared `Promise<boolean>`. A caller written against that signature does
 *     `if (!await entity.Delete())` and gets an exception instead of `false`.
 *   · `LatestResult` is how MJ carries the reason for a refused write — it is what `ResolverBase`
 *     reads to build the GraphQL error, and what a refused `Save()` already populates. Throwing routes
 *     around the one channel built for this.
 *   · `RegisterResultHistoryEntry` is public precisely so a subclass can do this.
 *
 * ⚠ **This depends on an MJ fix to be VISIBLE.** `ResolverBase.DeleteRecord` read
 * `LatestResult?.Message` rather than `CompleteMessage`, so a registered refusal reached the API as
 * the literal string "Unknown error". Measured on this instance; the one-word fix is applied locally
 * in `instances/contracts-mj6/mj` and was commented onto MJ#3973. **On an unpatched MJ these messages
 * are correct and invisible** — the delete is still refused, so this is a message-quality dependency,
 * not a correctness one.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import { BaseEntity, BaseEntityResult, type EntityDeleteOptions } from '@memberjunction/core';

/**
 * One thing that can block a delete: the rows to look for, and how to describe them once counted.
 *
 * `describe` takes the count because the useful sentence names it — "3 contracts negotiated this
 * clause" tells someone how much work the cleanup is, where "this clause is in use" does not.
 */
export type DeleteDependency = {
    /** The MJ entity name holding the referencing rows. */
    EntityName: string;
    /** `ExtraFilter` selecting the rows that reference the record being deleted. */
    Filter: string;
    /** The clause describing what was found, given how many. */
    Describe: (count: number) => string;
};

/**
 * Count each dependency and return the refusal text, or null when nothing blocks the delete.
 *
 * COUNTS, NOT EXISTENCE. `count_only` costs the same as `TOP 1` on an indexed FK (MJ auto-indexes
 * every FK), and the number is most of the value of the message.
 *
 * ALL dependencies are checked, not just the first. Deleting a template usually trips both its
 * provisions and its contracts, and being told about one, fixing it, and then being refused again for
 * the other is the worst version of this interaction.
 *
 * A FAILED COUNT ABORTS rather than defaulting to zero. Reading "could not verify" as "nothing
 * references it" would let this guard wave through exactly the delete it exists to stop; the FK is
 * still the floor, but a guard that fails open is worse than no guard because it looks like one.
 */
export async function DescribeDeleteBlockers(entity: BaseEntity, dependencies: readonly DeleteDependency[]): Promise<string | null> {
    const blockers: string[] = [];

    for (const dependency of dependencies) {
        const result = await entity.RunViewProviderToUse.RunView(
            {
                EntityName: dependency.EntityName,
                ExtraFilter: dependency.Filter,
                ResultType: 'count_only',
            },
            entity.ContextCurrentUser,
        );
        if (!result?.Success) {
            throw new Error(
                `Could not check whether ${dependency.EntityName} still references this record: ` +
                    `${result?.ErrorMessage ?? 'unknown error'}. The delete was not attempted.`,
            );
        }
        const count = result.TotalRowCount ?? 0;
        if (count > 0) blockers.push(dependency.Describe(count));
    }

    return blockers.length > 0 ? blockers.join(' ') : null;
}

/**
 * Record a delete refusal on the entity so `LatestResult` carries the reason, and return false.
 *
 * Registered BEFORE `super.Delete()` is ever called, so nothing else has written a result — `Message`
 * is what `CompleteMessage` reads first, so the sentence survives without needing an `Errors` entry.
 * There is no field to name: a delete refusal is about the record, not about one of its columns, which
 * is part of why `ValidationErrorInfo` is the wrong vehicle here and MJ#3971 asks for a delete-shaped
 * one.
 */
export function RefuseDelete(entity: BaseEntity, message: string): false {
    const result = new BaseEntityResult();
    result.Success = false;
    result.Type = 'delete';
    result.Message = message;
    result.EndedAt = new Date();
    entity.RegisterResultHistoryEntry(result);
    return false;
}

/**
 * The whole guard: count the blockers, refuse with an explanation if there are any, otherwise delete.
 *
 * Every subclass override is one call to this, which is the point — the only thing that varies between
 * the four is the dependency list and the leading sentence.
 */
export async function GuardedDelete(
    entity: BaseEntity,
    options: EntityDeleteOptions | undefined,
    lead: string,
    dependencies: readonly DeleteDependency[],
    superDelete: (options?: EntityDeleteOptions) => Promise<boolean>,
): Promise<boolean> {
    const blockers = await DescribeDeleteBlockers(entity, dependencies);
    if (blockers) return RefuseDelete(entity, `${lead} ${blockers}`);
    return superDelete(options);
}

/** `'1 contract'` / `'3 contracts'` — so a message never reads "1 contracts". */
export function plural(count: number, singular: string, pluralForm?: string): string {
    return `${count} ${count === 1 ? singular : (pluralForm ?? `${singular}s`)}`;
}
